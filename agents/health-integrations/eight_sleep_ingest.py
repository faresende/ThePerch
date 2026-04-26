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

# Make the shared supabase helper importable.
sys.path.insert(0, str(Path(__file__).parent))
from _supabase_client import upsert_health_metric, insert_agent_run  # noqa: E402

LOGIN_URL = "https://api.8slp.net/v1/login"
APP_BASE = "https://app-api.8slp.net"

TOKEN_CACHE = Path.home() / ".openclaw" / "state" / "8sleep-token.json"
TOKEN_CACHE.parent.mkdir(parents=True, exist_ok=True)


# ─── Auth ───────────────────────────────────────────────────────────


def _login(email: str, password: str) -> dict[str, Any]:
    """POST credentials → returns dict with `session.token` etc."""
    body = json.dumps({"email": email, "password": password}).encode()
    req = Request(
        LOGIN_URL,
        data=body,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    with urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def _load_cached_token() -> str | None:
    if not TOKEN_CACHE.exists():
        return None
    try:
        cached = json.loads(TOKEN_CACHE.read_text())
        # Use cached token if not expired (with 5-min buffer).
        expires_at = cached.get("expiresAt")
        if expires_at:
            exp = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
            if exp > datetime.now(timezone.utc) + timedelta(minutes=5):
                return cached.get("token")
    except Exception:
        pass
    return None


def _save_token(token: str, expires_in_seconds: int = 3600) -> None:
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=expires_in_seconds)
    TOKEN_CACHE.write_text(
        json.dumps(
            {"token": token, "expiresAt": expires_at.isoformat()},
            indent=2,
        )
    )
    os.chmod(TOKEN_CACHE, 0o600)


def _get_token() -> str:
    """Cached-or-fresh JWT for the 8sleep API."""
    if cached := _load_cached_token():
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
    session = resp.get("session") or {}
    token = session.get("token")
    if not token:
        raise RuntimeError(f"login response missing token: {resp}")
    _save_token(token)
    return token


# ─── API calls ──────────────────────────────────────────────────────


def _api_get(path: str, token: str) -> dict[str, Any]:
    """GET `${APP_BASE}${path}` with the bearer token."""
    req = Request(
        f"{APP_BASE}{path}",
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/json",
            "User-Agent": "ThePerch/1.0 (8sleep ingest)",
        },
    )
    with urlopen(req, timeout=20) as resp:
        return json.loads(resp.read())


def fetch_recent_intervals(token: str, *, hours_back: int = 36) -> list[dict[str, Any]]:
    """Last-N-hours of sleep intervals. Each interval = one session."""
    since = (datetime.now(timezone.utc) - timedelta(hours=hours_back)).isoformat()
    until = datetime.now(timezone.utc).isoformat()
    data = _api_get(
        f"/v1/users/me/intervals?from={since}&to={until}",
        token,
    )
    return data.get("intervals") or []


def fetch_recent_trends(token: str) -> dict[str, Any]:
    """Latest HRV / RHR / sleep-score trends. Returns most recent values."""
    return _api_get("/v2/users/me/trends?days=1", token)


# ─── Normalise → health_metrics rows ────────────────────────────────


def _interval_to_metrics(interval: dict[str, Any]) -> list[dict[str, Any]]:
    """Pull the metrics we care about out of one interval payload."""
    rows: list[dict[str, Any]] = []
    sid = interval.get("id") or interval.get("interval_id")
    end_ts = interval.get("ts") or interval.get("end")
    if not sid or not end_ts:
        return rows
    measured_at = end_ts if "T" in end_ts else f"{end_ts}T00:00:00Z"

    # Total sleep duration
    if "total_in_bed_seconds" in interval:
        rows.append({
            "metric": "time_in_bed_min",
            "value": float(interval["total_in_bed_seconds"]) / 60.0,
            "unit": "minutes",
            "source_id": f"{sid}-tib",
            "measured_at": measured_at,
            "details": None,
        })
    sleep_seconds = (
        interval.get("sleep_seconds")
        or interval.get("total_sleep_seconds")
        or (interval.get("score", {}) or {}).get("sleep_seconds")
    )
    if sleep_seconds:
        rows.append({
            "metric": "sleep_duration_min",
            "value": float(sleep_seconds) / 60.0,
            "unit": "minutes",
            "source_id": f"{sid}-sleep",
            "measured_at": measured_at,
            "details": None,
        })

    # Sleep score (0-100)
    score = (interval.get("score") or {}).get("score")
    if score is not None:
        rows.append({
            "metric": "sleep_score",
            "value": float(score),
            "unit": "score",
            "source_id": f"{sid}-score",
            "measured_at": measured_at,
            "details": None,
        })

    # Sleep stages: deep, REM, light, awake (in seconds → minutes)
    stages = interval.get("stages") or {}
    for stage_key, metric_key in [
        ("deep", "sleep_deep_min"),
        ("rem", "sleep_rem_min"),
        ("light", "sleep_light_min"),
        ("awake", "sleep_awake_min"),
    ]:
        seconds = stages.get(stage_key)
        if seconds is not None:
            rows.append({
                "metric": metric_key,
                "value": float(seconds) / 60.0,
                "unit": "minutes",
                "source_id": f"{sid}-{stage_key}",
                "measured_at": measured_at,
                "details": None,
            })

    # HRV / RHR — sometimes embedded in the interval
    if (hrv := interval.get("hrv")) is not None:
        rows.append({
            "metric": "hrv_rmssd_ms",
            "value": float(hrv),
            "unit": "ms",
            "source_id": f"{sid}-hrv",
            "measured_at": measured_at,
            "details": None,
        })
    if (rhr := interval.get("resting_heart_rate")) is not None:
        rows.append({
            "metric": "resting_heart_rate_bpm",
            "value": float(rhr),
            "unit": "bpm",
            "source_id": f"{sid}-rhr",
            "measured_at": measured_at,
            "details": None,
        })

    return rows


# ─── Main ───────────────────────────────────────────────────────────


def main() -> int:
    started = datetime.now(timezone.utc)
    written = 0
    failed = 0
    error: str | None = None

    try:
        token = _get_token()
        intervals = fetch_recent_intervals(token)
        for interval in intervals:
            for row in _interval_to_metrics(interval):
                ok = upsert_health_metric(
                    metric=row["metric"],
                    value=row["value"],
                    unit=row["unit"],
                    source="8sleep",
                    source_id=row["source_id"],
                    measured_at_iso=row["measured_at"],
                    details=row["details"],
                )
                if ok:
                    written += 1
                else:
                    failed += 1
        # Trends — single payload of latest values
        try:
            trends = fetch_recent_trends(token)
            now_iso = started.isoformat()
            # Dig into common trend keys; tolerate schema drift.
            for tk, mk, unit in [
                ("hrv", "hrv_rmssd_ms", "ms"),
                ("heart_rate", "resting_heart_rate_bpm", "bpm"),
                ("sleep_score", "sleep_score", "score"),
            ]:
                v = trends.get(tk)
                if isinstance(v, dict):
                    v = v.get("value") or v.get("avg")
                if isinstance(v, (int, float)):
                    if upsert_health_metric(
                        metric=mk,
                        value=float(v),
                        unit=unit,
                        source="8sleep",
                        source_id=f"trend-{started.date().isoformat()}-{mk}",
                        measured_at_iso=now_iso,
                        details=None,
                    ):
                        written += 1
                    else:
                        failed += 1
        except Exception as e:
            sys.stderr.write(f"[8sleep] trends fetch failed: {e}\n")

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
