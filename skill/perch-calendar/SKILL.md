# perch-calendar

## Trigger

Any task involving calendar events, schedule management, event ingestion from Apple Calendar, travel mode detection, or the calendar data pipeline for The Perch. Also triggered when debugging calendar-related cards or event display issues in the iOS app.

## What it does

This skill manages the calendar data pipeline for The Perch, ingesting events from Apple Calendar (iCloud-synced) via icalBuddy and persisting them to the Supabase `records` table with `category=calendar`. The iOS app reads these records and renders them as event cards with time, location, and attendee information.

The pipeline handles timezone-aware timestamps (ISO8601 with explicit timezone offsets), supports travel mode detection by parsing event location fields, and integrates with the training schedule to surface workout sessions alongside regular calendar events.

## Architecture

```
Apple Calendar (iCloud)
     │
     │  icalBuddy CLI
     ▼
Calendar Ingestion Script
  ├─ Parse events (title, start, end, location, notes)
  ├─ Detect travel mode via location heuristics
  └─ Format timestamps as ISO8601 with timezone
     │
     ▼
┌──────────────────────────────────────────────────────┐
│              Supabase `records` table                 │
│                                                      │
│  category = "calendar"                               │
│  type = "event"                                      │
│  data (JSON): start, end, location, travel_mode, etc.│
└──────────────────────────────────────────────────────┘
                      │
                      │  anon key + user auth (RLS)
                      ▼
            ┌──────────────────────┐
            │   The Perch iOS App  │
            │                      │
            │  CalendarView        │
            │    └─ EventCard      │
            │                      │
            │  Home tab            │
            │    └─ Upcoming events│
            └──────────────────────┘
```

### Data Flow

1. **Ingestion**: icalBuddy reads upcoming events from Apple Calendar. The agent runs this on a schedule (typically every 30-60 minutes).
2. **Transformation**: Raw icalBuddy output is parsed into structured event records with timezone-aware timestamps.
3. **Travel Detection**: Location fields are analyzed for travel indicators (airport codes, city names, hotel chains) to set a `travel_mode` flag.
4. **Persistence**: Events are upserted into `records` with `category=calendar`, `type=event`, and ISO8601 timestamps including timezone offset (e.g., `+00:00` for UTC).
5. **Display**: The iOS app renders events via `EventCard` in `CalendarView` and upcoming events on the Home tab.

### Travel Mode Detection

Events with location data are checked against heuristics:
- Airport names or codes (e.g., "LIS", "Schiphol")
- Foreign city names outside the user's home area
- Hotel chain keywords (e.g., "Marriott", "Hilton")
- Explicit travel keywords (e.g., "flight", "train to")

When detected, the record includes `"travel_mode": true` and the app can show travel-specific UI.

## Data Schema

### Supabase `records` table (calendar rows)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Owner (references auth.users) |
| `category` | text | Always `"calendar"` |
| `type` | text | Always `"event"` |
| `title` | text | Event title (e.g., "Team Standup", "Flight to Amsterdam") |
| `data` | JSONB | Event payload (see below) |
| `created_at` | timestamptz | Record creation time |

### Event Data (`type=event`, `data` JSON)

```json
{
  "start_time": "2025-04-21T09:00:00+01:00",
  "end_time": "2025-04-21T09:30:00+01:00",
  "location": "Office, Room 3B",
  "notes": "Weekly sync with engineering",
  "calendar_name": "Work",
  "all_day": false,
  "travel_mode": false,
  "attendees": ["alice@example.com", "bob@example.com"]
}
```

### Travel Event Example

```json
{
  "start_time": "2025-04-25T06:30:00+00:00",
  "end_time": "2025-04-25T10:15:00+01:00",
  "location": "Lisbon Airport (LIS) → Schiphol (AMS)",
  "calendar_name": "Personal",
  "all_day": false,
  "travel_mode": true,
  "travel_details": {
    "origin": "Lisbon",
    "destination": "Amsterdam",
    "type": "flight"
  }
}
```

**Critical**: All timestamps must use ISO8601 with explicit timezone offset (e.g., `+00:00`, `+01:00`). Never use naive datetime strings. The iOS app parses these with `ISO8601DateFormatter` and expects the offset.

## Setup

### Prerequisites

- macOS with Apple Calendar configured and iCloud sync enabled
- icalBuddy installed: `brew install ical-buddy`
- Supabase project with migrations applied (see perch-supabase)

### Ingesting Events

```bash
# List today's and tomorrow's events
icalBuddy -f -n -nc -nrd -b "" -ps "/: /" eventsFrom:today to:tomorrow

# Example output:
# • Team Standup
#   2025-04-21 09:00 - 09:30
#   Location: Office, Room 3B
```

### Writing to Supabase

```bash
curl -X POST "https://cgmaotzmeoiueyzlchaz.supabase.co/rest/v1/records" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "user_id": "00000000-0000-0000-0000-000000000000",
    "category": "calendar",
    "type": "event",
    "title": "Team Standup",
    "data": {
      "start_time": "2025-04-21T09:00:00+01:00",
      "end_time": "2025-04-21T09:30:00+01:00",
      "location": "Office, Room 3B",
      "calendar_name": "Work",
      "all_day": false,
      "travel_mode": false
    }
  }'
```

## Maintenance

### Debugging

- **Events not showing**: Verify icalBuddy has calendar access in System Settings → Privacy & Security → Calendars. Also check that the agent is running the ingestion on schedule.
- **Wrong timezone**: Ensure timestamps include the `+00:00` / `+01:00` suffix. The iOS app will not parse naive datetimes correctly.
- **Missing travel detection**: Add new location patterns to the travel detection heuristics in the ingestion script.

### Monitoring

```sql
-- Check recent calendar records
SELECT title, data->>'start_time' as start_time, data->>'location' as location,
       data->>'travel_mode' as travel_mode
FROM records
WHERE category = 'calendar'
  AND created_at > now() - interval '24 hours'
ORDER BY (data->>'start_time') ASC;
```

### Common Issues

- **icalBuddy permission denied**: Re-grant calendar access in macOS Privacy settings. Terminal/iTerm may lose calendar access after macOS updates.
- **Duplicate events**: The pipeline should upsert based on title + start_time. If duplicates appear, deduplicate with a SQL query matching on title and start_time proximity.
- **Stale events**: The pipeline should clean up past events periodically. Events older than the current day can be deleted or archived.
