#!/usr/bin/env python3
"""
biochecha_event_insight.py — thin wrapper that constructs an
EventTrigger from CLI args and calls into biochecha_dynamic_insight.py
with slot=event_logistics.

Called by orders-autopilot's pollAndUpdateShipment when a shipment
flips to out_for_delivery or its ETA becomes today.

Usage:
    biochecha_event_insight.py out_for_delivery <merchant> <carrier> <tracking> [<old_status>] [<new_status>]
    biochecha_event_insight.py eta_today        <merchant> <carrier> <tracking> <eta_iso>
"""
from __future__ import annotations

import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from biochecha_dynamic_insight import (
    EventTrigger,
    gather_state,
    rank,
    is_recent_topic_overlap,
    _fetch_most_recent_today_insight,
    _generate_insight,
    _upsert_insight,
    score_logistics_event_out_for_delivery,
    score_logistics_event_eta_today,
    CategoryResult,
)
from _supabase_client import insert_agent_run


def main() -> int:
    if len(sys.argv) < 5:
        sys.stderr.write(
            "usage: biochecha_event_insight.py <kind> <merchant> <carrier> <tracking> [<eta_iso|old_status>] [<new_status>]\n"
        )
        return 2
    kind = sys.argv[1]
    if kind not in ("out_for_delivery", "eta_today"):
        sys.stderr.write(f"unknown kind: {kind}\n")
        return 2

    merchant = sys.argv[2]
    carrier = sys.argv[3]
    tracking = sys.argv[4]
    eta_at = None
    old_status = None
    new_status = None
    if kind == "eta_today" and len(sys.argv) >= 6:
        try:
            eta_at = datetime.fromisoformat(sys.argv[5].replace("Z", "+00:00"))
        except Exception:
            eta_at = None
    elif kind == "out_for_delivery" and len(sys.argv) >= 7:
        old_status = sys.argv[5]
        new_status = sys.argv[6]

    et = EventTrigger(
        kind=kind, merchant=merchant, carrier=carrier,
        tracking_number=tracking, old_status=old_status,
        new_status=new_status, eta_at=eta_at,
    )

    error = None
    body = None
    try:
        state = gather_state("event_logistics", event_trigger=et)
        # Don't-churn guard
        recent = _fetch_most_recent_today_insight()
        if recent and is_recent_topic_overlap(recent, tracking):
            print(f"[event:{kind}] skipped — recent insight already covers {tracking}")
            return 0

        candidates = []
        for fn in (
            score_logistics_event_out_for_delivery,
            score_logistics_event_eta_today,
        ):
            r = fn(state)
            if r is not None:
                candidates.append(r)
        winner = rank(candidates) if candidates else CategoryResult(
            category="quiet_day_fallback", score=0.0,
            fact_bundle={"reason": "no event category fired"},
        )
        body = _generate_insight("event_logistics", winner.fact_bundle,
                                 recent_feedback=state.recent_feedback)
        _upsert_insight("event_logistics", body, winner)
    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[event:{kind}] {error}\n")

    insert_agent_run(
        agent_id="biochecha", run_type=f"event_insight_{kind}",
        status="error" if error else "ok",
        summary={"merchant": merchant, "tracking": tracking, "length": len(body) if body else 0},
        error_detail=error,
    )
    if error:
        return 1
    print(f"[event:{kind}] generated for {merchant}: {body}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
