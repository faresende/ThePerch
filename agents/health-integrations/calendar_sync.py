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

First-run note: macOS will prompt the terminal app for Calendar access
the first time this runs. Grant it. Without permission, this script
exits with `error="No calendars."` and the time-aware insights'
opportunity-based categories silently degrade to 0 score.
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
    try:
        with urlopen(req, timeout=15) as resp:
            return resp.status
    except HTTPError as e:
        # PostgREST puts the actual error reason in the response body —
        # surface it so 4xx/5xx debugging doesn't require curl reproduction.
        try:
            detail = e.read().decode("utf-8", errors="replace")
        except Exception:
            detail = ""
        raise RuntimeError(f"POST {path} HTTP {e.code}: {detail[:500]}") from e


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
                    "agent_id": "calendar-sync",
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
