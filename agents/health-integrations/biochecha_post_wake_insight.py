#!/usr/bin/env python3
"""
biochecha_post_wake_insight.py — fired AFTER the InBody ingest lands
(by the launchd watcher) OR manually by the user. Two surfaces:

  1. iOS card  — short single-paragraph insight, written via
                  _generate_insight + _upsert_insight (insight_type
                  = 'daily_health_morning_post_wake'). Pull-to-refresh
                  on the Today tab and it shows up.
  2. Telegram  — long-form briefing via _generate_telegram_summary +
                  _telegram_client.send_message. The conversational
                  surface BioChecha used to send manually.

iOS-first: if Telegram is down or rate-limited, the iOS card still
updates. Telegram is best-effort.

Usage:
    biochecha_post_wake_insight.py
"""
from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from biochecha_dynamic_insight import (
    gather_state,
    rank,
    _generate_insight,
    _generate_telegram_summary,
    _upsert_insight,
    CategoryResult,
    score_body_composition_change,
    score_reflective_morning,
    score_anomaly_recent_pattern,
    score_anticipatory_today_training,
    score_anticipatory_today_macros,
    OPENAI_MODEL,
)
from _supabase_client import insert_agent_run
from _telegram_client import send_message as telegram_send

SLOT = "morning_post_wake"


def main() -> int:
    started = datetime.now(timezone.utc)
    error: str | None = None
    body: str | None = None
    long_body: str | None = None
    telegram_ok = False

    try:
        state = gather_state(SLOT)

        candidates: list[CategoryResult] = []
        for fn in (
            score_body_composition_change,
            score_reflective_morning,
            score_anomaly_recent_pattern,
            score_anticipatory_today_training,
            score_anticipatory_today_macros,
        ):
            r = fn(state)
            if r is not None:
                candidates.append(r)

        winner = rank(candidates) if candidates else CategoryResult(
            category="quiet_day_fallback", score=0.0,
            fact_bundle={"reason": "no eligible category for post-wake slot"},
        )

        # Surface 1: iOS card (short). Generate first so a Telegram
        # failure doesn't block the card update.
        body = _generate_insight(
            SLOT, winner.fact_bundle,
            recent_feedback=state.recent_feedback,
        )
        ios_ok = _upsert_insight(SLOT, body, winner)
        if not ios_ok:
            # Don't abort — log and try Telegram anyway. The card will
            # retry on the next watcher fire.
            sys.stderr.write("[post-wake] iOS upsert returned non-2xx\n")

        # Surface 2: Telegram (long-form). Best-effort.
        try:
            long_body = _generate_telegram_summary(
                SLOT, winner.fact_bundle,
                recent_feedback=state.recent_feedback,
            )
            telegram_ok = telegram_send(long_body, parse_mode="Markdown")
        except Exception as e:
            sys.stderr.write(f"[post-wake] telegram pipeline failed: "
                             f"{type(e).__name__}: {e}\n")

    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[post-wake] {error}\n")

    insert_agent_run(
        agent_id="biochecha",
        run_type="post_wake_insight",
        status="error" if error else "ok",
        summary={
            "slot": SLOT,
            "model": OPENAI_MODEL,
            "ios_length": len(body) if body else 0,
            "telegram_length": len(long_body) if long_body else 0,
            "telegram_sent": telegram_ok,
        },
        error_detail=error,
    )
    if error:
        return 1
    print(f"[post-wake] iOS={len(body) if body else 0} chars, "
          f"telegram_sent={telegram_ok}")
    if body:
        print(f"--- iOS ---\n{body}")
    if long_body:
        print(f"--- Telegram ---\n{long_body}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
