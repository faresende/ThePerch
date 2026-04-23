#!/usr/bin/env python3
"""
calendar_dashboard_sync.py

Replaces the former agent-turn driven calendar cron. Pulls today + tomorrow's
events via icalBuddy, emits ISO8601 timestamps with explicit timezone offsets,
and replaces the calendar records in dashboard_records so the iOS app always
sees a fresh two-day window.

Why this exists:
  - The previous implementation was an LLM-generated agent turn that baked the
    Supabase anon key straight into ~/.openclaw/cron/jobs.json (which is part
    of the weekly backup set). Moving the work to a script means secrets stay
    in ~/.openclaw/secrets/perch.env only.
  - The previous agent turn also produced naive datetimes in some runs. This
    script formats every timestamp with an explicit +HH:MM offset against the
    user's home timezone.

Env (all required):
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY
  PERCH_USER_ID
  PERCH_TZ                 (default: Europe/Lisbon)

Exit codes:
  0 = success
  1 = irrecoverable error (Supabase write failed, icalBuddy error, etc.)
  2 = missing configuration
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, date, time, timedelta
from typing import Iterable
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from zoneinfo import ZoneInfo

ICALBUDDY_BIN = os.environ.get("ICALBUDDY_BIN", "/opt/homebrew/bin/icalBuddy")
USER_TZ_NAME = os.environ.get("PERCH_TZ", "Europe/Lisbon")
USER_TZ = ZoneInfo(USER_TZ_NAME)
AGENT_ID = os.environ.get("CALENDAR_AGENT_ID", "calendario")

REQUIRED_ENV = ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "PERCH_USER_ID")
for k in REQUIRED_ENV:
    if not os.environ.get(k):
        print(f"calendar-sync: {k} is required", file=sys.stderr)
        sys.exit(2)

SUPABASE_URL = os.environ["SUPABASE_URL"].rstrip("/")
SUPABASE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
USER_ID = os.environ["PERCH_USER_ID"]

# Exclusion keywords (case-insensitive). These never show up as dashboard
# events because they're blocking/focus holders.
EXCLUDE_TITLE_PATTERNS = [
    re.compile(r"^break\b", re.I),
    re.compile(r"^block time\b", re.I),
    re.compile(r"^focus\b", re.I),
    re.compile(r"^no meeting\b", re.I),
    re.compile(r"\bcancell?ed\b", re.I),
]


# ─── icalBuddy output parser ───────────────────────────────────────────────

@dataclass
class RawEvent:
    title: str
    start_str: str
    end_str: str | None
    location: str | None
    notes: str | None
    calendar_name: str | None
    all_day: bool


def _run_icalbuddy() -> str:
    """Run icalBuddy with a machine-friendly separator so parsing is reliable.

    We ask for a set of properties delimited by a known sentinel so we can
    rebuild structured records without relying on the pretty two-space-indent
    convention icalBuddy uses by default.
    """
    sentinel = "~~~|~~~"
    # -ic ''  : include all calendars (default behavior when omitted).
    # -ea     : don't show empty attributes.
    # -b ''   : no bullet prefix.
    # -nc     : no calendar-name prefix on each line.
    # -nrd    : no relative dates (we want the raw ones).
    # -ps     : property-separator: between properties, use our sentinel.
    # -pb     : property-bullet: suppress the default "property: " prefix.
    # -eep    : exclude empty properties (redundant with -ea but harmless).
    cmd = [
        ICALBUDDY_BIN,
        "-eep", "",
        "-ea",
        "-b", "",
        "-nc",
        "-nrd",
        "-ps", f"|{sentinel}|",
        "eventsFrom:today",
        "to:tomorrow",
    ]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (subprocess.SubprocessError, OSError) as e:
        raise RuntimeError(f"icalBuddy invocation failed: {e}") from e
    if out.returncode != 0:
        # icalBuddy writes "error: No calendars." when permission is missing.
        raise RuntimeError(
            f"icalBuddy exited {out.returncode}: {out.stderr.strip() or out.stdout.strip()}"
        )
    return out.stdout


def _parse_icalbuddy(raw_output: str) -> list[RawEvent]:
    """Parse icalBuddy's output into RawEvent records.

    Each event begins with a bold title line (which icalBuddy emits with a
    leading "* " or "• " by default; we suppress that via -b '' above). The
    rest of the event's properties follow on indented lines. Multiple events
    are separated by blank lines.

    We keep this defensive — icalBuddy's output format has drifted across
    versions — so any unparseable block becomes a RawEvent with best-effort
    fields rather than an exception.
    """
    events: list[RawEvent] = []
    blocks = [b for b in raw_output.split("\n\n") if b.strip()]
    for block in blocks:
        lines = [ln for ln in block.splitlines() if ln.strip()]
        if not lines:
            continue
        # First non-indented line is the title.
        title_line = lines[0].strip()
        title = title_line.strip()
        props = {}
        for ln in lines[1:]:
            # Typical prop lines: "    location: Room 3B"
            s = ln.strip()
            if not s:
                continue
            # Match 'key: value' defensively.
            m = re.match(r"([a-z ]+?)\s*:\s*(.*)$", s, re.I)
            if m:
                key = m.group(1).strip().lower()
                value = m.group(2).strip()
                props[key] = value
            else:
                # No key — append to 'notes' if we have room.
                props["notes"] = (props.get("notes", "") + "\n" + s).strip()

        events.append(RawEvent(
            title=title,
            start_str=(props.get("start") or props.get("starts") or props.get("time") or ""),
            end_str=(props.get("end") or props.get("ends")),
            location=props.get("location"),
            notes=props.get("notes"),
            calendar_name=props.get("calendar") or props.get("calendar name"),
            all_day="all-day" in (props.get("time") or "") or "all-day" in title.lower(),
        ))
    return events


# ─── Timestamp coercion ────────────────────────────────────────────────────

# Accept a few icalBuddy output shapes.
_DATE_PATTERNS = [
    # "2026-04-22 at 09:00"
    (re.compile(r"(\d{4}-\d{2}-\d{2})\s+at\s+(\d{2}:\d{2}(?::\d{2})?)"), "%Y-%m-%d %H:%M"),
    # "Wednesday, April 22, 2026 at 09:00"
    (re.compile(r"(\w+,\s+\w+\s+\d{1,2},\s+\d{4})\s+at\s+(\d{2}:\d{2}(?::\d{2})?)"), "%A, %B %d, %Y %H:%M"),
    # "today at 09:00" / "tomorrow at 09:00"
    (re.compile(r"(today|tomorrow)\s+at\s+(\d{2}:\d{2}(?::\d{2})?)", re.I), "TOKEN"),
]


def _parse_wallclock(s: str, default_day: date | None = None) -> datetime | None:
    """Best-effort wall-clock parsing. Returns a tz-aware datetime in USER_TZ."""
    if not s:
        return None
    s = s.strip()

    # Simple HH:MM — combine with default_day.
    m = re.match(r"^(\d{2}:\d{2}(?::\d{2})?)$", s)
    if m and default_day:
        t = datetime.strptime(m.group(1), "%H:%M" if m.group(1).count(":") == 1 else "%H:%M:%S").time()
        return datetime.combine(default_day, t, tzinfo=USER_TZ)

    for pat, fmt in _DATE_PATTERNS:
        m = pat.search(s)
        if not m:
            continue
        if fmt == "TOKEN":
            day_token = m.group(1).lower()
            today = datetime.now(USER_TZ).date()
            day = today if day_token == "today" else today + timedelta(days=1)
            t = datetime.strptime(m.group(2), "%H:%M" if m.group(2).count(":") == 1 else "%H:%M:%S").time()
            return datetime.combine(day, t, tzinfo=USER_TZ)
        try:
            if "," in fmt:
                # Month-name format has weekday + month spelled out.
                dt = datetime.strptime(f"{m.group(1)} {m.group(2)}", fmt)
            else:
                dt = datetime.strptime(f"{m.group(1)} {m.group(2)}", fmt)
            return dt.replace(tzinfo=USER_TZ)
        except ValueError:
            continue
    return None


def _iso(dt: datetime) -> str:
    """Format a tz-aware datetime as ISO8601 with explicit offset (+01:00)."""
    # isoformat() emits "+01:00" style; ensure seconds precision.
    return dt.replace(microsecond=0).isoformat()


# ─── Dashboard records writer ──────────────────────────────────────────────

def _api(path: str, method: str, body: object | None = None, params: dict | None = None) -> tuple[int, str]:
    url = f"{SUPABASE_URL}/rest/v1{path}"
    if params:
        qs = "&".join(f"{k}={v}" for k, v in params.items())
        url = f"{url}?{qs}"
    data = json.dumps(body).encode() if body is not None else None
    req = Request(
        url,
        data=data,
        method=method,
        headers={
            "apikey": SUPABASE_KEY,
            "Authorization": f"Bearer {SUPABASE_KEY}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
    )
    try:
        with urlopen(req, timeout=30) as resp:
            return resp.status, resp.read().decode()
    except HTTPError as e:
        return e.code, e.read().decode()


def _delete_existing_calendar_records() -> int:
    status, body = _api(
        "/dashboard_records",
        "DELETE",
        params={"user_id": f"eq.{USER_ID}", "category": "eq.calendar"},
    )
    if status >= 300:
        raise RuntimeError(f"DELETE calendar records failed: {status} {body}")
    return status


def _insert_event_record(event_data: dict, title: str) -> None:
    row = {
        "agent_id": AGENT_ID,
        "user_id": USER_ID,
        "category": "calendar",
        "type": "event",
        "title": title,
        "display_hint": "calendar_event",
        "pinned": False,
        "data": event_data,
    }
    status, body = _api("/dashboard_records", "POST", body=[row])
    if status >= 300:
        raise RuntimeError(f"POST event failed: {status} {body}")


# ─── agent_runs brackets ───────────────────────────────────────────────────

def _start_run() -> str | None:
    status, body = _api(
        "/agent_runs",
        "POST",
        body={"agent_id": AGENT_ID, "run_type": "sync", "status": "running"},
    )
    if status >= 300:
        print(f"calendar-sync: WARN could not start agent_runs row: {status}", file=sys.stderr)
        return None
    # PostgREST returns "" when Prefer: return=minimal; we re-query to get id.
    # Cheap follow-up read:
    q_status, q_body = _api(
        "/agent_runs",
        "GET",
        params={
            "agent_id": f"eq.{AGENT_ID}",
            "run_type": "eq.sync",
            "status": "eq.running",
            "order": "started_at.desc",
            "limit": "1",
            "select": "id",
        },
    )
    try:
        rows = json.loads(q_body or "[]")
        return rows[0]["id"] if rows else None
    except (ValueError, KeyError, IndexError):
        return None


def _end_run(run_id: str | None, status: str, summary: dict | None, error: str | None) -> None:
    if not run_id:
        return
    patch: dict = {"ended_at": datetime.utcnow().isoformat() + "Z", "status": status}
    if summary is not None:
        patch["summary"] = summary
    if error:
        patch["error_detail"] = error[:3900]
    _api("/agent_runs", "PATCH", body=patch, params={"id": f"eq.{run_id}"})


# ─── Filter + transform ────────────────────────────────────────────────────

def _should_include(ev: RawEvent) -> bool:
    title = ev.title.strip()
    if not title:
        return False
    for pat in EXCLUDE_TITLE_PATTERNS:
        if pat.search(title):
            return False
    return True


def _events_to_records(raws: Iterable[RawEvent]) -> list[tuple[str, dict]]:
    out: list[tuple[str, dict]] = []
    today = datetime.now(USER_TZ).date()
    for ev in raws:
        if not _should_include(ev):
            continue
        start_dt = _parse_wallclock(ev.start_str, default_day=today)
        end_dt = _parse_wallclock(ev.end_str or "", default_day=today)
        data = {
            "start_time": _iso(start_dt) if start_dt else None,
            "end_time": _iso(end_dt) if end_dt else None,
            "location": ev.location,
            "notes": ev.notes,
            "calendar_name": ev.calendar_name,
            "all_day": bool(ev.all_day),
        }
        # Drop keys with None to keep the JSON lean.
        data = {k: v for k, v in data.items() if v not in (None, "")}
        if not data.get("start_time"):
            # Don't ship events we couldn't place on a timeline.
            continue
        out.append((ev.title, data))
    return out


# ─── Main ──────────────────────────────────────────────────────────────────

def main() -> int:
    run_id = _start_run()
    try:
        raw_output = _run_icalbuddy()
        raws = _parse_icalbuddy(raw_output)
        records = _events_to_records(raws)

        _delete_existing_calendar_records()
        for title, data in records:
            _insert_event_record(data, title)

        summary = {
            "icalbuddy_events": len(raws),
            "inserted": len(records),
            "skipped": len(raws) - len(records),
        }
        _end_run(run_id, "ok", summary, None)
        print(json.dumps(summary))
        return 0
    except Exception as e:
        detail = f"{type(e).__name__}: {e}"
        _end_run(run_id, "error", None, detail)
        print(f"calendar-sync error: {detail}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
