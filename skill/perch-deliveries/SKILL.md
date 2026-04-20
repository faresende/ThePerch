# perch-deliveries

## Trigger

Any task involving package tracking, delivery status, the Orders tab in the iOS app, the Home Deliveries card, or Live Activity tracking updates.

## What it does

The Perch has two parallel delivery tracking pipelines, reflecting its historical evolution. Understanding why they are separate is key to working with this feature.

**Pipeline 1 (Canonical)**: Orders and shipments are tracked in dedicated `orders` + `shipments` tables. This is the authoritative source for tracked packages shown in the Orders tab. It uses the `orders_autopilot_ingest_fastmail.py` script for ingestion and 17track for ongoing tracking updates.

**Pipeline 2 (Legacy)**: A parallel delivery surface uses `dashboard_records` with `category=deliveries`. This powers the Deliveries card on the Home screen. It was the original implementation before the canonical orders pipeline existed. The two pipelines are kept in sync via `OrderWithShipments.trackedDeliveryData`, which projects the canonical model into the legacy dashboard_records shape.

Live Activities use the canonical pipeline's `OrderWithShipments` model, driven by `DeliveryActivityAttributes` in the WidgetKit extension.

## Architecture

```
PIPELINE 1 (Canonical) — Orders tab
─────────────────────────────────────
Fastmail emails
        │
        │ orders_autopilot_ingest_fastmail.py
        ▼
  orders + shipments tables (Supabase)
        │
        │ OrdersViewModel → OrdersService → SupabaseService
        ▼
  iOS: OrdersView
       └─→ OrderCard (per order, with shipment timeline)

PIPELINE 2 (Legacy) — Home Deliveries card
───────────────────────────────────────────
  orders_autopilot_ingest_fastmail.py
        │
        │ upsert_delivery_record()
        ▼
  dashboard_records (category=deliveries)
        │
        │ DashboardViewModel → HomeViewModel
        ▼
  iOS: DeliveryHomeCard (on Today tab)

LIVE ACTIVITIES
───────────────────────────────────────────
  OrderWithShipments.trackedDeliveryData projection
        │
        │ DeliveryLiveActivity (WidgetKit)
        ▼
  Dynamic Island + Lock Screen
```

### Why Two Pipelines?

Pipeline 2 (`dashboard_records`) predates the `orders` + `shipments` schema. It was built for rapid iteration during the initial dashboard-sync skill development. Pipeline 1 was added later with a proper relational model (order → shipment) and 17track polling.

The canonical pipeline (Pipeline 1) is the source of truth. Pipeline 2 exists for backward compatibility with the Home Deliveries card and cannot be easily removed without rewriting the card's data fetching logic.

When working on delivery features: prefer adding to Pipeline 1 (orders + shipments) and projecting to Pipeline 2 via `trackedDeliveryData` if the Home card needs to display it.

## Data Schema

### orders table (primary)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `merchant_name` | TEXT | Display name |
| `order_number` | TEXT | Order number (nullable) |
| `status` | TEXT | ordered, shipped, delivered, cancelled |
| `manual_delivered_at` | TIMESTAMPTZ | User override |
| `created_at` | TIMESTAMPTZ | When created |

### shipments table (linked)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `order_id` | UUID | FK → orders |
| `tracking_number` | TEXT | Carrier tracking number |
| `carrier` | TEXT | DHL, UPS, FedEx, etc. |
| `status` | TEXT | label_created, in_transit, out_for_delivery, delivered |
| `tracking_url` | TEXT | Direct carrier URL |
| `created_at` | TIMESTAMPTZ | When created |

### dashboard_records (legacy)

| Column | Type | Description |
|--------|------|-------------|
| `type` | TEXT | `delivery` |
| `category` | TEXT | `deliveries` |
| `title` | TEXT | Merchant name |
| `data` | JSONB | Delivery payload |

## Live Activity

The `DeliveryLiveActivity` widget displays real-time delivery status on the lock screen and Dynamic Island. It is started when a shipment transitions to `in_transit` or `out_for_delivery`.

```swift
// Starting a Live Activity
let attributes = DeliveryActivityAttributes(
  trackingNumber: trackingNumber,
  carrier: carrier
)
let state = DeliveryActivityAttributes.ContentState(
  status: "In Transit",
  eta: estimatedDelivery,
  lastUpdated: Date()
)
// Request the activity...
```

Attributes are defined in `PerchSharedKit/DeliveryActivityAttributes.swift` and consumed by both the main app and the widget extension.

## Adding a Delivery

1. **Via email** (automatic): The orders autopilot script picks up confirmation emails and creates order + shipment records automatically.
2. **Manually**: Insert directly into the `orders` table with `user_id`, `merchant_name`, and optionally `order_number`. Then insert into `shipments` with `order_id` and tracking details.
3. **Via iOS app** (UI): The OrdersView may have an "Add Order" button for manual entry.

## Maintenance

### Debugging

```bash
# Check canonical orders
curl -G "https://cgmaotzmeoiueyzlchaz.supabase.co/rest/v1/orders" \
  -H "apikey: $ANON_KEY" \
  --data-urlencode "order=created_at.desc" \
  --data-urlencode "limit=10"

# Check shipments for an order
curl -G ".../shipments" \
  -H "apikey: $ANON_KEY" \
  --data-urlencode "order_id=eq.<uuid>"

# Check legacy dashboard_records
curl -G ".../dashboard_records" \
  -H "apikey: $ANON_KEY" \
  --data-urlencode "category=eq.deliveries" \
  --data-urlencode "order=created_at.desc" \
  --data-urlencode "limit=10"
```

### Common Issues

- **Order in app but no Live Activity**: Verify the shipment status transitioned to `in_transit` or `out_for_delivery`. Live Activities are started on status transitions, not on order creation.
- **Home Deliveries card not showing**: Check that the `dashboard_records` entry has `category=deliveries` and the iOS app's HomeViewModel is querying for it correctly.
- **Stale status**: The 17track polling updates shipment status. If the app shows outdated info, the polling may have failed or hit rate limits.
- **manualDeliveredAt not working**: Setting `manualDeliveredAt` on an order should cause `effectiveStatus` to return `delivered`. Check that `OrderWithShipments.effectiveStatus` is being used in the view model.
