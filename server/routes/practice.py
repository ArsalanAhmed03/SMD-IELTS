from __future__ import annotations
from flask import Blueprint, jsonify, request, abort
from datetime import datetime, timezone
from supabase_client import get_supabase
from utils import get_current_user_id

practice_bp = Blueprint("practice", __name__, url_prefix="/api")


def _get_profile(user_id: str):
    sb = get_supabase()
    res = sb.table("profiles").select("user_id,is_premium").eq("user_id", user_id).single().execute()
    return res.data


@practice_bp.post("/practice-sessions")
def create_practice_session():
    user_id = get_current_user_id()
    sb = get_supabase()
    body = request.get_json(force=True) or {}
    ps_id = body.get("practice_set_id")
    if not ps_id:
        abort(400, description="practice_set_id required")
    ps = sb.table("practice_sets").select("id,title,estimated_minutes,is_premium").eq("id", ps_id).single().execute().data
    if not ps:
        abort(404, description="Practice set not found")
    profile = _get_profile(user_id)
    if ps.get("is_premium") and not (profile and profile.get("is_premium")):
        abort(403, description="Premium required for this practice set")
    started_at = datetime.now(timezone.utc).isoformat()
    row = sb.table("practice_sessions").insert({
        "user_id": user_id,
        "practice_set_id": ps_id,
        "started_at": started_at,
    }).execute().data[0]
    return jsonify({
        "id": row["id"],
        "practice_set": {"id": ps_id, "title": ps["title"], "estimated_minutes": ps["estimated_minutes"]},
        "started_at": started_at,
    }), 201


@practice_bp.post("/practice-sessions/<session_id>/answers")
def add_practice_answer(session_id: str):
    user_id = get_current_user_id()
    sb = get_supabase()
    sess = sb.table("practice_sessions").select("id,user_id").eq("id", session_id).single().execute().data
    if not sess or sess["user_id"] != user_id:
        abort(404, description="Session not found")
    body = request.get_json(force=True) or {}
    q_id = body.get("question_id")
    option_id = body.get("option_id")
    answer_text = body.get("answer_text")
    if not q_id:
        abort(400, description="question_id required")
    q = sb.table("questions").select("id,type").eq("id", q_id).single().execute().data
    if not q:
        abort(404, description="Question not found")
    is_correct = None
    if option_id:
        correct = (
            sb.table("question_options").select("id").eq("question_id", q_id).eq("is_correct", True).single().execute().data
        )
        if correct:
            is_correct = (option_id == correct["id"])
    row = sb.table("practice_answers").insert({
        "session_id": session_id,
        "question_id": q_id,
        "option_id": option_id,
        "answer_text": answer_text,
        "is_correct": is_correct,
        "answered_at": datetime.now(timezone.utc).isoformat(),
    }).execute().data[0]
    return jsonify(row), 201


@practice_bp.post("/practice-sessions/<session_id>/complete")
def complete_practice_session(session_id: str):
    user_id = get_current_user_id()
    sb = get_supabase()

    # 1) Validate session ownership
    sess = (
        sb.table("practice_sessions")
        .select("id,user_id,practice_set_id")
        .eq("id", session_id)
        .single()
        .execute()
        .data
    )
    if not sess or sess["user_id"] != user_id:
        abort(404, description="Session not found")

    body = request.get_json(silent=True) or {}
    time_taken = body.get("time_taken_seconds")
    ps_id = sess["practice_set_id"]

    # 2) Load all answers for this session
    answers_raw = (
        sb.table("practice_answers")
        .select("id, question_id, option_id, answer_text, is_correct")
        .eq("session_id", session_id)
        .execute()
        .data
    )

    # 3) Fetch all questions + options for this practice set
    # IMPORTANT: use the actual relationship/table name: question_options
    qrows = (
        sb.table("questions")
        .select("id, prompt, question_options(id, text, is_correct)")
        .eq("practice_set_id", ps_id)
        .execute()
        .data
    )

    # Map questions by id
    qmap = {q["id"]: q for q in qrows}

    # 4) Build enriched answer list
    enriched_answers = []
    for ans in answers_raw:
        qid = ans["question_id"]
        q = qmap.get(qid)

        prompt = q["prompt"] if q else None
        raw_opts = q.get("question_options", []) if q else []

        # Map options by id for quick lookup
        option_map = {opt["id"]: opt for opt in raw_opts}

        user_option = option_map.get(ans["option_id"])
        user_option_text = user_option["text"] if user_option else None

        # Find correct option text
        correct_option_text = None
        for opt in raw_opts:
            if opt.get("is_correct") is True:
                correct_option_text = opt["text"]
                break

        # Pick best representation of the user's answer
        user_answer_final = ans["answer_text"] or user_option_text

        enriched_answers.append(
            {
                "question_id": qid,
                "prompt": prompt,
                "user_answer": user_answer_final,
                "user_option_text": user_option_text,
                "answer_text": ans["answer_text"],
                "is_correct": ans["is_correct"],
                "correct_option_text": correct_option_text,
                "correct_answer": correct_option_text,  # alias for frontend
            }
        )

    # 5) Calculate stats
    total_q = (
        sb.table("questions")
        .select("id", count="exact")
        .eq("practice_set_id", ps_id)
        .execute()
        .count
        or 0
    )
    total_correct = sum(1 for a in answers_raw if a["is_correct"])
    completed_at = datetime.now(timezone.utc).isoformat()
    score = float(total_correct) / total_q * 100 if total_q else 0.0

    # 6) Update session meta
    sb.table("practice_sessions").update(
        {
            "completed_at": completed_at,
            "time_taken_seconds": time_taken,
            "total_questions": total_q,
            "correct_questions": total_correct,
            "score": score,
        }
    ).eq("id", session_id).execute()

    # 7) Get practice set & skill
    ps = (
        sb.table("practice_sets")
        .select("id,title,skill_id")
        .eq("id", ps_id)
        .single()
        .execute()
        .data
    )
    skill = (
        sb.table("skills")
        .select("slug, name")
        .eq("id", ps["skill_id"])
        .single()
        .execute()
        .data
    )

    # 8) Final response
    return jsonify(
        {
            "practice_set": {
                "id": ps["id"],
                "title": ps["title"],
                "skill_slug": skill["slug"],
                "skill_name": skill.get("name"),
            },
            "stats": {
                "total_questions": total_q,
                "correct_questions": total_correct,
                "time_taken_seconds": time_taken,
                "score": score,
            },
            "answers": enriched_answers,
            "completed_at": completed_at,
        }
    )


@practice_bp.get("/practice-sessions/recent")
def recent_sessions():
    user_id = get_current_user_id()
    sb = get_supabase()
    rows = (
        sb.table("practice_sessions")
        .select("id,practice_set_id,completed_at,total_questions,correct_questions,score")
        .eq("user_id", user_id)
        .order("completed_at", desc=True)
        .limit(10)
        .execute()
        .data
        or []
    )
    # Attach practice set title and skill slug
    out = []
    for r in rows:
        ps = (
            sb.table("practice_sets").select("title,skill_id").eq("id", r["practice_set_id"]).single().execute().data
        )
        skill = sb.table("skills").select("slug").eq("id", ps["skill_id"]).single().execute().data
        r.update({"practice_set_title": ps["title"], "skill_slug": skill["slug"]})
        out.append(r)
    return jsonify(out)

