#!/usr/bin/env python3
"""
Withings ingest — pulls latest measurements (weight / body comp / BP /
heart rate) into public.health_metrics. Runs on cron (hourly is plenty).

Reads tokens from ~/.openclaw/state/withings-tokens.json — populated
the first time by withings_setup.py.

Usage (cron):
    bash -c 'set -a && source ~/.openclaw/secrets/perch.env && set +a && python3 ~/.openclaw/workspace/scripts/health-integrations/withings_ingest.py'

Withings API docs: https://developer.withings.com/api-reference
"""
from __future__ import annotations

import json
import os
import sys
import urllib.parse
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# Make the shared supabase helper importable.
sys.path.insert(0, str(Path(__file__).parent))
from _supabase_client import upsert_health_metric, insert_agent_run  # noqa: E402

TOKEN_URL = "https://wbsapi.withings.net/v2/oauth2"
MEASURE_URL = "https://wbsapi.withings.net/measure"

TOKENS_FILE = Path.home() / ".openclaw" / "state" / "withings-tokens.json"


# ─── Token management ──────────────────────────────────────────────


def _load_tokens() -> dict[str, Any]:
    if not TOKENS_FILE.exists():
        sys.stderr.write(
            "[withings] no tokens file. Run withings_setup.py first.\n"
        )
        sys.exit(2)
    return json.loads(TOKENS_FILE.read_text())


def _save_tokens(tokens: dict[str, Any]) -> None:
    TOKENS_FILE.write_text(json.dumps(tokens, indent=2))
    os.chmod(TOKENS_FILE, 0o600)


def _refresh_if_needed(tokens: dict[str, Any]) -> dict[str, Any]:
    """If access token expires in <5 min, refresh it. Returns updated tokens."""
    expires_at = datetime.fromisoformat(tokens["expires_at"].replace("Z", "+00:00"))
    if expires_at > datetime.now(timezone.utc) + timedelta(minutes=5):
        return tokens

    client_id = os.environ.get("WITHINGS_CLIENT_ID")
    client_secret = os.environ.get("WITHINGS_CLIENT_SECRET")
    if not client_id or not client_secret:
        raise RuntimeError("WITHINGS_CLIENT_ID/SECRET missing; cannot refresh")
    body = urllib.parse.urlencode({
        "action": "requesttoken",
        "grant_type": "refresh_token",
        "client_id": client_id,
        "client_secret": client_secret,
        "refresh_token": tokens["refresh_token"],
    }).encode()
    req = Request(
        TOKEN_URL,
        data=body,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urlopen(req, timeout=15) as resp:
        payload = json.loads(resp.read())
    if payload.get("status") != 0:
        raise RuntimeError(f"refresh failed: {payload}")
    body_payload = payload.get("body") or {}
    new_expires = datetime.now(timezone.utc) + timedelta(seconds=int(body_payload.get("expires_in") or 0))
    tokens.update({
        "access_token": body_payload.get("access_token"),
        "refresh_token": body_payload.get("refresh_token") or tokens.get("refresh_token"),
        "expires_at": new_expires.isoformat(),
        "scope": body_payload.get("scope") or tokens.get("scope"),
    })
    _save_tokens(tokens)
    return tokens


# ─── Withings measurement codes → our metric keys ─────────────────


# https://developer.withings.com/api-reference#tag/measure/operation/measure-getmeas
# meastype values we care about. Add more here as they become useful.
MEASURE_TYPES: dict[int, tuple[str, str, float]] = {
    # type → (metric, unit, scale-factor-for-display)
    1:  ("weight_kg",          "kg",      1.0),    # Weight (kg)
    4:  ("height_m",           "m",       1.0),    # Height (m)
    5:  ("fat_free_mass_kg",   "kg",      1.0),    # Fat-free mass
    6:  ("body_fat_pct",       "percent", 1.0),    # Fat ratio %
    8:  ("fat_mass_kg",        "kg",      1.0),    # Fat mass
    9:  ("bp_diastolic_mmhg",  "mmHg",    1.0),    # Diastolic
    10: ("bp_systolic_mmhg",   "mmHg",    1.0),    # Systolic
    11: ("heart_rate_bpm",     "bpm",     1.0),    # Heart pulse
    12: ("temperature_c",      "C",       1.0),    # Temperature
    71: ("body_temperature_c", "C",       1.0),    # Body temperature
    73: ("skin_temperature_c", "C",       1.0),    # Skin temperature
    76: ("muscle_mass_kg",     "kg",      1.0),    # Muscle mass
    77: ("hydration_kg",       "kg",      1.0),    # Hydration
    88: ("bone_mass_kg",       "kg",      1.0),    # Bone mass
    91: ("pulse_wave_velocity_ms", "m/s", 1.0),    # PWV
}


def _api_get_measures(access_token: str, *, since_ts: int) -> dict[str, Any]:
    # Filter by MEASUREMENT date (`startdate`/`enddate`), not by record
    # last-modified time (`lastupdate`). With `lastupdate`, the Withings
    # API only returns records that were SYNCED in the window — so a
    # weight scale that synced months ago and hasn't been touched
    # since silently disappears even though the underlying measurement
    # is recent. `startdate`/`enddate` filter on the measurement date
    # itself, which is what we actually want.
    body = urllib.parse.urlencode({
        "action": "getmeas",
        "startdate": since_ts,
        "enddate": int(datetime.now(timezone.utc).timestamp()),
        # Pull all the measurement types we know about, comma-separated.
        "meastypes": ",".join(str(k) for k in MEASURE_TYPES.keys()),
        "category": 1,  # 1 = real measures (vs. user-entered objectives)
    }).encode()
    req = Request(
        MEASURE_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    with urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


# ─── Main ──────────────────────────────────────────────────────────


def main() -> int:
    started = datetime.now(timezone.utc)
    written = 0
    failed = 0
    error: str | None = None

    try:
        tokens = _refresh_if_needed(_load_tokens())
        access = tokens["access_token"]
        # Pull the last 60 days of measurements. Idempotency in upsert
        # collapses repeats, so re-running an hour later just adds new
        # readings without duplicating prior ones. Window is 60 days
        # (not 7) because Withings users sometimes go a few weeks
        # between weigh-ins / BP readings — a 7-day window misses those
        # users entirely. Caught in the wild: the user's most recent
        # weigh-in was 17 days ago when we first ran ingest.
        since = int((started - timedelta(days=60)).timestamp())
        payload = _api_get_measures(access, since_ts=since)
        if payload.get("status") != 0:
            raise RuntimeError(f"Withings getmeas status={payload.get('status')}: {payload}")

        groups = (payload.get("body") or {}).get("measuregrps") or []
        for group in groups:
            grp_id = group.get("grpid")
            ts = group.get("date")  # epoch seconds
            measured_at = datetime.fromtimestamp(int(ts), tz=timezone.utc).isoformat()

            for measure in group.get("measures") or []:
                meastype = measure.get("type")
                value_raw = measure.get("value")
                unit_exp = measure.get("unit", 0)  # base-10 exponent
                if meastype not in MEASURE_TYPES or value_raw is None:
                    continue
                metric, unit, _scale = MEASURE_TYPES[meastype]
                value = float(value_raw) * (10 ** int(unit_exp))
                ok = upsert_health_metric(
                    metric=metric,
                    value=value,
                    unit=unit,
                    source="withings",
                    source_id=f"withings-{grp_id}-{meastype}",
                    measured_at_iso=measured_at,
                    details=None,
                )
                if ok:
                    written += 1
                else:
                    failed += 1

    except (HTTPError, URLError) as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[withings] fatal: {error}\n")
    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[withings] fatal: {error}\n")

    insert_agent_run(
        agent_id="biochecha",
        run_type="withings_ingest",
        status="error" if error else ("partial" if failed > 0 else "ok"),
        summary={"written": written, "failed": failed},
        error_detail=error,
    )
    print(f"[withings] written={written} failed={failed} error={error}")
    return 1 if error else 0


if __name__ == "__main__":
    sys.exit(main())
