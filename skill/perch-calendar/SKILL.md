# perch-calendar

## Trigger

Any task involving calendar events, travel detection, event scheduling, or syncing Apple Calendar data to The Perch.

## What it does

The calendar pipeline reads events from the user's Apple Calendar (synced via iCloud) using icalBuddy, then stores them in the Supabase `records` table with `category=calendar` and `type=event`. The iOS app displays these events in CalendarView and uses them for travel mode detection (identifying when the user is away from their home location).

The pipeline runs on a schedule (typically every 15-30 minutes via a LaunchAgent or cron) and does delta syncs — only fetching events that have changed since the last run.

## Architecture

```
Apple Calendar (iCloud synced)
        │
        │ icalBuddy CLI
        ▼
  calendar-sync agent (Node/Python)
  ├─ icalBuddy - CalendarName "eventsToday+14" → raw event text
  ├─ Parse: title, start/end times, location, attendees
  ├─ Normalize: ISO8601 with timezone (+00:00 suffix)
  └─ Upsert to Supabase
        │
        ▼
  records table (category=calendar, type=event)
        │
        ▼
  iOS: CalendarView → CalendarDecodingTests (Swift)
         └─→ TravelViewModel (travel mode detection)
```

### icalBuddy Usage

```bash
# Today's events
icalBuddy -Calendar "Home" -sd -tf "%Y-%m-%dT%H:%M:%S%z" eventsToday

# Next 14 days
icalBuddy -Calendar "Home" -sd -tf "%Y-%m-%dT%H:%M:%S%z" eventsToday+14

# Specific calendar
icalBuddy -Calendar "Work" -sd -tf "%Y-%m-%dT%H:%M:%S%z" eventsToday+7
```

### ISO8601 Timezone Requirement

**All event times MUST include a timezone suffix** (e.g., `+00:00`, `+01:00`, `Z`). 

Without a timezone, the iOS app's Swift date decoder (`ISO8601Decoder`) fails silently and the card shows empty. This is the most common calendar integration bug.

Valid: `2026-04-20T09:00:00+01:00`
Invalid: `2026-04-20T09:00:00` (missing timezone)

### Travel Mode Detection

Travel mode is triggered when an event's `location` field matches known airport codes, hotel patterns, or non-home city names. The TravelViewModel scans upcoming events for location data that indicates the user is away. When detected, The Perch switches to travel mode, which:
- Adjusts health/nutrition targets (e.g., looser calorie targets)
- Shows a travel indicator in the HomeView
- Switches weather display to destination city

## Data Schema

### records table (calendar category)

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID | Primary key |
| `user_id` | UUID | Owner |
| `category` | TEXT | `calendar` |
| `type` | TEXT | `event` |
| `title` | TEXT | Event title |
| `data` | JSONB | Event payload |
| `display_hint` | TEXT | `calendar_event` |
| `created_at` | TIMESTAMPTZ | When stored |

### data payload

```json
{
  "start_time": "2026-04-20T09:00:00+01:00",
  "end_time": "2026-04-20T10:30:00+01:00",
  "location": "Lisbon, PT",
  "attendees": ["Fábio Resende", "Jane Doe"],
  "calendar": "Home",
  "uid": "ical-uuid-12345@calendarserver"
}
```

## Common Parsing Errors

| Error | Cause | Fix |
|-------|-------|-----|
| Empty card in iOS | Missing timezone suffix on times | Always output `+00:00` or `+01:00` |
| Wrong date | All-day events parsed as 00:00 UTC | Handle all-day events separately |
| Missing location | Event has no location field | Default to null, don't omit |
| Duplicate events | Running sync twice without dedup | Use event `uid` for upsert key |

## Setup

### icalBuddy Installation

```bash
brew install icalBuddy
```

### Cron Schedule

```cron
# Every 15 minutes
*/15 * * * * cd /Users/faresende/.openclaw/workspace/ThePerch && node scripts/calendar-sync.js >> ~/.openclaw/logs/calendar.log 2>&1
```

## Maintenance

### Debugging

```bash
# Test icalBuddy output
icalBuddy -Calendar "Home" -sd -tf "%Y-%m-%dT%H:%M:%S%z" eventsToday+7

# Check calendar records in Supabase
curl -G "https://cgmaotzmeoiueyzlchaz.supabase.co/rest/v1/records" \
  -H "apikey: $ANON_KEY" \
  --data-urlencode "category=eq.calendar" \
  --data-urlencode "order=created_at.desc" \
  --data-urlencode "limit=20"
```

### Common Issues

- **Card shows empty in iOS**: Verify all times have timezone suffixes. Run icalBuddy directly to check raw output.
- **Events not syncing**: Check that the calendar name matches exactly (case-sensitive). Run with verbose logging.
- **Travel mode not triggering**: Travel detection looks for location field in events. If calendars don't have location set, travel mode won't activate.
