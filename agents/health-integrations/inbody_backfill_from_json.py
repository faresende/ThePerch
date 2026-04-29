#!/usr/bin/env python3
"""
inbody_backfill_from_json.py — one-shot import of historical InBody
scans from the legacy body-composition.json into health_metrics.

Why this exists: the previous chat-based InBody flow had BioChecha
read each CSV, log the row into a local JSON file, and verbally
summarise. Numeric data never reached Supabase, so 53 historical
scans (Feb 3 → Apr 29) are sitting in JSON and invisible to the
post-wake categories.

This backfill walks the JSON and writes one health_metrics row per
metric per scan, using the same source='inbody' / source_id design
as the live `inbody_ingest.py` (timestamp-based, dedupe-safe). Idempotent
via the existing health_metrics upsert — re-running is a no-op.

Usage:
    python3 inbody_backfill_from_json.py [--dry-run] [--json PATH]

This is a one-shot migration from a legacy JSON dump format that pre-
dated the InBody H30 watcher pipeline. Most installs won't need it —
skip if you don't have a `body-composition.json` already.

Default JSON path: ~/Documents/InBody/body-composition.json
Override via --json or the INBODY_BACKFILL_JSON env var.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, time as dt_time, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _supabase_client import bulk_upsert_health_metrics, insert_agent_run  # noqa: E402

DEFAULT_JSON = Path(
    os.environ.get(
        "INBODY_BACKFILL_JSON",
        str(Path.home() / "Documents" / "InBody" / "body-composition.json"),
    )
)

# Map JSON keys → (metric_key, unit). Keys mirror inbody_ingest.py and
# the existing health_metrics conventions (Withings-compatible names
# for the shared metrics).
JSON_KEY_MAP: dict[str, tuple[str, str]] = {
    "weight_kg":          ("weight_kg",         "kg"),
    "skeletal_muscle_kg": ("muscle_mass_kg",    "kg"),
    "body_fat_mass_kg":   ("fat_mass_kg",       "kg"),
    "body_fat_pct":       ("body_fat_pct",      "percent"),
    "soft_lean_mass_kg":  ("soft_lean_mass_kg", "kg"),
    "bmi":                ("bmi",               "kg/m2"),
    "bmr_kcal":           ("bmr_kcal",          "kcal"),
    "inbody_score":       ("inbody_score",      "score"),
    "waist_hip_ratio":    ("whr",               "ratio"),
    "visceral_fat_level": ("visceral_fat_level","level"),
}


def _scan_to_rows(scan: dict, user_id: str) -> list[dict]:
    """Convert one inbody_scans entry to health_metrics rows.
    Returns [] if the date is unparseable."""
    date_str = scan.get("date")
    if not date_str:
        return []

    # JSON has separate `date` ('2026-04-29') + `time` ('06:49') fields.
    # Reconstruct the measurement instant; if `time` is missing fall back
    # to 06:00 UTC (the user's typical morning weigh-in slot).
    time_str = scan.get("time", "06:00")
    try:
        date_part = datetime.strptime(date_str, "%Y-%m-%d").date()
    except Exception:
        return []
    try:
        hh, mm = (int(x) for x in time_str.split(":")[:2])
    except Exception:
        hh, mm = 6, 0
    measured_dt = datetime.combine(date_part, dt_time(hh, mm), tzinfo=timezone.utc)
    measured_at = measured_dt.isoformat()
    scan_id = measured_dt.strftime("%Y%m%dT%H%M%S")

    rows: list[dict] = []
    for json_key, (metric, unit) in JSON_KEY_MAP.items():
        raw = scan.get(json_key)
        if raw is None:
            continue
        try:
            value = float(raw)
        except (TypeError, ValueError):
            continue
        rows.append({
            "user_id": user_id,
            "metric": metric,
            "value": value,
            "unit": unit,
            "source": "inbody",
            "source_id": f"inbody-{scan_id}-{metric}",
            "measured_at": measured_at,
            "details": None,
        })
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", type=Path, default=DEFAULT_JSON,
                        help=f"path to body-composition.json (default: {DEFAULT_JSON})")
    parser.add_argument("--dry-run", action="store_true",
                        help="parse + count only; don't write to Supabase")
    args = parser.parse_args()

    user_id = os.environ.get("PERCH_USER_ID")
    if not user_id:
        sys.stderr.write("[inbody-backfill] PERCH_USER_ID not set\n")
        return 2

    if not args.json.exists():
        sys.stderr.write(f"[inbody-backfill] JSON not found: {args.json}\n")
        return 2

    error: str | None = None
    written = 0
    failed = 0
    scans_processed = 0
    scans_skipped: list[str] = []

    try:
        data = json.loads(args.json.read_text())
        scans = data.get("inbody_scans", [])
        all_rows: list[dict] = []
        for scan in scans:
            rows = _scan_to_rows(scan, user_id)
            if not rows:
                scans_skipped.append(str(scan.get("date") or "<no-date>"))
                continue
            all_rows.extend(rows)
            scans_processed += 1

        print(f"[inbody-backfill] scans={scans_processed} "
              f"skipped={len(scans_skipped)} rows={len(all_rows)}")

        if args.dry_run:
            print(f"[inbody-backfill] DRY RUN — first 3 rows:")
            for r in all_rows[:3]:
                print("  ", r)
            return 0

        if all_rows:
            written, failed = bulk_upsert_health_metrics(all_rows)

    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[inbody-backfill] fatal: {error}\n")

    insert_agent_run(
        agent_id="biochecha",
        run_type="inbody_backfill",
        status="error" if error else ("partial" if failed else "ok"),
        summary={
            "json_path": str(args.json),
            "scans_processed": scans_processed,
            "scans_skipped": scans_skipped,
            "rows_written": written,
            "rows_failed": failed,
        },
        error_detail=error,
    )
    print(f"[inbody-backfill] written={written} failed={failed} error={error}")
    return 1 if error else 0


if __name__ == "__main__":
    sys.exit(main())
