# Agent Integration Guide

ThePerch is designed to be populated by agents — automated scripts or AI assistants that write structured data to your Supabase backend. The app reads it and displays it.

Important: The app now has two data planes.

- `dashboard_records` is the generic card feed for measurements, meals, events, notes, bookmarks, status, and similar dashboard content.
- `orders` + `shipments` is the canonical tracked-delivery model for package tracking shown in the current Hub > Orders surface.

Do not default new tracked packages into `dashboard_records` just because they are “deliveries”. Use `orders` + `shipments` unless you intentionally need a temporary legacy compatibility card.

## How It Works

Agents write generic dashboard cards to the `dashboard_records` table using the Supabase `service_role` key. The iOS app reads using the `anon` key (Row Level Security ensures users only see their own data).

```
Agent (Python/Node/bash) → Supabase dashboard_records → ThePerch iOS app cards
Agent (Python/Node/bash) → Supabase orders + shipments → ThePerch Hub > Orders
```

## Required Fields

Every record needs these fields:

| Field | Type | Description |
|-------|------|-------------|
| `user_id` | UUID | Your Supabase auth user ID |
| `agent_id` | String | Identifier for your agent (e.g., `"biochecha"`, `"my-health-agent"`) |
| `type` | String | Record type (see below) |
| `category` | String | Tab it appears in (see below) |
| `title` | String | Human-readable title |
| `data` | JSON | The actual payload (schema depends on type) |
| `display_hint` | String | How to render it (see below) |

## Supported Types

### `measurement` (category: `health`)
Health and fitness metrics.

```json
{
  "metric": "daily_calories",
  "value": 2847,
  "unit": "kcal",
  "target": 3400,
  "context": "2026-03-18"
}
```

Common `metric` values: `daily_calories`, `weight`, `skeletal_muscle`, `body_fat_pct`, `sleep_duration`, `sleep_score`, `readiness_score`, `avg_sleep_hrv`, `lowest_sleep_hr`, `deep_sleep`, `activity_score`

### `workout_session` (category: `health`)
A logged gym session.

```json
{
  "date": "2026-03-18",
  "session_number": 39,
  "muscle_groups": ["chest", "biceps", "triceps"],
  "duration_min": 64,
  "active_calories": 520,
  "avg_hr": 131,
  "exercises": [
    {
      "name": "Bench Press",
      "sets": [
        {"reps": 8, "weight_kg": 80},
        {"reps": 8, "weight_kg": 85}
      ]
    }
  ]
}
```

### `delivery` (category: `deliveries`)
A legacy compatibility delivery card.

For new tracked packages, prefer `orders` + `shipments` instead of a `dashboard_records` delivery row.

```json
{
  "carrier": "DHL Express",
  "tracking_number": "1234567890",
  "status": "in_transit",
  "eta": "2026-03-20T18:00:00Z",
  "items": [{"name": "Package", "quantity": 1}]
}
```

### `event` (category: `calendar`)
A calendar event.

```json
{
  "title": "Team standup",
  "start": "2026-03-19T10:00:00+01:00",
  "end": "2026-03-19T10:30:00+01:00",
  "location": "Zoom"
}
```

## Display Hints

| `display_hint` | Used for |
|----------------|----------|
| `single_value` | Simple number/text cards |
| `chart` | Time-series chart cards |
| `macros_bar` | Macro nutrition bars |
| `progress_gauge` | Circular progress ring |
| `timeline` | Event timeline |
| `calendar_event` | Calendar events |

## Authentication

Use the **service_role key** (not the anon key) for agent writes. Find it in:
`Supabase Dashboard → Settings → API → service_role`

⚠️ Never expose the service_role key in a mobile app or public repo.

## Example: Python Agent

```python
import os
from datetime import date
from supabase import create_client

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_SERVICE_KEY = os.environ["SUPABASE_SERVICE_KEY"]
USER_ID = os.environ["PERCH_USER_ID"]

client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

# Write a daily calorie measurement
client.table("dashboard_records").insert({
    "user_id": USER_ID,
    "agent_id": "my-nutrition-agent",
    "type": "measurement",
    "category": "health",
    "title": "Daily Calories",
    "display_hint": "progress_gauge",
    "data": {
        "metric": "daily_calories",
        "value": 2847,
        "unit": "kcal",
        "target": 3400,
        "context": str(date.today())
    }
}).execute()
```

## Example: curl

```bash
curl -X POST "$SUPABASE_URL/rest/v1/dashboard_records" \
  -H "apikey: $SUPABASE_SERVICE_KEY" \
  -H "Authorization: Bearer $SUPAB...KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "'$USER_ID'",
    "agent_id": "test-agent",
    "type": "measurement",
    "category": "health",
    "title": "Weight",
    "display_hint": "single_value",
    "data": {
      "metric": "weight",
      "value": 85.5,
      "unit": "kg",
      "context": "2026-03-18"
    }
  }'
```

## Tracked deliveries: canonical path

If the task is “add this package/tracking number to ThePerch,” write to:

- `orders`
- `shipments`

Minimal shape:

### `orders`

```json
{
  "user_id": "00000000-0000-0000-0000-000000000000",
  "merchant_name": "UPS",
  "normalized_merchant": "ups",
  "order_number": "1Z123...",
  "status": "shipped",
  "source_email_ids": ["manual_tracking_entry"],
  "confidence_score": 1.0
}
```

### `shipments`

```json
{
  "order_id": "<uuid from orders>",
  "tracking_number": "1Z123...",
  "carrier": "UPS",
  "status": "in_transit",
  "latest_checkpoint": "Added manually from tracking link",
  "source_email_ids": ["manual_tracking_entry"],
  "confidence_score": 1.0
}
```

Use `dashboard_records` delivery rows only when you explicitly need a legacy compatibility mirror for older home/search/widget surfaces.

## Updating Records

To update an existing record (e.g., intraday calorie updates), use `upsert` or `update`:

```python
# Update by searching for existing record
existing = client.table("dashboard_records").select("id")\
    .eq("user_id", USER_ID)\
    .eq("type", "measurement")\
    .eq("data->>metric", "daily_calories")\
    .eq("data->>context", str(date.today()))\
    .execute()

if existing.data:
    client.table("dashboard_records")\
        .update({"data": {...updated_data...}})\
        .eq("id", existing.data[0]["id"])\
        .execute()
else:
    client.table("dashboard_records").insert({...new_record...}).execute()
```

The app always displays the most recently **updated** record for a given metric/date, so intraday updates work correctly.
