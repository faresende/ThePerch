# Time-Aware BioChecha Insights Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single 7am BioChecha insight with 4 scheduled slots (morning/midday/afternoon/evening) plus an event-driven slot fired by 17track polling on out-for-delivery / ETA-flips-to-today.

**Architecture:** Single `biochecha_dynamic_insight.py` script takes a `<slot>` argument. Each run gathers `AppState`, scores eligible categories via a deterministic rule engine, picks the winner by score, packages a fact bundle, and the LLM writes 30-55 words in slot-specific voice. iOS reads the most-recent-today insight where `insight_type` matches `daily_health_*` or `event_logistics`.

**Tech Stack:** Python 3.11+ stdlib (no new deps), TypeScript (existing dashboard-sync skill), Swift (existing iOS app), PostgREST against Supabase, OpenAI gpt-4o-mini. Tests: Python `unittest` (stdlib).

**Spec:** `docs/superpowers/specs/2026-04-28-time-aware-insights-design.md`

---

## File structure

**New Python files:**
- `agents/health-integrations/biochecha_dynamic_insight.py` — main entry point + AppState gather + categories + ranker + LLM + persist (~600 LOC)
- `agents/health-integrations/biochecha_event_insight.py` — thin CLI wrapper that builds an `EventTrigger` from argv and calls into the dynamic script with `slot=event_logistics` (~50 LOC)
- `agents/health-integrations/test_dynamic_insight.py` — `unittest`-based unit tests for category scorers + ranker + don't-churn guard (~250 LOC)

**Modified Python files:**
- `agents/health-integrations/biochecha_daily_insight.py` — left in place during transition (Phase 1+2 don't touch it). Removed at end of Phase 4 once cron is migrated.

**Modified TypeScript files:**
- `skill/dashboard-sync/src/orders-autopilot.ts` — `pollAndUpdateShipment` gains a small post-update branch that detects status flip / ETA-becomes-today and fire-and-forgets a shell-out to `biochecha_event_insight.py`.

**Modified Swift files:**
- `ios/ThePerch/Sources/ThePerch/Models/Insight.swift` — `InsightKind` enum gains `dailyHealthMorning`, `dailyHealthMidday`, `dailyHealthAfternoon`, `dailyHealthEvening`, `eventLogistics`. `kicker` computed property maps all to `"TODAY · BIOCHECHA"`.
- `ios/ThePerch/Sources/ThePerch/Services/InsightsService.swift` — `fetchTodayDailyInsight()` query changes from `eq.insight_type=daily_health` to a multi-value match.

**Cron config:**
- `~/.openclaw/cron/jobs.json` — rename existing `biochecha-daily-insight` to `biochecha-morning-insight` + add 3 new entries (`midday`, `afternoon`, `evening`).

**Migration SQL (one-shot, applied once):**
- `UPDATE public.insights SET insight_type = 'daily_health_morning' WHERE insight_type = 'daily_health' AND agent_id = 'biochecha';`

---

# PHASE 0 — Calendar sync agent (prep for opportunity/anticipatory categories)

Goal: keep today's calendar events in `public.dashboard_records` so the categories that depend on calendar (`anticipatory_lunch_window`, `opportunistic_walk`, `opportunistic_workout`) have data to score against. Without this, those categories silently return 0 and the afternoon slot will mostly fall back to `goal_pacing` or `quiet_day_fallback`.

## Task 0.1: Install + verify `icalBuddy`

**Files:** None — system tool.

- [ ] **Step 1: Install icalBuddy if missing**

```bash
which icalBuddy || brew install ical-buddy
```
Expected: prints a path to `icalBuddy` (e.g. `/opt/homebrew/bin/icalBuddy`).

- [ ] **Step 2: Verify it can read today's events (will trigger macOS permission prompt the first time)**

```bash
icalBuddy -nc -nrd -ea -tf "%H:%M" -df "%Y-%m-%d" eventsToday
```
Expected: prints today's events in plain-text format. **First run will trigger a macOS calendar permission prompt for the terminal app** — grant access. If denied, this task fails and Phase 0 is skipped (the spec's "no calendar source" fallback applies).

- [ ] **Step 3: Document permission grant in setup instructions**

Append a line to `SETUP-FOR-AGENTS.md` Step 11 (or wherever calendar agent setup lives):

```markdown
> **Calendar agent first-run note:** the first time the calendar sync agent runs, macOS will prompt the terminal app for Calendar access. Grant it. Without permission, opportunity-based insights (e.g. "free afternoon, walk Osso") won't fire — the rest of the system still works.
```

## Task 0.2: Build `calendar_sync.py`

**Files:**
- Create: `agents/health-integrations/calendar_sync.py`

- [ ] **Step 1: Write the script**

```python
#!/usr/bin/env python3
"""
calendar_sync.py — pushes today's Mac Calendar.app events into
public.dashboard_records (category='calendar', type='event') so
the BioChecha dynamic insight script can read them.

Source: `icalBuddy eventsToday` (homebrew, macOS-only).
Cadence: every 15 min via cron during waking hours.
Idempotent: deletes today's calendar rows then re-inserts the
current set. No partial state on failure (writes inside a single
PostgREST batch).

Env required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PERCH_USER_ID.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, date, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).parent))
from _supabase_client import insert_agent_run  # noqa: E402

ICALBUDDY_PATHS = ("/opt/homebrew/bin/icalBuddy", "/usr/local/bin/icalBuddy")


def _icalbuddy_path() -> str:
    for p in ICALBUDDY_PATHS:
        if os.path.exists(p):
            return p
    raise RuntimeError("icalBuddy not found (brew install ical-buddy)")


def _read_today_events() -> list[dict]:
    """Run icalBuddy and parse the plain-text output."""
    out = subprocess.check_output([
        _icalbuddy_path(),
        "-nc", "-nrd", "-ea",
        "-tf", "%H:%M", "-df", "%Y-%m-%d",
        "eventsToday",
    ], text=True, timeout=15)
    today = date.today()
    events: list[dict] = []
    current: dict | None = None
    # Format example:
    #   • Lunch with someone
    #       2026-04-28
    #       12:30 - 13:30
    for line in out.splitlines():
        line = line.rstrip()
        if not line:
            continue
        if line.startswith("• "):
            # New event
            if current and "start" in current:
                events.append(current)
            current = {"title": line[2:].strip()}
        elif current is not None:
            # Time line ("12:30 - 13:30")
            m = re.match(r"\s*(\d{2}:\d{2})\s*-\s*(\d{2}:\d{2})", line)
            if m:
                start_h, start_m = map(int, m.group(1).split(":"))
                end_h, end_m = map(int, m.group(2).split(":"))
                start = datetime(today.year, today.month, today.day, start_h, start_m, tzinfo=timezone.utc)
                end = datetime(today.year, today.month, today.day, end_h, end_m, tzinfo=timezone.utc)
                current["start"] = start.isoformat()
                current["end"] = end.isoformat()
    if current and "start" in current:
        events.append(current)
    return events


def _supabase_post(path: str, body: bytes, headers_extra: dict | None = None) -> int:
    url = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    if headers_extra:
        headers.update(headers_extra)
    req = Request(f"{url}/rest/v1/{path}", data=body, method="POST", headers=headers)
    with urlopen(req, timeout=15) as resp:
        return resp.status


def _supabase_delete(path: str) -> int:
    url = os.environ["SUPABASE_URL"].rstrip("/")
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    req = Request(f"{url}/rest/v1/{path}", method="DELETE", headers={
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Prefer": "return=minimal",
    })
    try:
        with urlopen(req, timeout=10) as resp:
            return resp.status
    except HTTPError as e:
        return e.code


def main() -> int:
    started = datetime.now(timezone.utc)
    error: str | None = None
    inserted = 0
    user = os.environ["PERCH_USER_ID"]

    try:
        events = _read_today_events()
        today = date.today().isoformat()
        # Delete today's calendar slice for this user (idempotent).
        _supabase_delete(
            f"dashboard_records?user_id=eq.{user}&category=eq.calendar&"
            f"created_at=gte.{today}T00:00:00Z&created_at=lt.{today}T23:59:59Z"
        )
        if events:
            payload = [
                {
                    "user_id": user,
                    "type": "event",
                    "category": "calendar",
                    "title": e["title"][:200],
                    "data": {"start_at": e["start"], "end_at": e["end"]},
                    "created_at": e["start"],
                }
                for e in events
                if "start" in e and "end" in e
            ]
            if payload:
                _supabase_post(
                    "dashboard_records",
                    json.dumps(payload).encode(),
                )
                inserted = len(payload)
    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[calendar-sync] {error}\n")

    insert_agent_run(
        agent_id="calendar-sync",
        run_type="sync_today",
        status="error" if error else "ok",
        summary={"inserted": inserted},
        error_detail=error,
    )
    print(f"[calendar-sync] inserted={inserted} error={error}")
    return 1 if error else 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Manual run to verify**

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/Developer/ThePerch/agents/health-integrations/calendar_sync.py
```
Expected: prints `[calendar-sync] inserted=N error=None` where N matches the events visible in your Calendar.app today.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/ThePerch
git add agents/health-integrations/calendar_sync.py
git commit -m "feat(insights): calendar_sync agent — Mac Calendar.app → dashboard_records"
```

## Task 0.3: Add cron entry for calendar sync

**Files:** `~/.openclaw/cron/jobs.json`

- [ ] **Step 1: Back up + add the entry programmatically**

```bash
cp ~/.openclaw/cron/jobs.json ~/.openclaw/cron/jobs.json.bak-pre-calendar-sync-$(date +%Y%m%d-%H%M%S)
python3 << 'PY'
import json, uuid, time
from pathlib import Path
p = Path.home() / ".openclaw/cron/jobs.json"
d = json.loads(p.read_text())
new_job = {
    "id": str(uuid.uuid4()),
    "agentId": "cron-agent",
    "name": "calendar-sync",
    "description": "Push today's Mac Calendar events to dashboard_records for time-aware insights",
    "enabled": True,
    "schedule": {"kind": "cron", "expr": "*/15 6-22 * * *", "tz": "Europe/Lisbon"},
    "sessionTarget": "isolated",
    "wakeMode": "now",
    "delivery": {"channel": "last", "mode": "none"},
    "payload": {
        "kind": "agentTurn",
        "message": "Run: python3 ~/.openclaw/workspace/scripts/health-integrations/calendar_sync.py. Report results.",
        "model": "minimax-portal/MiniMax-M2.7-highspeed",
        "timeoutSeconds": 60,
    },
    "createdAtMs": int(time.time() * 1000),
    "state": {},
}
d["jobs"].append(new_job)
p.write_text(json.dumps(d, indent=2) + "\n")
print(f"added calendar-sync (id={new_job['id']}). total jobs: {len(d['jobs'])}")
PY
```

- [ ] **Step 2: Symlink the script into the openclaw workspace**

```bash
ln -sf ~/Developer/ThePerch/agents/health-integrations/calendar_sync.py \
       ~/.openclaw/workspace/scripts/health-integrations/calendar_sync.py
ls -la ~/.openclaw/workspace/scripts/health-integrations/calendar_sync.py
```
Expected: symlink resolves correctly.

- [ ] **Step 3: Done. No commit needed (jobs.json outside repo).**

---

# PHASE 1 — Scaffolding + morning slot proven end-to-end

Goal: replace the existing morning insight with the new dynamic script using `slot=morning`. Output quality must match or beat the current daily insight. After Phase 1, cron still calls the OLD script (no swap yet) — Phase 4 does the swap.

## Task 1.1: Create `biochecha_dynamic_insight.py` skeleton

**Files:**
- Create: `agents/health-integrations/biochecha_dynamic_insight.py`

- [ ] **Step 1: Create the skeleton with env auto-load + main entrypoint**

```python
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


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] not in VALID_SLOTS:
        sys.stderr.write(f"usage: {sys.argv[0]} <{'|'.join(sorted(VALID_SLOTS))}>\n")
        return 2
    slot = sys.argv[1]

    started = datetime.now(timezone.utc)
    error: Optional[str] = None
    body: Optional[str] = None
    try:
        # AppState gather + ranker + LLM + persist all happen in
        # subsequent tasks. For now the entrypoint just stubs.
        raise NotImplementedError("Phase 1 task 1.4 implements gather_state")
    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[biochecha-dynamic] {error}\n")

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
```

- [ ] **Step 2: Verify the skeleton runs and produces the expected error**

Run:
```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/Developer/ThePerch/agents/health-integrations/biochecha_dynamic_insight.py morning
```

Expected: stderr contains `NotImplementedError: Phase 1 task 1.4 implements gather_state`. Exit code 1. The `insert_agent_run` call succeeds (a row appears in `agent_runs` with `status='error'`).

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/ThePerch
git add agents/health-integrations/biochecha_dynamic_insight.py
git commit -m "feat(insights): scaffold biochecha_dynamic_insight.py — Phase 1 scaffolding"
```

---

## Task 1.2: Define `AppState` dataclass + types

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`

- [ ] **Step 1: Add the dataclass + supporting types after the imports**

Insert before `def main()`:

```python
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


# ─── Category scoring contract ──────────────────────────────────────


@dataclass(frozen=True)
class CategoryResult:
    category: str          # name (also used for tie-break priority)
    score: float           # 0-1
    fact_bundle: dict[str, Any]   # the LLM's input data — what TO say
```

- [ ] **Step 2: Verify the file still parses (no runtime call yet)**

Run:
```bash
python3 -c "import importlib.util, sys; spec = importlib.util.spec_from_file_location('m', '~/Developer/ThePerch/agents/health-integrations/biochecha_dynamic_insight.py'); m = importlib.util.module_from_spec(spec); spec.loader.exec_module.__call__ if False else 0"
```
Expected: no output, exit code 0. (Just imports the module without running main.)

Or simpler:
```bash
python3 -c "import ast; ast.parse(open('~/Developer/ThePerch/agents/health-integrations/biochecha_dynamic_insight.py').read())"
```
Expected: no output, exit code 0.

- [ ] **Step 3: Commit**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py
git commit -m "feat(insights): AppState + Category dataclasses"
```

---

## Task 1.3: Implement `gather_state()` — minimal version (just sleep + nutrition + targets)

The existing `biochecha_daily_insight.py` already has gather helpers we can lift verbatim. This task ports them into the dynamic script and shapes the result into the typed `AppState`.

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`

- [ ] **Step 1: Add the supabase-get helper (copy from existing daily insight)**

After the dataclasses, add:

```python
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
```

- [ ] **Step 2: Add `gather_state()` with minimal fields — sleep + nutrition + targets**

Append:

```python
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
    today = date.today().isoformat()
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
    # Fallback default — matches the rest/training profile in the cron config.
    return NutritionTargets(calories=2500, protein=180, carbs=280, fat=80)


def gather_state(slot: str, event_trigger: Optional[EventTrigger] = None) -> AppState:
    """Gather everything categories might need. Single round of queries.

    Phase 1 minimum: sleep, meals, targets. Calendar + orders +
    body_comp + workout_schedule + steps stubbed empty/unknown
    until Phase 2 extends gather.
    """
    return AppState(
        slot=slot,
        now=datetime.now(timezone.utc),
        today_meals=_gather_today_meals(),
        today_targets=_gather_targets(),
        today_calendar_remaining=[],     # Phase 2
        today_orders_in_transit=[],      # Phase 2
        sleep_last_7=_gather_sleep_last_7(),
        body_comp_last_30=[],            # Phase 2
        workout_schedule_today="unknown",  # Phase 2
        avg_steps_last_7_at_this_hour=0,   # Phase 2 (or never if step data isn't ingested)
        event_trigger=event_trigger,
    )
```

- [ ] **Step 3: Wire `gather_state` into `main()` (still produces NotImplementedError, just from the next step)**

Replace the body of the `try:` block in `main()`:

```python
    try:
        state = gather_state(slot)
        # Score categories + pick winner — implemented in Task 1.4 + 1.5
        raise NotImplementedError("Phase 1 task 1.5 implements categories")
```

- [ ] **Step 4: Smoke test — verify gather works without crashing**

Run:
```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 -c "
import sys
sys.path.insert(0, '~/Developer/ThePerch/agents/health-integrations')
from biochecha_dynamic_insight import gather_state
s = gather_state('morning')
print(f'meals: {len(s.today_meals)}')
print(f'sleep_last_7: {len(s.sleep_last_7)}')
print(f'targets: cal={s.today_targets.calories} prot={s.today_targets.protein}')
"
```
Expected: prints non-zero counts (you have meal data + sleep data + targets in your DB). No exceptions.

- [ ] **Step 5: Commit**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py
git commit -m "feat(insights): gather_state with sleep+meals+targets"
```

---

## Task 1.4: Implement Ranker + fallback

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`

- [ ] **Step 1: Add the ranker constants and function**

After the gather block:

```python
# ─── Ranker ─────────────────────────────────────────────────────────


# Static priority order (descending) — used for tie-breaks when two
# categories score equal. Logistics events are most time-sensitive.
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

# Score floor below which we drop into the fallback "quiet day" insight.
QUIET_THRESHOLD = 0.3


def rank(results: list[CategoryResult]) -> CategoryResult:
    """Return the highest-scoring CategoryResult, breaking ties by
    static priority (lower priority loses).

    If everything scores < QUIET_THRESHOLD, returns a quiet-day
    fallback CategoryResult that the caller passes to the LLM with a
    minimal voice prompt.
    """
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
```

- [ ] **Step 2: Commit (no test yet — first test lands in Task 1.6 with the first real category)**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py
git commit -m "feat(insights): ranker with static priority tie-break + quiet-day fallback"
```

---

## Task 1.5: Implement first category — `reflective_morning`

This is the category that produces the morning insight body. It always scores 0.5 baseline (always eligible in the morning slot) plus 0.1 per "notable signal" found in recent data. Signals: 3+ short nights, weight drift in last 14d, protein streak, etc. The fact_bundle hands the LLM the actual numbers.

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`
- Create: `agents/health-integrations/test_dynamic_insight.py`

- [ ] **Step 1: Write a failing unit test for the category**

Create `test_dynamic_insight.py`:

```python
#!/usr/bin/env python3
"""Unit tests for biochecha_dynamic_insight category scorers + ranker."""
import sys
import unittest
from dataclasses import replace
from datetime import datetime, timezone, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from biochecha_dynamic_insight import (
    AppState, NutritionTargets, SleepNight, Meal, CategoryResult,
    score_reflective_morning, rank,
)


def _base_state(slot: str = "morning") -> AppState:
    """Minimal state for tests — fill in only what each test needs."""
    return AppState(
        slot=slot,
        now=datetime(2026, 4, 28, 7, 0, tzinfo=timezone.utc),
        today_meals=[],
        today_targets=NutritionTargets(2500, 180, 280, 80),
        today_calendar_remaining=[],
        today_orders_in_transit=[],
        sleep_last_7=[],
        body_comp_last_30=[],
        workout_schedule_today="unknown",
        avg_steps_last_7_at_this_hour=0,
        event_trigger=None,
    )


class TestReflectiveMorning(unittest.TestCase):
    def test_baseline_score_is_at_least_threshold(self):
        """With no notable signals, reflective_morning still clears
        QUIET_THRESHOLD so the slot has something to say."""
        state = _base_state("morning")
        result = score_reflective_morning(state)
        self.assertIsNotNone(result)
        self.assertGreaterEqual(result.score, 0.3,
            "reflective_morning is a fallback — must always exceed quiet threshold")
        self.assertEqual(result.category, "reflective_morning")

    def test_returns_none_when_slot_isnt_morning(self):
        state = _base_state("midday")
        self.assertIsNone(score_reflective_morning(state))

    def test_short_nights_streak_boosts_score(self):
        """3+ consecutive short (<6h) nights bumps the score and
        adds a 'short_night_streak' signal to the fact bundle."""
        state = _base_state("morning")
        short_nights = [
            SleepNight(date=f"2026-04-{d}", duration_min=300.0)
            for d in (25, 26, 27, 28)
        ]
        state = replace(state, sleep_last_7=short_nights)
        result = score_reflective_morning(state)
        self.assertGreater(result.score, 0.6,
            "short-night streak should push score above baseline")
        self.assertIn("short_night_streak", result.fact_bundle)
        self.assertEqual(result.fact_bundle["short_night_streak"], 4)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test to verify it fails with `ImportError: cannot import name 'score_reflective_morning'`**

Run:
```bash
cd ~/Developer/ThePerch/agents/health-integrations
python3 -m unittest test_dynamic_insight -v
```
Expected: FAIL with `ImportError: cannot import name 'score_reflective_morning' from 'biochecha_dynamic_insight'`.

- [ ] **Step 3: Implement `score_reflective_morning` in `biochecha_dynamic_insight.py`**

Add after the ranker:

```python
# ─── Categories ─────────────────────────────────────────────────────


def score_reflective_morning(state: AppState) -> Optional[CategoryResult]:
    """Always-eligible morning fallback. Baseline 0.5; adds per signal.

    Signals scanned (each adds ~0.1):
      - 3+ consecutive short (<6h) nights
      - HRV trending up (5+ days each ≥ previous)
      - Weight drift > 1kg over 14 days (when body comp later)
      - Protein streak — every day this week ≥ target * 0.95

    Phase 1 implements only the sleep-based signals — others are
    stubbed out and added as gather_state grows.
    """
    if state.slot != "morning":
        return None

    score = 0.5
    facts: dict[str, Any] = {
        "summary": "morning reflection",
    }

    # Short-night streak. Walk sleep_last_7 (already oldest-first).
    if state.sleep_last_7:
        threshold_min = 6 * 60
        streak = 0
        for night in reversed(state.sleep_last_7):  # newest first
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

    # HRV trending. Compute simple "5+ ascending days" check.
    hrv_values = [n.hrv for n in state.sleep_last_7 if n.hrv is not None]
    if len(hrv_values) >= 5:
        trailing = hrv_values[-5:]
        if all(trailing[i] >= trailing[i - 1] for i in range(1, len(trailing))):
            score += 0.1
            facts["hrv_climbing_days"] = 5
            facts["hrv_recent"] = [round(v, 1) for v in trailing]

    # Always include the most-recent night's totals so the LLM has
    # something concrete to reference even when no streak fired.
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
cd ~/Developer/ThePerch/agents/health-integrations
python3 -m unittest test_dynamic_insight -v
```
Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py agents/health-integrations/test_dynamic_insight.py
git commit -m "feat(insights): reflective_morning category + first unit tests"
```

---

## Task 1.6: Slot voice prompts + LLM call + persist

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`

- [ ] **Step 1: Add SYSTEM_PROMPT (lifted from existing daily insight) + slot prompts**

Append to the file:

```python
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


def _build_user_prompt(slot: str, fact_bundle: dict[str, Any]) -> str:
    """Compose the per-slot user message handed to the LLM."""
    today = date.today()
    return "\n".join([
        f"Today: {today.isoformat()} ({today.strftime('%A')})",
        f"Slot: {slot}",
        SLOT_PROMPT_ADDENDUM[slot],
        "",
        "FACTS (real numbers from your data — write the insight from these):",
        json.dumps(fact_bundle, indent=2, default=str),
        "",
        "Write the insight (30-55 words, single paragraph, no preamble).",
    ])


def _generate_insight(slot: str, fact_bundle: dict[str, Any]) -> str:
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("OPENAI_API_KEY not set")
    body = json.dumps({
        "model": OPENAI_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": _build_user_prompt(slot, fact_bundle)},
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

    # Delete any prior row from today with the same type.
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
        pass  # 404 = no prior row; fine

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
```

- [ ] **Step 2: Wire it all together in `main()`**

Replace the body of the try-block in `main()`:

```python
    try:
        state = gather_state(slot)
        # Phase 1 only has reflective_morning — extend in Phase 2.
        candidates = []
        if state.slot == "morning":
            r = score_reflective_morning(state)
            if r is not None:
                candidates.append(r)
        winner = rank(candidates) if candidates else CategoryResult(
            category="quiet_day_fallback", score=0.0,
            fact_bundle={"reason": "no eligible category for this slot"},
        )
        body = _generate_insight(slot, winner.fact_bundle)
        ok = _upsert_insight(slot, body, winner)
        if not ok:
            error = "insert returned non-2xx"
    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[biochecha-dynamic:{slot}] {error}\n")
```

- [ ] **Step 3: Manual integration test — run with slot=morning**

Run:
```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/Developer/ThePerch/agents/health-integrations/biochecha_dynamic_insight.py morning
```

Expected output: a generated insight body printed to stdout (~30-55 words). Body lands in `public.insights` with `insight_type='daily_health_morning'`.

- [ ] **Step 4: Verify the row landed in the DB**

Run:
```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
curl -s "$SUPABASE_URL/rest/v1/insights?user_id=eq.$PERCH_USER_ID&insight_type=eq.daily_health_morning&order=generated_at.desc&limit=1" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | python3 -m json.tool
```
Expected: a JSON object with the new insight, `insight_type='daily_health_morning'`, `data.winning_category='reflective_morning'`.

- [ ] **Step 5: Commit**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py
git commit -m "feat(insights): LLM call + persist + morning slot wired end-to-end"
```

---

# PHASE 2 — Remaining 3 scheduled slots + remaining categories

Goal: midday, afternoon, evening slots fully working. AppState gather extended for calendar + orders + body composition + workout schedule. All 9 categories from the spec implemented.

## Task 2.1: Extend `gather_state` with calendar, orders, body comp, workout schedule

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`

- [ ] **Step 1: Add the new gather helpers after the existing `_gather_targets`**

Insert before `def gather_state(`:

```python
def _gather_today_calendar() -> list[CalendarEvent]:
    """Calendar events for the rest of today.

    Source: dashboard_records with category='calendar'. EventKit-backed
    iOS data isn't pushed to Supabase — only agent-fed entries land
    here. If the user has only EventKit calendar, this returns []
    and opportunity/anticipatory categories degrade to 0 score
    (intentional — better silent than wrong).
    """
    now = datetime.now(timezone.utc)
    end_of_day = now.replace(hour=23, minute=59, second=59)
    rows = _supabase_get(
        "dashboard_records",
        {
            "category": "eq.calendar",
            "created_at": f"gte.{now.replace(hour=0,minute=0,second=0).isoformat()}",
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
    """Active shipments for today/this week — not delivered, has tracking."""
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
    """Best-effort: scan today's calendar titles for workout cues.

    Maps to the same enum values the spec uses:
      'training' — gym / lifting / heavy day cues
      'light'    — yoga / pilates / mobility / recovery cues
      'rest'     — explicit "rest day" cue OR no workout-shaped title
      'unknown'  — calendar empty (we genuinely don't know)
    """
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
```

- [ ] **Step 2: Update `gather_state` to call the new helpers**

Replace `gather_state`:

```python
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
        avg_steps_last_7_at_this_hour=0,  # No step source ingested yet.
        event_trigger=event_trigger,
    )
```

- [ ] **Step 3: Smoke-test gather_state runs without errors**

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 -c "
import sys
sys.path.insert(0, '~/Developer/ThePerch/agents/health-integrations')
from biochecha_dynamic_insight import gather_state
s = gather_state('midday')
print(f'meals: {len(s.today_meals)}')
print(f'calendar: {len(s.today_calendar_remaining)}')
print(f'orders: {len(s.today_orders_in_transit)}')
print(f'body_comp: {len(s.body_comp_last_30)}')
print(f'workout: {s.workout_schedule_today}')
"
```
Expected: prints non-zero counts, no exceptions.

- [ ] **Step 4: Commit**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py
git commit -m "feat(insights): extend gather_state with calendar, orders, body comp, workout"
```

---

## Task 2.2: Midday categories — `anticipatory_lunch_window`, `goal_pacing_protein`, `logistics_arriving_today`

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`
- Modify: `agents/health-integrations/test_dynamic_insight.py`

- [ ] **Step 1: Write failing tests for the three new categories**

Append to `test_dynamic_insight.py`:

```python
from biochecha_dynamic_insight import (  # extends previous imports
    score_anticipatory_lunch_window,
    score_goal_pacing_protein,
    score_logistics_arriving_today,
    CalendarEvent, OrderSummary,
)


class TestAnticipatoryLunchWindow(unittest.TestCase):
    def test_high_score_when_busy_afternoon_and_low_calories(self):
        state = _base_state("midday")
        state = replace(state, now=datetime(2026, 4, 28, 12, 0, tzinfo=timezone.utc))
        # 3 events in next 4h → busy afternoon trigger
        state = replace(state, today_calendar_remaining=[
            CalendarEvent(
                start=datetime(2026, 4, 28, 14, 0, tzinfo=timezone.utc),
                end=datetime(2026, 4, 28, 14, 30, tzinfo=timezone.utc),
                title="Meeting 1",
            ),
            CalendarEvent(
                start=datetime(2026, 4, 28, 15, 0, tzinfo=timezone.utc),
                end=datetime(2026, 4, 28, 15, 30, tzinfo=timezone.utc),
                title="Meeting 2",
            ),
            CalendarEvent(
                start=datetime(2026, 4, 28, 16, 0, tzinfo=timezone.utc),
                end=datetime(2026, 4, 28, 16, 30, tzinfo=timezone.utc),
                title="Meeting 3",
            ),
        ])
        # No meals → calories=0 < 40% of 2500
        result = score_anticipatory_lunch_window(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.7)
        self.assertEqual(result.category, "anticipatory_lunch_window")

    def test_zero_when_not_midday(self):
        state = _base_state("morning")
        self.assertIsNone(score_anticipatory_lunch_window(state))


class TestGoalPacingProtein(unittest.TestCase):
    def test_score_scales_with_deficit(self):
        state = _base_state("midday")
        # Big deficit: 0g of 180g target.
        result = score_goal_pacing_protein(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.5)

    def test_low_score_when_on_track(self):
        state = _base_state("midday")
        state = replace(state, today_meals=[
            Meal(calories=500, protein=170, carbs=40, fat=15,
                 meal_time=datetime(2026, 4, 28, 12, 0, tzinfo=timezone.utc)),
        ])
        result = score_goal_pacing_protein(state)
        self.assertLess(result.score, 0.3,
            "near-target protein should not surface as a slot winner")


class TestLogisticsArrivingToday(unittest.TestCase):
    def test_high_score_when_eta_today(self):
        state = _base_state("afternoon")
        state = replace(state, today_orders_in_transit=[
            OrderSummary(
                merchant="Body & Fit", order_number="BF1429199",
                carrier="DHL", tracking_number="CQ478942688DE",
                eta_at=datetime(2026, 4, 28, 17, 0, tzinfo=timezone.utc),
                status="in_transit",
            ),
        ])
        result = score_logistics_arriving_today(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.8)
        self.assertIn("arriving", result.fact_bundle)
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd ~/Developer/ThePerch/agents/health-integrations
python3 -m unittest test_dynamic_insight -v
```
Expected: ImportError for the three new function names.

- [ ] **Step 3: Implement the three categories**

Append to `biochecha_dynamic_insight.py` after `score_reflective_morning`:

```python
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
    """Midday/afternoon. Score = min(1, deficit_ratio). Returns None
    when on-track to keep it from surfacing as a winner."""
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
```

- [ ] **Step 4: Wire all three into `main()`**

Replace the candidate block in `main()`:

```python
        candidates: list[CategoryResult] = []
        SLOT_CATEGORY_FNS = {
            "morning": [score_reflective_morning],
            "midday": [
                score_anticipatory_lunch_window,
                score_goal_pacing_protein,
                score_logistics_arriving_today,
            ],
            # afternoon, evening, event_logistics extended in later tasks
        }
        for fn in SLOT_CATEGORY_FNS.get(state.slot, []):
            r = fn(state)
            if r is not None:
                candidates.append(r)
        winner = rank(candidates) if candidates else CategoryResult(
            category="quiet_day_fallback", score=0.0,
            fact_bundle={"reason": "no eligible category for this slot"},
        )
```

- [ ] **Step 5: Run tests to confirm pass**

```bash
cd ~/Developer/ThePerch/agents/health-integrations
python3 -m unittest test_dynamic_insight -v
```
Expected: all 7+ tests pass.

- [ ] **Step 6: Manual integration test for midday slot**

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/Developer/ThePerch/agents/health-integrations/biochecha_dynamic_insight.py midday
```
Expected: a body printed, plus a row in `insights` with `insight_type='daily_health_midday'`.

- [ ] **Step 7: Commit**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py agents/health-integrations/test_dynamic_insight.py
git commit -m "feat(insights): midday categories (anticipatory_lunch / pacing_protein / logistics_today)"
```

---

## Task 2.3: Afternoon categories — `opportunistic_walk`, `opportunistic_workout`, `goal_pacing_calories`, `goal_pacing_steps`, `anomaly_recent_pattern`

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`
- Modify: `agents/health-integrations/test_dynamic_insight.py`

- [ ] **Step 1: Write failing tests**

Append to `test_dynamic_insight.py`:

```python
from biochecha_dynamic_insight import (
    score_opportunistic_walk,
    score_opportunistic_workout,
    score_goal_pacing_calories,
    score_anomaly_recent_pattern,
)


class TestOpportunisticWalk(unittest.TestCase):
    def test_fires_on_rest_day_with_calendar_gap(self):
        state = _base_state("afternoon")
        state = replace(state,
            now=datetime(2026, 4, 28, 15, 0, tzinfo=timezone.utc),
            workout_schedule_today="rest",
            today_calendar_remaining=[
                CalendarEvent(
                    start=datetime(2026, 4, 28, 17, 30, tzinfo=timezone.utc),
                    end=datetime(2026, 4, 28, 18, 0, tzinfo=timezone.utc),
                    title="Design review"),
            ],
        )
        result = score_opportunistic_walk(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.7)
        self.assertEqual(result.fact_bundle.get("gap_min"), 150)

    def test_skips_when_workout_scheduled_today(self):
        state = _base_state("afternoon")
        state = replace(state, workout_schedule_today="training")
        self.assertIsNone(score_opportunistic_walk(state))


class TestAnomalyRecentPattern(unittest.TestCase):
    def test_three_short_nights_in_a_row(self):
        state = _base_state("morning")
        state = replace(state, sleep_last_7=[
            SleepNight(date="2026-04-26", duration_min=320),
            SleepNight(date="2026-04-27", duration_min=300),
            SleepNight(date="2026-04-28", duration_min=280),
        ])
        result = score_anomaly_recent_pattern(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.5)
        self.assertIn("pattern", result.fact_bundle)
```

- [ ] **Step 2: Run tests; expect ImportError on the new symbols**

```bash
python3 -m unittest test_dynamic_insight -v
```
Expected: ImportError on the new function names.

- [ ] **Step 3: Implement the categories**

Append after `score_logistics_arriving_today`:

```python
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
    """Afternoon. Fires when today is NOT a rest day, no workout logged
    yet, AND there's a meaningful calendar gap. Encourages doing the
    scheduled workout if it hasn't happened."""
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
    >120% of target proportional-to-time-of-day OR <50% by mid-afternoon."""
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
```

- [ ] **Step 4: Extend the SLOT_CATEGORY_FNS map in `main()`**

Update the mapping in `main()`:

```python
        SLOT_CATEGORY_FNS = {
            "morning": [score_reflective_morning, score_anomaly_recent_pattern],
            "midday": [
                score_anticipatory_lunch_window,
                score_goal_pacing_protein,
                score_goal_pacing_calories,
                score_logistics_arriving_today,
                score_anomaly_recent_pattern,
            ],
            "afternoon": [
                score_opportunistic_walk,
                score_opportunistic_workout,
                score_goal_pacing_protein,
                score_goal_pacing_calories,
                score_goal_pacing_steps,
                score_logistics_arriving_today,
                score_anomaly_recent_pattern,
            ],
            # evening + event_logistics in later tasks
        }
```

- [ ] **Step 5: Run all tests**

```bash
python3 -m unittest test_dynamic_insight -v
```
Expected: all tests pass.

- [ ] **Step 6: Manual integration test for afternoon slot**

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/Developer/ThePerch/agents/health-integrations/biochecha_dynamic_insight.py afternoon
```
Expected: an insight body printed, row lands in DB with `insight_type='daily_health_afternoon'`.

- [ ] **Step 7: Commit**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py agents/health-integrations/test_dynamic_insight.py
git commit -m "feat(insights): afternoon categories (opportunistic + pacing + anomaly)"
```

---

## Task 2.4: Evening categories — `recap_day`, `anticipatory_tomorrow`, `reflective_evening`, `behavioral_capture_gap`

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`
- Modify: `agents/health-integrations/test_dynamic_insight.py`

- [ ] **Step 1: Write failing tests**

Append to `test_dynamic_insight.py`:

```python
from biochecha_dynamic_insight import (
    score_recap_day,
    score_anticipatory_tomorrow,
    score_reflective_evening,
    score_behavioral_capture_gap,
)


class TestRecapDay(unittest.TestCase):
    def test_always_eligible_in_evening(self):
        state = _base_state("evening")
        result = score_recap_day(state)
        self.assertIsNotNone(result)
        self.assertEqual(result.score, 1.0)
        self.assertEqual(result.category, "recap_day")

    def test_skips_outside_evening(self):
        state = _base_state("morning")
        self.assertIsNone(score_recap_day(state))


class TestBehavioralCaptureGap(unittest.TestCase):
    def test_fires_when_no_meals_logged_today(self):
        state = _base_state("evening")
        state = replace(state, now=datetime(2026, 4, 28, 20, 0, tzinfo=timezone.utc))
        # No today_meals at 20:00 — capture is broken or skipped.
        result = score_behavioral_capture_gap(state)
        self.assertIsNotNone(result)
        self.assertGreater(result.score, 0.5)
        self.assertEqual(result.fact_bundle.get("hours_since_last"), None)
        self.assertEqual(result.fact_bundle.get("today_meal_count"), 0)
```

- [ ] **Step 2: Run tests, expect ImportError**

- [ ] **Step 3: Implement the categories**

Append:

```python
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
```

- [ ] **Step 4: Wire evening + behavioral into SLOT_CATEGORY_FNS**

Update `main()`:

```python
        SLOT_CATEGORY_FNS = {
            "morning": [
                score_reflective_morning,
                score_anomaly_recent_pattern,
                score_behavioral_capture_gap,
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
            # event_logistics in Phase 3
        }
```

- [ ] **Step 5: Run all tests**

```bash
python3 -m unittest test_dynamic_insight -v
```
Expected: all pass.

- [ ] **Step 6: Manual integration test — evening slot**

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/Developer/ThePerch/agents/health-integrations/biochecha_dynamic_insight.py evening
```
Expected: insight body printed, row in DB.

- [ ] **Step 7: Commit**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py agents/health-integrations/test_dynamic_insight.py
git commit -m "feat(insights): evening categories (recap + reflective + behavioral)"
```

---

# PHASE 3 — Event-driven slot + 17track hook

Goal: when 17track polling detects a status flip to `out_for_delivery` or an ETA change to today, fire a fresh insight via `biochecha_event_insight.py` if don't-churn guard allows.

## Task 3.1: Implement event categories + don't-churn guard

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`
- Modify: `agents/health-integrations/test_dynamic_insight.py`

- [ ] **Step 1: Write failing tests for the two event categories + don't-churn**

Append to tests:

```python
from biochecha_dynamic_insight import (
    score_logistics_event_out_for_delivery,
    score_logistics_event_eta_today,
    EventTrigger,
    is_recent_topic_overlap,
)


class TestLogisticsEventCategories(unittest.TestCase):
    def test_out_for_delivery_scores_high(self):
        state = _base_state("event_logistics")
        state = replace(state, event_trigger=EventTrigger(
            kind="out_for_delivery",
            merchant="Body & Fit", carrier="DHL",
            tracking_number="CQ478942688DE",
            old_status="in_transit", new_status="out_for_delivery",
            eta_at=None,
        ))
        result = score_logistics_event_out_for_delivery(state)
        self.assertIsNotNone(result)
        self.assertEqual(result.score, 1.0)

    def test_eta_today_only_fires_for_eta_today_event(self):
        state = _base_state("event_logistics")
        state = replace(state, event_trigger=EventTrigger(
            kind="eta_today",
            merchant="Hardgraft", carrier="DPD",
            tracking_number="15976785968210",
            old_status="in_transit", new_status="in_transit",
            eta_at=datetime(2026, 4, 28, 17, 0, tzinfo=timezone.utc),
        ))
        result = score_logistics_event_eta_today(state)
        self.assertIsNotNone(result)
        self.assertGreaterEqual(result.score, 0.9)


class TestDontChurnGuard(unittest.TestCase):
    def test_overlap_blocks_when_same_shipment_referenced(self):
        recent = {
            "winning_category": "logistics_event_out_for_delivery",
            "fact_bundle": {"tracking_number": "CQ478942688DE"},
        }
        self.assertTrue(is_recent_topic_overlap(recent, "CQ478942688DE"))

    def test_overlap_clears_when_different_shipment(self):
        recent = {
            "winning_category": "logistics_event_out_for_delivery",
            "fact_bundle": {"tracking_number": "AAAA"},
        }
        self.assertFalse(is_recent_topic_overlap(recent, "BBBB"))

    def test_overlap_clears_when_different_topic(self):
        recent = {
            "winning_category": "reflective_morning",
            "fact_bundle": {},
        }
        self.assertFalse(is_recent_topic_overlap(recent, "any-tracking"))
```

- [ ] **Step 2: Run tests, expect ImportError**

- [ ] **Step 3: Implement event categories + the don't-churn helper**

Append:

```python
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
    return rows[0].get("data") or {}
```

- [ ] **Step 4: Update `main()` to invoke the don't-churn guard for event_logistics slot only**

Replace the candidate block with:

```python
        # Event slot has special handling: fetch latest insight,
        # check don't-churn, skip silently if overlap.
        if state.slot == "event_logistics":
            recent = _fetch_most_recent_today_insight()
            if recent and recent.get("generated_at_age_min", 999) <= 30 if False else False:
                # placeholder; real guard below
                pass

        candidates: list[CategoryResult] = []
        SLOT_CATEGORY_FNS = {
            "morning": [
                score_reflective_morning,
                score_anomaly_recent_pattern,
                score_behavioral_capture_gap,
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

        # Don't-churn guard: only for event slot. If a recent (≤30min)
        # insight already covers the same shipment, silently skip.
        if state.slot == "event_logistics" and candidates:
            recent = _fetch_most_recent_today_insight()
            if recent:
                # Compute age in minutes from generated_at.
                gen_at_str = recent.get("generated_at") if isinstance(recent, dict) else None
                # If recent has the same tracking_number as our event, skip.
                tn = state.event_trigger.tracking_number if state.event_trigger else None
                if is_recent_topic_overlap(recent, tn):
                    print(f"[biochecha-dynamic:{slot}] skipped — overlap with recent insight")
                    return 0  # quiet skip

        winner = rank(candidates) if candidates else CategoryResult(
            category="quiet_day_fallback", score=0.0,
            fact_bundle={"reason": "no eligible category for this slot"},
        )
```

- [ ] **Step 5: Run tests**

```bash
python3 -m unittest test_dynamic_insight -v
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py agents/health-integrations/test_dynamic_insight.py
git commit -m "feat(insights): event_logistics categories + don't-churn guard"
```

---

## Task 3.2: Create `biochecha_event_insight.py` thin wrapper

**Files:**
- Create: `agents/health-integrations/biochecha_event_insight.py`

- [ ] **Step 1: Write the wrapper script**

```python
#!/usr/bin/env python3
"""
biochecha_event_insight.py — thin wrapper that constructs an
EventTrigger from CLI args and calls into biochecha_dynamic_insight.py
with slot=event_logistics.

Called by orders-autopilot's pollAndUpdateShipment when a shipment
flips to out_for_delivery or its ETA becomes today.

Usage:
    biochecha_event_insight.py out_for_delivery <merchant> <carrier> <tracking> [<old_status>] [<new_status>]
    biochecha_event_insight.py eta_today        <merchant> <carrier> <tracking> <eta_iso>
"""
from __future__ import annotations

import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from biochecha_dynamic_insight import (
    EventTrigger,
    gather_state,
    rank,
    is_recent_topic_overlap,
    _fetch_most_recent_today_insight,
    _generate_insight,
    _upsert_insight,
    score_logistics_event_out_for_delivery,
    score_logistics_event_eta_today,
    CategoryResult,
)
from _supabase_client import insert_agent_run


def main() -> int:
    if len(sys.argv) < 5:
        sys.stderr.write(
            "usage: biochecha_event_insight.py <kind> <merchant> <carrier> <tracking> [<eta_iso|old_status>] [<new_status>]\n"
        )
        return 2
    kind = sys.argv[1]
    if kind not in ("out_for_delivery", "eta_today"):
        sys.stderr.write(f"unknown kind: {kind}\n")
        return 2

    merchant = sys.argv[2]
    carrier = sys.argv[3]
    tracking = sys.argv[4]
    eta_at = None
    old_status = None
    new_status = None
    if kind == "eta_today" and len(sys.argv) >= 6:
        try:
            eta_at = datetime.fromisoformat(sys.argv[5].replace("Z", "+00:00"))
        except Exception:
            eta_at = None
    elif kind == "out_for_delivery" and len(sys.argv) >= 7:
        old_status = sys.argv[5]
        new_status = sys.argv[6]

    et = EventTrigger(
        kind=kind, merchant=merchant, carrier=carrier,
        tracking_number=tracking, old_status=old_status,
        new_status=new_status, eta_at=eta_at,
    )

    error = None
    body = None
    try:
        state = gather_state("event_logistics", event_trigger=et)
        # Don't-churn guard
        recent = _fetch_most_recent_today_insight()
        if recent and is_recent_topic_overlap(recent, tracking):
            print(f"[event:{kind}] skipped — recent insight already covers {tracking}")
            return 0

        candidates = []
        for fn in (
            score_logistics_event_out_for_delivery,
            score_logistics_event_eta_today,
        ):
            r = fn(state)
            if r is not None:
                candidates.append(r)
        winner = rank(candidates) if candidates else CategoryResult(
            category="quiet_day_fallback", score=0.0,
            fact_bundle={"reason": "no event category fired"},
        )
        body = _generate_insight("event_logistics", winner.fact_bundle)
        _upsert_insight("event_logistics", body, winner)
    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[event:{kind}] {error}\n")

    insert_agent_run(
        agent_id="biochecha", run_type=f"event_insight_{kind}",
        status="error" if error else "ok",
        summary={"merchant": merchant, "tracking": tracking, "length": len(body) if body else 0},
        error_detail=error,
    )
    if error:
        return 1
    print(f"[event:{kind}] generated for {merchant}: {body}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Manual integration test — fire a synthetic event**

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
python3 ~/Developer/ThePerch/agents/health-integrations/biochecha_event_insight.py out_for_delivery "Body & Fit" "DHL" "CQ478942688DE" "in_transit" "out_for_delivery"
```
Expected: a generated insight body printed; a row lands in `insights` with `insight_type='event_logistics'`.

- [ ] **Step 3: Manual test of the don't-churn guard — re-run the same command immediately**

Run the same command again right after.

Expected: `[event:out_for_delivery] skipped — recent insight already covers CQ478942688DE`. No new row in DB.

- [ ] **Step 4: Commit**

```bash
git add agents/health-integrations/biochecha_event_insight.py
git commit -m "feat(insights): biochecha_event_insight.py thin wrapper for event slot"
```

---

## Task 3.3: TypeScript hook in `pollAndUpdateShipment`

**Files:**
- Modify: `skill/dashboard-sync/src/orders-autopilot.ts` (around `pollAndUpdateShipment` near line 920)
- Sync: `~/.openclaw/skills/dashboard-sync/src/orders-autopilot.ts` (mirror of the above)

- [ ] **Step 1: Add the helper that invokes the Python event script (fire-and-forget)**

Append after the existing imports in `orders-autopilot.ts`:

```typescript
import { spawn } from 'node:child_process';
```

Append after the existing helpers (e.g. after `pollAndUpdateShipment`):

```typescript
/**
 * Fire-and-forget shellout to biochecha_event_insight.py. Called when
 * 17track polling detects a status flip or ETA change. The Python
 * script handles its own idempotency via the don't-churn guard.
 *
 * Path resolution: $HOME/.openclaw/workspace/scripts/health-integrations/
 * biochecha_event_insight.py is the canonical install location (see
 * SETUP-FOR-AGENTS.md). Falls back to repo-relative path during dev.
 */
function fireEventInsight(args: string[]): void {
  const home = process.env.HOME || '';
  const scriptPath = `${home}/.openclaw/workspace/scripts/health-integrations/biochecha_event_insight.py`;
  // Don't await — let it run in the background and let the polling
  // loop continue. Errors are logged inside the Python script's own
  // agent_runs row.
  const proc = spawn('python3', [scriptPath, ...args], {
    detached: true,
    stdio: 'ignore',
  });
  proc.unref();  // allow parent to exit independently
  proc.on('error', (err) => {
    // Log and swallow — never let this block the poll loop.
    console.error('[event-insight] spawn failed:', err.message);
  });
}
```

- [ ] **Step 2: Modify `pollAndUpdateShipment` to detect status flip and ETA-becomes-today**

Find the function (currently ~line 920+). After the call to `updateShipmentFromTracker`, add:

```typescript
  // ─── Phase 3: event-insight hook ───────────────────────────────
  //
  // Detect two transitions worth a fresh BioChecha event insight:
  //   1. status flipped to `out_for_delivery` (was anything else)
  //   2. ETA went from no-eta-or-future to today
  //
  // The Python script handles don't-churn internally (skips if a
  // recent insight already covers this tracking number).
  try {
    const previouslyOFD = currentShipment?.status === 'out_for_delivery';
    const nowOFD = result.status === 'out_for_delivery';
    if (nowOFD && !previouslyOFD) {
      fireEventInsight([
        'out_for_delivery',
        merchantName ?? 'Unknown',
        carrier ?? 'unknown',
        trackingNumber,
        currentShipment?.status ?? 'unknown',
        'out_for_delivery',
      ]);
    }

    if (etaUpdate?.eta_at) {
      const newEtaDate = new Date(etaUpdate.eta_at).toDateString();
      const oldEtaDate = currentShipment?.eta_at
        ? new Date(currentShipment.eta_at).toDateString()
        : '';
      const todayDate = new Date().toDateString();
      if (newEtaDate === todayDate && oldEtaDate !== todayDate) {
        fireEventInsight([
          'eta_today',
          merchantName ?? 'Unknown',
          carrier ?? 'unknown',
          trackingNumber,
          etaUpdate.eta_at,
        ]);
      }
    }
  } catch (err) {
    // Never let event-insight failure break tracking updates.
    console.warn('[event-insight] hook error:', (err as Error).message);
  }
```

(Variable names like `currentShipment`, `result`, `etaUpdate`, `merchantName`, `trackingNumber`, `carrier` already exist in `pollAndUpdateShipment`'s scope. If yours differ slightly, match the local names.)

- [ ] **Step 3: Sync to runtime path + typecheck + run tests**

```bash
cp ~/Developer/ThePerch/skill/dashboard-sync/src/orders-autopilot.ts \
   ~/.openclaw/skills/dashboard-sync/src/orders-autopilot.ts
cd ~/.openclaw/skills/dashboard-sync
npx tsc --noEmit 2>&1 | head -10
npm run build 2>&1 | tail -3
node --test dist/**/*.test.js 2>&1 | tail -5
```
Expected: typecheck clean, build clean, 31/31 existing tests still pass.

- [ ] **Step 4: Commit**

```bash
cd ~/Developer/ThePerch
git add skill/dashboard-sync/src/orders-autopilot.ts
git commit -m "feat(insights): pollAndUpdateShipment fires event_insight on OFD / ETA-today"
```

---

# PHASE 4 — iOS + migration + cron config

Goal: iOS reads the new insight types correctly; existing morning insight rows migrate; cron runs all 5 generators (4 scheduled + 0 explicit event — event is triggered by the existing 17track poll).

## Task 4.1: Update `Insight.kind` enum

**Files:**
- Modify: `ios/ThePerch/Sources/ThePerch/Models/Insight.swift`

- [ ] **Step 1: Add new cases to `InsightKind` enum**

Find the `InsightKind` enum (currently has `dailyHealth`, etc.). Add the new raw values:

```swift
enum InsightKind: String, Codable, Sendable {
    case dailyHealth         = "daily_health"           // legacy — kept until migration runs

    case dailyHealthMorning   = "daily_health_morning"
    case dailyHealthMidday    = "daily_health_midday"
    case dailyHealthAfternoon = "daily_health_afternoon"
    case dailyHealthEvening   = "daily_health_evening"

    case eventLogistics       = "event_logistics"

    // existing other cases stay below if any (crossDomain, anomaly, etc.)
    case crossDomain          = "cross_domain"
    case spendingPattern      = "spending_pattern"
    case anomaly              = "anomaly"
    case negativeSpace        = "negative_space"
    case latency              = "latency"
}
```

- [ ] **Step 2: Update the `kicker` computed property to map all new kinds to "TODAY · BIOCHECHA"**

Find `var kicker: String { ... }` on `Insight`. Update the switch:

```swift
var kicker: String {
    switch kind {
    case .dailyHealth, .dailyHealthMorning, .dailyHealthMidday,
         .dailyHealthAfternoon, .dailyHealthEvening:
        return "TODAY · BIOCHECHA"
    case .eventLogistics:
        return "TODAY · BIOCHECHA"
    case .crossDomain:    return "PATTERN · BIOCHECHA"
    case .spendingPattern: return "SPENDING · BIOCHECHA"
    case .anomaly:        return "ANOMALY · BIOCHECHA"
    case .negativeSpace:  return "GAP · BIOCHECHA"
    case .latency:        return "LATENCY · BIOCHECHA"
    }
}
```

- [ ] **Step 3: xcodebuild verify — should still build**

```bash
cd ~/Developer/ThePerch/ios/ThePerch && xcodebuild -scheme ThePerch -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | grep -E "error:|FAILED|BUILD SUCCEEDED|BUILD FAILED" | head -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add ios/ThePerch/Sources/ThePerch/Models/Insight.swift
git commit -m "feat(insights): InsightKind enum gains time-aware + event_logistics cases"
```

---

## Task 4.2: Update `InsightsService.fetchTodayDailyInsight()`

**Files:**
- Modify: `ios/ThePerch/Sources/ThePerch/Services/InsightsService.swift`

- [ ] **Step 1: Find the existing `fetchTodayDailyInsight` method and update its query**

Replace the body of the method to fetch by `agent_id=biochecha` + valid_for_date=today + ordered desc by generated_at, no insight_type filter (we want any of the 5 new kinds, whichever is most recent). The decoder still returns an `Insight`.

Concrete change inside the function:

```swift
func fetchTodayDailyInsight() async throws -> Insight? {
    let today = ISO8601DateFormatter.dateOnlyString(from: .now)  // or your existing date formatter
    let response = try await supabaseService.databaseClient
        .from("insights")
        .select()
        .eq("agent_id", value: "biochecha")
        .eq("valid_for_date", value: today)
        .order("generated_at", ascending: false)
        .limit(1)
        .execute()

    let decoded = try insightDecoder.decode([Insight].self, from: response.data)
    return decoded.first
}
```

(If the existing implementation already orders by `generated_at desc limit 1`, the only change is removing the `eq("insight_type", value: "daily_health")` line. That's the minimum change.)

- [ ] **Step 2: xcodebuild verify**

```bash
xcodebuild -scheme ThePerch -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | grep -E "error:|FAILED|BUILD SUCCEEDED|BUILD FAILED" | head -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ThePerch/Sources/ThePerch/Services/InsightsService.swift
git commit -m "feat(insights): fetchTodayDailyInsight reads any insight_type, latest wins"
```

---

## Task 4.3: Apply the SQL migration

**Files:** No file changes — runs against Supabase directly.

- [ ] **Step 1: Apply the rename SQL**

Use the Supabase MCP `apply_migration` tool, or paste into the Supabase SQL Editor:

```sql
-- 20260428000000_rename_legacy_daily_health_insights.sql
-- Renames the legacy `daily_health` insight_type to `daily_health_morning`
-- so it shows up correctly under the new time-aware fetch query.

UPDATE public.insights
SET insight_type = 'daily_health_morning'
WHERE insight_type = 'daily_health'
  AND agent_id = 'biochecha';
```

- [ ] **Step 2: Verify the rename**

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
curl -s "$SUPABASE_URL/rest/v1/insights?agent_id=eq.biochecha&select=insight_type" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  | python3 -c "import json,sys; rows=json.load(sys.stdin); from collections import Counter; print(Counter(r['insight_type'] for r in rows))"
```
Expected: no `daily_health` rows remain. New `daily_health_morning` count matches the previous `daily_health` count.

- [ ] **Step 3: Save the migration SQL into the repo for posterity**

Create `supabase/migrations/20260428000000_rename_legacy_daily_health_insights.sql`:

```sql
-- 20260428000000_rename_legacy_daily_health_insights.sql
-- Time-aware insights migration: renames legacy daily_health → daily_health_morning.
-- See docs/superpowers/specs/2026-04-28-time-aware-insights-design.md.

UPDATE public.insights
SET insight_type = 'daily_health_morning'
WHERE insight_type = 'daily_health'
  AND agent_id = 'biochecha';
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260428000000_rename_legacy_daily_health_insights.sql
git commit -m "chore(insights): record SQL migration that renamed legacy daily_health"
```

---

## Task 4.4: Cron config — rename existing + 3 new entries

**Files:** `~/.openclaw/cron/jobs.json`

This is OUTSIDE the repo. Provide the user the exact JSON to paste and the verification command.

- [ ] **Step 1: Back up the current jobs file**

```bash
cp ~/.openclaw/cron/jobs.json ~/.openclaw/cron/jobs.json.bak-pre-time-aware-insights-$(date +%Y%m%d-%H%M%S)
```

- [ ] **Step 2: Modify the existing biochecha-daily-insight entry**

Find the entry with `"name": "biochecha-daily-insight"` (added earlier in the project). Change two fields:

```jsonc
{
  "name": "biochecha-morning-insight",   // was: biochecha-daily-insight
  // ... other fields unchanged ...
  "payload": {
    "kind": "agentTurn",
    "message": "Run the BioChecha morning insight: python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_dynamic_insight.py morning. Report the generated insight or any errors.",
    // model, timeoutSeconds unchanged
  }
}
```

- [ ] **Step 3: Add 3 new entries**

Append to the `jobs` array. Use `uuidgen` to generate a UUID for each `id` field. Replace `<UUID>` below.

```jsonc
{
  "id": "<UUID>",
  "agentId": "cron-agent",
  "name": "biochecha-midday-insight",
  "description": "Pre-afternoon checkpoint insight (anticipatory)",
  "enabled": true,
  "schedule": { "kind": "cron", "expr": "0 12 * * *", "tz": "Europe/Lisbon" },
  "sessionTarget": "isolated",
  "wakeMode": "now",
  "delivery": { "channel": "last", "mode": "none" },
  "payload": {
    "kind": "agentTurn",
    "message": "Run: python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_dynamic_insight.py midday. Report results.",
    "model": "minimax-portal/MiniMax-M2.7-highspeed",
    "timeoutSeconds": 600
  },
  "createdAtMs": <NOW_MS>,
  "state": {}
},
{
  "id": "<UUID>",
  "agentId": "cron-agent",
  "name": "biochecha-afternoon-insight",
  "description": "Gap-aware opportunity insight",
  "enabled": true,
  "schedule": { "kind": "cron", "expr": "0 15 * * *", "tz": "Europe/Lisbon" },
  "sessionTarget": "isolated",
  "wakeMode": "now",
  "delivery": { "channel": "last", "mode": "none" },
  "payload": {
    "kind": "agentTurn",
    "message": "Run: python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_dynamic_insight.py afternoon. Report results.",
    "model": "minimax-portal/MiniMax-M2.7-highspeed",
    "timeoutSeconds": 600
  },
  "createdAtMs": <NOW_MS>,
  "state": {}
},
{
  "id": "<UUID>",
  "agentId": "cron-agent",
  "name": "biochecha-evening-insight",
  "description": "Day recap + tomorrow setup",
  "enabled": true,
  "schedule": { "kind": "cron", "expr": "0 20 * * *", "tz": "Europe/Lisbon" },
  "sessionTarget": "isolated",
  "wakeMode": "now",
  "delivery": { "channel": "last", "mode": "none" },
  "payload": {
    "kind": "agentTurn",
    "message": "Run: python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_dynamic_insight.py evening. Report results.",
    "model": "minimax-portal/MiniMax-M2.7-highspeed",
    "timeoutSeconds": 600
  },
  "createdAtMs": <NOW_MS>,
  "state": {}
}
```

Use this Python helper to generate the JSON for paste:

```bash
python3 << 'PY'
import json, uuid, time
ms = int(time.time()*1000)
schedules = [
    ("biochecha-midday-insight",    "0 12 * * *", "midday",    "Pre-afternoon checkpoint insight (anticipatory)"),
    ("biochecha-afternoon-insight", "0 15 * * *", "afternoon", "Gap-aware opportunity insight"),
    ("biochecha-evening-insight",   "0 20 * * *", "evening",   "Day recap + tomorrow setup"),
]
out = []
for name, expr, slot, desc in schedules:
    out.append({
        "id": str(uuid.uuid4()),
        "agentId": "cron-agent",
        "name": name,
        "description": desc,
        "enabled": True,
        "schedule": {"kind": "cron", "expr": expr, "tz": "Europe/Lisbon"},
        "sessionTarget": "isolated",
        "wakeMode": "now",
        "delivery": {"channel": "last", "mode": "none"},
        "payload": {
            "kind": "agentTurn",
            "message": f"Run: python3 ~/.openclaw/workspace/scripts/health-integrations/biochecha_dynamic_insight.py {slot}. Report results.",
            "model": "minimax-portal/MiniMax-M2.7-highspeed",
            "timeoutSeconds": 600,
        },
        "createdAtMs": ms,
        "state": {},
    })
print(json.dumps(out, indent=2))
PY
```

Paste the output into `jobs.json`'s `jobs` array (between existing entries, valid JSON commas).

- [ ] **Step 4: Verify the file still parses**

```bash
python3 -c "import json; d=json.load(open('~/.openclaw/cron/jobs.json')); print(f'jobs: {len(d[\"jobs\"])}')"
```
Expected: count is 4 more than before (3 added + 0 removed; the rename doesn't change count).

- [ ] **Step 5: Verify each new cron is recognized by listing jobs**

```bash
python3 -c "
import json
d = json.load(open('~/.openclaw/cron/jobs.json'))
for j in d['jobs']:
    if 'biochecha' in j['name']:
        print(j['name'], '→', j['schedule']['expr'])
"
```
Expected: 4 lines — `biochecha-morning-insight`, `biochecha-midday-insight`, `biochecha-afternoon-insight`, `biochecha-evening-insight`.

- [ ] **Step 6: No commit needed** (jobs.json lives outside the repo). Document the cron config in `docs/superpowers/specs/2026-04-28-time-aware-insights-design.md` if it's not already there. (Spec already documents it — no action.)

---

## Task 4.5: End-to-end smoke test on device

- [ ] **Step 1: Bump iOS build, install on device**

In Xcode: Product → Archive (or just bump build number + Run on device). Confirm the app loads.

- [ ] **Step 2: Run all 4 slot generators in sequence (manually)**

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
for slot in morning midday afternoon evening; do
  echo "--- $slot ---"
  python3 ~/Developer/ThePerch/agents/health-integrations/biochecha_dynamic_insight.py "$slot"
  echo
done
```
Expected: 4 different insight bodies printed; each lands in `insights` table.

- [ ] **Step 3: Pull-to-refresh on the iOS app**

In the app's Today tab, pull down to refresh. The `DailyInsightCard` should now show the most-recent of the 4 insights (likely "evening" since that ran last).

- [ ] **Step 4: Verify the kicker reads `TODAY · BIOCHECHA`**

Visually confirm the eyebrow text is unchanged. Body content reflects the latest slot.

- [ ] **Step 5: Final commit**

```bash
cd ~/Developer/ThePerch
git status  # confirm working tree clean
git log --oneline -10
git push
```
Expected: working tree clean, all commits pushed.

---

# PHASE 5 — Rage-shake feedback loop

Goal: when the user shakes the device on the Today tab, present a sheet pre-loaded with the current insight + a free-text field to react ("too coachy", "wrong topic", "this is great"). Feedback persists to a new `insight_feedback` table and gets fed to BioChecha as few-shot context on subsequent generations — so the voice can self-correct over time.

## Task 5.1: Migration — `insight_feedback` table

**Files:**
- Create: `supabase/migrations/20260428100000_insight_feedback.sql`

- [ ] **Step 1: Write the migration**

```sql
-- 20260428100000_insight_feedback.sql
-- Rage-shake feedback channel for time-aware BioChecha insights.
-- See docs/superpowers/specs/2026-04-28-time-aware-insights-design.md.

BEGIN;

CREATE TABLE IF NOT EXISTS public.insight_feedback (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  insight_id   uuid REFERENCES public.insights(id) ON DELETE SET NULL,
  insight_body text,                  -- snapshot at feedback time
  reaction     text NOT NULL,         -- user's free text
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS insight_feedback_user_created_idx
  ON public.insight_feedback (user_id, created_at DESC);

ALTER TABLE public.insight_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS insight_feedback_select_own ON public.insight_feedback;
DROP POLICY IF EXISTS insight_feedback_insert_own ON public.insight_feedback;

CREATE POLICY insight_feedback_select_own
  ON public.insight_feedback FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY insight_feedback_insert_own
  ON public.insight_feedback FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

COMMIT;
```

- [ ] **Step 2: Apply via Supabase MCP**

Apply the migration. Verify the table exists:

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
curl -s "$SUPABASE_URL/rest/v1/insight_feedback?select=count&limit=1" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
```
Expected: `[{"count": 0}]` — table exists, empty.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260428100000_insight_feedback.sql
git commit -m "feat(insights): insight_feedback table + RLS for rage-shake feedback"
```

## Task 5.2: iOS shake detector + InsightFeedback service

**Files:**
- Create: `ios/ThePerch/Sources/ThePerch/Services/InsightFeedbackService.swift`
- Create: `ios/ThePerch/Sources/ThePerch/Views/Components/ShakeDetector.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/TodayTab.swift` (attach shake handler + sheet)

- [ ] **Step 1: Create the shake detector**

```swift
// ShakeDetector.swift
import SwiftUI
import UIKit

/// View modifier that detects iOS device shake gestures (UIEvent.motionEnded
/// with motion=.motionShake). Used by the Today tab to fire the rage-shake
/// feedback sheet for the active BioChecha insight.

struct ShakeDetector: ViewModifier {
    let onShake: () -> Void

    func body(content: Content) -> some View {
        content
            .background(ShakeUIView(onShake: onShake))
    }
}

private struct ShakeUIView: UIViewRepresentable {
    let onShake: () -> Void

    func makeUIView(context: Context) -> _ShakeUIView {
        _ShakeUIView(onShake: onShake)
    }
    func updateUIView(_ uiView: _ShakeUIView, context: Context) {}
}

private final class _ShakeUIView: UIView {
    let onShake: () -> Void
    init(onShake: @escaping () -> Void) {
        self.onShake = onShake
        super.init(frame: .zero)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canBecomeFirstResponder: Bool { true }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { onShake() }
    }
}

extension View {
    /// Fire `onShake` when the device is physically shaken while this view
    /// is on screen. Backed by UIEvent.motionEnded.
    func onDeviceShake(perform onShake: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(onShake: onShake))
    }
}
```

- [ ] **Step 2: Create the feedback service**

```swift
// InsightFeedbackService.swift
import Foundation
import Supabase
import PostgREST

@MainActor
final class InsightFeedbackService {
    static let shared = InsightFeedbackService()
    private let supabaseService: SupabaseService
    init() { self.supabaseService = .shared }
    init(supabaseService: SupabaseService) { self.supabaseService = supabaseService }

    /// Insert a feedback row tied to the given insight (or untied if nil).
    func submit(insightId: UUID?, insightBody: String, reaction: String) async throws {
        try await supabaseService.databaseClient
            .from("insight_feedback")
            .insert(InsightFeedbackPayload(
                insight_id: insightId,
                insight_body: insightBody,
                reaction: reaction
            ))
            .execute()
    }
}

nonisolated private struct InsightFeedbackPayload: Encodable, Sendable {
    let insight_id: UUID?
    let insight_body: String
    let reaction: String
}
```

- [ ] **Step 3: Add the sheet to TodayTab**

In `TodayTab.swift`, add state + sheet + shake hookup. Near the existing `@State` declarations:

```swift
    @State private var showingFeedbackSheet = false
    @State private var feedbackText = ""
```

Find the outermost `ScrollView` body and append (just before the `.background()` modifier or wherever modifiers stack):

```swift
            .onDeviceShake {
                if dashboardViewModel.todayInsight != nil {
                    PerchHaptics.medium()
                    showingFeedbackSheet = true
                }
            }
            .sheet(isPresented: $showingFeedbackSheet) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 16) {
                        if let insight = dashboardViewModel.todayInsight {
                            Text("THE INSIGHT")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(.secondary)
                            Text(insight.body)
                                .font(.system(size: 14, design: .serif).italic())
                                .foregroundStyle(.primary)
                        }
                        Divider().padding(.vertical, 4)
                        Text("WHAT'S OFF")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $feedbackText)
                            .font(.system(size: 15))
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .background(Color(.systemGray6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Spacer()
                    }
                    .padding()
                    .navigationTitle("React")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                feedbackText = ""
                                showingFeedbackSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Send") {
                                let body = dashboardViewModel.todayInsight?.body ?? ""
                                let id = dashboardViewModel.todayInsight?.id
                                let reaction = feedbackText
                                Task {
                                    try? await InsightFeedbackService.shared.submit(
                                        insightId: id,
                                        insightBody: body,
                                        reaction: reaction
                                    )
                                }
                                feedbackText = ""
                                showingFeedbackSheet = false
                            }
                            .disabled(feedbackText.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
```

- [ ] **Step 4: Add files to Xcode project (via xcodeproj Ruby)**

```bash
ruby -e "
require 'xcodeproj'
proj = Xcodeproj::Project.open('~/Developer/ThePerch/ios/ThePerch/ThePerch.xcodeproj')
target = proj.targets.find { |t| t.name == 'ThePerch' }
services = proj.main_group.find_subpath('Sources/ThePerch/Services', false)
components = proj.main_group.find_subpath('Sources/ThePerch/Views/Components', false)
[
  ['~/Developer/ThePerch/ios/ThePerch/Sources/ThePerch/Services/InsightFeedbackService.swift', services],
  ['~/Developer/ThePerch/ios/ThePerch/Sources/ThePerch/Views/Components/ShakeDetector.swift', components],
].each do |path, group|
  next if group.files.any? { |f| f.real_path.to_s == path }
  ref = group.new_reference(path)
  ref.last_known_file_type = 'sourcecode.swift'
  target.source_build_phase.add_file_reference(ref)
  puts \"+ #{File.basename(path)}\"
end
proj.save
"
```

- [ ] **Step 5: xcodebuild verify**

```bash
cd ~/Developer/ThePerch/ios/ThePerch && xcodebuild -scheme ThePerch -destination 'generic/platform=iOS Simulator' -configuration Debug build 2>&1 | grep -E "error:|FAILED|BUILD SUCCEEDED|BUILD FAILED" | head -5
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add ios/ThePerch/Sources/ThePerch/Services/InsightFeedbackService.swift \
        ios/ThePerch/Sources/ThePerch/Views/Components/ShakeDetector.swift \
        ios/ThePerch/Sources/ThePerch/Views/App/TodayTab.swift \
        ios/ThePerch/ThePerch.xcodeproj/project.pbxproj
git commit -m "feat(insights): rage-shake → feedback sheet wired on Today tab"
```

## Task 5.3: Plumb feedback into Python `gather_state` + few-shot prompt

**Files:**
- Modify: `agents/health-integrations/biochecha_dynamic_insight.py`

- [ ] **Step 1: Extend AppState with `recent_feedback: list[str]`**

In the AppState dataclass (added in Task 1.2), append:

```python
    recent_feedback: list[str] = field(default_factory=list)  # most-recent reactions
```

(`field` from `dataclasses` is already imported.)

- [ ] **Step 2: Add a gather helper for recent feedback**

After the existing gather helpers, append:

```python
def _gather_recent_feedback(limit: int = 5) -> list[str]:
    """Return up to `limit` most-recent feedback reactions, freshest first.
    Used as few-shot guidance for the LLM — 'last time you wrote X, the
    user said Y; don't do that again.'"""
    rows = _supabase_get(
        "insight_feedback",
        {
            "select": "reaction,created_at",
            "order": "created_at.desc",
            "limit": str(limit),
        },
    )
    return [r["reaction"] for r in rows if r.get("reaction")]
```

- [ ] **Step 3: Wire into `gather_state`**

Add to the AppState constructor call in `gather_state`:

```python
        recent_feedback=_gather_recent_feedback(limit=5),
```

- [ ] **Step 4: Inject feedback into the LLM user prompt**

Update `_build_user_prompt`:

```python
def _build_user_prompt(slot: str, fact_bundle: dict[str, Any], recent_feedback: list[str] | None = None) -> str:
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
```

And update the call in `_generate_insight`:

```python
def _generate_insight(slot: str, fact_bundle: dict[str, Any], recent_feedback: list[str] | None = None) -> str:
    # ... rest unchanged, but pass recent_feedback to _build_user_prompt
```

And update both call sites in `main()` and `biochecha_event_insight.py`'s main:

```python
        body = _generate_insight(slot, winner.fact_bundle, recent_feedback=state.recent_feedback)
```

- [ ] **Step 5: Manual integration test — submit feedback, then run a slot, confirm it's in the prompt**

```bash
# Manually insert a feedback row via curl
set -a && source ~/.openclaw/secrets/perch.env && set +a
curl -s -X POST "$SUPABASE_URL/rest/v1/insight_feedback" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"user_id":"'$PERCH_USER_ID'","reaction":"too coachy, drop the recommendations"}'

# Run a slot
python3 ~/Developer/ThePerch/agents/health-integrations/biochecha_dynamic_insight.py morning
```
Expected: insight is generated. Check `agent_runs` for the most recent row — its summary should reflect the feedback influence (or just verify by reviewing the body text).

- [ ] **Step 6: Commit**

```bash
git add agents/health-integrations/biochecha_dynamic_insight.py
git commit -m "feat(insights): rage-shake feedback feeds back as few-shot context to LLM"
```

---

## Self-review

After writing this plan, I checked:

**Spec coverage:**
- ✅ 4 scheduled slots — Tasks 1.6, 2.2, 2.3, 2.4
- ✅ Event-driven slot — Tasks 3.1, 3.2, 3.3
- ✅ 9 categories — Tasks 1.5, 2.2, 2.3, 2.4, 3.1
- ✅ Don't-churn guard — Task 3.1
- ✅ Slot-specific voice prompts — Task 1.6
- ✅ Migration — Task 4.3
- ✅ iOS — Tasks 4.1, 4.2
- ✅ Cron — Task 4.4

**Type consistency:** `CategoryResult.fact_bundle: dict[str, Any]` used consistently. `EventTrigger.tracking_number: Optional[str]` consistent. `gather_state(slot, event_trigger=None)` signature consistent across callers.

**Scope:** focused. Phase boundaries clear. Each phase produces a working state independently.

**Ambiguity:** "Replace the body of the try-block in main()" repeats across tasks — engineer should follow the most recent task's version.
