#!/usr/bin/env python3
"""
8sleep ingest — pulls last-24h sleep sessions + trends from the
reverse-engineered private API used by the Pod app, normalises into
public.health_metrics rows.

Auth: email + password from ~/.openclaw/secrets/perch.env:
    EIGHT_SLEEP_EMAIL
    EIGHT_SLEEP_PASSWORD

Auth tokens cached in ~/.openclaw/state/8sleep-token.json (JWT plus
refresh token). Refreshed automatically when expired.

Risk: 8sleep can change endpoints at any time. Failures land in
public.agent_runs with status='error' so they're visible immediately
in the autopilot health view.

Usage (cron):
    bash -c 'set -a && source ~/.openclaw/secrets/perch.env && set +a && python3 ~/.openclaw/workspace/scripts/health-integrations/eight_sleep_ingest.py'

Schedule: every 30 minutes is fine. Sessions don't update mid-night
in any meaningful way — once-per-night data plus trend updates.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# Make the shared supabase helper importable. Importing it also
# auto-loads ~/.openclaw/secrets/perch.env into os.environ if needed,
# so EIGHT_SLEEP_EMAIL/PASSWORD lookups below "just work" without
# requiring `set -a && source ... && python3 ...`.
sys.path.insert(0, str(Path(__file__).parent))
from _supabase_client import (  # noqa: E402
    bulk_upsert_health_metrics,
    insert_agent_run,
)

# 8sleep moved auth to a proper OAuth password-grant endpoint at
# auth-api.8slp.net in early 2024. The old client-api `/v1/login`
# still returns a session-token but the data API rejects it with
# "session token not supported".
#
# The client_id + client_secret below are extracted from the official
# iOS Pod app — they identify the app, not the user. Multiple open-
# source community projects ship the same constants (the alternative
# would be every fork having to MITM the iOS app to obtain them).
# That said:
#
#   - Eight Sleep does not officially support third-party API access.
#     They may roll these credentials at any time, breaking this
#     integration for everyone. There is no official replacement.
#   - Distributing app-extracted credentials may breach Eight Sleep's
#     ToS. Use this script for personal data access only; do not
#     redistribute as a service.
#
# If 8sleep eventually publishes an official API, switch to it and
# rip these out.
LOGIN_URL = "https://auth-api.8slp.net/v1/tokens"
APP_BASE = "https://app-api.8slp.net"
EIGHT_SLEEP_CLIENT_ID = "0894c7f33bb94800a03f1f4df13a4f38"
EIGHT_SLEEP_CLIENT_SECRET = (
    "f0954a3ed5763ba3d06834c73731a32f15f168f47d4f164751275def86db0c76"
)

TOKEN_CACHE = Path.home() / ".openclaw" / "state" / "8sleep-token.json"
TOKEN_CACHE.parent.mkdir(parents=True, exist_ok=True)


# ─── Auth ───────────────────────────────────────────────────────────


def _login(email: str, password: str) -> dict[str, Any]:
    """OAuth password grant → returns dict with access_token etc.

    Body (per the OAuth 2 password-grant flow that 8sleep adopted):
        {
          "client_id": "...",          # baked-in from official iOS app
          "client_secret": "...",      # baked-in
          "grant_type": "password",
          "username": "<email>",
          "password": "<password>"
        }

    Response includes `access_token`, `userId`, `expiresIn`, `refreshToken`.
    """
    body = json.dumps({
        "client_id": EIGHT_SLEEP_CLIENT_ID,
        "client_secret": EIGHT_SLEEP_CLIENT_SECRET,
        "grant_type": "password",
        "username": email,
        "password": password,
    }).encode()
    req = Request(
        LOGIN_URL,
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "Eight%20Sleep/3.6.0 (com.eightsleep.sleep; build:1; iOS 17.0.0) Alamofire/5.6.4",
        },
    )
    try:
        with urlopen(req, timeout=15) as resp:
            return json.loads(resp.read())
    except HTTPError as e:
        body_text = e.read().decode(errors="replace")[:300]
        raise RuntimeError(f"login HTTP {e.code}: {body_text}") from None


def _load_cached_session() -> tuple[str, str] | None:
    """Returns (token, user_id) if cache is fresh, else None."""
    if not TOKEN_CACHE.exists():
        return None
    try:
        cached = json.loads(TOKEN_CACHE.read_text())
        expires_at = cached.get("expiresAt")
        if expires_at:
            exp = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
            if exp > datetime.now(timezone.utc) + timedelta(minutes=5):
                token = cached.get("token")
                user_id = cached.get("userId")
                if token and user_id:
                    return token, user_id
    except Exception:
        pass
    return None


def _save_session(token: str, user_id: str, expires_at_iso: str) -> None:
    """Persist token + userId + the API-given expiration."""
    TOKEN_CACHE.write_text(
        json.dumps(
            {"token": token, "userId": user_id, "expiresAt": expires_at_iso},
            indent=2,
        )
    )
    os.chmod(TOKEN_CACHE, 0o600)


def _get_session() -> tuple[str, str]:
    """Returns (token, user_id). Logs in fresh when cache expired."""
    if cached := _load_cached_session():
        return cached
    email = os.environ.get("EIGHT_SLEEP_EMAIL")
    password = os.environ.get("EIGHT_SLEEP_PASSWORD")
    if not email or not password:
        sys.stderr.write(
            "[8sleep] missing EIGHT_SLEEP_EMAIL or EIGHT_SLEEP_PASSWORD. "
            "Add them to ~/.openclaw/secrets/perch.env.\n"
        )
        sys.exit(2)
    resp = _login(email, password)
    # OAuth response shape: { access_token, expires_in (seconds),
    # refresh_token, userId }
    token = resp.get("access_token")
    user_id = resp.get("userId")
    expires_in = int(resp.get("expires_in") or 3600)
    expires_at = (
        datetime.now(timezone.utc) + timedelta(seconds=expires_in)
    ).isoformat()
    if not token or not user_id:
        raise RuntimeError(f"login response missing access_token/userId: {resp}")
    _save_session(token, user_id, expires_at)
    return token, user_id


# ─── API calls ──────────────────────────────────────────────────────


def _api_get(path: str, token: str, user_id: str | None = None) -> dict[str, Any]:
    """GET `${APP_BASE}${path}` with the OAuth bearer token.

    Post-2024 8sleep auth: standard OAuth `Authorization: Bearer`
    against the access_token returned by /v1/tokens. The legacy
    Session-Token header is no longer accepted.
    """
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
        "User-Agent": "Eight%20Sleep/3.6.0 (com.eightsleep.sleep; build:1; iOS 17.0.0) Alamofire/5.6.4",
    }
    if user_id:
        headers["User-Id"] = user_id
    req = Request(f"{APP_BASE}{path}", headers=headers)
    try:
        with urlopen(req, timeout=20) as resp:
            return json.loads(resp.read())
    except HTTPError as e:
        body_text = e.read().decode(errors="replace")[:300]
        raise RuntimeError(f"GET {path} HTTP {e.code}: {body_text}") from None


def fetch_recent_sessions(token: str, user_id: str) -> list[dict[str, Any]]:
    """Latest sleep sessions (most recent first). The `/sessions`
    endpoint returns ALL recent sessions in one call — no need for a
    `from`/`to` window since we dedupe via session.id on upsert.
    Each session contains stages + timeseries (HRV/RMSSD/HR/etc.)."""
    data = _api_get(
        f"/v1/users/{user_id}/sessions",
        token,
        user_id=user_id,
    )
    return data.get("sessions") or []


# ─── Normalise → health_metrics rows ────────────────────────────────


def _avg(values: list[float]) -> float | None:
    """Mean of non-empty list. Returns None for empty input."""
    if not values:
        return None
    return sum(values) / len(values)


def _ts_values(timeseries: dict[str, Any], key: str) -> list[float]:
    """Pull just the values out of an 8sleep timeseries entry.

    Timeseries entries are arrays of `[ts, value]` pairs. We don't
    need the timestamps for daily aggregates; just the value column.
    Filters out None / non-numeric entries defensively.
    """
    series = timeseries.get(key) or []
    out: list[float] = []
    for entry in series:
        if isinstance(entry, list) and len(entry) >= 2 and isinstance(entry[1], (int, float)):
            out.append(float(entry[1]))
    return out


def _session_to_metrics(session: dict[str, Any]) -> list[dict[str, Any]]:
    """Translate one 8sleep session payload into health_metrics rows.

    Schema (post-2024 8sleep API):
      - `id`, `ts` (sleep start), `sleepEnd`
      - `duration` (seconds, total in bed)
      - `score` (0-100 sleep score)
      - `stages` array of `{stage, duration}`. Stages: light, deep,
        rem, out, awake. "out" = bed unoccupied (e.g. bathroom run).
      - `timeseries` with arrays-of-[timestamp, value] for:
          heartRate, hrv (raw), rmssd (the canonical HRV metric in ms),
          respiratoryRate, tempBedC, tempRoomC, tnt, shortAwakes
    """
    rows: list[dict[str, Any]] = []
    sid = session.get("id")
    measured_at = session.get("sleepEnd") or session.get("ts")
    if not sid or not measured_at:
        return rows

    # Total in-bed time
    if (duration := session.get("duration")) is not None:
        rows.append({
            "metric": "time_in_bed_min",
            "value": float(duration) / 60.0,
            "unit": "minutes",
            "source_id": f"{sid}-tib",
            "measured_at": measured_at,
        })

    # Sleep score (still computing on a freshly-ended session — value 0
    # is normal for the latest row, will fill in later).
    if (score := session.get("score")) is not None and score > 0:
        rows.append({
            "metric": "sleep_score",
            "value": float(score),
            "unit": "score",
            "source_id": f"{sid}-score",
            "measured_at": measured_at,
        })

    # Stage durations — sum across the array. "out" means "not in bed";
    # everything else counts as time in bed. Real "sleep duration" =
    # in-bed minus awake minus out.
    stage_seconds: dict[str, float] = {}
    for entry in session.get("stages") or []:
        stage = entry.get("stage")
        dur = entry.get("duration")
        if not stage or not isinstance(dur, (int, float)):
            continue
        stage_seconds[stage] = stage_seconds.get(stage, 0.0) + float(dur)

    for stage_key, metric_key in [
        ("deep", "sleep_deep_min"),
        ("rem", "sleep_rem_min"),
        ("light", "sleep_light_min"),
        ("awake", "sleep_awake_min"),
        ("out", "sleep_out_of_bed_min"),
    ]:
        if stage_key in stage_seconds:
            rows.append({
                "metric": metric_key,
                "value": stage_seconds[stage_key] / 60.0,
                "unit": "minutes",
                "source_id": f"{sid}-{stage_key}",
                "measured_at": measured_at,
            })

    # Computed total sleep = sum of light + rem + deep (excludes "out"
    # and "awake"). Most useful single number for downstream insight.
    asleep_seconds = sum(
        stage_seconds.get(s, 0.0) for s in ("light", "rem", "deep")
    )
    if asleep_seconds > 0:
        rows.append({
            "metric": "sleep_duration_min",
            "value": asleep_seconds / 60.0,
            "unit": "minutes",
            "source_id": f"{sid}-sleep",
            "measured_at": measured_at,
        })

    # Timeseries-derived: HRV (rmssd), heart rate, respiratory rate,
    # bed/room temperature averages. These are aggregated across the
    # whole night so BioChecha gets one number per metric per session.
    ts = session.get("timeseries") or {}
    if (rmssd := _avg(_ts_values(ts, "rmssd"))) is not None:
        rows.append({
            "metric": "hrv_rmssd_ms",
            "value": rmssd,
            "unit": "ms",
            "source_id": f"{sid}-rmssd",
            "measured_at": measured_at,
        })
    hr_values = _ts_values(ts, "heartRate")
    if hr_values:
        # Resting heart rate ≈ minimum sustained HR during sleep. Using
        # min directly is noisy (single-sample dips); take the 5th
        # percentile to be robust.
        sorted_hr = sorted(hr_values)
        idx = max(0, int(len(sorted_hr) * 0.05))
        rows.append({
            "metric": "resting_heart_rate_bpm",
            "value": sorted_hr[idx],
            "unit": "bpm",
            "source_id": f"{sid}-rhr",
            "measured_at": measured_at,
        })
    if (rr := _avg(_ts_values(ts, "respiratoryRate"))) is not None:
        rows.append({
            "metric": "respiratory_rate_bpm",
            "value": rr,
            "unit": "breaths/min",
            "source_id": f"{sid}-rr",
            "measured_at": measured_at,
        })
    if (bed_t := _avg(_ts_values(ts, "tempBedC"))) is not None:
        rows.append({
            "metric": "bed_temperature_c",
            "value": bed_t,
            "unit": "C",
            "source_id": f"{sid}-bedtemp",
            "measured_at": measured_at,
        })
    if (room_t := _avg(_ts_values(ts, "tempRoomC"))) is not None:
        rows.append({
            "metric": "room_temperature_c",
            "value": room_t,
            "unit": "C",
            "source_id": f"{sid}-roomtemp",
            "measured_at": measured_at,
        })

    return rows


# ─── Main ───────────────────────────────────────────────────────────


def main() -> int:
    started = datetime.now(timezone.utc)
    written = 0
    failed = 0
    error: str | None = None
    rows: list[dict[str, Any]] = []  # Phase 3 perf: batched once at end

    try:
        token, user_id = _get_session()
        sessions = fetch_recent_sessions(token, user_id)
        for session in sessions:
            for row in _session_to_metrics(session):
                rows.append({
                    "user_id": os.environ["PERCH_USER_ID"],
                    "metric": row["metric"],
                    "value": row["value"],
                    "unit": row["unit"],
                    "source": "8sleep",
                    "source_id": row["source_id"],
                    "measured_at": row["measured_at"],
                    "details": None,
                })

        # Single bulk POST. ~111 metrics × 100ms = 11s previously;
        # now one ~250ms request.
        if rows:
            written, failed = bulk_upsert_health_metrics(rows)

    except (HTTPError, URLError) as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[8sleep] fatal: {error}\n")
    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[8sleep] fatal: {error}\n")

    insert_agent_run(
        agent_id="biochecha",
        run_type="8sleep_ingest",
        status="error" if error else ("partial" if failed > 0 else "ok"),
        summary={"written": written, "failed": failed},
        error_detail=error,
    )
    print(f"[8sleep] written={written} failed={failed} error={error}")
    return 1 if error else 0


if __name__ == "__main__":
    sys.exit(main())
