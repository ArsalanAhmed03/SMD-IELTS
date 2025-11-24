from __future__ import annotations
from flask import Blueprint, jsonify, abort
from supabase_client import get_supabase

content_bp = Blueprint("content", __name__, url_prefix="/api")


@content_bp.get("/skills")
def list_skills():
    sb = get_supabase()
    res = (
        sb.table("skills")
        .select("id,slug,name,description,color_hex,icon_key")
        .order("name")
        .execute()
    )
    return jsonify(res.data or [])


@content_bp.get("/skills/<slug>/practice-sets")
def skill_practice_sets(slug: str):
    sb = get_supabase()

    # 1) Fetch skill
    skill_resp = (
        sb.table("skills")
        .select("id,slug,name")
        .eq("slug", slug)
        .execute()
    )
    skill_rows = skill_resp.data or []
    if not skill_rows:
        abort(404, description="Skill not found")
    skill = skill_rows[0]

    # 2) Fetch sets + aggregated question counts in ONE call
    # Make sure your DB has a relation from questions.practice_set_id to practice_sets.id
    sets_resp = (
        sb.table("practice_sets")
        .select(
            "id,title,level_tag,short_description,estimated_minutes,is_premium,"
            "questions(count)"
        )
        .eq("skill_id", skill["id"])
        .eq("is_active", True)
        .order("created_at", desc=True)
        .execute()
    )

    rows = sets_resp.data or []

    sets = []
    for row in rows:
        # Supabase returns something like: "questions": [{"count": 12}]
        questions_rel = row.get("questions") or []
        q_count = 0
        if questions_rel and isinstance(questions_rel, list):
            first = questions_rel[0] or {}
            q_count = first.get("count", 0) or 0

        sets.append(
            {
                "id": row["id"],
                "title": row["title"],
                "level_tag": row.get("level_tag"),
                "short_description": row.get("short_description"),
                "estimated_minutes": row.get("estimated_minutes"),
                "is_premium": row.get("is_premium"),
                "question_count": q_count,
            }
        )

    return jsonify(
        {
            "skill": {
                "slug": skill["slug"],
                "name": skill["name"],
            },
            "items": sets,
        }
    )


@content_bp.get("/practice-sets/<ps_id>")
def get_practice_set(ps_id: str):
    sb = get_supabase()
    ps = (
        sb.table("practice_sets")
        .select(
            "id,skill_id,title,level_tag,short_description,"
            "estimated_minutes,is_premium,is_active"
        )
        .eq("id", ps_id)
        .single()
        .execute()
        .data
    )
    if not ps:
        abort(404, description="Practice set not found")
    skill = (
        sb.table("skills")
        .select("slug,name")
        .eq("id", ps["skill_id"])
        .single()
        .execute()
        .data
    )
    qcount = (
        sb.table("questions")
        .select("id", count="exact")
        .eq("practice_set_id", ps_id)
        .execute()
        .count
        or 0
    )
    tracks = (
        sb.table("listening_tracks")
        .select("id,title,audio_path,duration_seconds")
        .eq("practice_set_id", ps_id)
        .execute()
        .data
        or []
    )
    return jsonify(
        {
            "practice_set": ps,
            "skill": skill,
            "question_count": qcount,
            "listening_tracks": tracks,
        }
    )


@content_bp.get("/practice-sets/<ps_id>/questions")
def practice_set_questions(ps_id: str):
    sb = get_supabase()
    ps = (
        sb.table("practice_sets")
        .select("id")
        .eq("id", ps_id)
        .single()
        .execute()
        .data
    )
    if not ps:
        abort(404, description="Practice set not found")

    qs = (
        sb.table("questions")
        .select(
            "id,type,order_index,prompt,passage,max_score,"
            "listening_track_id,audio_start_sec,audio_end_sec"
        )
        .eq("practice_set_id", ps_id)
        .order("order_index")
        .execute()
        .data
        or []
    )

    # Map listening tracks
    track_ids = [q["listening_track_id"] for q in qs if q.get("listening_track_id")]
    track_map = {}
    if track_ids:
        tracks = (
            sb.table("listening_tracks")
            .select("id,title,audio_path,duration_seconds")
            .in_("id", track_ids)
            .execute()
            .data
            or []
        )
        track_map = {t["id"]: t for t in tracks}

    # Attach options and listening track
    for q in qs:
        opts = (
            sb.table("question_options")
            .select("id,option_index,text")
            .eq("question_id", q["id"])
            .order("option_index")
            .execute()
            .data
            or []
        )
        q["options"] = opts
        if q.get("listening_track_id") and q["listening_track_id"] in track_map:
            q["listening_track"] = track_map[q["listening_track_id"]]

    return jsonify(qs)
