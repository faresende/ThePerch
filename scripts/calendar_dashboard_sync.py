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
from datetime import datetime, time, timedelta
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
    """Parse icalBuddy's sentinel-delimited output into RawEvent records.

    Shape observed on real output (macOS icalBuddy 1.10+):
      TITLE~~~key1: value1~~~key2: value2 (may span\n newlines)~~~DATE at TIME - TIME\n
      NEXT_TITLE~~~...

    Each event is one logical record terminated by a newline whose next
    character is a non-whitespace event-title start. Notes fields may embed
    literal newlines indented with whitespace, so we split on `\\n(?=\\S)`
    rather than `\\n\\n` to keep those notes attached to their event.

    The last `~~~`-delimited chunk is always the date/time range; the first
    is always the title; middle chunks are `key: value` property lines.

    Events can appear more than once when the same iCloud entry is synced to
    multiple calendars — we dedupe by (title, last-field) after parsing.
    """
    events: list[RawEvent] = []
    seen: set[tuple[str, str]] = set()

    # Event boundary: each event's last `~~~`-delimited field is always the
    # date-time range, e.g. "23 Apr 2026 at 09:30 - 11:00" or "24 Apr 2026"
    # for all-day events. We anchor parsing on that suffix because line-based
    # splitting is fragile — some calendars wrap a location/notes field onto
    # an unindented continuation line that contains its own `~~~` (the date
    # range lives on the same wrapped line).
    end_re = re.compile(
        r"~~~(\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4}"
        r"(?:\s+at\s+\d{1,2}:\d{2}(?:\s*-\s*\d{1,2}:\d{2})?)?)\s*(?:\n|$)"
    )
    pos = 0
    blocks: list[tuple[str, str]] = []  # (body_without_final_separator, time_str)
    for m in end_re.finditer(raw_output):
        body = raw_output[pos:m.start()].strip()
        time_str = m.group(1).strip()
        if body:
            blocks.append((body, time_str))
        pos = m.end()

    for body, time_str in blocks:
        if not body.strip():
            continue
        parts = body.split("~~~")
        # parts = [title, prop1?, prop2?, ...] — the trailing date is already
        # captured by the end_re split; we don't include it here.
        if not parts:
            continue

        title = parts[0].strip()
        prop_parts = parts[1:]

        dedup_key = (title, time_str)
        if dedup_key in seen:
            continue
        seen.add(dedup_key)

        props: dict[str, str] = {}
        for chunk in prop_parts:
            # "key: value" where value may span embedded \n lines. Strip
            # leading/trailing whitespace on the joined value.
            first_line, _, rest = chunk.partition("\n")
            m = re.match(r"\s*([a-z ]+?)\s*:\s*(.*)$", first_line, re.I)
            if m:
                key = m.group(1).strip().lower()
                value = m.group(2).strip()
                if rest:
                    # Re-join continuation lines with single newlines, dropping
                    # the leading indent icalBuddy adds.
                    cont = "\n".join(ln.strip() for ln in rest.splitlines() if ln.strip())
                    value = f"{value}\n{cont}" if cont else value
                props[key] = value.strip()

        events.append(RawEvent(
            title=title,
            start_str=time_str,
            end_str=None,  # embedded in start_str as "HH:MM - HH:MM"
            location=props.get("location"),
            notes=props.get("notes"),
            calendar_name=props.get("calendar") or props.get("calendar name"),
            all_day=("all-day" in time_str.lower()) or ("all day" in time_str.lower()),
        ))
    return events


# ─── Timestamp coercion ────────────────────────────────────────────────────

# icalBuddy's actual output format is `DD MMM YYYY at HH:MM - HH:MM`, with
# the month as a three-letter English abbreviation. Examples observed:
#   "23 Apr 2026 at 09:30 - 11:00"
#   "23 Apr 2026 at 10:00 - 11:00"
#   "24 Apr 2026 at 09:00 - 10:00"
# All-day events come out as "23 Apr 2026" (no time range).
#
# We parse [start, end] as a tuple so callers can emit both ends to
# dashboard_records.
_RANGE_RE = re.compile(
    r"""
    ^\s*
    (?P<day>\d{1,2})\s+
    (?P<month>[A-Za-z]{3,9})\s+
    (?P<year>\d{4})
    (?:
        \s+at\s+
        (?P<start>\d{1,2}:\d{2})
        (?:\s*-\s*(?P<end>\d{1,2}:\d{2}))?
    )?
    \s*$
    """,
    re.VERBOSE,
)


def _parse_range(s: str) -> tuple[datetime | None, datetime | None, bool]:
    """Parse "23 Apr 2026 at 09:30 - 11:00" into (start, end, all_day).

    Returns (None, None, False) if the string doesn't match. Timestamps are
    tz-aware in USER_TZ. When no end is provided, returns (start, None, False).
    For date-only inputs, returns (midnight, midnight+1d, True).
    """
    if not s:
        return None, None, False
    m = _RANGE_RE.match(s.strip())
    if not m:
        return None, None, False
    try:
        day_dt = datetime.strptime(f"{m['day']} {m['month']} {m['year']}", "%d %b %Y").date()
    except ValueError:
        try:
            day_dt = datetime.strptime(f"{m['day']} {m['month']} {m['year']}", "%d %B %Y").date()
        except ValueError:
            return None, None, False

    if not m["start"]:
        start = datetime.combine(day_dt, time(0, 0), tzinfo=USER_TZ)
        end = start + timedelta(days=1)
        return start, end, True

    start_t = datetime.strptime(m["start"], "%H:%M").time()
    start = datetime.combine(day_dt, start_t, tzinfo=USER_TZ)
    end: datetime | None = None
    if m["end"]:
        end_t = datetime.strptime(m["end"], "%H:%M").time()
        end = datetime.combine(day_dt, end_t, tzinfo=USER_TZ)
        # If the event crosses midnight (end < start), push end to next day.
        if end <= start:
            end = end + timedelta(days=1)
    return start, end, False


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
    for ev in raws:
        if not _should_include(ev):
            continue
        start_dt, end_dt, all_day = _parse_range(ev.start_str)
        data = {
            "start_time": _iso(start_dt) if start_dt else None,
            "end_time": _iso(end_dt) if end_dt else None,
            "location": ev.location,
            "notes": ev.notes,
            "calendar_name": ev.calendar_name,
            "all_day": bool(all_day or ev.all_day),
        }
        # Drop keys with None/empty-string to keep the JSON lean. Note: we
        # intentionally keep `all_day=False` so the iOS decoder always sees it.
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
