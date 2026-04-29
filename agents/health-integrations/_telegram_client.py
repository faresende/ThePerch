"""
_telegram_client.py — minimal Telegram Bot API client for the
BioChecha bot. Reads the bot token from openclaw's secrets.json so
this module's surface is just `send_message(text)`.

Config sources (no env addition needed if openclaw is configured):
  - bot token  : ~/.openclaw/secrets.json
                 path: /channels/telegram/accounts/biochecha/botToken
  - chat id    : env TELEGRAM_CHAT_ID, else the first entry in
                 /channels/telegram/accounts/biochecha/allowFrom
                 (single-user deployment — that IS the user)

Best-effort: any failure here returns False without raising. Caller
(currently the post-wake wrapper) does its own logging and never
makes Telegram delivery a blocker for the iOS card path.
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

OPENCLAW_SECRETS = Path.home() / ".openclaw" / "secrets.json"
OPENCLAW_CONFIG  = Path.home() / ".openclaw" / "openclaw.json"
ACCOUNT_NAME     = "biochecha"


def _load_bot_token(account: str = ACCOUNT_NAME) -> str | None:
    """Pull the bot token out of openclaw's secrets.json. The file
    structure is /channels/telegram/accounts/<account>/botToken."""
    try:
        data = json.loads(OPENCLAW_SECRETS.read_text())
    except Exception as e:
        sys.stderr.write(f"[telegram] secrets read failed: {e}\n")
        return None
    try:
        return (data.get("channels", {})
                    .get("telegram", {})
                    .get("accounts", {})
                    .get(account, {})
                    .get("botToken"))
    except Exception:
        return None


def _resolve_chat_id(account: str = ACCOUNT_NAME) -> str | None:
    """Resolve the target chat in this priority:
       1. TELEGRAM_CHAT_ID env (explicit override)
       2. openclaw.json allowFrom[0] for this account
    """
    env_id = os.environ.get("TELEGRAM_CHAT_ID")
    if env_id:
        return env_id.strip()
    try:
        cfg = json.loads(OPENCLAW_CONFIG.read_text())
        allow = (cfg.get("channels", {})
                    .get("telegram", {})
                    .get("accounts", {})
                    .get(account, {})
                    .get("allowFrom") or [])
        if allow:
            return str(allow[0])
    except Exception:
        pass
    return None


def send_message(text: str, *, parse_mode: str = "Markdown",
                 account: str = ACCOUNT_NAME, timeout: int = 10) -> bool:
    """Send a text message via the BioChecha Telegram bot.
    Returns True on 200, False on any failure (logs to stderr)."""
    token = _load_bot_token(account)
    chat_id = _resolve_chat_id(account)
    if not token:
        sys.stderr.write(f"[telegram] no bot token for account={account}; skipped\n")
        return False
    if not chat_id:
        sys.stderr.write(f"[telegram] no chat_id resolvable for account={account}; skipped\n")
        return False

    url = f"https://api.telegram.org/bot{token}/sendMessage"
    body = urlencode({
        "chat_id": chat_id,
        "text": text,
        "parse_mode": parse_mode,
        "disable_web_page_preview": "true",
    }).encode()
    req = Request(url, data=body, method="POST", headers={
        "Content-Type": "application/x-www-form-urlencoded",
    })
    try:
        with urlopen(req, timeout=timeout) as resp:
            return 200 <= resp.status < 300
    except HTTPError as e:
        try:
            detail = e.read().decode("utf-8", errors="replace")[:300]
        except Exception:
            detail = ""
        sys.stderr.write(f"[telegram] HTTP {e.code}: {detail}\n")
        return False
    except URLError as e:
        sys.stderr.write(f"[telegram] network error: {e}\n")
        return False
    except Exception as e:
        sys.stderr.write(f"[telegram] send failed: {type(e).__name__}: {e}\n")
        return False
