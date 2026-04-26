#!/usr/bin/env python3
"""
BioChecha daily insight — reads recent nutrition + workout + sleep +
body-comp + spending data, calls GPT-4o-mini with the writerly prompt,
writes ONE row to public.insights for the day. iOS app's DailyInsightCard
reads from there.

Voice: writerly, factual, slightly literary. Examples:
  ✅ "Three short nights and HRV's been ducking. Lifting hard while
      light on sleep is the part you've been getting away with —
      until you don't."
  ❌ "You should sleep more!" (preachy)
  ❌ "Sleep duration: 6.4h, HRV: 51ms" (data dump)

Schedule: 7am Lisbon time (after 6am morning briefing assembly).
Idempotent on (user_id, valid_for_date) — re-running on the same day
overwrites the existing row instead of duplicating.

Usage:
    bash -c 'set -a && source ~/.openclaw/secrets/perch.env && set +a && python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_daily_insight.py'

Env required:
    SUPABASE_URL
    SUPABASE_SERVICE_ROLE_KEY
    PERCH_USER_ID
    OPENAI_API_KEY
"""
from __future__ import annotations

import json
import os
import sys
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).parent))
from _supabase_client import insert_agent_run  # noqa: E402

OPENAI_URL = "https://api.openai.com/v1/chat/completions"
OPENAI_MODEL = os.environ.get("OPENAI_INSIGHT_MODEL", "gpt-4o-mini")


# ─── Prompt ─────────────────────────────────────────────────────────


SYSTEM_PROMPT = """You are BioChecha, the user's AI health & nutrition coach.

You're writing today's insight: a single short paragraph (40–80 words, MAX 100) that connects what the user's data shows across nutrition, workouts, sleep, and body composition into something useful.

Voice
- Writerly. Factual. Slightly literary. Conversational.
- Direct. Backed by specifics from the data.
- Like a knowledgeable gym buddy who also happens to be a nutritionist.

EXAMPLES OF GOOD INSIGHTS

"Three short nights and HRV's been ducking. Lifting hard while light on sleep is the part you've been getting away with — until you don't. Today's a good candidate for a recovery day; if not, drop the volume."

"Protein hit 110g yesterday — closer to target than you've been all week. Notice the difference at the gym today; if the lift feels easier, that's the data telling you something."

"Sleep score 88 last night. Best of the week. Morning workout's the move."

"Weight steady at 78.4kg for the third week. You're flat, which after last month's drift is fine — but if you wanted to be losing, the calorie target needs another 200kcal off."

EXAMPLES OF BAD INSIGHTS (don't write like this)

❌ "You should sleep more!" (preachy)
❌ "Sleep duration: 6.4h, HRV: 51ms, calories: 2400" (data dump, no synthesis)
❌ "Your body is amazing! Keep it up! 💪" (woo, unhelpful)
❌ "Based on the data, it appears that..." (hedging, AI-formal)

RULES
- ONLY output the insight text. No prefix, no greeting, no signoff. Just the paragraph.
- One paragraph. No bullet points. No headers.
- Reference SPECIFICS from the data — actual numbers, actual dates, actual patterns.
- If the data is sparse / boring / unremarkable, say so honestly. Don't invent insight where there isn't one. Examples of honest "boring day" insights:
  ✅ "Quiet data day — sleep within range, calories on target, nothing pulling. Sometimes that's the win."
  ✅ "Nothing notable in the data this morning. Steady week."
- If the data is genuinely concerning, say so directly — but match it to action, not alarm.
- Skip 'today's insight'-style preambles. Lead with the observation.
"""


def _build_user_prompt(data: dict[str, Any]) -> str:
    """Render the gathered data into the user-message body."""
    parts: list[str] = [
        f"Today: {date.today().isoformat()} ({date.today().strftime('%A')})",
        "",
    ]

    if sleep := data.get("sleep_last_7_days"):
        parts.append("SLEEP (last 7 days, oldest first):")
        for s in sleep:
            parts.append(
                f"  {s['date']}: {s.get('duration_min', '?'):.0f}min, "
                f"score {s.get('score', '?')}, HRV {s.get('hrv', '?')}, "
                f"RHR {s.get('rhr', '?')}"
            )
    else:
        parts.append("SLEEP: no data this week.")
    parts.append("")

    if workouts := data.get("workouts_last_7_days"):
        parts.append("WORKOUTS (last 7 days, oldest first):")
        for w in workouts:
            parts.append(
                f"  {w['date']}: {w.get('title', '?')} — "
                f"{w.get('duration_min', '?')}min, RPE {w.get('rpe', '?')}"
            )
    else:
        parts.append("WORKOUTS: no logged sessions this week.")
    parts.append("")

    if nutrition := data.get("nutrition_last_7_days"):
        parts.append("NUTRITION daily totals (last 7 days, oldest first):")
        for n in nutrition:
            parts.append(
                f"  {n['date']}: {n.get('calories', '?'):.0f}kcal, "
                f"P{n.get('protein', '?'):.0f}g C{n.get('carbs', '?'):.0f}g "
                f"F{n.get('fat', '?'):.0f}g"
            )
    else:
        parts.append("NUTRITION: no meals logged this week.")
    parts.append("")

    if weight := data.get("weight_recent"):
        parts.append("WEIGHT (most recent first, last 14 days):")
        for w in weight[:8]:
            parts.append(f"  {w['date']}: {w['kg']:.1f}kg")
    parts.append("")

    if targets := data.get("targets"):
        parts.append("CURRENT TARGETS:")
        if t_cal := targets.get("calories"):
            parts.append(f"  calories: {t_cal:.0f}/day")
        if t_p := targets.get("protein"):
            parts.append(f"  protein: {t_p:.0f}g/day")
    parts.append("")

    parts.append(
        "Write today's insight (40–80 words, single paragraph, no preamble)."
    )
    return "\n".join(parts)


# ─── Data gathering ─────────────────────────────────────────────────


def _supabase_get(path: str, params: dict[str, str]) -> list[dict[str, Any]]:
    url = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    user = os.environ["PERCH_USER_ID"]
    qs = "&".join(f"{k}={v}" for k, v in params.items())
    qs += f"&user_id=eq.{user}"
    req = Request(
        f"{url}/rest/v1/{path}?{qs}",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
        },
    )
    with urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def _gather_sleep() -> list[dict[str, Any]]:
    """Aggregate health_metrics into nightly sleep summaries."""
    since = (datetime.now(timezone.utc) - timedelta(days=8)).isoformat()
    rows = _supabase_get(
        "health_metrics",
        {
            "metric": "in.(sleep_duration_min,sleep_score,hrv_rmssd_ms,resting_heart_rate_bpm)",
            "measured_at": f"gte.{since}",
            "select": "metric,value,measured_at",
            "order": "measured_at.asc",
        },
    )
    by_day: dict[str, dict[str, Any]] = {}
    for r in rows:
        day = r["measured_at"][:10]
        d = by_day.setdefault(day, {"date": day})
        m = r["metric"]
        v = float(r["value"])
        if m == "sleep_duration_min":
            d["duration_min"] = v
        elif m == "sleep_score":
            d["score"] = v
        elif m == "hrv_rmssd_ms":
            d["hrv"] = v
        elif m == "resting_heart_rate_bpm":
            d["rhr"] = v
    return sorted(by_day.values(), key=lambda x: x["date"])


def _gather_workouts() -> list[dict[str, Any]]:
    since = (datetime.now(timezone.utc) - timedelta(days=8)).isoformat()
    # We assume workouts live in dashboard_records as type='workout_session'.
    rows = _supabase_get(
        "dashboard_records",
        {
            "type": "eq.workout_session",
            "created_at": f"gte.{since}",
            "select": "title,data,created_at",
            "order": "created_at.asc",
        },
    )
    out = []
    for r in rows:
        d = r.get("data") or {}
        out.append({
            "date": r["created_at"][:10],
            "title": r.get("title", "Workout"),
            "duration_min": d.get("duration_min"),
            "rpe": d.get("rpe"),
        })
    return out


def _gather_nutrition() -> list[dict[str, Any]]:
    since = (datetime.now(timezone.utc) - timedelta(days=8)).isoformat()
    rows = _supabase_get(
        "dashboard_records",
        {
            "type": "eq.meal",
            "category": "eq.nutrition",
            "created_at": f"gte.{since}",
            "select": "data,created_at",
            "order": "created_at.asc",
        },
    )
    by_day: dict[str, dict[str, float]] = {}
    for r in rows:
        d = r.get("data") or {}
        # Use meal_time when present (user can backfill), else created_at.
        when = d.get("meal_time") or r["created_at"]
        day = str(when)[:10]
        bucket = by_day.setdefault(day, {"date": day, "calories": 0.0, "protein": 0.0, "carbs": 0.0, "fat": 0.0})
        for k in ("calories", "protein", "carbs", "fat"):
            v = d.get(k)
            if isinstance(v, (int, float)):
                bucket[k] += float(v)
    return sorted(by_day.values(), key=lambda x: x["date"])


def _gather_weight() -> list[dict[str, Any]]:
    since = (datetime.now(timezone.utc) - timedelta(days=14)).isoformat()
    rows = _supabase_get(
        "health_metrics",
        {
            "metric": "eq.weight_kg",
            "measured_at": f"gte.{since}",
            "select": "value,measured_at",
            "order": "measured_at.desc",
        },
    )
    return [{"date": r["measured_at"][:10], "kg": float(r["value"])} for r in rows]


def _gather_targets() -> dict[str, float]:
    """Pull current targets from dashboard_records (progress_summary) if any."""
    rows = _supabase_get(
        "dashboard_records",
        {
            "type": "eq.measurement",
            "title": "ilike.*calorie target*",
            "select": "data",
            "order": "created_at.desc",
            "limit": "1",
        },
    )
    if not rows:
        return {}
    d = rows[0].get("data") or {}
    out: dict[str, float] = {}
    for k in ("calories", "protein"):
        v = d.get(k)
        if isinstance(v, (int, float)):
            out[k] = float(v)
    return out


def _gather_all() -> dict[str, Any]:
    """Collect every signal into one dict for the prompt."""
    return {
        "sleep_last_7_days": _gather_sleep(),
        "workouts_last_7_days": _gather_workouts(),
        "nutrition_last_7_days": _gather_nutrition(),
        "weight_recent": _gather_weight(),
        "targets": _gather_targets(),
    }


# ─── LLM call ──────────────────────────────────────────────────────


def _generate_insight(data: dict[str, Any]) -> str:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY not set")
    user_prompt = _build_user_prompt(data)
    body = json.dumps({
        "model": OPENAI_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        "temperature": 0.5,
        "max_tokens": 250,
    }).encode()
    req = Request(
        OPENAI_URL,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    with urlopen(req, timeout=60) as resp:
        payload = json.loads(resp.read())
    return payload["choices"][0]["message"]["content"].strip()


# ─── Persist ───────────────────────────────────────────────────────


def _upsert_insight(body: str, data_summary: dict[str, Any]) -> bool:
    """Idempotent insert: one daily_health insight per user per day.

    Strategy: delete any existing daily_health row for today, then
    insert. (We don't have a unique constraint on (user_id, valid_for_date,
    insight_type) by design — different agents could write same-day
    rows in the future. Delete-then-insert keeps biochecha's specific
    daily row at-most-one for the day.)
    """
    url = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    user = os.environ["PERCH_USER_ID"]
    today = date.today().isoformat()

    # Delete prior row for today.
    qs = (
        f"user_id=eq.{user}&agent_id=eq.biochecha"
        f"&insight_type=eq.daily_health&valid_for_date=eq.{today}"
    )
    del_req = Request(
        f"{url}/rest/v1/insights?{qs}",
        method="DELETE",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Prefer": "return=minimal",
        },
    )
    try:
        with urlopen(del_req, timeout=10) as resp:
            _ = resp.read()
    except HTTPError:
        pass  # not finding any rows → 404; fine

    # Insert the fresh insight.
    payload = {
        "user_id": user,
        "agent_id": "biochecha",
        "insight_type": "daily_health",
        "body": body,
        "valid_for_date": today,
        "data": {
            "model": OPENAI_MODEL,
            "data_window_days": 7,
            "summary_counts": {
                "sleep_nights": len(data_summary.get("sleep_last_7_days") or []),
                "workouts": len(data_summary.get("workouts_last_7_days") or []),
                "nutrition_days": len(data_summary.get("nutrition_last_7_days") or []),
                "weight_readings": len(data_summary.get("weight_recent") or []),
            },
        },
    }
    req = Request(
        f"{url}/rest/v1/insights",
        data=json.dumps(payload).encode(),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
    )
    with urlopen(req, timeout=15) as resp:
        return 200 <= resp.status < 300


# ─── Main ──────────────────────────────────────────────────────────


def main() -> int:
    started = datetime.now(timezone.utc)
    error: str | None = None
    body: str | None = None

    try:
        data = _gather_all()
        body = _generate_insight(data)
        ok = _upsert_insight(body, data)
        if not ok:
            error = "insert returned non-2xx"
    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[biochecha-insight] {error}\n")

    insert_agent_run(
        agent_id="biochecha",
        run_type="daily_insight",
        status="error" if error else "ok",
        summary={"length": len(body) if body else 0, "model": OPENAI_MODEL},
        error_detail=error,
    )
    if error:
        return 1
    print(f"[biochecha-insight] generated ({len(body)} chars)")
    print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
