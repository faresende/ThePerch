#!/usr/bin/env python3
"""
orders_ingest_catchup.py

Safety-net ingester. Runs every 12h (cron) to catch any email the real-time
listener missed during restarts, JMAP outages, or classifier failures.

Flow:
  1. Fetch Fastmail emails received in the last `--lookback-hours` (default 48).
  2. For each email not already in the state file, feed it to the TS
     classifier via `node <dashboard-sync>/cli.js process-email`.
  3. Record the result in the state file (`~/.openclaw/workspace/state/
     orders-ingest-state.json`).
  4. Print a summary. Exit non-zero only on unrecoverable errors.

Env:
  PERCH_STATE_DIR               override the default state dir
  DASHBOARD_SYNC_DIR            override the default skill path
  PERCH_CATCHUP_LOOKBACK_HOURS  override default 48 h window
  FASTMAIL_JMAP_TOKEN           override keychain token lookup

Auth: the Fastmail JMAP token is read from the macOS keychain entry
  `security find-generic-password -a fastmail-jmap -s fastmail-jmap-token -w`
to stay consistent with the existing jmap_client.py. An env override
`FASTMAIL_JMAP_TOKEN` or `FASTMAIL_API_TOKEN` wins if set.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone, timedelta
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

DEFAULT_STATE_DIR = Path.home() / ".openclaw/workspace/state"
DEFAULT_DASHBOARD_SYNC_DIR = Path.home() / ".openclaw/skills/dashboard-sync"
DEFAULT_LOOKBACK_HOURS = 48

SESSION_URL = "https://api.fastmail.com/jmap/session"


# ─── JMAP plumbing (self-contained to avoid cross-script coupling) ─────────

def get_jmap_token() -> str:
    token = os.environ.get("FASTMAIL_JMAP_TOKEN") or os.environ.get("FASTMAIL_API_TOKEN")
    if token:
        return token
    try:
        result = subprocess.run(
            ["security", "find-generic-password",
             "-a", "fastmail-jmap", "-s", "fastmail-jmap-token", "-w"],
            capture_output=True, text=True, timeout=10,
        )
        token = result.stdout.strip()
    except (subprocess.SubprocessError, OSError):
        token = ""
    if not token:
        print(
            "[catchup] ERROR: no Fastmail JMAP token. Store with\n"
            "  security add-generic-password -a fastmail-jmap -s fastmail-jmap-token -w '<TOKEN>' -U\n"
            "or export FASTMAIL_JMAP_TOKEN=... .",
            file=sys.stderr,
        )
        sys.exit(2)
    return token


def jmap_session(token: str) -> dict:
    req = Request(SESSION_URL, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    })
    data = json.loads(urlopen(req, timeout=30).read())
    account_id = next(iter(data["accounts"]))
    return {"apiUrl": data["apiUrl"], "accountId": account_id, "token": token}


def jmap_call(session: dict, method_calls: list) -> list:
    body = json.dumps({
        "using": ["urn:ietf:params:jmap:core", "urn:ietf:params:jmap:mail"],
        "methodCalls": method_calls,
    }).encode()
    req = Request(
        session["apiUrl"],
        data=body,
        headers={
            "Authorization": f"Bearer {session['token']}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    resp = json.loads(urlopen(req, timeout=60).read())
    return resp["methodResponses"]


def fetch_recent_emails(session: dict, lookback_hours: int, limit: int = 500) -> list[dict]:
    """Return a list of `{id, subject, sender, date, body}` for the last N hours."""
    since_dt = datetime.now(timezone.utc) - timedelta(hours=lookback_hours)
    since_iso = since_dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    responses = jmap_call(session, [
        ["Email/query", {
            "accountId": session["accountId"],
            "filter": {"after": since_iso},
            "sort": [{"property": "receivedAt", "isAscending": False}],
            "limit": limit,
            "calculateTotal": False,
        }, "0"],
        ["Email/get", {
            "accountId": session["accountId"],
            "#ids": {"resultOf": "0", "name": "Email/query", "path": "/ids"},
            "properties": [
                "id", "subject", "from", "receivedAt",
                "preview", "bodyValues", "textBody",
            ],
            "fetchTextBodyValues": True,
            "maxBodyValueBytes": 200_000,
        }, "1"],
    ])
    # Expect two responses, second is Email/get list.
    email_list = []
    for name, payload, _cid in responses:
        if name == "Email/get":
            email_list = payload.get("list", []) or []
            break

    simplified: list[dict] = []
    for e in email_list:
        sender = ""
        frm = e.get("from") or []
        if frm:
            first = frm[0]
            name = first.get("name") or ""
            addr = first.get("email") or ""
            sender = f"{name} <{addr}>".strip() if name else addr
        # Assemble body text from bodyValues, preferring textBody parts.
        body_values = e.get("bodyValues") or {}
        text_parts = e.get("textBody") or []
        body_chunks: list[str] = []
        for part in text_parts:
            part_id = part.get("partId")
            if not part_id:
                continue
            value = body_values.get(part_id) or {}
            text = value.get("value") or ""
            if text:
                body_chunks.append(text)
        body = "\n".join(body_chunks) or (e.get("preview") or "")

        simplified.append({
            "id": e.get("id", ""),
            "subject": e.get("subject") or "",
            "sender": sender,
            "date": e.get("receivedAt") or "",
            "body": body,
        })
    return simplified


# ─── State file ────────────────────────────────────────────────────────────

def load_state(path: Path) -> dict:
    if not path.exists():
        return {"version": 1, "processed": {}, "lastCatchupAt": None}
    try:
        with path.open() as f:
            data = json.load(f)
        data.setdefault("processed", {})
        data.setdefault("version", 1)
        return data
    except (json.JSONDecodeError, OSError) as e:
        print(f"[catchup] WARN: state file unreadable ({e}); starting fresh", file=sys.stderr)
        return {"version": 1, "processed": {}, "lastCatchupAt": None}


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        "w", dir=path.parent, delete=False, prefix=".orders-ingest-", suffix=".tmp",
    ) as tf:
        json.dump(state, tf, indent=2)
        tmp_path = Path(tf.name)
    os.replace(tmp_path, path)


# ─── Processor ─────────────────────────────────────────────────────────────

def process_email_via_cli(dashboard_sync_dir: Path, email: dict) -> dict:
    cli = dashboard_sync_dir / "cli.js"
    if not cli.exists():
        return {"success": False, "action": "error", "detail": f"cli.js missing at {cli}"}
    try:
        result = subprocess.run(
            ["node", str(cli), "process-email"],
            input=json.dumps(email),
            capture_output=True,
            text=True,
            timeout=45,
        )
    except (subprocess.SubprocessError, OSError) as e:
        return {"success": False, "action": "error", "detail": f"subprocess: {e}"}
    stdout = (result.stdout or "").strip()
    try:
        parsed = json.loads(stdout) if stdout else {}
    except json.JSONDecodeError:
        parsed = {}
    if not parsed:
        return {
            "success": False,
            "action": "error",
            "detail": (result.stderr or stdout or f"exit {result.returncode}")[:500],
        }
    return parsed


# ─── Main ──────────────────────────────────────────────────────────────────

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lookback-hours", type=int, default=None)
    parser.add_argument("--limit", type=int, default=None, help="Max emails to process this run")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args()

    state_dir = Path(os.environ.get("PERCH_STATE_DIR", str(DEFAULT_STATE_DIR)))
    state_file = state_dir / "orders-ingest-state.json"
    dashboard_sync_dir = Path(os.environ.get("DASHBOARD_SYNC_DIR", str(DEFAULT_DASHBOARD_SYNC_DIR)))
    lookback = args.lookback_hours or int(
        os.environ.get("PERCH_CATCHUP_LOOKBACK_HOURS", str(DEFAULT_LOOKBACK_HOURS))
    )

    state = load_state(state_file)
    processed_ids: set[str] = set(state["processed"].keys())

    started = time.time()

    token = get_jmap_token()
    session = jmap_session(token)
    try:
        emails = fetch_recent_emails(session, lookback)
    except HTTPError as e:
        print(f"[catchup] ERROR: JMAP call failed: {e.code} {e.reason}", file=sys.stderr)
        return 1

    to_process = [e for e in emails if e.get("id") and e["id"] not in processed_ids]

    if args.limit:
        to_process = to_process[: args.limit]

    if args.verbose:
        print(
            f"[catchup] window={lookback}h fetched={len(emails)} "
            f"already_seen={len(emails) - len(to_process)} to_process={len(to_process)}"
        )

    stats: dict[str, int] = {}

    for i, email in enumerate(to_process, 1):
        eid = email["id"]
        if args.dry_run:
            print(f"[catchup] DRY {i}/{len(to_process)} {eid} subject={email.get('subject','')[:60]!r}")
            continue

        result = process_email_via_cli(dashboard_sync_dir, email)
        action = result.get("action", "error")
        stats[action] = stats.get(action, 0) + 1

        state["processed"][eid] = {
            "at": datetime.now(timezone.utc).isoformat(),
            "type": result.get("type", "unknown"),
            "action": action,
            "detail": (result.get("detail") or "")[:200],
            "confidence": result.get("confidence", 0),
        }

        if args.verbose:
            print(
                f"[catchup] {i}/{len(to_process)} {eid} → {action} "
                f"({result.get('type','?')}) {result.get('detail','')[:80]}"
            )

        # Persist every 10 emails so a crash doesn't lose progress.
        if i % 10 == 0:
            state["lastCatchupAt"] = datetime.now(timezone.utc).isoformat()
            save_state(state_file, state)

    state["lastCatchupAt"] = datetime.now(timezone.utc).isoformat()
    if not args.dry_run:
        save_state(state_file, state)

    elapsed = time.time() - started
    summary = (
        f"[catchup] done in {elapsed:.1f}s; window={lookback}h; "
        f"processed={len(to_process)}; "
        + " ".join(f"{k}={v}" for k, v in stats.items() if v)
    )
    print(summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
