#!/usr/bin/env python3
"""
Shared Supabase HTTP helper for the health-integration ingest scripts.

Reads SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY + PERCH_USER_ID from env
(populated by sourcing ~/.openclaw/secrets/perch.env). Talks to PostgREST
directly — no SDK dependency, keeps the scripts portable.
"""
from __future__ import annotations

import json
import os
import sys
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen


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
