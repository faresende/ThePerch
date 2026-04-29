# QUICKSTART.md - Perch Orders Pipeline

## What It Does

Ingests commerce order/shipment confirmation emails from Fastmail via JMAP, extracts order numbers and tracking information, and writes to the `orders` and `shipments` Supabase tables. The iOS app reads these tables to display the Orders tab and trigger Live Activities for in-transit packages.

## Files

| File | Purpose |
|------|---------|
| `sandbox/fastmail-jmap/orders_ingest_hook.py` | JMAP listener that fires per new commerce email |
| `skill/dashboard-sync/cli.js process-email` | Per-email classifier + ingestion entrypoint |
| `skill/dashboard-sync/src/orders-autopilot.ts` | Classifier + 17track polling |
| `skill/dashboard-sync/src/orders-store.ts` | Supabase upsert logic |
| `skill/dashboard-sync/src/seventeen-track.ts` | 17track.net API polling |
| `scripts/orders_ingest_catchup.py` | 12h catchup safety net (re-scans recent inbox/Paper-Trail) |

> The previous monolithic `scripts/orders_autopilot_ingest_fastmail.py` was retired on 2026-04-23 — see `scripts/archive/README.md`. The listener + per-email cli is now canonical.

## Quick Test

```bash
# Replay the most recent few emails through the cli classifier
node skill/dashboard-sync/cli.js process-email --limit 5 --json

# Or run the catchup against the last 12h
python3 scripts/orders_ingest_catchup.py --json
```

Expected output:
```json
{"emails": 5, "orders": 2, "shipments": 1, "skipped": 2, "errors": 0}
```

## Adding a Merchant

1. Find an order confirmation from the merchant in Fastmail
2. Note the subject line patterns
3. The classifier lives in `skill/dashboard-sync/src/email-classifier.ts` — add to its STRONG/WEAK signal lists if content-based detection misses it
4. If the merchant uses a unique tracking format, add to `extract_tracking_number()` in `skill/dashboard-sync/src/llm-extractor.ts` (or its companion regex helpers)

## Cron Setup

The listener fires per-email in real time via `sandbox/fastmail-jmap/orders_ingest_hook.py`. The catchup is the periodic safety net:

```cron
# Catchup every 30 minutes (covers anything the listener missed)
0,30 * * * * cd <REPO> && python3 scripts/orders_ingest_catchup.py >> ~/.openclaw/logs/orders.log 2>&1
```

## Troubleshooting

- **No orders detected**: Run `node skill/dashboard-sync/cli.js process-email --limit 5 --json` to see what's being scanned
- **Tracking number missing**: Check the regex helpers in `skill/dashboard-sync/src/llm-extractor.ts` for the carrier
- **Double entries**: Ingestion deduplicates by `order_number` and `normalized_merchant + recent_window`
