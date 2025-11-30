from __future__ import annotations
from flask import Blueprint, jsonify, request, abort
from datetime import datetime, timezone
from supabase_client import get_supabase
from utils import get_current_user_id, to_jsonable
from ai_helpers import evaluate_ielts_writing

exam_bp = Blueprint("exam", __name__, url_prefix="/api")


def _ensure_premium(user_id: str):
    sb = get_supabase()
    prof = sb.table("profiles").select("is_premium").eq("user_id", user_id).single().execute().data
    if not (prof and prof.get("is_premium")):
        abort(403, description="Full exam simulations are for Premium users")


@exam_bp.post("/exam-sessions")
def create_exam_session():
    user_id = get_current_user_id()
    _ensure_premium(user_id)
    sb = get_supabase()
    row = sb.table("exam_sessions").insert({
        "user_id": user_id,
        "started_at": datetime.now(timezone.utc).isoformat(),
    }).execute().data[0]
    return jsonify({"exam_session_id": row["id"]}), 201


@exam_bp.post("/exam-sections")
def create_exam_section():
    user_id = get_current_user_id()
    body = request.get_json(force=True) or {}
    exam_session_id = body.get("exam_session_id")
    skill_slug = body.get("skill_slug")
    if not exam_session_id or not skill_slug:
        abort(400, description="exam_session_id and skill_slug required")
    sb = get_supabase()
    sess = sb.table("exam_sessions").select("id,user_id").eq("id", exam_session_id).single().execute().data
    if not sess or sess["user_id"] != user_id:
        abort(404, description="Exam session not found")
    skill = sb.table("skills").select("id").eq("slug", skill_slug).single().execute().data
    if not skill:
        abort(404, description="Skill not found")
    row = sb.table("exam_section_results").insert({
        "exam_session_id": exam_session_id,
        "skill_id": skill["id"],
        "started_at": datetime.now(timezone.utc).isoformat(),
    }).execute().data[0]
    return jsonify({"section_result_id": row["id"]}), 201


@exam_bp.post("/exam-answers")
def add_exam_answer():
    user_id = get_current_user_id()
    body = request.get_json(force=True) or {}
    exam_session_id = body.get("exam_session_id")
    section_result_id = body.get("section_result_id")
    question_id = body.get("question_id")
    option_id = body.get("option_id")
    answer_text = body.get("answer_text")
    if not (exam_session_id and section_result_id and question_id):
        abort(400, description="exam_session_id, section_result_id, question_id required")
    sb = get_supabase()
    sess = sb.table("exam_sessions").select("id,user_id").eq("id", exam_session_id).single().execute().data
    if not sess or sess["user_id"] != user_id:
        abort(404, description="Exam session not found")
    q = sb.table("questions").select("id,skill_id").eq("id", question_id).single().execute().data
    if not q:
        abort(404, description="Question not found")
    is_correct = None
    if option_id:
        correct = sb.table("question_options").select("id").eq("question_id", question_id).eq("is_correct", True).single().execute().data
        if correct:
            is_correct = (option_id == correct["id"])
    row = sb.table("exam_answers").insert({
        "exam_session_id": exam_session_id,
        "section_result_id": section_result_id,
        "skill_id": q["skill_id"],
        "question_id": question_id,
        "option_id": option_id,
        "answer_text": answer_text,
        "is_correct": is_correct,
        "answered_at": datetime.now(timezone.utc).isoformat(),
    }).execute().data[0]
    return jsonify(row), 201


@exam_bp.post("/writing-eval/exam/<exam_answer_id>")
def create_writing_eval_for_exam(exam_answer_id: str):
    user_id = get_current_user_id()
    sb = get_supabase()
    body = request.get_json(silent=True) or {}
    target_band = float(body.get("target_band") or 7.0)

    ans = (
        sb.table("exam_answers")
        .select("id,exam_session_id,section_result_id,question_id,answer_text")
        .eq("id", exam_answer_id)
        .single()
        .execute()
        .data
    )
    if not ans:
        abort(404, description="Exam answer not found")

    sess = (
        sb.table("exam_sessions")
        .select("user_id")
        .eq("id", ans["exam_session_id"])
        .single()
        .execute()
        .data
    )
    if not sess or sess["user_id"] != user_id:
        abort(404, description="Exam session not found")

    q = sb.table("questions").select("id,prompt,task_type").eq("id", ans["question_id"]).single().execute().data
    if not q:
        abort(404, description="Question not found")

    eval_res = evaluate_ielts_writing(
        q.get("prompt") or "",
        ans.get("answer_text") or "",
        q.get("task_type") or "Task 2",
        target_band,
    )

    row = (
        sb.table("writing_evaluations")
        .insert(
            {
                "mode": "exam",
                "practice_answer_id": None,
                "exam_answer_id": exam_answer_id,
                "exam_session_id": ans["exam_session_id"],
                "exam_section_result_id": ans["section_result_id"],
                "user_id": user_id,
                "question_id": q["id"],
                "overall_band": eval_res.get("overall_band"),
                "band_task_response": eval_res.get("task_response"),
                "band_coherence": eval_res.get("coherence_and_cohesion"),
                "band_lexical": eval_res.get("lexical_resource"),
                "band_grammar": eval_res.get("grammatical_range_and_accuracy"),
                "is_good_enough": eval_res.get("is_good_enough"),
                "feedback_short": eval_res.get("feedback_short"),
                "feedback_detailed": eval_res.get("feedback_detailed"),
                "model_answer": eval_res.get("model_answer"),
            }
        )
        .execute()
        .data[0]
    )
    return jsonify(to_jsonable(row)), 201


@exam_bp.post("/exam-sections/<section_id>/complete")
def complete_section(section_id: str):
    user_id = get_current_user_id()
    body = request.get_json(force=True) or {}
    time_taken = body.get("time_taken_seconds")
    total_questions = body.get("total_questions")
    sb = get_supabase()
    sec = sb.table("exam_section_results").select("id,exam_session_id").eq("id", section_id).single().execute().data
    if not sec:
        abort(404, description="Section not found")
    sess = sb.table("exam_sessions").select("user_id").eq("id", sec["exam_session_id"]).single().execute().data
    if not sess or sess["user_id"] != user_id:
        abort(404, description="Exam session not found")
    correct = sb.table("exam_answers").select("id", count="exact").eq("section_result_id", section_id).eq("is_correct", True).execute().count or 0
    score = float(correct) / total_questions * 100 if total_questions else 0.0
    updated = sb.table("exam_section_results").update({
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "time_taken_seconds": time_taken,
        "total_questions": total_questions,
        "correct_questions": correct,
        "score": score,
    }).eq("id", section_id).execute().data[0]
    return jsonify(updated)


@exam_bp.post("/exam-sessions/<exam_id>/complete")
def complete_exam(exam_id: str):
    user_id = get_current_user_id()
    body = request.get_json(silent=True) or {}
    total_time = body.get("total_time_seconds")
    sb = get_supabase()

    # Validate session
    sess = (
        sb.table("exam_sessions")
        .select("id,user_id")
        .eq("id", exam_id)
        .single()
        .execute()
        .data
    )
    if not sess or sess["user_id"] != user_id:
        abort(404, description="Exam session not found")

    # Mark exam completed
    completed_at = datetime.now(timezone.utc).isoformat()
    updated = (
        sb.table("exam_sessions")
        .update(
            {
                "completed_at": completed_at,
                "total_time_seconds": total_time,
            }
        )
        .eq("id", exam_id)
        .execute()
        .data[0]
    )

    # Build section summaries
    sections = (
        sb.table("exam_section_results")
        .select("id,skill_id,time_taken_seconds,total_questions,correct_questions,score")
        .eq("exam_session_id", exam_id)
        .execute()
        .data
        or []
    )

    out_sections = []

    for s in sections:
        # skill slug
        skill = (
            sb.table("skills")
            .select("slug")
            .eq("id", s["skill_id"])
            .single()
            .execute()
            .data
        )

        # raw answers for this section
        answers = (
            sb.table("exam_answers")
            .select("id,question_id,option_id,answer_text,is_correct")
            .eq("section_result_id", s["id"])
            .execute()
            .data
            or []
        )

        writing_evals = (
            sb.table("writing_evaluations")
            .select("*")
            .eq("exam_section_result_id", s["id"])
            .execute()
            .data
            or []
        )
        writing_by_answer = {
            w.get("exam_answer_id"): w for w in writing_evals if w.get("exam_answer_id")
        }

        # simple caches to avoid querying the same question over and over
        question_cache: dict[str, dict] = {}
        correct_option_cache: dict[str, dict | None] = {}
        options_cache: dict[str, list] = {}

        for a in answers:
            qid = a["question_id"]

            # question prompt (cached)
            if qid not in question_cache:
                q = (
                    sb.table("questions")
                    .select("prompt")
                    .eq("id", qid)
                    .single()
                    .execute()
                    .data
                )
                question_cache[qid] = q or {}
            q = question_cache[qid]
            a["prompt"] = q.get("prompt")

            # user answer text
            user_answer = a.get("answer_text")
            user_option_text = None

            if a.get("option_id"):
                opt = (
                    sb.table("question_options")
                    .select("text,question_id")
                    .eq("id", a["option_id"])
                    .single()
                    .execute()
                    .data
                )
                if opt:
                    user_option_text = opt["text"]
                    user_answer = user_option_text

            a["user_answer"] = user_answer

            # correct option text (cached per question)
            if qid not in correct_option_cache:
                opts = (
                    sb.table("question_options")
                    .select("text,is_correct,option_index")
                    .eq("question_id", qid)
                    .order("option_index")
                    .execute()
                    .data
                    or []
                )
                correct_opt = None
                for o in opts:
                    if o.get("is_correct"):
                        correct_opt = o
                        break
                correct_option_cache[qid] = correct_opt
                options_cache[qid] = opts

            correct_opt = correct_option_cache[qid]
            correct_text = correct_opt["text"] if correct_opt else None

            a["correct_option_text"] = correct_text
            a["correct_answer"] = correct_text  # alias for frontend
            a["options"] = options_cache.get(qid, [])

            # we don't need to expose option_id to the client
            a.pop("option_id", None)

            w_eval = writing_by_answer.get(a["id"])
            a["writing_eval"] = to_jsonable(w_eval) if w_eval else None
            a.pop("id", None)

        # speaking attempts (if any) tied to this section
        speaking_attempts = (
            sb.table("speaking_attempts")
            .select("id,audio_path,duration_seconds,question_id")
            .eq("exam_section_result_id", s["id"])
            .execute()
            .data
            or []
        )
        attempt_ids = [a["id"] for a in speaking_attempts]
        speaking_evals = (
            sb.table("speaking_evaluations")
            .select("*")
            .in_("attempt_id", attempt_ids or [""])
            .execute()
            .data
            or []
        )
        eval_by_attempt = {e["attempt_id"]: e for e in speaking_evals}
        question_prompt_cache: dict[str, str | None] = {}

        speaking_summary = []
        for at in speaking_attempts:
            ev = eval_by_attempt.get(at["id"])
            qid = at.get("question_id")
            if qid not in question_prompt_cache:
                qp = (
                    sb.table("questions")
                    .select("prompt")
                    .eq("id", qid)
                    .single()
                    .execute()
                    .data
                )
                question_prompt_cache[qid] = qp.get("prompt") if qp else None
            speaking_summary.append(
                {
                    **at,
                    "question_prompt": question_prompt_cache.get(qid),
                    "evaluation": to_jsonable(ev) if ev else None,
                }
            )

        out_sections.append(
            {
                "section_result_id": s["id"],
                "skill_slug": skill["slug"],
                "time_taken_seconds": s.get("time_taken_seconds"),
                "total_questions": s.get("total_questions"),
                "correct_questions": s.get("correct_questions"),
                "score": s.get("score"),
                "answers": answers,
                "writing_evaluations": [to_jsonable(w) for w in writing_evals],
                "speaking_attempts": speaking_summary,
            }
        )

    summary = {
        "exam_session": updated,
        "sections": out_sections,
    }
    return jsonify(summary)
