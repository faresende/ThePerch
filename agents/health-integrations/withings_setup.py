#!/usr/bin/env python3
"""
Withings OAuth setup — one-shot authorization handshake. Run this
ONCE manually (it opens a browser tab) to get an access + refresh
token; subsequent ingestion runs reuse the cached refresh token to
mint new access tokens automatically.

Setup before running:
  1. Go to https://developer.withings.com/dashboard/ and register a
     personal app. Set redirect URI to:
       http://localhost:8127/withings/callback
  2. Copy the client_id + client_secret into ~/.openclaw/secrets/perch.env:
       export WITHINGS_CLIENT_ID=...
       export WITHINGS_CLIENT_SECRET=...
  3. Run this script:
       set -a && source ~/.openclaw/secrets/perch.env && set +a
       python3 ~/.openclaw/workspace/scripts/health-integrations/withings_setup.py

  The script:
    - opens the Withings auth URL in your browser
    - spins up a one-shot HTTP server on localhost:8127
    - captures the OAuth code from the redirect
    - exchanges it for refresh + access tokens
    - persists tokens to ~/.openclaw/state/withings-tokens.json (mode 600)

  After the handshake, withings_ingest.py runs from cron uses the
  refresh token to keep itself fresh — no further manual steps.
"""
from __future__ import annotations

import http.server
import json
import os
import socketserver
import sys
import threading
import time
import urllib.parse
import webbrowser
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

# Auto-load perch.env so user doesn't have to `set -a && source ... &&`
# every time. Importing _supabase_client triggers the load.
sys.path.insert(0, str(Path(__file__).parent))
import _supabase_client  # noqa: F401, E402

CALLBACK_HOST = "localhost"
CALLBACK_PORT = 8127
CALLBACK_PATH = "/withings/callback"
REDIRECT_URI = f"http://{CALLBACK_HOST}:{CALLBACK_PORT}{CALLBACK_PATH}"

AUTH_URL = "https://account.withings.com/oauth2_user/authorize2"
TOKEN_URL = "https://wbsapi.withings.net/v2/oauth2"

# Comma-separated scopes. `user.metrics` covers weight + body comp +
# blood pressure + temp; `user.activity` covers HR + activity. We don't
# need user.info (profile data) for the insight pipeline.
SCOPES = "user.metrics,user.activity"

TOKENS_FILE = Path.home() / ".openclaw" / "state" / "withings-tokens.json"
TOKENS_FILE.parent.mkdir(parents=True, exist_ok=True)

# Held in module scope so the HTTP handler can write into it.
_capture: dict[str, str | None] = {"code": None, "error": None}


class _CallbackHandler(http.server.BaseHTTPRequestHandler):
    """One-shot handler that captures the OAuth `code` and shuts down."""

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != CALLBACK_PATH:
            self.send_response(404)
            self.end_headers()
            return
        params = urllib.parse.parse_qs(parsed.query)
        if "code" in params:
            _capture["code"] = params["code"][0]
            self._respond_ok()
        elif "error" in params:
            _capture["error"] = params.get("error_description", [params["error"][0]])[0]
            self._respond_err()
        else:
            self.send_response(400)
            self.end_headers()

    def _respond_ok(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(
            b"<html><body style='font-family:-apple-system;padding:40px;background:#FCF8EF;color:#1a1a1a'>"
            b"<h2>All set.</h2>"
            b"<p>You can close this tab. Tokens persisted; cron will pick it up.</p>"
            b"</body></html>"
        )

    def _respond_err(self) -> None:
        self.send_response(400)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.end_headers()
        msg = (_capture["error"] or "unknown").encode()
        self.wfile.write(b"<html><body><h2>Error</h2><p>" + msg + b"</p></body></html>")

    def log_message(self, *_args, **_kw) -> None:  # silence default logger
        return


def _open_auth_url(client_id: str) -> str:
    state = f"perch-{int(time.time())}"
    qs = urllib.parse.urlencode({
        "response_type": "code",
        "client_id": client_id,
        "redirect_uri": REDIRECT_URI,
        "scope": SCOPES,
        "state": state,
    })
    url = f"{AUTH_URL}?{qs}"
    print(f"\nOpening: {url}\n(if it doesn't open automatically, paste it into your browser)\n")
    webbrowser.open(url)
    return state


def _wait_for_code(timeout_seconds: int = 300) -> str:
    server = socketserver.TCPServer((CALLBACK_HOST, CALLBACK_PORT), _CallbackHandler)
    server.timeout = 0.5

    started = time.time()
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    print(f"Waiting up to {timeout_seconds}s for the redirect…")
    try:
        while time.time() - started < timeout_seconds:
            if _capture["code"]:
                return _capture["code"]
            if _capture["error"]:
                raise RuntimeError(f"OAuth error: {_capture['error']}")
            time.sleep(0.25)
        raise TimeoutError("Withings did not redirect within timeout. Try again.")
    finally:
        server.shutdown()
        server.server_close()


def _exchange_code(code: str, client_id: str, client_secret: str) -> dict[str, object]:
    body = urllib.parse.urlencode({
        "action": "requesttoken",
        "grant_type": "authorization_code",
        "client_id": client_id,
        "client_secret": client_secret,
        "code": code,
        "redirect_uri": REDIRECT_URI,
    }).encode()
    req = Request(
        TOKEN_URL,
        data=body,
        method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read())
    except HTTPError as e:
        raise RuntimeError(f"Withings token exchange HTTP {e.code}: {e.read().decode()[:300]}")
    status = payload.get("status")
    if status != 0:
        raise RuntimeError(f"Withings token exchange returned status={status}: {payload}")
    body_payload = payload.get("body") or {}
    return body_payload


def _persist(tokens: dict[str, object]) -> None:
    """Write tokens to ~/.openclaw/state/withings-tokens.json (mode 600)."""
    expires_in = int(tokens.get("expires_in") or 0)
    expires_at = datetime.now(timezone.utc) + timedelta(seconds=expires_in)
    payload = {
        "access_token": tokens.get("access_token"),
        "refresh_token": tokens.get("refresh_token"),
        "userid": tokens.get("userid"),
        "expires_at": expires_at.isoformat(),
        "scope": tokens.get("scope"),
    }
    TOKENS_FILE.write_text(json.dumps(payload, indent=2))
    os.chmod(TOKENS_FILE, 0o600)
    print(f"\nTokens saved → {TOKENS_FILE}")
    print(f"  user_id:    {payload['userid']}")
    print(f"  expires_at: {payload['expires_at']}")
    print(f"  scope:      {payload['scope']}")


def main() -> int:
    client_id = os.environ.get("WITHINGS_CLIENT_ID")
    client_secret = os.environ.get("WITHINGS_CLIENT_SECRET")
    if not client_id or not client_secret:
        sys.stderr.write(
            "[withings-setup] WITHINGS_CLIENT_ID and WITHINGS_CLIENT_SECRET "
            "must be in ~/.openclaw/secrets/perch.env. Register a personal "
            "app at https://developer.withings.com/dashboard/ first; set its "
            f"redirect URI to {REDIRECT_URI}.\n"
        )
        return 2

    _open_auth_url(client_id)
    try:
        code = _wait_for_code()
    except (TimeoutError, RuntimeError) as e:
        sys.stderr.write(f"[withings-setup] {e}\n")
        return 1

    print("Got code, exchanging for tokens…")
    tokens = _exchange_code(code, client_id, client_secret)
    _persist(tokens)
    print("\nDone. The hourly withings_ingest.py cron will use these "
          "tokens (and refresh as needed).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
