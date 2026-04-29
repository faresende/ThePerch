#!/usr/bin/env python3
"""
oura_ingest.py — pulls last-14d sleep + daily-sleep score + readiness
from the Oura Cloud API v2, normalises into public.health_metrics.

Oura is the SOURCE OF TRUTH for sleep data per the precedence wiring
in biochecha_dynamic_insight.py:SLEEP_SOURCE_PRIORITY. 8sleep stays
as the fallback / gap-filler (mostly for nights the ring's off the
charger).

Auth: a personal access token from
  https://cloud.ouraring.com/personal-access-tokens
Set in ~/.openclaw/secrets/perch.env:
  OURA_PERSONAL_TOKEN=...

Usage (cron every 30min):
    bash -c 'set -a && source ~/.openclaw/secrets/perch.env && set +a && \
             python3 ~/.openclaw/workspace/scripts/health-integrations/oura_ingest.py'

Idempotent: rows upsert by (user_id, source, source_id, metric) — the
existing health_metrics unique key. Re-running is a no-op.

API reference: https://cloud.ouraring.com/v2/docs
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, date, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).parent))
from _supabase_client import bulk_upsert_health_metrics, insert_agent_run  # noqa: E402

API_BASE = "https://api.ouraring.com/v2/usercollection"

# Days of history to pull. 14 is enough to cover a Pod-charging gap +
# any Oura sync delay; the upsert dedupes within Supabase.
LOOKBACK_DAYS = 14


def _api_get(path: str, token: str, params: dict[str, str]) -> dict[str, Any]:
    """GET against the Oura Cloud API v2. Raises on non-2xx — caller
    is responsible for swallowing into agent_runs telemetry."""
    url = f"{API_BASE}/{path}?{urlencode(params)}"
    req = Request(url, headers={
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    })
    with urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def _to_iso(d: date) -> str:
    return d.isoformat()


def _safe_get(d: dict, *keys, default=None):
    """Walk nested dict keys; return default if any step is missing."""
    cur: Any = d
    for k in keys:
        if not isinstance(cur, dict) or k not in cur:
            return default
        cur = cur[k]
    return cur


def _parse_oura_ts(raw: str | None) -> str | None:
    """Oura returns ISO-8601 with microseconds + offset. Re-emit as
    UTC-naive ISO so PostgREST is happy and the timestamp is
    timezone-stable."""
    if not raw:
        return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    return dt.astimezone(timezone.utc).isoformat()


def _sleep_session_rows(session: dict, user_id: str) -> list[dict]:
    """One row per metric for one sleep session. Skips fields the API
    didn't return for this session (Oura sometimes omits HRV on naps
    or short sleeps).

    Measurement timestamp = bedtime_end (when the user woke up). That
    aligns the daily reading with the morning the data is fresh, so
    the post-wake category sees today's row when it asks for "this
    morning's sleep"."""
    bedtime_end_iso = _parse_oura_ts(session.get("bedtime_end"))
    if not bedtime_end_iso:
        return []
    session_id = session.get("id") or session.get("day") or bedtime_end_iso
    rows: list[dict] = []

    # (Oura field, our metric, our unit, transform fn)
    field_map: list[tuple[str, str, str, Any]] = [
        ("total_sleep_duration",  "sleep_duration_min",     "min",  lambda s: s / 60),
        ("awake_time",            "sleep_awake_min",        "min",  lambda s: s / 60),
        ("deep_sleep_duration",   "sleep_deep_min",         "min",  lambda s: s / 60),
        ("rem_sleep_duration",    "sleep_rem_min",          "min",  lambda s: s / 60),
        ("light_sleep_duration",  "sleep_light_min",        "min",  lambda s: s / 60),
        ("latency",               "sleep_latency_min",      "min",  lambda s: s / 60),
        ("efficiency",            "sleep_efficiency_pct",   "percent", lambda x: x),
        ("average_hrv",           "hrv_rmssd_ms",           "ms",   lambda x: x),
        # Oura's `lowest_heart_rate` is a closer analog to traditional
        # RHR than `average_heart_rate` (which spans REM/awake spikes).
        ("lowest_heart_rate",     "resting_heart_rate_bpm", "bpm",  lambda x: x),
        ("average_breath",        "respiratory_rate_bpm",   "bpm",  lambda x: x),
    ]

    for oura_field, metric, unit, transform in field_map:
        raw = session.get(oura_field)
        if raw is None:
            continue
        try:
            value = float(transform(float(raw)))
        except (TypeError, ValueError):
            continue
        rows.append({
            "user_id": user_id,
            "metric": metric,
            "value": value,
            "unit": unit,
            "source": "oura",
            "source_id": f"oura-sleep-{session_id}-{metric}",
            "measured_at": bedtime_end_iso,
            "details": None,
        })
    return rows


def _daily_score_rows(entry: dict, user_id: str, *, metric: str,
                      score_field: str = "score") -> list[dict]:
    """Daily-grain rows (sleep score, readiness score). Oura gives one
    per day. measured_at = end of that local day in UTC, since the
    score reflects the night-just-finished."""
    day = entry.get("day")
    if not day:
        return []
    # Materialize as 23:59 UTC of `day` so it's deterministic and ranks
    # latest-of-the-day for dedup ties.
    measured_at = f"{day}T23:59:00+00:00"
    raw = entry.get(score_field)
    if raw is None:
        return []
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return []
    return [{
        "user_id": user_id,
        "metric": metric,
        "value": value,
        "unit": "score",
        "source": "oura",
        "source_id": f"oura-daily-{day}-{metric}",
        "measured_at": measured_at,
        "details": None,
    }]


def main() -> int:
    user_id = os.environ.get("PERCH_USER_ID")
    token = os.environ.get("OURA_PERSONAL_TOKEN")

    if not user_id:
        sys.stderr.write("[oura] PERCH_USER_ID not set\n")
        return 2
    if not token:
        sys.stderr.write(
            "[oura] OURA_PERSONAL_TOKEN not set. Generate one at "
            "https://cloud.ouraring.com/personal-access-tokens and add "
            "to ~/.openclaw/secrets/perch.env as:\n"
            "    export OURA_PERSONAL_TOKEN=ABC123...\n"
        )
        return 2

    started = datetime.now(timezone.utc)
    error: str | None = None
    written = 0
    failed = 0
    sleep_sessions = 0
    daily_sleep = 0
    daily_readiness = 0

    try:
        end = date.today()
        start = end - timedelta(days=LOOKBACK_DAYS)
        params = {"start_date": _to_iso(start), "end_date": _to_iso(end)}

        all_rows: list[dict] = []

        # 1. Sleep sessions — the meat: stages, HRV, RHR, efficiency.
        sleep = _api_get("sleep", token, params)
        for s in (sleep.get("data") or []):
            rows = _sleep_session_rows(s, user_id)
            if rows:
                sleep_sessions += 1
                all_rows.extend(rows)

        # 2. Daily sleep score (separate endpoint, one row per day).
        daily = _api_get("daily_sleep", token, params)
        for d in (daily.get("data") or []):
            rows = _daily_score_rows(d, user_id, metric="sleep_score")
            if rows:
                daily_sleep += 1
                all_rows.extend(rows)

        # 3. Readiness score — Oura's recovery proxy. Useful future
        # signal for a `score_recovery_today` category.
        readiness = _api_get("daily_readiness", token, params)
        for d in (readiness.get("data") or []):
            rows = _daily_score_rows(d, user_id, metric="readiness_score")
            if rows:
                daily_readiness += 1
                all_rows.extend(rows)

        if all_rows:
            written, failed = bulk_upsert_health_metrics(all_rows)

    except HTTPError as e:
        try:
            detail = e.read().decode("utf-8", errors="replace")[:300]
        except Exception:
            detail = ""
        error = f"HTTPError {e.code}: {detail}"
        sys.stderr.write(f"[oura] {error}\n")
    except (URLError, Exception) as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[oura] {error}\n")

    insert_agent_run(
        agent_id="biochecha",
        run_type="oura_ingest",
        status="error" if error else ("partial" if failed else "ok"),
        summary={
            "sleep_sessions": sleep_sessions,
            "daily_sleep_scores": daily_sleep,
            "daily_readiness_scores": daily_readiness,
            "rows_written": written,
            "rows_failed": failed,
            "lookback_days": LOOKBACK_DAYS,
        },
        error_detail=error,
    )
    print(f"[oura] sessions={sleep_sessions} daily_sleep={daily_sleep} "
          f"readiness={daily_readiness} written={written} failed={failed} "
          f"error={error}")
    return 1 if error else 0


if __name__ == "__main__":
    sys.exit(main())
