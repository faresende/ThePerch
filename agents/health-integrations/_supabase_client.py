#!/usr/bin/env python3
"""
Shared Supabase HTTP helper for the health-integration ingest scripts.

Reads SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY + PERCH_USER_ID from env.
On import, auto-loads `~/.openclaw/secrets/perch.env` if present and the
required vars aren't already in the environment — same resolution chain
as the dashboard-sync `cli.js` so the user never has to remember
`set -a && source ... && python3 ...`. Talks to PostgREST directly —
no SDK dependency, keeps the scripts portable.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen


# ─── Env auto-loader (mirrors cli.js behaviour) ─────────────────────


def _load_env_file(path: Path) -> bool:
    """Parse a shell-exportable env file. Returns True if loaded."""
    if not path.exists():
        return False
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Strip optional `export ` prefix so shell-source format works.
        if line.startswith("export "):
            line = line[len("export "):]
        if "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        val = val.strip()
        # Strip wrapping quotes if present.
        if (val.startswith('"') and val.endswith('"')) or (val.startswith("'") and val.endswith("'")):
            val = val[1:-1]
        # Only set if not already in environment (caller's explicit env wins).
        if key and not os.environ.get(key):
            os.environ[key] = val
    return True


def _autoload_env_once() -> None:
    """Auto-load perch.env at import time if Supabase vars aren't set.

    Same resolution chain as the dashboard-sync skill's cli.js so behaviour
    is consistent across the Python + Node halves of the stack.
    """
    needed = ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY", "PERCH_USER_ID")
    if all(os.environ.get(k) for k in needed):
        return
    candidates = [
        os.environ.get("DASHBOARD_SYNC_ENV_FILE"),
        Path.home() / ".openclaw/secrets/dashboard-sync.env",
        Path.home() / ".openclaw/secrets/perch.env",
    ]
    for c in candidates:
        if c and _load_env_file(Path(c)):
            return


_autoload_env_once()


def _supabase_env() -> tuple[str, str, str]:
    url = os.environ.get("SUPABASE_URL", "").rstrip("/")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    user = os.environ.get("PERCH_USER_ID", "")
    if not url or not key or not user:
        sys.stderr.write(
            "[supabase] missing env. Source ~/.openclaw/secrets/perch.env first.\n"
        )
        sys.exit(2)
    return url, key, user


def upsert_health_metric(
    *,
    metric: str,
    value: float,
    unit: str | None,
    source: str,
    source_id: str | None,
    measured_at_iso: str,
    details: dict[str, Any] | None = None,
) -> bool:
    """Insert or upsert one health_metrics row. Returns True on 2xx.

    Idempotent: PostgREST `Prefer: resolution=merge-duplicates` collapses
    repeat (user_id, source, source_id, metric) inserts to a single row.
    """
    url, key, user_id = _supabase_env()
    payload = {
        "user_id": user_id,
        "metric": metric,
        "value": value,
        "unit": unit,
        "source": source,
        "source_id": source_id,
        "measured_at": measured_at_iso,
        "details": details,
    }
    req = Request(
        f"{url}/rest/v1/health_metrics",
        data=json.dumps(payload).encode(),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal",
        },
    )
    try:
        with urlopen(req, timeout=15) as resp:
            return 200 <= resp.status < 300
    except HTTPError as e:
        sys.stderr.write(f"[supabase] upsert {metric}: HTTP {e.code} {e.read().decode()[:200]}\n")
        return False


def insert_agent_run(
    *,
    agent_id: str,
    run_type: str,
    status: str = "ok",
    summary: dict[str, Any] | None = None,
    error_detail: str | None = None,
) -> bool:
    """Record an agent run in public.agent_runs for observability."""
    url, key, _ = _supabase_env()
    from datetime import datetime, timezone

    now = datetime.now(timezone.utc).isoformat()
    payload = {
        "agent_id": agent_id,
        "run_type": run_type,
        "started_at": now,
        "ended_at": now,
        "status": status,
        "summary": summary,
        "error_detail": error_detail,
    }
    req = Request(
        f"{url}/rest/v1/agent_runs",
        data=json.dumps(payload).encode(),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
        },
    )
    try:
        with urlopen(req, timeout=10) as resp:
            return 200 <= resp.status < 300
    except HTTPError as e:
        sys.stderr.write(f"[supabase] agent_run insert: HTTP {e.code} {e.read().decode()[:200]}\n")
        return False
