#!/usr/bin/env python3
"""
BioChecha dynamic insight — generates one of 4 scheduled slots
(morning/midday/afternoon/evening) or an event-driven slot
(event_logistics).

Architecture: gather AppState → score eligible categories → pick
winner → pack fact bundle → LLM writes prose → upsert insights row.

See docs/superpowers/specs/2026-04-28-time-aware-insights-design.md.

Usage:
    python3 biochecha_dynamic_insight.py morning
    python3 biochecha_dynamic_insight.py midday
    python3 biochecha_dynamic_insight.py afternoon
    python3 biochecha_dynamic_insight.py evening
    # event_logistics is invoked via biochecha_event_insight.py wrapper
"""
from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass, field
from datetime import datetime, date, timedelta, timezone
from pathlib import Path
from typing import Any, Optional
from urllib.error import HTTPError
from urllib.request import Request, urlopen

# Importing _supabase_client triggers env auto-load (perch.env, etc.)
sys.path.insert(0, str(Path(__file__).parent))
from _supabase_client import insert_agent_run  # noqa: E402

OPENAI_URL = "https://api.openai.com/v1/chat/completions"
OPENAI_MODEL = os.environ.get("OPENAI_INSIGHT_MODEL", "gpt-4o-mini")

VALID_SLOTS = {"morning", "midday", "afternoon", "evening", "event_logistics"}


# ─── Types ──────────────────────────────────────────────────────────


@dataclass(frozen=True)
class Meal:
    calories: float
    protein: float
    carbs: float
    fat: float
    meal_time: datetime


@dataclass(frozen=True)
class NutritionTargets:
    calories: float
    protein: float
    carbs: float
    fat: float


@dataclass(frozen=True)
class CalendarEvent:
    start: datetime
    end: datetime
    title: str


@dataclass(frozen=True)
class SleepNight:
    date: str  # YYYY-MM-DD
    duration_min: Optional[float] = None
    score: Optional[float] = None
    hrv: Optional[float] = None
    rhr: Optional[float] = None


@dataclass(frozen=True)
class BodyComp:
    date: str
    weight_kg: Optional[float] = None
    body_fat_pct: Optional[float] = None
    fat_mass_kg: Optional[float] = None
    muscle_mass_kg: Optional[float] = None


@dataclass(frozen=True)
class OrderSummary:
    merchant: str
    order_number: str
    carrier: Optional[str]
    tracking_number: Optional[str]
    eta_at: Optional[datetime]
    status: str


@dataclass(frozen=True)
class EventTrigger:
    """Populated only when slot == 'event_logistics'. Source of the event."""
    kind: str  # 'out_for_delivery' | 'eta_today'
    merchant: str
    carrier: Optional[str]
    tracking_number: Optional[str]
    old_status: Optional[str]
    new_status: Optional[str]
    eta_at: Optional[datetime]


WorkoutKind = str  # 'rest' | 'light' | 'training' | 'unknown'


@dataclass(frozen=True)
class AppState:
    """Snapshot of the user's relevant state at insight-generation time.

    Built once per slot run by gather_state(slot). All categories
    receive the SAME state — they read what they need.
    """
    slot: str
    now: datetime
    today_meals: list[Meal]
    today_targets: NutritionTargets
    today_calendar_remaining: list[CalendarEvent]
    today_orders_in_transit: list[OrderSummary]
    sleep_last_7: list[SleepNight]
    body_comp_last_30: list[BodyComp]
    workout_schedule_today: WorkoutKind
    avg_steps_last_7_at_this_hour: int
    event_trigger: Optional[EventTrigger] = None
    recent_feedback: list[str] = field(default_factory=list)


# ─── Category scoring contract ──────────────────────────────────────


@dataclass(frozen=True)
class CategoryResult:
    category: str          # name (also used for tie-break priority)
    score: float           # 0-1
    fact_bundle: dict[str, Any]   # the LLM's input data — what TO say


# ─── Supabase HTTP helper ───────────────────────────────────────────


def _supabase_get(path: str, params: dict[str, str]) -> list[dict[str, Any]]:
    """GET against PostgREST scoped to the perch user. Stdlib only."""
    url = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    user = os.environ["PERCH_USER_ID"]
    import urllib.parse as _up
    qs = "&".join(f"{k}={_up.quote(str(v), safe='*.,()')}" for k, v in params.items())
    qs += f"&user_id=eq.{user}"
    req = Request(
        f"{url}/rest/v1/{path}?{qs}",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Accept": "application/json",
        },
    )
    try:
        with urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except HTTPError as e:
        body_text = e.read().decode(errors="replace")[:300]
        raise RuntimeError(
            f"Supabase GET {path}?{qs[:80]} HTTP {e.code}: {body_text}"
        ) from None


# ─── State gathering ────────────────────────────────────────────────


def _gather_sleep_last_7() -> list[SleepNight]:
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
        m, v = r["metric"], float(r["value"])
        if m == "sleep_duration_min":     d["duration_min"] = v
        elif m == "sleep_score":          d["score"] = v
        elif m == "hrv_rmssd_ms":         d["hrv"] = v
        elif m == "resting_heart_rate_bpm": d["rhr"] = v
    return [SleepNight(**d) for d in sorted(by_day.values(), key=lambda x: x["date"])]


def _gather_today_meals() -> list[Meal]:
    today_start = datetime.now(timezone.utc).replace(hour=0, minute=0, second=0, microsecond=0)
    rows = _supabase_get(
        "dashboard_records",
        {
            "type": "eq.meal",
            "category": "eq.nutrition",
            "created_at": f"gte.{today_start.isoformat()}",
            "select": "data,created_at",
            "order": "created_at.asc",
        },
    )
    out: list[Meal] = []
    for r in rows:
        d = r.get("data") or {}
        when = d.get("meal_time") or r["created_at"]
        try:
            mt = datetime.fromisoformat(str(when).replace("Z", "+00:00"))
        except Exception:
            continue
        out.append(Meal(
            calories=float(d.get("calories") or 0),
            protein=float(d.get("protein") or 0),
            carbs=float(d.get("carbs") or 0),
            fat=float(d.get("fat") or 0),
            meal_time=mt,
        ))
    return out


def _gather_targets() -> NutritionTargets:
    """Read today's progress_summary for target macros. Falls back to
    a sensible default if no progress_summary exists yet (e.g. first
    install)."""
    rows = _supabase_get(
        "dashboard_records",
        {
            "type": "eq.progress_summary",
            "category": "eq.nutrition",
            "select": "data",
            "order": "created_at.desc",
            "limit": "1",
        },
    )
    if rows:
        d = rows[0].get("data") or {}
        targets = d.get("targets") or {}
        if targets:
            return NutritionTargets(
                calories=float(targets.get("calories") or 2500),
                protein=float(targets.get("protein") or 180),
                carbs=float(targets.get("carbs") or 280),
                fat=float(targets.get("fat") or 80),
            )
    return NutritionTargets(calories=2500, protein=180, carbs=280, fat=80)


def _gather_today_calendar() -> list[CalendarEvent]:
    """Calendar events for the rest of today.

    Source: dashboard_records with category='calendar', populated by
    calendar_sync.py. EventKit-backed iOS data isn't pushed to Supabase —
    only agent-fed entries land here. If the user has only EventKit
    calendar (or no Calendar permission yet), this returns [] and
    opportunity/anticipatory categories degrade to 0 score.
    """
    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    rows = _supabase_get(
        "dashboard_records",
        {
            "category": "eq.calendar",
            "type": "eq.event",
            "created_at": f"gte.{today_start.isoformat()}",
            "select": "title,data,created_at",
            "order": "created_at.asc",
        },
    )
    out: list[CalendarEvent] = []
    for r in rows:
        d = r.get("data") or {}
        try:
            start = datetime.fromisoformat(str(d.get("start_at") or r["created_at"]).replace("Z", "+00:00"))
        except Exception:
            continue
        if start < now:
            continue
        try:
            end = datetime.fromisoformat(str(d.get("end_at") or "").replace("Z", "+00:00"))
        except Exception:
            end = start + timedelta(minutes=int(d.get("duration_min") or 30))
        out.append(CalendarEvent(start=start, end=end, title=str(r.get("title") or "Event")))
    return out


def _gather_orders_in_transit() -> list[OrderSummary]:
    """Active shipments — not delivered, has tracking."""
    rows = _supabase_get(
        "orders",
        {
            "status": "neq.delivered",
            "select": "merchant_name,order_number,manual_delivered_at,shipments(carrier,tracking_number,eta_at,delivered_at,status)",
            "limit": "20",
        },
    )
    out: list[OrderSummary] = []
    for r in rows:
        if r.get("manual_delivered_at"):
            continue
        for s in (r.get("shipments") or []):
            if s.get("delivered_at"):
                continue
            try:
                eta = datetime.fromisoformat(str(s.get("eta_at") or "").replace("Z", "+00:00")) if s.get("eta_at") else None
            except Exception:
                eta = None
            out.append(OrderSummary(
                merchant=str(r.get("merchant_name") or "?"),
                order_number=str(r.get("order_number") or ""),
                carrier=s.get("carrier"),
                tracking_number=s.get("tracking_number"),
                eta_at=eta,
                status=str(s.get("status") or "unknown"),
            ))
    return out


def _gather_body_comp_last_30() -> list[BodyComp]:
    since = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    rows = _supabase_get(
        "health_metrics",
        {
            "metric": "in.(weight_kg,body_fat_pct,fat_mass_kg,muscle_mass_kg)",
            "measured_at": f"gte.{since}",
            "select": "metric,value,measured_at",
            "order": "measured_at.asc",
        },
    )
    by_day: dict[str, dict[str, Any]] = {}
    for r in rows:
        day = r["measured_at"][:10]
        d = by_day.setdefault(day, {"date": day})
        d[r["metric"]] = float(r["value"])
    return sorted(
        [BodyComp(**d) for d in by_day.values()],
        key=lambda b: b.date,
    )


def _classify_workout_today(calendar: list[CalendarEvent]) -> WorkoutKind:
    """Best-effort: scan today's calendar titles for workout cues."""
    if not calendar:
        return "unknown"
    text = " ".join(e.title.lower() for e in calendar)
    training_cues = ("gym", "lift", "training", "push day", "pull day",
                     "leg day", "weights", "crossfit", "deadlift", "squat")
    light_cues = ("yoga", "pilates", "mobility", "stretch", "walk", "recovery",
                  "swim", "run easy", "z2")
    if any(c in text for c in training_cues):
        return "training"
    if any(c in text for c in light_cues):
        return "light"
    return "rest"


def _gather_recent_feedback(limit: int = 5) -> list[str]:
    """Up to `limit` most-recent feedback reactions, freshest first.
    Used as few-shot guidance for the LLM. Returns [] if the table
    doesn't exist yet (Phase 5 hasn't shipped) — silent fail."""
    try:
        rows = _supabase_get(
            "insight_feedback",
            {
                "select": "reaction,created_at",
                "order": "created_at.desc",
                "limit": str(limit),
            },
        )
        return [r["reaction"] for r in rows if r.get("reaction")]
    except Exception:
        return []  # table doesn't exist (pre-Phase 5) — fine


def gather_state(slot: str, event_trigger: Optional[EventTrigger] = None) -> AppState:
    """Gather everything categories might need. Single round of queries."""
    calendar = _gather_today_calendar()
    return AppState(
        slot=slot,
        now=datetime.now(timezone.utc),
        today_meals=_gather_today_meals(),
        today_targets=_gather_targets(),
        today_calendar_remaining=calendar,
        today_orders_in_transit=_gather_orders_in_transit(),
        sleep_last_7=_gather_sleep_last_7(),
        body_comp_last_30=_gather_body_comp_last_30(),
        workout_schedule_today=_classify_workout_today(calendar),
        avg_steps_last_7_at_this_hour=0,
        event_trigger=event_trigger,
        recent_feedback=_gather_recent_feedback(limit=5),
    )


# ─── Ranker ─────────────────────────────────────────────────────────


CATEGORY_PRIORITY: dict[str, int] = {
    "logistics_event_out_for_delivery": 100,
    "logistics_event_eta_today": 99,
    "logistics_arriving_today": 80,
    "opportunistic_walk": 70,
    "opportunistic_workout": 69,
    "anticipatory_lunch_window": 60,
    "anticipatory_broad": 59,
    "anticipatory_tomorrow": 58,
    "goal_pacing_protein": 50,
    "goal_pacing_calories": 49,
    "goal_pacing_steps": 48,
    "anomaly_recent_pattern": 40,
    "behavioral_capture_gap": 30,
    "recap_day": 20,
    "reflective_morning": 10,
    "reflective_evening": 9,
    "quiet_day_fallback": 0,
}

QUIET_THRESHOLD = 0.3


def rank(results: list[CategoryResult]) -> CategoryResult:
    """Highest-scoring CategoryResult; ties broken by static priority.
    Falls back to quiet_day if everything is below QUIET_THRESHOLD."""
    best = max(
        results,
        key=lambda r: (r.score, CATEGORY_PRIORITY.get(r.category, 0)),
        default=None,
    )
    if best is None or best.score < QUIET_THRESHOLD:
        return CategoryResult(
            category="quiet_day_fallback",
            score=0.0,
            fact_bundle={
                "reason": "no category cleared the QUIET_THRESHOLD",
                "highest_other": best.category if best else None,
                "highest_other_score": best.score if best else None,
            },
        )
    return best


# ─── Categories ─────────────────────────────────────────────────────


def score_reflective_morning(state: AppState) -> Optional[CategoryResult]:
    """Always-eligible morning fallback. Baseline 0.5; signals add."""
    if state.slot != "morning":
        return None

    score = 0.5
    facts: dict[str, Any] = {"summary": "morning reflection"}

    if state.sleep_last_7:
        threshold_min = 6 * 60
        streak = 0
        for night in reversed(state.sleep_last_7):
            if night.duration_min is not None and night.duration_min < threshold_min:
                streak += 1
            else:
                break
        if streak >= 3:
            score += 0.2
            facts["short_night_streak"] = streak
            facts["recent_durations_min"] = [
                int(n.duration_min) for n in state.sleep_last_7[-streak:] if n.duration_min
            ]

    hrv_values = [n.hrv for n in state.sleep_last_7 if n.hrv is not None]
    if len(hrv_values) >= 5:
        trailing = hrv_values[-5:]
        if all(trailing[i] >= trailing[i - 1] for i in range(1, len(trailing))):
            score += 0.1
            facts["hrv_climbing_days"] = 5
            facts["hrv_recent"] = [round(v, 1) for v in trailing]

    if state.sleep_last_7:
        last = state.sleep_last_7[-1]
        facts["last_night"] = {
            "duration_min": last.duration_min,
            "score": last.score,
            "hrv": last.hrv,
            "rhr": last.rhr,
        }

    return CategoryResult(
        category="reflective_morning",
        score=min(score, 1.0),
        fact_bundle=facts,
    )


# ─── Voice prompts ──────────────────────────────────────────────────


SYSTEM_PROMPT = """You are BioChecha, the user's AI health & nutrition coach.

Write today's insight: a single tight paragraph (30-55 words, MAX 60) that
surfaces ONE useful thing from what the data shows.

VOICE: read like a smart friend texting a heads-up. Not a coach, not a
doctor, not an AI assistant. Carry about 20% snark — dry, observational,
occasionally self-aware. Not jokey, not cute, never an exclamation.
Earned snark only — when the data actually warrants noticing.

  ✅ "Sleep collapsed last night while body fat's been creeping. Protein's
      the missing lever. The pattern's been there a while."
  ✅ "HRV's the lowest in a week, second night sub-fifteen. Body's finally
      got something to say about the load."
  ✅ "Protein fell short today after clearing target all week. One off-day
      isn't a streak — but two would be."

PREFER COMPARATIVE OVER ABSOLUTE NUMBERS.
The user already knows their numbers. Tell them what changed in plain
language.
  ✅ "Sleep dropped to less than half what you usually pull."
  ❌ "Sleep dropped to 190 minutes — well below your typical 436-498."

MIX DOMAINS. Don't write a sleep-only or HRV-only insight. The
interesting things live at intersections (sleep+nutrition, HRV+workout,
weight+protein). Single-domain only if there's truly nothing else moving.

ABSOLUTELY AVOID:
  ❌ "indicating", "suggesting", "hinting", "reflecting" — hedge verbs
  ❌ "consider taking", "you should", "remember to" — coachy / preachy
  ❌ "rollercoaster", "yo-yo", "all over the place" — cliché metaphors
  ❌ Reciting raw numbers when comparison would carry the meaning
  ❌ The word "recharge". The word "recalibrate".
  ❌ Exclamation points. Cuteness. Emoji. "Pro tip" / "Fun fact".
  ❌ Any phrase a friend wouldn't actually text you

Output ONLY the insight. No greeting, no signoff, no metadata. ONE
paragraph. No bullets. No headers. No emoji. 30-55 words, hard 60 max."""


SLOT_PROMPT_ADDENDUM: dict[str, str] = {
    "morning": (
        "This is the MORNING slot — reflect on overnight + recent. "
        "Frame what's coming today gently, not as instruction."
    ),
    "midday": (
        "This is the MIDDAY slot — what's worth noticing now, before "
        "the afternoon. Anticipatory > retrospective."
    ),
    "afternoon": (
        "This is the AFTERNOON slot — pick the most pressing thing right "
        "now (gap, opportunity, package, pacing). Direct, present-tense."
    ),
    "evening": (
        "This is the EVENING slot — recap the day in 30 words. Tomorrow's "
        "setup if useful. No exclamation, no 'you did great'."
    ),
    "event_logistics": (
        "This is an EVENT slot — lead with the event. The fact is the "
        "headline. One line, maybe two."
    ),
}


# ─── LLM + persist ──────────────────────────────────────────────────


def _build_user_prompt(slot: str, fact_bundle: dict[str, Any], recent_feedback: Optional[list[str]] = None) -> str:
    today = date.today()
    parts = [
        f"Today: {today.isoformat()} ({today.strftime('%A')})",
        f"Slot: {slot}",
        SLOT_PROMPT_ADDENDUM[slot],
    ]
    if recent_feedback:
        parts.append("")
        parts.append("RECENT USER FEEDBACK on past insights (correct course accordingly):")
        for r in recent_feedback[:5]:
            parts.append(f"  - {r[:300]}")
    parts += [
        "",
        "FACTS (real numbers from your data — write the insight from these):",
        json.dumps(fact_bundle, indent=2, default=str),
        "",
        "Write the insight (30-55 words, single paragraph, no preamble).",
    ]
    return "\n".join(parts)


def _generate_insight(slot: str, fact_bundle: dict[str, Any], recent_feedback: Optional[list[str]] = None) -> str:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY not set")
    body = json.dumps({
        "model": OPENAI_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": _build_user_prompt(slot, fact_bundle, recent_feedback)},
        ],
        "temperature": 0.8,
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


def _upsert_insight(slot: str, body: str, winner: CategoryResult) -> bool:
    """Insert (or replace today's row of the same insight_type)."""
    url = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    user = os.environ["PERCH_USER_ID"]
    today = date.today().isoformat()
    insight_type = (
        "event_logistics" if slot == "event_logistics"
        else f"daily_health_{slot}"
    )

    qs = (
        f"user_id=eq.{user}&agent_id=eq.biochecha"
        f"&insight_type=eq.{insight_type}&valid_for_date=eq.{today}"
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
        pass

    payload = {
        "user_id": user,
        "agent_id": "biochecha",
        "insight_type": insight_type,
        "body": body,
        "valid_for_date": today,
        "data": {
            "model": OPENAI_MODEL,
            "slot": slot,
            "winning_category": winner.category,
            "winning_score": winner.score,
            "fact_bundle": winner.fact_bundle,
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


def _fetch_most_recent_today_insight() -> Optional[dict[str, Any]]:
    """Return the most-recent insight row from today (any insight_type
    starting with daily_health_ OR event_logistics). None when empty."""
    today = date.today().isoformat()
    rows = _supabase_get(
        "insights",
        {
            "agent_id": "eq.biochecha",
            "valid_for_date": f"eq.{today}",
            "select": "data,generated_at",
            "order": "generated_at.desc",
            "limit": "1",
        },
    )
    if not rows:
        return None
    out = rows[0].get("data") or {}
    out["_generated_at"] = rows[0].get("generated_at")
    return out


# ─── Main ───────────────────────────────────────────────────────────


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in VALID_SLOTS:
        sys.stderr.write(f"usage: {sys.argv[0]} <{'|'.join(sorted(VALID_SLOTS))}>\n")
        return 2
    slot = sys.argv[1]

    started = datetime.now(timezone.utc)
    error: Optional[str] = None
    body: Optional[str] = None
    try:
        state = gather_state(slot)

        candidates: list[CategoryResult] = []
        SLOT_CATEGORY_FNS: dict[str, list] = {
            "morning": [score_reflective_morning],
            "midday": [],
            "afternoon": [],
            "evening": [],
            "event_logistics": [],
        }
        for fn in SLOT_CATEGORY_FNS.get(state.slot, []):
            r = fn(state)
            if r is not None:
                candidates.append(r)

        winner = rank(candidates) if candidates else CategoryResult(
            category="quiet_day_fallback", score=0.0,
            fact_bundle={"reason": "no eligible category for this slot"},
        )
        body = _generate_insight(slot, winner.fact_bundle, recent_feedback=state.recent_feedback)
        ok = _upsert_insight(slot, body, winner)
        if not ok:
            error = "insert returned non-2xx"
    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[biochecha-dynamic:{slot}] {error}\n")

    insert_agent_run(
        agent_id="biochecha",
        run_type=f"dynamic_insight_{slot}",
        status="error" if error else "ok",
        summary={"length": len(body) if body else 0, "model": OPENAI_MODEL, "slot": slot},
        error_detail=error,
    )
    if error:
        return 1
    print(f"[biochecha-dynamic:{slot}] generated ({len(body)} chars)")
    print(body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
