# server/ai_client.py

from __future__ import annotations
import os
from pathlib import Path
from dotenv import load_dotenv

import google.generativeai as genai

# Load .env reliably
BASE_DIR = Path(__file__).resolve().parent
load_dotenv(BASE_DIR / ".env")

API_KEY = os.getenv("GOOGLE_API_KEY") or os.getenv("GOOGLE_AI_KEY")
if not API_KEY:
    raise RuntimeError("Missing GOOGLE_API_KEY or GOOGLE_AI_KEY in server/.env")

# New-style AI Studio client
client = genai.Client(api_key=API_KEY)

# Choose a stable, supported model
MODEL_NAME = "gemini-2.0-flash"  # You can also use gemini-3-pro-preview


def gemini_text(prompt: str) -> str:
    """
    Returns the AI-generated text using the new Google AI Studio client.
    """
    response = client.models.generate_content(
        model=MODEL_NAME,
        contents=prompt,
    )

    # response.text always exists; client handles tokens internally
    return response.text.strip()
