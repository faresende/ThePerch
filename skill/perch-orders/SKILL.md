---
name: perch-orders
description: "Scans commerce confirmation emails from Fastmail via JMAP, extracts orders and shipments, writes to Supabase orders and shipments tables."
version: 1.0.0
---

# perch-orders

## Trigger

Any task involving order ingestion from commerce emails, shipment tracking, order status management, or modifying the email→Supabase orders pipeline.

## What it does

The orders pipeline scans commerce confirmation emails from Fastmail (JMAP), detects order and shipment information using content-based pattern matching (not sender whitelist), and persists them to the `orders` and `shipments` Supabase tables. This data is then displayed in the iOS app's Orders tab and fed into Live Activities for in-transit packages.

Two entry points handle this (both share the same TypeScript classifier + store):
- **`sandbox/fastmail-jmap/orders_ingest_hook.py`** (listener): fires per new commerce email, shells out to `node skill/dashboard-sync/cli.js process-email`. Real-time path.
- **`scripts/orders_ingest_catchup.py`** (catchup): re-scans Inbox + Paper Trail every 30 min as a safety net for anything the listener missed.
- **`skill/dashboard-sync/src/orders-autopilot.ts`**: shared classifier with purchase confirmation vs shipping notification handling, 17track polling, and review items for ambiguous cases. Both entry points call into this.

> The legacy monolithic `scripts/orders_autopilot_ingest_fastmail.py` was retired on 2026-04-23 — see `scripts/archive/README.md`.

## Architecture

```
Fastmail JMAP (Paper Trail P7V + Inbox P-F)
        │
        │ orders_ingest_hook.py (listener)  OR  orders_ingest_catchup.py (30-min cron)
        ▼
node skill/dashboard-sync/cli.js process-email
  ├─ email-classifier.ts   — content-based detection
  ├─ llm-extractor.ts      — order number / tracking-number extraction
  ├─ orders-autopilot.ts   — purchase vs shipping decision + review items
  └─ orders-store.ts       — upsert into orders + shipments
        │
        ▼
  Supabase: orders + shipments tables
        │
        ├─→ OrdersView (iOS) via OrdersViewModel → OrdersService
        │
        └─→ Live Activity (DeliveryLiveActivity)
            via OrderWithShipments.trackedDeliveryData projection
```

### Content Detection

The script detects orders by analyzing email content, not senders. Strong signals:
- Keywords in subject: `order`, `confirmation`, `shipped`, `tracking`, `invoice`, `fatura`, `encomenda`, `bestellung`
- Portuguese, English, Dutch, German keyword support

Weak signals (require additional evidence like a tracking number):
- `shipped`, `package`, `parcel`, `in transit`

Excluded regardless of content:
- Food delivery: glovo, uber eats, deliveroo, just eat, bolt food, freenow
- Logistics: DHL on-demand, sendcloud, loox
- Marketing: newsletters, promotions, password resets

### Carrier Tracking URLs

| Carrier | URL Pattern |
|---------|-------------|
| DHL | `https://www.dhl.com/pt-en/home/tracking.html?tracking-id={tracking_number}&submit=1` |
| FedEx | `https://www.fedex.com/fedextrack/?trknbr={tracking_number}` |
| UPS | `https://www.ups.com/track?trackNums={tracking_number}` |
| USPS | `https://www.usps.com/tracking/{tracking_number}` |
| CTT | `https://www.ctt.pt/track-and-trace?trackingId={tracking_number}` |
| DPD | `https://tracking.dpd.de/status/en_US/parcel/{tracking_number}` |
| GLS | `https://gls-group.eu/EN/track-and-trace?match={tracking_number}` |
| Fallback | `https://t.17track.net/en#nums={tracking_number}` |

## Data Schema

### `orders` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Owner (FK → auth.users) |
| `merchant` | TEXT | Raw merchant domain |
| `merchant_name` | TEXT | Display name |
| `normalized_merchant` | TEXT | Lowercase stripped (for matching) |
| `order_number` | TEXT | Order number (nullable) |
| `total_amount` | DECIMAL | Order total |
| `currency` | TEXT | Currency (default EUR) |
| `status` | TEXT | ordered, processing, shipped, shipped_partial, delivered, cancelled, issue |
| `source_email_ids` | TEXT[] | JMAP email IDs that contributed |
| `confidence_score` | DOUBLE | 0–1 classification confidence |
| `manual_delivered_at` | TIMESTAMPTZ | User-set delivery timestamp |
| `created_at` | TIMESTAMPTZ | Creation time |

### `shipments` table

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `order_id` | UUID | FK → orders |
| `user_id` | UUID | Owner |
| `tracking_number` | TEXT | Carrier tracking number |
| `carrier` | TEXT | DHL, UPS, FedEx, etc. |
| `tracking_url` | TEXT | Direct carrier URL |
| `status` | TEXT | label_created, in_transit, out_for_delivery, delivered, exception |
| `latest_checkpoint` | TEXT | Last tracking event |
| `created_at` | TIMESTAMPTZ | Creation time |

## Setup

### Run manually

```bash
cd ThePerch
# Per-email replay through the canonical cli
node skill/dashboard-sync/cli.js process-email --limit 5 --json

# Catchup (12h window by default, override via --lookback-hours)
python3 scripts/orders_ingest_catchup.py --json
python3 scripts/orders_ingest_catchup.py --lookback-hours 168  # 7 days
```

### Cron schedule

The JMAP listener (`sandbox/fastmail-jmap/orders_ingest_hook.py`) fires per-email in real time. The catchup runs as a safety net:

```cron
# Catchup every 30 minutes
0,30 * * * * cd <REPO> && python3 scripts/orders_ingest_catchup.py >> ~/.openclaw/logs/orders.log 2>&1
```

### Environment

The catchup script reads Fastmail JMAP credentials from `sandbox/fastmail-jmap/jmap_client.py`. Supabase credentials come from `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` env vars; fail-fast when missing. See the script's header for the full list.

## Adding a New Merchant

The classifier uses **content-based detection**, not a sender whitelist. To add a new merchant:

1. Test the detection: send a test order confirmation from the merchant and replay it via `node skill/dashboard-sync/cli.js process-email --limit 5 --json`
2. If detection fails, add merchant-specific patterns to the STRONG/WEAK signal lists in `skill/dashboard-sync/src/email-classifier.ts`
3. If the merchant sends shipping emails, ensure the regex helpers in `skill/dashboard-sync/src/llm-extractor.ts` handle their tracking format
4. For carriers not yet supported, add to the carrier URL map in `orders-autopilot.ts`

### Excluded senders

These are never treated as orders regardless of content:
```
glovo, uber, bolt, freenow, taxis, lyft, deliveroo, just eat,
net-a-porter (restaurant), paypal, sendcloud, loox, amazon (all locales)
```

## Maintenance

### Debugging

```bash
# Dry run with verbose output
node skill/dashboard-sync/cli.js process-email --limit 5 --json

# Check recent orders in Supabase
curl -G "https://<YOUR-PROJECT-REF>.supabase.co/rest/v1/orders" \
  -H "apikey: $ANON_KEY" \
  --data-urlencode "order=created_at.desc" \
  --data-urlencode "limit=10"

# Check shipments for an order
curl -G ".../shipments" \
  -H "apikey: $ANON_KEY" \
  --data-urlencode "order_id=eq.<order_uuid>"
```

### Common Issues

- **Order not detected**: Check if the email subject/body contains a strong order signal. If it's a new merchant format, add patterns to the detection logic.
- **Tracking number not extracted**: Check if the carrier's tracking number format is supported in `extract_tracking_number()`. Common formats: UPS 1Z, DHL numeric (10-15 digits), generic alphanumeric after "tracking-id:".
- **Manual delivery override**: Setting `manualDeliveredAt` on an order causes `OrderWithShipments.effectiveStatus` to always return `delivered`, regardless of shipment status.
- **Missing Live Activity**: The Live Activity uses `OrderWithShipments.trackedDeliveryData` projection. If orders appear in the app but no Live Activity fires, verify the `DeliveryActivityAttributes` are correctly configured in the widget extension.

### Dashboard-sync Integration

The dashboard-sync skill (`orders-autopilot.ts`) is the canonical classifier and is shared by both the JMAP listener and the catchup script. 17track polling runs out of the same TypeScript layer (`scripts/poll-shipments.js` invoked by the LaunchAgent) and writes back to the same `orders` + `shipments` tables.
