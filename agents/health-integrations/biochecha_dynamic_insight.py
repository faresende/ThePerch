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

VALID_SLOTS = {
    "morning",            # 7am cron — pre-wake, forward-looking only
    "morning_post_wake",  # event-fired by inbody_ingest watcher — sleep + body comp + plan
    "midday",
    "afternoon",
    "evening",
    "event_logistics",
}


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


# ─── Source-of-truth precedence ─────────────────────────────────────
#
# When the same metric is written by multiple sources for the same
# day, the higher-priority source wins. Lower-priority sources fill
# gaps where the primary is silent.
#
# Sleep:  Oura > 8sleep      (Oura ingest TBD; code is ready for it)
# Body:   InBody > Withings  (InBody is the H30 CSV path; Withings is
#                              the smart-scale fallback for body-comp)
SLEEP_SOURCE_PRIORITY = ("oura", "8sleep")
BODY_COMP_SOURCE_PRIORITY = ("inbody", "withings")


def _pick_by_priority(
    rows: list[dict[str, Any]],
    priority: tuple[str, ...],
) -> dict[tuple[str, str], dict[str, Any]]:
    """Group rows by (day, metric) and keep the highest-priority source.
    Returns a dict keyed by (YYYY-MM-DD, metric) → row.

    `rows` must include `source`, `metric`, `value`, `measured_at`.
    Within a single source, ties on (day, metric) keep the latest by
    `measured_at` (caller orders the query that way)."""
    rank = {src: i for i, src in enumerate(priority)}
    chosen: dict[tuple[str, str], dict[str, Any]] = {}
    for r in rows:
        day = r["measured_at"][:10]
        metric = r["metric"]
        src = r.get("source") or ""
        # Sources outside the priority list are tolerated but rank
        # last, so an unexpected source still gets surfaced when it's
        # the only data point.
        new_rank = rank.get(src, len(priority))
        key = (day, metric)
        if key not in chosen:
            chosen[key] = r
            continue
        prev = chosen[key]
        prev_rank = rank.get(prev.get("source") or "", len(priority))
        if new_rank < prev_rank:
            chosen[key] = r            # higher-priority source wins
        elif new_rank == prev_rank and r["measured_at"] > prev["measured_at"]:
            chosen[key] = r            # same source, newer reading
    return chosen


def _gather_sleep_last_7() -> list[SleepNight]:
    """Sleep over the last 7 days with source-of-truth precedence
    AND session-aware aggregation.

    A single day can have multiple sleep sessions (a main night plus
    a nap, or a fragmented night the tracker split in two). Naive
    "latest measured_at wins" picks the nap, polluting the trailing
    average with a 30-min reading.

    Resolution order per (day, source):
      1. Pick the MAIN session — the one with the longest
         `sleep_duration_min`. That session's bedtime_end becomes the
         canonical measured_at for the day.
      2. Carry every metric from THAT session (duration, HRV, RHR,
         score) so HRV/RHR aren't mixed across sessions.
    Then apply SLEEP_SOURCE_PRIORITY across the surviving (day, source)
    rows.

    Within Oura specifically, every metric in one session shares the
    same `measured_at` (= bedtime_end). 8sleep follows the same pattern.
    So filtering rows by "matches the main-session measured_at" is
    equivalent to "rows from the main session"."""
    since = (datetime.now(timezone.utc) - timedelta(days=8)).isoformat()
    rows = _supabase_get(
        "health_metrics",
        {
            "metric": "in.(sleep_duration_min,sleep_score,hrv_rmssd_ms,resting_heart_rate_bpm)",
            "measured_at": f"gte.{since}",
            "select": "metric,value,measured_at,source",
            "order": "measured_at.asc",
        },
    )

    # 1. Identify the main session per (day, source) by largest duration.
    main_session_at: dict[tuple[str, str], str] = {}
    for r in rows:
        if r["metric"] != "sleep_duration_min":
            continue
        key = (r["measured_at"][:10], r.get("source") or "")
        prev_at = main_session_at.get(key)
        if prev_at is None:
            main_session_at[key] = r["measured_at"]
        else:
            # Find the row with larger value among the candidates.
            prev_row = next(
                (x for x in rows
                 if x["metric"] == "sleep_duration_min"
                 and x["measured_at"] == prev_at
                 and (x.get("source") or "") == key[1]),
                None,
            )
            if prev_row is None or float(r["value"]) > float(prev_row["value"]):
                main_session_at[key] = r["measured_at"]

    # 2. Filter to rows that came from the main session of their (day,source).
    # Daily-grain metrics (sleep_score, etc.) live at their own measured_at
    # (Oura emits them at 23:59 of the day) — they're not session-bound, so
    # they pass through untouched. Only session-bound metrics get filtered.
    SESSION_METRICS = {"sleep_duration_min", "hrv_rmssd_ms", "resting_heart_rate_bpm"}
    main_rows = []
    for r in rows:
        if r["metric"] not in SESSION_METRICS:
            main_rows.append(r)
            continue
        if main_session_at.get(
            (r["measured_at"][:10], r.get("source") or "")
        ) == r["measured_at"]:
            main_rows.append(r)

    # 3. Apply source priority over the cleaned rows.
    chosen = _pick_by_priority(main_rows, SLEEP_SOURCE_PRIORITY)

    by_day: dict[str, dict[str, Any]] = {}
    for (day, metric), r in chosen.items():
        d = by_day.setdefault(day, {"date": day})
        v = float(r["value"])
        if metric == "sleep_duration_min":     d["duration_min"] = v
        elif metric == "sleep_score":          d["score"] = v
        elif metric == "hrv_rmssd_ms":         d["hrv"] = v
        elif metric == "resting_heart_rate_bpm": d["rhr"] = v
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
    """Last 30 days of body composition with source-of-truth precedence.
    InBody (CSV-fed) wins where available; Withings (smart-scale)
    fills in for any day InBody is silent. The same metric on the
    same day from both sources collapses to the higher-priority one
    so the trailing-average math doesn't double-count a single weigh-in."""
    since = (datetime.now(timezone.utc) - timedelta(days=30)).isoformat()
    rows = _supabase_get(
        "health_metrics",
        {
            "metric": "in.(weight_kg,body_fat_pct,fat_mass_kg,muscle_mass_kg)",
            "measured_at": f"gte.{since}",
            "select": "metric,value,measured_at,source",
            "order": "measured_at.asc",
        },
    )
    chosen = _pick_by_priority(rows, BODY_COMP_SOURCE_PRIORITY)
    by_day: dict[str, dict[str, Any]] = {}
    for (day, metric), r in chosen.items():
        d = by_day.setdefault(day, {"date": day})
        d[metric] = float(r["value"])
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
    """Always-eligible morning fallback. Baseline 0.5; signals add.
    Runs in the post-wake slot (where sleep/HRV data is fresh) — NOT
    in the 7am pre-wake slot, where retrospection on stale data is
    actively misleading."""
    if state.slot != "morning_post_wake":
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


# ─── Midday categories ──────────────────────────────────────────────


def score_anticipatory_lunch_window(state: AppState) -> Optional[CategoryResult]:
    """Midday slot. Fires when calendar's busy in next 4h AND today's
    calories are <40% of target AND it's still before 14:00 local."""
    if state.slot != "midday":
        return None
    if state.now.hour >= 14:
        return None
    end_window = state.now + timedelta(hours=4)
    events_in_window = [e for e in state.today_calendar_remaining
                        if state.now <= e.start <= end_window]
    if len(events_in_window) < 2:
        return None
    consumed_cal = sum(m.calories for m in state.today_meals)
    target_cal = state.today_targets.calories
    if target_cal <= 0:
        return None
    cal_ratio = consumed_cal / target_cal
    if cal_ratio >= 0.4:
        return None  # not enough deficit to call out
    score = 0.7 + min(0.3, (0.4 - cal_ratio) * 1.0)  # bigger deficit → higher score
    return CategoryResult(
        category="anticipatory_lunch_window",
        score=min(score, 1.0),
        fact_bundle={
            "events_in_next_4h": len(events_in_window),
            "first_event_title": events_in_window[0].title,
            "first_event_starts_in_min": int(
                (events_in_window[0].start - state.now).total_seconds() / 60
            ),
            "consumed_calories": int(consumed_cal),
            "target_calories": int(target_cal),
            "calories_pct": round(cal_ratio * 100, 1),
            "consumed_protein": round(sum(m.protein for m in state.today_meals), 1),
            "target_protein": int(state.today_targets.protein),
        },
    )


def score_goal_pacing_protein(state: AppState) -> Optional[CategoryResult]:
    """Midday/afternoon. Score = min(1, deficit_ratio). Returns a low-score
    result when on-track to keep it from surfacing as a winner."""
    if state.slot not in ("midday", "afternoon"):
        return None
    consumed = sum(m.protein for m in state.today_meals)
    target = state.today_targets.protein
    if target <= 0:
        return None
    deficit_ratio = max(0.0, (target - consumed) / target)
    if deficit_ratio < 0.4:
        # Within reach by end of day — not worth surfacing.
        return CategoryResult(
            category="goal_pacing_protein",
            score=deficit_ratio * 0.5,
            fact_bundle={"on_track": True, "consumed": round(consumed, 1), "target": int(target)},
        )
    score = 0.5 + (deficit_ratio - 0.4) * 0.7  # 0.4-1.0 deficit → 0.5-0.92 score
    return CategoryResult(
        category="goal_pacing_protein",
        score=min(score, 1.0),
        fact_bundle={
            "consumed_protein": round(consumed, 1),
            "target_protein": int(target),
            "deficit_g": int(target - consumed),
            "meals_logged_today": len(state.today_meals),
        },
    )


def score_logistics_arriving_today(state: AppState) -> Optional[CategoryResult]:
    """Midday/afternoon. Fires when ≥1 shipment has ETA today + not delivered."""
    if state.slot not in ("midday", "afternoon"):
        return None
    today = state.now.date()
    arriving_today = [
        o for o in state.today_orders_in_transit
        if o.eta_at is not None and o.eta_at.date() == today
    ]
    if not arriving_today:
        return None
    return CategoryResult(
        category="logistics_arriving_today",
        score=0.85 if len(arriving_today) == 1 else 0.92,
        fact_bundle={
            "arriving": [
                {
                    "merchant": o.merchant,
                    "carrier": o.carrier,
                    "eta_iso": o.eta_at.isoformat() if o.eta_at else None,
                    "status": o.status,
                }
                for o in arriving_today
            ],
            "count": len(arriving_today),
        },
    )


# ─── Afternoon categories ───────────────────────────────────────────


def score_opportunistic_walk(state: AppState) -> Optional[CategoryResult]:
    """Afternoon. Fires on rest/light day + ≥45min gap before next event."""
    if state.slot != "afternoon":
        return None
    if state.workout_schedule_today not in ("rest", "light"):
        return None
    upcoming = [e for e in state.today_calendar_remaining if e.start > state.now]
    next_event = upcoming[0] if upcoming else None
    if next_event:
        gap_min = int((next_event.start - state.now).total_seconds() / 60)
    else:
        gap_min = 240  # treat "free rest of day" as plenty of room
    if gap_min < 45:
        return None
    score = 0.6 + min(0.35, gap_min / 300)  # bigger gap → slightly higher
    return CategoryResult(
        category="opportunistic_walk",
        score=min(score, 1.0),
        fact_bundle={
            "gap_min": gap_min,
            "workout_schedule": state.workout_schedule_today,
            "next_event_title": next_event.title if next_event else None,
            "next_event_starts_at": next_event.start.isoformat() if next_event else None,
        },
    )


def score_opportunistic_workout(state: AppState) -> Optional[CategoryResult]:
    """Afternoon. Fires when today is a training day with a meaningful
    calendar gap. Encourages doing the scheduled workout if it hasn't
    happened yet."""
    if state.slot != "afternoon":
        return None
    if state.workout_schedule_today not in ("training",):
        return None
    upcoming = [e for e in state.today_calendar_remaining if e.start > state.now]
    if not upcoming:
        return None
    gap_min = int((upcoming[0].start - state.now).total_seconds() / 60)
    if gap_min < 75:
        return None  # not enough for a session
    return CategoryResult(
        category="opportunistic_workout",
        score=0.7,
        fact_bundle={
            "gap_min": gap_min,
            "next_event_title": upcoming[0].title,
            "next_event_starts_at": upcoming[0].start.isoformat(),
        },
    )


def score_goal_pacing_calories(state: AppState) -> Optional[CategoryResult]:
    """Midday/afternoon. Surfaces when consumed calories are
    >120% of target proportional-to-time-of-day OR <70% by mid-afternoon."""
    if state.slot not in ("midday", "afternoon"):
        return None
    consumed = sum(m.calories for m in state.today_meals)
    target = state.today_targets.calories
    if target <= 0:
        return None
    # Proportional target: assume even distribution across 16 waking hours
    waking_hours_so_far = max(1, state.now.hour - 6)
    expected = target * (waking_hours_so_far / 16)
    ratio = consumed / max(1, expected)
    if 0.7 <= ratio <= 1.2:
        return None  # in normal band
    score = min(0.9, abs(ratio - 1.0) * 0.8)
    return CategoryResult(
        category="goal_pacing_calories",
        score=score,
        fact_bundle={
            "consumed": int(consumed),
            "expected_by_now": int(expected),
            "target_today": int(target),
            "direction": "ahead" if ratio > 1.2 else "behind",
        },
    )


def score_goal_pacing_steps(state: AppState) -> Optional[CategoryResult]:
    """Stub for v1 — no step source ingested yet. Returns None.
    Wired into ranker so categories list is complete; will activate
    when avg_steps_last_7_at_this_hour > 0."""
    if state.avg_steps_last_7_at_this_hour <= 0:
        return None
    # Placeholder shape if/when steps land:
    return None  # no actual signal source in v1


def score_anomaly_recent_pattern(state: AppState) -> Optional[CategoryResult]:
    """Cross-slot. Detects multi-day deviations: short-night streak,
    HRV trending, recent dietary shifts."""
    facts: dict[str, Any] = {}
    score = 0.0

    # Short-night streak (also looked at by reflective_morning, but
    # this surfaces it in midday/afternoon/evening too).
    if state.sleep_last_7:
        threshold_min = 6 * 60
        streak = 0
        for night in reversed(state.sleep_last_7):
            if night.duration_min is not None and night.duration_min < threshold_min:
                streak += 1
            else:
                break
        if streak >= 3:
            score = max(score, 0.6 + min(0.3, (streak - 3) * 0.1))
            facts["pattern"] = "short_night_streak"
            facts["streak_days"] = streak

    if score <= 0:
        return None
    return CategoryResult(
        category="anomaly_recent_pattern",
        score=min(score, 1.0),
        fact_bundle=facts,
    )


# ─── Evening categories ─────────────────────────────────────────────


def score_recap_day(state: AppState) -> Optional[CategoryResult]:
    """Evening only. Always 1.0 — the slot's purpose is recap."""
    if state.slot != "evening":
        return None
    consumed_cal = int(sum(m.calories for m in state.today_meals))
    consumed_prot = round(sum(m.protein for m in state.today_meals), 1)
    return CategoryResult(
        category="recap_day",
        score=1.0,
        fact_bundle={
            "meals_logged": len(state.today_meals),
            "consumed_calories": consumed_cal,
            "target_calories": int(state.today_targets.calories),
            "consumed_protein": consumed_prot,
            "target_protein": int(state.today_targets.protein),
            "workout_today": state.workout_schedule_today,
            "events_today": len(state.today_calendar_remaining),
            "shipments_active": len(state.today_orders_in_transit),
        },
    )


def score_anticipatory_tomorrow(state: AppState) -> Optional[CategoryResult]:
    """Evening only — looks at tomorrow's load. Stub returns None
    until tomorrow-fetch lands. Intentional: keep evening focused
    on recap_day in v1; tomorrow-anticipation is a Phase 2 nice-to-have."""
    if state.slot != "evening":
        return None
    return None


def score_reflective_evening(state: AppState) -> Optional[CategoryResult]:
    """Evening only — analogous to reflective_morning but rear-facing.
    Lower baseline because recap_day is the primary evening surface."""
    if state.slot != "evening":
        return None
    return CategoryResult(
        category="reflective_evening",
        score=0.4,  # below recap_day's 1.0; secondary fallback
        fact_bundle={"summary": "evening reflection"},
    )


def score_behavioral_capture_gap(state: AppState) -> Optional[CategoryResult]:
    """Any slot. Fires when no meals logged today AND it's past
    midday — strongly suggests capture pipeline broken."""
    today_count = len(state.today_meals)
    hours_into_day = state.now.hour
    if today_count > 0 or hours_into_day < 12:
        return None
    score = 0.4 + min(0.4, (hours_into_day - 12) * 0.1)
    return CategoryResult(
        category="behavioral_capture_gap",
        score=min(score, 1.0),
        fact_bundle={
            "today_meal_count": 0,
            "hours_since_last": None,  # Phase 2 if we want yesterday's last
            "current_hour": hours_into_day,
        },
    )


# ─── Forward-looking morning categories ─────────────────────────────


def score_anticipatory_today_training(state: AppState) -> Optional[CategoryResult]:
    """Pre-wake MORNING slot. Surfaces today's workout context against
    the calendar so the user can plan around it. Fires when there's
    a training day ahead AND a meaningful gap exists (or doesn't)."""
    if state.slot != "morning":
        return None

    workout = state.workout_schedule_today  # 'training' | 'light' | 'rest' | 'unknown'
    cal = state.today_calendar_remaining

    # Pre-wake: calendar windows we care about are the whole day, not "remaining"
    today_meeting_minutes = sum(
        max(0, int((e.end - e.start).total_seconds() / 60))
        for e in cal
    )
    meeting_count = len(cal)

    # Score: training days + heavy calendar = high value (need to plan).
    # Rest days + heavy calendar = medium (still useful to flag the load).
    # Unknown workout + light calendar = low (not enough signal).
    if workout == "unknown" and meeting_count == 0:
        return None
    base = 0.4
    if workout == "training":
        base = 0.7
    elif workout == "light":
        base = 0.55
    if today_meeting_minutes >= 240:  # ≥4h of meetings
        base += 0.1
    return CategoryResult(
        category="anticipatory_today_training",
        score=min(base, 1.0),
        fact_bundle={
            "workout_today": workout,
            "meetings_today_count": meeting_count,
            "meetings_today_minutes": today_meeting_minutes,
            "first_meeting_iso": cal[0].start.isoformat() if cal else None,
            "first_meeting_title": cal[0].title if cal else None,
        },
    )


def score_anticipatory_today_macros(state: AppState) -> Optional[CategoryResult]:
    """Pre-wake MORNING slot. Frames today's macro targets against
    today's calendar density so the user knows when their eating
    windows will be tight."""
    if state.slot != "morning":
        return None

    target_cal = state.today_targets.calories
    target_prot = state.today_targets.protein
    if target_cal <= 0 or target_prot <= 0:
        return None

    cal = state.today_calendar_remaining
    # Find the largest contiguous gap between meetings during waking
    # hours (8am-9pm). That's the user's biggest eating window.
    waking_start = state.now.replace(hour=8, minute=0, second=0, microsecond=0)
    waking_end = state.now.replace(hour=21, minute=0, second=0, microsecond=0)
    if cal:
        # Sort by start, walk the gaps.
        sorted_events = sorted(cal, key=lambda e: e.start)
        cursor = waking_start
        biggest_gap_min = 0
        for ev in sorted_events:
            if ev.start <= waking_start or ev.start >= waking_end:
                continue
            gap = int((ev.start - cursor).total_seconds() / 60)
            if gap > biggest_gap_min:
                biggest_gap_min = gap
            cursor = max(cursor, ev.end)
        # Gap from last event to waking_end
        tail = int((waking_end - cursor).total_seconds() / 60)
        if tail > biggest_gap_min:
            biggest_gap_min = tail
    else:
        biggest_gap_min = int((waking_end - waking_start).total_seconds() / 60)

    # Score: tight day (largest gap < 90min) + high protein target = highly worth flagging.
    score = 0.45
    if biggest_gap_min < 90:
        score = 0.75
    elif biggest_gap_min < 150:
        score = 0.6

    return CategoryResult(
        category="anticipatory_today_macros",
        score=min(score, 1.0),
        fact_bundle={
            "target_calories": int(target_cal),
            "target_protein": int(target_prot),
            "target_carbs": int(state.today_targets.carbs),
            "target_fat": int(state.today_targets.fat),
            "biggest_eating_gap_min": biggest_gap_min,
            "meetings_today_count": len(cal),
            "workout_today": state.workout_schedule_today,
        },
    )


# ─── Post-wake morning categories ───────────────────────────────────


def score_body_composition_change(state: AppState) -> Optional[CategoryResult]:
    """Post-wake MORNING slot. Compares today's weigh-in against the
    7-day trailing average so the user gets a delta worth noticing
    (or a 'nothing's moved' confirmation)."""
    if state.slot != "morning_post_wake":
        return None

    series = state.body_comp_last_30
    if not series:
        return None

    today = state.now.date().isoformat()
    today_row = next((b for b in reversed(series) if b.date == today), None)
    if today_row is None or today_row.weight_kg is None:
        # Today's weigh-in didn't land — the watcher may have fired before
        # the ingest committed. Don't surface a stale comparison.
        return None

    # Trailing 7-day average, excluding today
    trail = [b for b in series if b.date != today and b.weight_kg is not None][-7:]
    if len(trail) < 2:
        # Not enough history yet — first few weigh-ins
        return CategoryResult(
            category="body_composition_change",
            score=0.5,
            fact_bundle={
                "weight_kg_today": round(today_row.weight_kg, 2),
                "trail_count": len(trail),
                "note": "early_data",
            },
        )

    avg = sum(b.weight_kg for b in trail) / len(trail)
    delta = today_row.weight_kg - avg

    # Body fat % delta (if we have it)
    bf_today = today_row.body_fat_pct
    bf_trail = [b.body_fat_pct for b in trail if b.body_fat_pct is not None]
    bf_avg = sum(bf_trail) / len(bf_trail) if bf_trail else None
    bf_delta = (bf_today - bf_avg) if (bf_today is not None and bf_avg is not None) else None

    # Score: bigger weight or body fat moves are higher-signal.
    abs_delta = abs(delta)
    score = 0.5
    if abs_delta >= 1.0:
        score = 0.85
    elif abs_delta >= 0.5:
        score = 0.7
    if bf_delta is not None and abs(bf_delta) >= 0.5:
        score = max(score, 0.75)

    return CategoryResult(
        category="body_composition_change",
        score=min(score, 1.0),
        fact_bundle={
            "weight_kg_today": round(today_row.weight_kg, 2),
            "weight_kg_7d_avg": round(avg, 2),
            "weight_delta_kg": round(delta, 2),
            "body_fat_pct_today": round(bf_today, 2) if bf_today is not None else None,
            "body_fat_pct_7d_avg": round(bf_avg, 2) if bf_avg is not None else None,
            "body_fat_delta_pct": round(bf_delta, 2) if bf_delta is not None else None,
            "fat_mass_kg_today": round(today_row.fat_mass_kg, 2) if today_row.fat_mass_kg is not None else None,
            "muscle_mass_kg_today": round(today_row.muscle_mass_kg, 2) if today_row.muscle_mass_kg is not None else None,
            "trail_days": len(trail),
        },
    )


# ─── Event categories ───────────────────────────────────────────────


def score_logistics_event_out_for_delivery(state: AppState) -> Optional[CategoryResult]:
    """Event slot only. Fires when event_trigger.kind == 'out_for_delivery'."""
    if state.slot != "event_logistics":
        return None
    et = state.event_trigger
    if et is None or et.kind != "out_for_delivery":
        return None
    return CategoryResult(
        category="logistics_event_out_for_delivery",
        score=1.0,
        fact_bundle={
            "merchant": et.merchant,
            "carrier": et.carrier,
            "tracking_number": et.tracking_number,
            "current_time": state.now.isoformat(),
        },
    )


def score_logistics_event_eta_today(state: AppState) -> Optional[CategoryResult]:
    """Event slot. Fires when event_trigger.kind == 'eta_today'."""
    if state.slot != "event_logistics":
        return None
    et = state.event_trigger
    if et is None or et.kind != "eta_today":
        return None
    return CategoryResult(
        category="logistics_event_eta_today",
        score=0.95,
        fact_bundle={
            "merchant": et.merchant,
            "carrier": et.carrier,
            "tracking_number": et.tracking_number,
            "eta_iso": et.eta_at.isoformat() if et.eta_at else None,
        },
    )


# ─── Don't-churn guard for the event slot ───────────────────────────


def is_recent_topic_overlap(
    recent_insight_data: dict[str, Any],
    new_tracking_number: Optional[str],
) -> bool:
    """True when a recent (≤30min) insight already covered the same
    shipment. Caller uses this to silently skip event generation."""
    if not recent_insight_data:
        return False
    cat = recent_insight_data.get("winning_category", "")
    if not cat.startswith("logistics_"):
        return False
    fb = recent_insight_data.get("fact_bundle") or {}
    same = fb.get("tracking_number") == new_tracking_number
    return bool(same)


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
        "This is the PRE-WAKE MORNING slot — fires at 7am before the user "
        "is up. Sleep, weight, and HRV data aren't fresh yet, so DO NOT "
        "retrospect on last night. Look forward: today's training, today's "
        "macros, the calendar load, anything in transit. Plan the day, "
        "don't reflect on yesterday."
    ),
    "morning_post_wake": (
        "This is the POST-WAKE MORNING slot — fires after the user weighed "
        "in and Oura synced overnight data. Sleep, HRV, weight, body comp "
        "are all fresh now. THIS is the slot for retrospection: how the "
        "night went, what the body's saying, today's plan adjusted for it."
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


# ─── Long-form Telegram summary (post-wake only, for now) ───────────


SYSTEM_PROMPT_TELEGRAM = """You are BioChecha, the user's AI health & nutrition coach.

You're writing the POST-WAKE Telegram briefing. The user has just
weighed in, Oura synced overnight, and the day's plan is taking
shape. They opened Telegram looking for a useful read of where
their body is and what's worth knowing.

LENGTH: 4-6 short lines, 200-400 chars. Multi-section is welcome.
You have more space than the iOS card — use it for context, not
filler.

VOICE: same as the iOS card — smart-friend texting style, ~20%
snark. Earned snark only — when the data warrants it. Not jokey,
not cute, never an exclamation.

ALLOWED IN THIS FORMAT (forbidden in the iOS card):
  ✅ Specific numbers when they carry the meaning (98.1 kg, 15 ms HRV)
  ✅ Markdown for emphasis: *bold* or _italics_
  ✅ Two short sections separated by a blank line — e.g. overnight
     read first, today's plan second. Pick the structure that
     serves the data, not a template.

STILL FORBIDDEN:
  ❌ "indicating", "suggesting", "hinting" — hedge verbs
  ❌ "consider taking", "you should", "remember to" — preachy
  ❌ Cliché metaphors (rollercoaster, yo-yo, recharge, recalibrate)
  ❌ Exclamation points, emoji, headers like "Today:" or "Body:"
  ❌ Greetings ("Good morning"), signoffs ("Have a great day")
  ❌ Bullet lists. Markdown headers (#, ##). Tables.
  ❌ Saying "your body" 3 times in 4 lines (rotate phrasing)

PREFER COMPARATIVE OVER ABSOLUTE — but when the absolute is the
point, use it. "Weight dropped 1.2 kg from your 7-day average"
beats both "weight is 98.1 kg" and "weight dropped a lot".

Output ONLY the briefing. No preamble, no signoff, no metadata."""


def _build_telegram_prompt(slot: str, fact_bundle: dict[str, Any],
                           recent_feedback: Optional[list[str]] = None) -> str:
    today = date.today()
    parts = [
        f"Today: {today.isoformat()} ({today.strftime('%A')})",
        f"Slot: {slot}",
        SLOT_PROMPT_ADDENDUM.get(slot, ""),
    ]
    if recent_feedback:
        parts.append("")
        parts.append("RECENT USER FEEDBACK (correct course accordingly):")
        for r in recent_feedback[:5]:
            parts.append(f"  - {r[:300]}")
    parts += [
        "",
        "FACTS (real numbers from today's data — write the briefing from these):",
        json.dumps(fact_bundle, indent=2, default=str),
        "",
        "Write the briefing (4-6 lines, 200-400 chars, multi-section ok, no preamble).",
    ]
    return "\n".join(parts)


def _generate_telegram_summary(slot: str, fact_bundle: dict[str, Any],
                               recent_feedback: Optional[list[str]] = None) -> str:
    """Generate the long-form Telegram briefing. Same model as
    _generate_insight but a different system prompt + user prompt
    that grants the longer format. Higher max_tokens budget."""
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY not set")
    body = json.dumps({
        "model": OPENAI_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT_TELEGRAM},
            {"role": "user", "content": _build_telegram_prompt(slot, fact_bundle, recent_feedback)},
        ],
        "temperature": 0.8,
        "max_tokens": 500,
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
            # Pre-wake — sleep / weight / HRV are stale at 7am, so no
            # reflective categories here. All forward-looking.
            "morning": [
                score_anticipatory_today_training,
                score_anticipatory_today_macros,
                score_logistics_arriving_today,
                score_behavioral_capture_gap,
            ],
            # Post-wake — fired by inbody_ingest watcher after fresh
            # data lands. Reflective categories now make sense.
            "morning_post_wake": [
                score_body_composition_change,
                score_reflective_morning,
                score_anomaly_recent_pattern,
                score_anticipatory_today_training,
                score_anticipatory_today_macros,
            ],
            "midday": [
                score_anticipatory_lunch_window,
                score_goal_pacing_protein,
                score_goal_pacing_calories,
                score_logistics_arriving_today,
                score_anomaly_recent_pattern,
                score_behavioral_capture_gap,
            ],
            "afternoon": [
                score_opportunistic_walk,
                score_opportunistic_workout,
                score_goal_pacing_protein,
                score_goal_pacing_calories,
                score_goal_pacing_steps,
                score_logistics_arriving_today,
                score_anomaly_recent_pattern,
                score_behavioral_capture_gap,
            ],
            "evening": [
                score_recap_day,
                score_anticipatory_tomorrow,
                score_reflective_evening,
                score_behavioral_capture_gap,
            ],
            "event_logistics": [
                score_logistics_event_out_for_delivery,
                score_logistics_event_eta_today,
            ],
        }
        for fn in SLOT_CATEGORY_FNS.get(state.slot, []):
            r = fn(state)
            if r is not None:
                candidates.append(r)

        # Don't-churn guard: only for event slot. If a recent insight
        # already covers the same shipment, silently skip.
        if state.slot == "event_logistics" and candidates:
            recent = _fetch_most_recent_today_insight()
            if recent:
                tn = state.event_trigger.tracking_number if state.event_trigger else None
                if is_recent_topic_overlap(recent, tn):
                    print(f"[biochecha-dynamic:{slot}] skipped — overlap with recent insight")
                    return 0  # quiet skip

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
