#!/usr/bin/env python3
"""
prune_agent_runs.py — daily retention for public.agent_runs.

Calls the prune_agent_runs(p_days) RPC, which deletes status='ok'
rows older than the cutoff (default 90 days). Errors and partials
are kept forever (they're the diagnostic trail).

The RPC enforces a 7-day safety floor, so even a misconfigured
caller can't accidentally wipe recent operational history.

Env required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY.

Suggested cron:
  0 4 * * *   # 04:00 Lisbon, runs once a day
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

sys.path.insert(0, str(Path(__file__).parent))
from _supabase_client import insert_agent_run  # noqa: E402

DAYS = int(os.environ.get("AGENT_RUNS_RETENTION_DAYS", "90"))


def main() -> int:
    url = os.environ.get("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url or not key:
        sys.stderr.write("[prune-agent-runs] missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY\n")
        return 2

    error: str | None = None
    deleted = 0
    try:
        body = json.dumps({"p_days": DAYS}).encode()
        req = Request(
            f"{url.rstrip('/')}/rest/v1/rpc/prune_agent_runs",
            data=body,
            method="POST",
            headers={
                "apikey": key,
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
            },
        )
        with urlopen(req, timeout=30) as resp:
            payload = resp.read().decode("utf-8") or "0"
            try:
                deleted = int(payload.strip())
            except ValueError:
                deleted = int(json.loads(payload))
    except HTTPError as e:
        try:
            detail = e.read().decode("utf-8", errors="replace")[:300]
        except Exception:
            detail = ""
        error = f"HTTPError {e.code}: {detail}"
        sys.stderr.write(f"[prune-agent-runs] {error}\n")
    except (URLError, Exception) as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[prune-agent-runs] {error}\n")

    insert_agent_run(
        agent_id="biochecha",
        run_type="prune_agent_runs",
        status="error" if error else "ok",
        summary={"deleted": deleted, "retention_days": DAYS},
        error_detail=error,
    )
    print(f"[prune-agent-runs] deleted={deleted} retention_days={DAYS} error={error}")
    return 1 if error else 0


if __name__ == "__main__":
    sys.exit(main())
