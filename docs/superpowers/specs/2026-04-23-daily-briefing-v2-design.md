# Daily Briefing v2 — deterministic signals + single-card surface

**Date:** 2026-04-23
**Status:** Design — pending implementation plan.
**Supersedes (partial):** `2026-04-23-biochecha-daily-surfaces.md` — the
`daily_briefing` display_hint is now owned by this spec; BioChecha still
owns `workout_hint`.

## Problem

Fábio's morning briefing today is a Telegram message written by Claudinho.
It's noisy enough that he ignores it:

- Events duplicate (same tire-change appointment twice).
- Every section gets the same weight — a flight at 16:45 reads the same as
  a promo email from Unidas.
- Stale data surfaces with no flag ("Apple ETA 2026-04-01" shown on
  2026-04-23).
- No conflict or anomaly detection — a 09:30 appointment in Köln with a
  10:00 hotel checkout 45 km away in Düsseldorf reads as a flat list.
- Infra status (gateway logs, failing crons) sits in the same surface as
  life stuff.

A briefing should answer three questions in 10 seconds:

1. What should I know right now?
2. What do I need to *do* today?
3. What's unusual and needs attention?

Everything else is reference material, not briefing material.

## Architecture — two passes

```
07:00 local cron
  └─ briefing_signals.py (deterministic)
        ├─ reads: calendar, orders+shipments, dashboard_records (health),
        │        email_summaries, user_location, cron state, agent_runs
        └─ writes: one briefing_signals record per day (category=admin,
                   type=briefing, display_hint=daily_briefing)

  (optional, deferred to v2)
  └─ Claudinho narrator
        └─ reads the signals record, adds a short human-voiced headline /
           summary, writes back to the same record (or appends).

The Perch iOS app renders one Daily Briefing card at the top of Today.
```

**Why deterministic first:** conflict and anomaly detection are exactly
where LLMs drift — missing a clash, inventing a problem that isn't there.
Code is dull and correct. Claudinho earns its keep as the narrator, not
the analyst, and that's an opt-in layer once the signal floor is stable.

**Where the detector runs:** Python script in
`~/.openclaw/workspace/scripts/briefing_signals.py`, scheduled via the
OpenClaw cron (`jobs.json`). Same pattern as
`detect_biochecha_day_type.py` and the 17track poller. Supabase edge
function is more "modern" but adds deploy overhead for a once-a-day job
on a machine that's already running.

## Signal catalog (v1)

Seven signal kinds. Each emits only when applicable; an empty signal type
is omitted from the output. Anchors (today's calendar events) are always
present, so even on quiet days the card has content.

| # | Signal | Source | Example |
|---|---|---|---|
| 2 | `travel_day` | calendar flights + user_location + weather | "Flying DUS→LIS at 16:45. Lisbon: 22 °C clear." |
| 3 | `stale_delivery` | orders + shipments tables | "Apple package ETA was 2026-04-01 — 22 days overdue." |
| 4 | `ship_to_mismatch` | orders + user_location + planned_trajectory | "Lofree keyboard → Amsterdam; you leave Köln for Lisbon today at 16:45." |
| 5 | `health_anomaly` | dashboard_records (health) | "HRV 78 ms — 2.1σ above 7d baseline." |
| 6 | `needs_reply` | email_summaries (new table) | "3 starred emails older than 48h." |
| 7 | `plan_break` | BioChecha day type + workout_session records | "Training day, no workout logged by 20:00." |
| 8 | `system_health` | cron state + agent_runs | "granola-sync-watchdog failed overnight." |

**Intentionally excluded from v1:** calendar conflicts. Fábio manages his
calendar carefully — an auto-detector here would mostly nag.

## Data model

### New tables

```sql
-- JMAP-backed email summary. Listener populates it alongside existing
-- orders-extraction path. Also unlocks future signals (inbox volume
-- anomaly, receipt rollups).
CREATE TABLE public.email_summaries (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message_id    text NOT NULL,            -- JMAP blob/message ID
  thread_id     text,
  from_address  text,
  subject       text,
  received_at   timestamptz,
  folder        text,                      -- "inbox", "archive", "hey", "paper-trail", ...
  starred       boolean DEFAULT false,
  read          boolean DEFAULT false,
  has_replied   boolean DEFAULT false,
  size_bytes    int,
  ingested_at   timestamptz DEFAULT now(),
  UNIQUE (user_id, message_id)
);

CREATE INDEX idx_email_summaries_user_received
  ON public.email_summaries (user_id, received_at DESC);
CREATE INDEX idx_email_summaries_user_starred_unread
  ON public.email_summaries (user_id, starred, read)
  WHERE starred = true AND read = false;

-- Device-provided present location. One row per user, upserted by the
-- iOS app on foreground. Detector reads it for current state; calendar
-- supplies the future trajectory.
CREATE TABLE public.user_location (
  user_id       uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  city          text,
  country_code  text,
  lat           double precision,
  lng           double precision,
  source        text CHECK (source IN ('ios_app', 'manual', 'calendar_inferred')),
  updated_at    timestamptz DEFAULT now()
);
```

Both tables have RLS with `user_id = auth.uid()` policies, same pattern
as existing Perch tables.

### Location strategy — dual source

| Source | Covers | Timing |
|---|---|---|
| `user_location` (app-written) | Current state, "where am I right now" | Real-time, refreshed on app foreground |
| Calendar inference | Future state, "where will I be later today" | Computed at briefing time from events with airport codes / locations |

Both feed into a single `location_context` block in the
briefing_signals payload:

```jsonc
"location_context": {
  "current": {
    "city": "Köln",
    "source": "ios_app",
    "as_of": "2026-04-23T05:30:00Z"
  },
  "planned_today": [
    { "city": "Köln",          "until": "14:30" },
    { "city": "DUS (transit)", "from": "14:30", "until": "16:45" },
    { "city": "Lisbon",        "from": "19:55" }
  ]
}
```

If `user_location.updated_at` is older than 24 hours, the detector falls
back to calendar inference for current state too. Airport → city mapping
lives in a static lookup table in the Python script (starter set: DUS,
LIS, FRA, MUC, JFK, LHR, GRU, CDG).

### briefing_signals record shape

Written to `dashboard_records` (so it flows through the existing Perch
pipeline). One row per day, upsert on `(user_id, date)`.

```jsonc
{
  // Record-level fields
  "category":     "admin",
  "type":         "briefing",
  "display_hint": "daily_briefing",
  "agent_id":     "briefing-signals",
  "title":        "Thu Apr 23",

  // data payload
  "data": {
    "date":         "2026-04-23",
    "generated_at": "2026-04-23T05:00:00Z",
    "location_context": { /* see above */ },
    "anchors": [
      { "kind": "flight",  "title": "TP543 DUS→LIS", "at": "16:45", "priority": "high" },
      { "kind": "meeting", "title": "Codec PM × Design Weekly", "at": "16:05", "priority": "medium" }
    ],
    "signals": [
      {
        "kind": "travel_day",
        "priority": "high",
        "summary": "Flying DUS→LIS at 16:45",
        "detail": {
          "flight": { "code": "TP543", "dep": "DUS", "arr": "LIS", "dep_time": "16:45", "arr_time": "19:55" },
          "dest_weather": { "temp_c": 22, "condition": "clear" }
        }
      },
      {
        "kind": "ship_to_mismatch",
        "priority": "high",
        "summary": "2 packages routed to Amsterdam; you're leaving for Lisbon today",
        "detail": {
          "your_city_today": "Köln → Lisbon",
          "leaving_at": "16:45",
          "shipments": [
            { "merchant": "Lofree",    "tracking": "…", "ship_to_city": "Amsterdam" },
            { "merchant": "Amazon.nl", "tracking": "…", "ship_to_city": "Amsterdam" }
          ]
        }
      },
      {
        "kind": "stale_delivery",
        "priority": "medium",
        "summary": "Apple package ETA 22 days overdue",
        "detail": {
          "orders": [
            { "merchant": "Apple", "eta": "2026-04-01", "last_update": "2026-04-18", "reason": "eta_past" }
          ]
        }
      },
      {
        "kind": "health_anomaly",
        "priority": "low",
        "summary": "HRV 2.1σ above 7d baseline",
        "detail": { "metric": "hrv", "value": 78, "baseline": 62, "z": 2.1, "direction": "up" }
      },
      {
        "kind": "needs_reply",
        "priority": "medium",
        "summary": "3 starred emails older than 48h",
        "detail": {
          "emails": [
            { "from": "…", "subject": "…", "received_at": "…", "age_hours": 72 }
          ]
        }
      },
      {
        "kind": "plan_break",
        "priority": "medium",
        "summary": "Training day, no workout logged yet",
        "detail": { "expected": "workout", "day_type": "training", "as_of": "2026-04-23T20:00Z" }
      },
      {
        "kind": "system_health",
        "priority": "low",
        "summary": "2 crons errored overnight",
        "detail": {
          "failing": [
            { "name": "granola-sync-watchdog", "last_status": "error" },
            { "name": "nutrition-aggregator",  "last_status": "error" }
          ]
        }
      }
    ]
  }
}
```

### Detection rules (per signal)

Concrete thresholds — tuned conservatively so signals feel earned, not nagging:

| Signal | Trigger |
|---|---|
| `travel_day` | Calendar event today with IATA airport code pattern `[A-Z]{3}` in title OR category/keyword "flight". Emits weather for destination city if available. |
| `stale_delivery` | Orders where `expected_delivery_at < now - 1 day` AND `status NOT IN ('delivered','cancelled')`; OR shipments where `updated_at < now - 3 days` AND `status NOT IN ('delivered','exception')`. |
| `ship_to_mismatch` | Active shipment with `destination_city NOT IN (current_city ∪ all cities in planned_today)`. Covers both the "you're leaving today" and "package routed to an old address" cases in a single rule. |
| `health_anomaly` | HRV / sleep_score / weight from last 24h is `>1.5σ` from 7d rolling mean. One signal per metric per day, only highest-z emitted. |
| `needs_reply` | `email_summaries` rows where `starred=true AND read=true AND has_replied=false AND received_at < now - 48h`. Cap at 3. |
| `plan_break` | BioChecha day_type = training AND no workout_session record with `created_at >= today 00:00`. Only emitted if `now > 20:00 local`. |
| `system_health` | Crons in `jobs.json` with `lastStatus=error` in last 24h; OR `agent_runs` rows with status in (`error`, `timeout`) in last 24h. Capped at 5. |

### Empty-day behavior (confirmed)

If nothing worth surfacing is detected, the detector still writes a
record with anchors populated from today's calendar. Signals array can
be empty. This ensures the card never looks broken.

## iOS rendering

Single `DailyBriefingCard` at the top of Today. All sections visible,
scrollable, no collapse-on-tap. Priority-ordered:

```
┌─────────────────────────────────────┐
│ Thu Apr 23 · Köln → LIS             │
│                                     │
│ ⚠️  2 packages → Amsterdam; you     │
│    leave for Lisbon at 16:45        │
│                                     │
│ ✈  Flying TP543 at 16:45            │
│    Lisbon: 22 °C clear              │
│                                     │
│ 📦 Apple ETA 22 days overdue        │
│                                     │
│ 📬 3 emails waiting >48h            │
│                                     │
│ 📅 Today's anchors                  │
│    09:30  Tire change               │
│    16:05  Codec PM × Design         │
│    16:45  ✈ TP543 DUS→LIS           │
└─────────────────────────────────────┘
```

Sections suppress quietly when their signal isn't emitted. Anchors
always render at the bottom as the stable "today at a glance" row.

The existing scaffolded `DailyBriefingCard.swift` (from the BioChecha
session) can be reshaped to this richer payload — no data has been
written to the old contract yet, so there's nothing to migrate.

## Rollout plan

1. **Migrations:** create `email_summaries` and `user_location`. Drop no
   existing artifacts.
2. **JMAP listener extension:** add `email_summaries` writer alongside
   the orders-extraction path. Backfill starts empty; signals ramp up
   as new mail arrives.
3. **iOS location writer:** add a small `LocationService` that fetches
   foreground location, reverse-geocodes to city, upserts
   `user_location`. Requires `NSLocationWhenInUseUsageDescription`
   plist entry.
4. **Detector:** implement `briefing_signals.py`, wire to cron at
   07:00 local. Start with anchors + travel_day + stale_delivery — add
   the rest incrementally as data sources come online.
5. **iOS card:** update `DailyBriefingCard` contract to the new shape.
6. **Deprecate Telegram briefing** once Fábio confirms the Perch card
   carries its weight. Claudinho narrator (pass 2) gets designed only
   if the raw signals feel too dry.

Each step is independently useful. Risk is low: tables are additive,
the card degrades gracefully on missing fields.

## Open questions / deferred

- **Claudinho narrator (pass 2):** whether a human-voiced headline adds
  enough over the structured signals to justify the LLM round-trip.
  Revisit after 2 weeks of using the deterministic version.
- **Location privacy:** considered storing city-only and dropping
  lat/lng for extra privacy. Punting — the data stays in your own
  Supabase with RLS.
- **Background location refresh:** foreground-only for v1. If signals
  start lagging badly on days Fábio doesn't open the app, revisit.
- **Multiple refreshes per day:** single 07:00 pass for v1. Flight
  delays, new shipments, etc. only reflected in the next morning's
  briefing. A 12:00 and 17:00 refresh pass can be added later if the
  card feels stale.
