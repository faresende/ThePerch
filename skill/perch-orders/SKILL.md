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

Two scripts handle this:
- **`orders_autopilot_ingest_fastmail.py`**: Fetches emails from Fastmail Paper Trail + Inbox, detects orders via content patterns, and upserts to `orders` + `shipments` tables
- **`dashboard-sync` skill (orders-autopilot.ts)**: More sophisticated classifier with purchase confirmation vs shipping notification handling, 17track polling, and review items for ambiguous cases

## Architecture

```
Fastmail JMAP (Paper Trail P7V + Inbox P-F)
        │
        │ jmap_client (Python)
        ▼
orders_autopilot_ingest_fastmail.py
  ├─ is_order_email()      — content-based detection
  ├─ extract_order_number() — regex: #ORDER-12345
  ├─ extract_tracking_number() — 1Z UPS, DHL numeric, generic patterns
  ├─ upsert_order()        — orders table
  └─ upsert_shipment()     — shipments table
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
python3 scripts/orders_autopilot_ingest_fastmail.py
python3 scripts/orders_autopilot_ingest_fastmail.py --json  # JSON output
python3 scripts/orders_autopilot_ingest_fastmail.py --lookback-hours 168  # 7 days
python3 scripts/orders_autopilot_ingest_fastmail.py --limit 30
```

### Cron schedule

```cron
# Every hour at :00 and :30
0,30 * * * * cd /Users/faresende/.openclaw/workspace && python3 scripts/orders_autopilot_ingest_fastmail.py >> logs/orders.log 2>&1
```

### Environment

The script reads Fastmail JMAP credentials from `~/.openclaw/workspace/sandbox/fastmail-jmap/jmap_client.py`. Supabase uses a hardcoded service role key (not env var based — review before deploying).

## Adding a New Merchant

The script uses **content-based detection**, not a sender whitelist. To add a new merchant:

1. Test the detection: send a test order confirmation from the merchant and run the script
2. If detection fails, add merchant-specific patterns to `STRONG_ORDER_SIGNALS` or `WEAK_ORDER_SIGNALS` in the script
3. If the merchant sends shipping emails, ensure the `extract_tracking_number()` regex handles their tracking format
4. For carriers not yet supported, add to `get_tracking_url()` function

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
python3 scripts/orders_autopilot_ingest_fastmail.py --limit 5 --json

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

The legacy dashboard-sync skill (`orders-autopilot.ts`) uses a different pipeline with 17track polling. The Python script handles initial email ingestion; the TypeScript skill handles ongoing tracking updates. Both write to the same `orders` + `shipments` tables.
