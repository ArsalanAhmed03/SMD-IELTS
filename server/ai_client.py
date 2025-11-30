# server/ai_client.py

from __future__ import annotations
import os
from pathlib import Path
from dotenv import load_dotenv

import google.generativeai as genai

# Load .env if present (local dev); on Render you’ll use real env vars
BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

# Prefer Render / system env; fall back to .env for local runs
API_KEY = os.getenv("GOOGLE_API_KEY") or os.getenv("GOOGLE_AI_KEY")
if not API_KEY:
    raise RuntimeError("Missing GOOGLE_API_KEY or GOOGLE_AI_KEY in environment")

# Configure global client for the SDK
genai.configure(api_key=API_KEY)

# Choose model (can be overridden via env)
MODEL_NAME = os.getenv("GOOGLE_MODEL_NAME", "gemini-2.0-flash")

# Create a reusable model instance
_model = genai.GenerativeModel(MODEL_NAME)


def gemini_text(prompt: str, **kwargs) -> str:
    """
    Convenience helper: generate text for a single prompt.
    """
    response = _model.generate_content(prompt, **kwargs)

    # Try to return response.text; fall back more defensively if needed
    text = getattr(response, "text", None)
    if text is not None:
        return text.strip()

    # Fallback for older/newer response shapes
    candidates = getattr(response, "candidates", None)
    if candidates:
        parts = getattr(candidates[0].content, "parts", None) or []
        if parts and getattr(parts[0], "text", None):
            return parts[0].text.strip()

    # As a last resort, just cast to str
    return str(response).strip()


# ---------------------------------------------------------------------
# Shim to keep `client.models.generate_content(...)` working
# ---------------------------------------------------------------------

class _ModelsWrapper:
    def __init__(self, model):
        self._model = model

    def generate_content(self, model: str | None = None, contents=None, **kwargs):
        """
        Shim so existing code like:
            client.models.generate_content(model=MODEL_NAME, contents=prompt)
        still works with the new SDK.

        We ignore the `model` argument and always use the configured `_model`.
        """
        if contents is None and "prompt" in kwargs:
            contents = kwargs.pop("prompt")

        # The new SDK happily accepts a string or richer content structure.
        return self._model.generate_content(contents, **kwargs)


class _ClientShim:
    def __init__(self, model):
        self.models = _ModelsWrapper(model)

    def generate_text(self, prompt: str, **kwargs) -> str:
        """
        Optional helper if you ever want `client.generate_text(...)`.
        """
        return gemini_text(prompt, **kwargs)


# This is what ai_helpers currently imports: `from ai_client import client, MODEL_NAME`
client = _ClientShim(_model)
