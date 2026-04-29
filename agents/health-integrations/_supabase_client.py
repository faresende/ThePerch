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


def bulk_upsert_health_metrics(rows: list[dict[str, Any]]) -> tuple[int, int]:
    """Bulk upsert N health_metrics rows in a single PostgREST call.

    `rows` is a list of dicts in the same shape `upsert_health_metric`
    builds for a single row (must include `user_id` already). Returns
    `(written, failed)`. Idempotent on the same
    `(user_id, source, source_id, metric)` tuple as the per-row helper.

    Why bulk: per-row upsert was costing ~100ms × N round-trips. Withings
    writes ~87 metrics, 8sleep ~111. Cumulative ingest time ~20s; bulk
    drops it to a single 200-300ms POST. PostgREST handles arrays of
    inserts with the same on_conflict semantics as single-row.

    Returns `(0, len(rows))` on any error so the caller's
    "failed" count reflects the real failure boundary (the batch).
    Per-row failures within a successful 2xx are not distinguished —
    `Prefer: resolution=merge-duplicates` makes them idempotent.
    """
    if not rows:
        return (0, 0)
    url, key, _ = _supabase_env()
    on_conflict = "user_id,source,source_id,metric"
    req = Request(
        f"{url}/rest/v1/health_metrics?on_conflict={on_conflict}",
        data=json.dumps(rows).encode(),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=minimal",
        },
    )
    try:
        with urlopen(req, timeout=30) as resp:
            ok = 200 <= resp.status < 300
            return (len(rows), 0) if ok else (0, len(rows))
    except HTTPError as e:
        sys.stderr.write(f"[supabase] bulk upsert: HTTP {e.code} {e.read().decode()[:300]}\n")
        return (0, len(rows))


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
    # PostgREST upsert needs BOTH the resolution=merge-duplicates Prefer
    # header AND an on_conflict query parameter pointing to the unique
    # constraint columns. Without on_conflict, PostgREST falls back to
    # the primary key (auto-generated UUID), which is unique on every
    # insert — so the merge never fires and the row's actual unique
    # constraint (user_id, source, source_id, metric) blows up on
    # duplicate. Caught in the wild after the first re-ingest day:
    # 87/87 inserts failed with 23505 duplicate key once rows from
    # yesterday's run already existed.
    on_conflict = "user_id,source,source_id,metric"
    req = Request(
        f"{url}/rest/v1/health_metrics?on_conflict={on_conflict}",
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


def _ensure_agent_registered(agent_id: str) -> bool:
    """Upsert a minimal public.agents row so FK-constrained writes succeed.

    public.dashboard_records.agent_id has a FK to agents(id); without
    a registered agent the first dashboard_records write fails with
    HTTP 409 / SQLSTATE 23503. public.agent_runs has no such FK, so
    agent_run inserts silently succeed and mask the problem until the
    real data write hits — caught the hard way by calendar_sync
    (commit 90e6b88, registered manually). Auto-registering here means
    new ingestors written against this helper just work.
    """
    url, key, user_id = _supabase_env()
    payload = {
        "id": agent_id,
        "display_name": agent_id,
        "model": f"python:{agent_id}",
        "is_active": True,
        "owner_id": user_id,
    }
    req = Request(
        f"{url}/rest/v1/agents?on_conflict=id",
        data=json.dumps(payload).encode(),
        method="POST",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "resolution=ignore-duplicates,return=minimal",
        },
    )
    try:
        with urlopen(req, timeout=10) as resp:
            return 200 <= resp.status < 300
    except HTTPError as e:
        sys.stderr.write(f"[supabase] agent register {agent_id}: HTTP {e.code} {e.read().decode()[:200]}\n")
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
    _ensure_agent_registered(agent_id)
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
