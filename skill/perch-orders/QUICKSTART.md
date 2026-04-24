# QUICKSTART.md - Perch Orders Pipeline

## What It Does

Ingests commerce order/shipment confirmation emails from Fastmail via JMAP, extracts order numbers and tracking information, and writes to the `orders` and `shipments` Supabase tables. The iOS app reads these tables to display the Orders tab and trigger Live Activities for in-transit packages.

## Files

| File | Purpose |
|------|---------|
| `scripts/orders_autopilot_ingest_fastmail.py` | Email ingestion (Python, JMAP) |
| `skill/dashboard-sync/src/orders-autopilot.ts` | Sophisticated classifier + 17track polling |
| `skill/dashboard-sync/src/orders-store.ts` | Supabase upsert logic |
| `skill/dashboard-sync/src/seventeen-track.ts` | 17track.net API polling |

## Quick Test

```bash
# Test with 5 most recent emails
python3 scripts/orders_autopilot_ingest_fastmail.py --limit 5 --json
```

Expected output:
```json
{"emails": 5, "orders": 2, "shipments": 1, "skipped": 2, "errors": 0}
```

## Adding a Merchant

1. Find an order confirmation from the merchant in Fastmail
2. Note the subject line patterns
3. Add to `STRONG_ORDER_SIGNALS` or `WEAK_ORDER_SIGNALS` in the Python script if content-based detection misses it
4. If the merchant uses a unique tracking format, add to `extract_tracking_number()`

## Cron Setup

```cron
# Run every 30 minutes
0,30 * * * * cd <REPO> && python3 scripts/orders_autopilot_ingest_fastmail.py >> ~/.openclaw/logs/orders.log 2>&1
```

## Troubleshooting

- **No orders detected**: Run with `--limit 5 --json` to see what's being scanned
- **Tracking number missing**: Check `extract_tracking_number()` patterns for the carrier
- **Double entries**: The script deduplicates by `order_number` and `normalized_merchant + recent_window`
