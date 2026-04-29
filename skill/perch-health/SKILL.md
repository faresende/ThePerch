---
name: perch-health
description: "Health data pipeline from Oura Ring sensor data through to Supabase records, including sleep, readiness, HRV, weight and body metrics."
version: 1.0.0
---

# perch-health

## Trigger

Any task involving health metrics, Oura Ring data, body measurements, sleep analysis, readiness scores, or the health data pipeline for The Perch. Also triggered when debugging health-related cards or widgets in the iOS app.

## What it does

This skill manages the end-to-end health data pipeline for The Perch, from Oura Ring sensor data through to iOS dashboard display. It covers two main data streams: Oura Ring biometrics (sleep stages, readiness, resting heart rate, HRV) and body composition metrics (weight, body fat percentage, muscle mass). All health data is persisted in the Supabase `records` table with `category=health`.

The Oura Ring API provides nightly sleep analysis, daily readiness scores, and continuous heart rate variability data. These are ingested on a schedule, transformed into structured records, and written to Supabase. The iOS app reads these records and renders them via `HealthSummaryCard`, `ChartCard`, and `SingleValueCard` views depending on the `display_hint` field.

## Architecture

```
Oura Ring API                        Manual Input / Other Sources
     │                                           │
     │  REST (Bearer token)                      │
     ▼                                           ▼
Oura Ingestion Script                        OpenClaw Agent
  ├─ /v2/usercollection/sleep                   │
  ├─ /v2/usercollection/daily_activity          │
  └─ /v2/usercollection/heartrate               │
     │                                           │
     ▼                                           ▼
┌──────────────────────────────────────────────────────┐
│              Supabase `records` table                 │
│                                                      │
│  category = "health"                                 │
│  type: health_summary | body_metrics                 │
│  data (JSON): sleep, readiness, HR, HRV, weight, etc.│
│  display_hint: chart | single_value                  │
└──────────────────────────────────────────────────────┘
                      │
                      │  anon key + user auth (RLS)
                      ▼
            ┌──────────────────────┐
            │   The Perch iOS App  │
            │                      │
            │  HealthViewModel     │
            │    ├─ HealthSummaryCard
            │    ├─ ChartCard (trends)
            │    └─ SingleValueCard (latest)
            │                      │
            │  Widget Extension    │
            └──────────────────────┘
```

### Data Flow

1. **Ingestion**: Oura API data is fetched by an OpenClaw agent or cron script, typically every morning after sleep data is available (usually by 8am local time).
2. **Transformation**: Raw Oura responses are normalized into two record types:
   - `health_summary`: Sleep stages, readiness score, HRV, resting heart rate
   - `body_metrics`: Weight, body fat %, muscle mass
3. **Persistence**: Records are upserted into `records` with `category=health` and appropriate `type`/`display_hint`.
4. **Display**: The iOS `HealthViewModel` queries records, aggregates trends, and renders cards.

## Data Schema

### Supabase `records` table (health rows)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Owner (references auth.users) |
| `category` | text | Always `"health"` |
| `type` | text | `"health_summary"` or `"body_metrics"` |
| `title` | text | Human-readable title (e.g., "Sleep Summary", "Body Weight") |
| `data` | JSONB | Type-specific payload (see below) |
| `created_at` | timestamptz | Record creation time |

### Health Summary (`type=health_summary`, `data` JSON)

```json
{
  "sleep_duration_hours": 7.5,
  "sleep_efficiency_pct": 92,
  "sleep_stages": {
    "deep_minutes": 95,
    "rem_minutes": 120,
    "light_minutes": 180,
    "awake_minutes": 15
  },
  "readiness_score": 85,
  "resting_heart_rate_bpm": 58,
  "hrv_ms": 45.2,
  "temperature_deviation": 0.3
}
```

### Body Metrics (`type=body_metrics`, `data` JSON)

```json
{
  "weight_kg": 82.5,
  "body_fat_pct": 16.8,
  "muscle_mass_kg": 38.2,
  "source": "oura | manual | withings",
  "notes": "Morning weigh-in"
}
```

### Display Hints for Health

| Display Hint | Used For | iOS Card |
|-------------|----------|----------|
| `chart` | Trend data (weight over time, HRV trends) | `ChartCard` |
| `single_value` | Latest metric (today's readiness) | `SingleValueCard` |
| (none / auto) | Full sleep summary | `HealthSummaryCard` |

## Setup

### Prerequisites

- Oura Ring account with API access (Personal Access Token)
- Supabase project with migrations applied (see perch-supabase)
- Environment variable `OURA_PERSONAL_TOKEN` set

### Configuration

1. Generate an Oura Personal Access Token at https://cloud.ouraring.com/personal-access-tokens
2. Set the token in the agent environment:
   ```bash
   export OURA_PERSONAL_TOKEN=your_token_here
   ```
3. Verify the Supabase `records` table accepts `category=health` rows (it should by default)

### Ingesting Data Manually

```bash
# Fetch yesterday's sleep data from Oura
curl -H "Authorization: Bearer $OURA_PERSONAL_TOKEN" \
  "https://api.ouraring.com/v2/usercollection/sleep?start_date=$(date -v-1d +%Y-%m-%d)&end_date=$(date +%Y-%m-%d)"

# Write to Supabase via dashboard_push or direct API call
```

### Adding a New Health Metric

1. Define the new `data` JSON structure
2. Update the ingestion script to include the new field
3. If needed, add a new `DisplayHint` case in the iOS `Record.swift` enum
4. Create or update the appropriate card view in `Views/Cards/`

## Maintenance

### Debugging

- **Missing Oura data**: Check that the Oura token is valid and hasn't expired. Oura data is typically available by 8am. Early runs may return empty results.
- **Duplicate records**: The pipeline should upsert based on date + type. If duplicates appear, deduplicate with:
  ```sql
  DELETE FROM records a USING records b
  WHERE a.id < b.id
    AND a.user_id = b.user_id
    AND a.category = 'health'
    AND a.type = b.type
    AND a.created_at::date = b.created_at::date;
  ```
- **Stale widget data**: iOS widgets cache aggressively. Force-refresh by pulling down on the Today tab.

### Monitoring

- Verify daily ingestion by checking for recent health records:
  ```sql
  SELECT type, title, created_at
  FROM records
  WHERE category = 'health'
    AND created_at > now() - interval '24 hours'
  ORDER BY created_at DESC;
  ```
- Track Oura API rate limits (generous, but worth monitoring for bulk backfills)

### Common Issues

- **Oura token expired**: Re-generate at the Oura developer portal and update the environment variable
- **Sleep data gaps**: Oura may not record data if the ring wasn't worn. These gaps are expected and should be handled gracefully in the iOS display
- **Timezone mismatches**: Oura uses UTC for API responses but groups by "sleep days" (a sleep day starts at 4pm UTC). The iOS app should display dates in the user's local timezone
