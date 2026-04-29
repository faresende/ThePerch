#!/usr/bin/env python3
"""
inbody_ingest.py — InBody Dial H30 CSV → health_metrics.

Mac-only. The H30's companion app exports a CSV per measurement to a
folder the user picks (we use ~/Documents/InBody/). This script:

  1. Reads each `InBody-*.csv` in the watch folder (default
     ~/Documents/InBody/, override with INBODY_WATCH_DIR).
  2. Parses the row, extracts the timestamp + every non-`-` field.
  3. Bulk-upserts the values into `public.health_metrics` under
     source='inbody', source_id='inbody-<file-stem>-<metric>' so the
     existing health_metrics dedupe collapses repeats.
  4. Deletes the source CSV.
  5. Records an agent_runs row for telemetry.

Why CSV (not Apple Health): the H30 only exports BMI, body fat %,
height, and weight to HealthKit. The CSV carries the rich set —
phase angle, ECW ratio, total body water, BMR, InBody Score, SMI,
visceral fat, segmental composition — that BioChecha's body-comp
categories want to score against.

CSV header reference (H30):
  date, Measurement device., Weight(kg), Skeletal Muscle Mass(kg),
  Soft Lean Mass(kg), Body Fat Mass(kg), BMI(kg/m²),
  Percent Body Fat(%), Basal Metabolic Rate(kcal), InBody Score,
  Right Arm Lean Mass(kg), ..., Whole Body Phase Angle(°)

Fields with `-` are skipped (segmental fields the H30 doesn't measure).

Env required: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, PERCH_USER_ID.

Triggered by: ~/Documents/InBody/ launchd watcher (see
ops/launchd/com.theperch.inbody-watcher.plist).
"""
from __future__ import annotations

import csv
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from _supabase_client import bulk_upsert_health_metrics, insert_agent_run  # noqa: E402


# CSV column → (metric_key, unit). Columns NOT in this map are skipped.
# Keys mirror the existing biochecha_dynamic_insight metric names so
# the body-comp categories pick them up without further mapping.
INBODY_COLUMN_MAP: dict[str, tuple[str, str]] = {
    # Core metrics shared with Withings — same metric names so
    # _gather_body_comp_last_30() reads from both sources interchangeably.
    "Weight(kg)":                    ("weight_kg",                "kg"),
    "Body Fat Mass(kg)":             ("fat_mass_kg",              "kg"),
    "Percent Body Fat(%)":           ("body_fat_pct",             "percent"),
    "Skeletal Muscle Mass(kg)":      ("muscle_mass_kg",           "kg"),

    # InBody-only signals (HealthKit drops these). Stored under unique
    # metric names so future categories can read them; today they're
    # captured-but-unread.
    "Soft Lean Mass(kg)":            ("soft_lean_mass_kg",        "kg"),
    "BMI(kg/m²)":                    ("bmi",                      "kg/m2"),
    "Basal Metabolic Rate(kcal)":    ("bmr_kcal",                 "kcal"),
    "InBody Score":                  ("inbody_score",             "score"),
    "Waist Hip Ratio":               ("whr",                      "ratio"),
    "Visceral Fat Area(cm²)":        ("visceral_fat_area_cm2",    "cm2"),
    "Visceral Fat Level(Level)":     ("visceral_fat_level",       "level"),
    "Total Body Water(L)":           ("total_body_water_l",       "L"),
    "Intracellular Water(L)":        ("intracellular_water_l",    "L"),
    "Extracellular Water(L)":        ("extracellular_water_l",    "L"),
    "ECW Ratio":                     ("ecw_ratio",                "ratio"),
    "Upper-Lower":                   ("upper_lower_ratio",        "ratio"),
    "Leg Lean Mass(kg)":             ("leg_lean_mass_kg",         "kg"),
    "Leg Muscle Level(Level)":       ("leg_muscle_level",         "level"),
    "Protein(kg)":                   ("protein_kg",               "kg"),
    "Mineral(kg)":                   ("mineral_kg",               "kg"),
    "Bone Mineral Content(kg)":      ("bone_mineral_content_kg",  "kg"),
    "Body Cell Mass(kg)":            ("body_cell_mass_kg",        "kg"),
    "SMI(kg/m²)":                    ("smi_kg_m2",                "kg/m2"),
    "Whole Body Phase Angle(°)":     ("phase_angle_deg",          "deg"),
    "Waist Circumference(cm)":       ("waist_circumference_cm",   "cm"),
}


def _parse_inbody_timestamp(raw: str) -> datetime:
    """H30 writes 'YYYYMMDDHHMMSS' (no separators). Local clock. We
    record as UTC because the rest of health_metrics is UTC; for a
    single-user, single-timezone deployment the offset is irrelevant
    for downstream queries (we filter by date, not by hour-of-day)."""
    return datetime.strptime(raw.strip(), "%Y%m%d%H%M%S").replace(tzinfo=timezone.utc)


def _rows_from_csv(path: Path, user_id: str) -> list[dict]:
    """Parse an InBody CSV file into health_metrics rows. Skips
    columns mapped to dashes, unmapped columns, and rows with bad
    numbers — but raises on a malformed timestamp (that's a structural
    problem worth surfacing).

    source_id is derived from the MEASUREMENT timestamp (not the
    filename) so re-importing the same scan under a different filename
    upserts cleanly instead of creating duplicates. The CSV's first
    column (`date`) is the H30's epoch-of-measurement ('YYYYMMDDHHMMSS')
    — a stable identifier across re-exports.
    """
    rows: list[dict] = []

    with path.open(newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for entry in reader:
            ts_raw = entry.get("date", "").strip()
            if not ts_raw:
                continue
            measured_dt = _parse_inbody_timestamp(ts_raw)
            measured_at = measured_dt.isoformat()
            # Compact, dedupe-safe identifier from the InBody-side timestamp.
            scan_id = measured_dt.strftime("%Y%m%dT%H%M%S")

            for col, (metric, unit) in INBODY_COLUMN_MAP.items():
                raw = (entry.get(col) or "").strip()
                if not raw or raw == "-":
                    continue
                try:
                    value = float(raw)
                except ValueError:
                    continue
                rows.append({
                    "user_id": user_id,
                    "metric": metric,
                    "value": value,
                    "unit": unit,
                    "source": "inbody",
                    # Stable per-scan source_id — re-importing the same
                    # measurement (any filename) upserts in place.
                    "source_id": f"inbody-{scan_id}-{metric}",
                    "measured_at": measured_at,
                    "details": None,
                })
    return rows


def _list_inbody_csvs(watch_dir: Path) -> list[Path]:
    if not watch_dir.exists():
        return []
    return sorted(p for p in watch_dir.iterdir()
                  if p.is_file() and p.name.lower().startswith("inbody-")
                  and p.suffix.lower() == ".csv")


def main() -> int:
    user_id = os.environ.get("PERCH_USER_ID")
    if not user_id:
        sys.stderr.write("[inbody-ingest] PERCH_USER_ID not set; aborting\n")
        return 2

    watch_dir = Path(os.environ.get("INBODY_WATCH_DIR")
                     or (Path.home() / "Documents" / "InBody"))

    started = datetime.now(timezone.utc)
    written = 0
    failed = 0
    files_processed = 0
    files_failed: list[str] = []
    error: str | None = None

    try:
        files = _list_inbody_csvs(watch_dir)
        if not files:
            print(f"[inbody-ingest] no CSV files in {watch_dir}")
        else:
            all_rows: list[dict] = []
            for f in files:
                try:
                    rows = _rows_from_csv(f, user_id)
                    if rows:
                        all_rows.extend(rows)
                        files_processed += 1
                except Exception as e:
                    files_failed.append(f"{f.name}: {type(e).__name__}: {e}")
                    sys.stderr.write(f"[inbody-ingest] parse failed for {f.name}: {e}\n")

            if all_rows:
                written, failed = bulk_upsert_health_metrics(all_rows)

            # Delete CSVs that PARSED successfully — even if a few rows
            # failed at upsert time. Failed-to-parse files stay so the
            # user sees them and can investigate.
            for f in files:
                if f.name not in (entry.split(":")[0] for entry in files_failed):
                    try:
                        f.unlink()
                    except Exception as e:
                        sys.stderr.write(f"[inbody-ingest] delete failed for {f.name}: {e}\n")

    except Exception as e:
        error = f"{type(e).__name__}: {e}"
        sys.stderr.write(f"[inbody-ingest] fatal: {error}\n")

    insert_agent_run(
        agent_id="biochecha",
        run_type="inbody_ingest",
        status="error" if error else ("partial" if (failed or files_failed) else "ok"),
        summary={
            "files_processed": files_processed,
            "rows_written": written,
            "rows_failed": failed,
            "files_failed": files_failed,
            "watch_dir": str(watch_dir),
        },
        error_detail=error,
    )
    print(f"[inbody-ingest] files={files_processed} written={written} "
          f"failed={failed} parse_failed={len(files_failed)} error={error}")
    return 1 if error else 0


if __name__ == "__main__":
    sys.exit(main())
