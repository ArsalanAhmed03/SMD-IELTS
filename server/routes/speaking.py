from __future__ import annotations

import mimetypes
from flask import Blueprint, abort, jsonify, request
import requests

from ai_helpers import evaluate_ielts_speaking
from supabase_client import get_supabase
from utils import get_current_user_id, to_jsonable

speaking_bp = Blueprint("speaking", __name__, url_prefix="/api")


@speaking_bp.post("/speaking-attempts")
def create_speaking_attempt():
    user_id = get_current_user_id()
    sb = get_supabase()
    body = request.get_json(force=True) or {}
    question_id = body.get("question_id")
    audio_path = body.get("audio_path")
    duration_seconds = body.get("duration_seconds")
    mode = (body.get("mode") or "").lower()
    exam_session_id = body.get("exam_session_id")
    exam_section_result_id = body.get("exam_section_result_id")

    if not question_id or not audio_path or duration_seconds is None or mode not in {"practice", "exam"}:
        abort(400, description="question_id, audio_path, duration_seconds, mode required")

    # Validate question exists
    q = sb.table("questions").select("id").eq("id", question_id).single().execute().data
    if not q:
        abort(404, description="Question not found")

    if mode == "exam":
        if not exam_session_id:
            abort(400, description="exam_session_id required for exam mode")
        sess = (
            sb.table("exam_sessions")
            .select("id,user_id")
            .eq("id", exam_session_id)
            .single()
            .execute()
            .data
        )
        if not sess or sess["user_id"] != user_id:
            abort(404, description="Exam session not found")

    row = (
        sb.table("speaking_attempts")
        .insert(
            {
                "user_id": user_id,
                "question_id": question_id,
                "audio_path": audio_path,
                "duration_seconds": duration_seconds,
                "mode": mode,
                "exam_session_id": exam_session_id,
                "exam_section_result_id": exam_section_result_id,
            }
        )
        .execute()
        .data[0]
    )
    return jsonify(to_jsonable(row)), 201


@speaking_bp.post("/speaking-eval/<attempt_id>")
def create_speaking_evaluation(attempt_id: str):
    user_id = get_current_user_id()
    sb = get_supabase()
    body = request.get_json(silent=True) or {}
    target_band = float(body.get("target_band") or 7.0)

    attempt = (
        sb.table("speaking_attempts")
        .select(
            "id,user_id,question_id,audio_path,duration_seconds,mode,exam_session_id,exam_section_result_id"
        )
        .eq("id", attempt_id)
        .single()
        .execute()
        .data
    )
    if not attempt or attempt["user_id"] != user_id:
        abort(404, description="Attempt not found")

    question = sb.table("questions").select("prompt").eq("id", attempt["question_id"]).single().execute().data
    if not question:
        abort(404, description="Question not found")

    storage = sb.storage.from_("speaking-attempts")
    public_url = storage.get_public_url(attempt["audio_path"])
    if not public_url:
        abort(502, description="Could not generate audio URL")

    audio_resp = requests.get(public_url, timeout=30)
    if audio_resp.status_code >= 400:
        abort(502, description="Failed to download audio for evaluation")

    mime_type = (
        audio_resp.headers.get("Content-Type")
        or mimetypes.guess_type(attempt["audio_path"])[0]
        or "audio/mpeg"
    )

    eval_res = evaluate_ielts_speaking(
        audio_resp.content,
        mime_type,
        question.get("prompt") or "",
        target_band,
        attempt.get("duration_seconds"),
    )

    row = (
        sb.table("speaking_evaluations")
        .insert(
            {
                "attempt_id": attempt_id,
                "user_id": user_id,
                "question_id": attempt["question_id"],
                "mode": attempt["mode"],
                "overall_band": eval_res.get("overall_band"),
                "band_fluency": eval_res.get("fluency_and_coherence"),
                "band_lexical": eval_res.get("lexical_resource"),
                "band_grammar": eval_res.get("grammatical_range_and_accuracy"),
                "band_pronunciation": eval_res.get("pronunciation"),
                "is_good_enough": eval_res.get("is_good_enough"),
                "feedback_short": eval_res.get("feedback_short"),
                "feedback_detailed": eval_res.get("feedback_detailed"),
                "transcript": eval_res.get("transcript"),
            }
        )
        .execute()
        .data[0]
    )
    response_payload = {
        **to_jsonable(row),
        "on_topic": eval_res.get("on_topic"),
        "relevance_score": eval_res.get("relevance_score"),
        "relevance_feedback": eval_res.get("relevance_feedback"),
    }
    return jsonify(response_payload), 201
