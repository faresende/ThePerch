# Your Agent Prompts for ThePerch Dashboard Data

These are instructions for OpenClaw agents to populate the Supabase `dashboard_records` table with data that ThePerch iOS app will display.

## How the Workflow Works

There are **two levels** of database operations:

### 1. Schema Setup (the user runs SQL manually — one-time)
Table creation, column changes, indexes, RLS policies — anything that changes the database *structure*. Your Agent generates the SQL, the user copies it into the **Supabase SQL Editor** and runs it.

### 2. Data Operations (Your Agent does directly via REST API)
Inserting, updating, and upserting *records* — Your Agent can do this autonomously using the **Supabase REST API** (PostgREST). He just needs:
- **Project URL:** `https://<project-ref>.supabase.co`
- **API Key:** the `anon` or `service_role` key from Supabase Settings → API
- **HTTP requests:** `POST` to insert, `PATCH` to update, with the table name in the URL path

So for day-to-day data entry (logging sleep, calories, deliveries, etc.), **Your Agent handles it directly** — no copy-pasting SQL needed.

### Example: Logging sleep data

> **the user:** "Log my sleep: 7h total, 1.5h deep, lowest HR 52, HRV 45"
>
> **Your Agent:** *(makes 4 POST requests to Supabase REST API and confirms)* "Done! Logged your sleep data — 7h total, 1.5h deep sleep, 52 bpm lowest HR, 45ms HRV."

### Example: Schema change (one-time)

> **the user:** "Add a new column for sleep scores"
>
> **Your Agent:** "Here's the SQL to run in the Supabase SQL Editor:"
> ```sql
> ALTER TABLE dashboard_records ADD COLUMN sleep_score integer;
> ```

---

## 1. Oura Ring Sleep Data (Daily)

**Agent:** Your Agent (or a dedicated sleep agent)
**Trigger:** When the user shares his Oura sleep data in chat
**Source:** the user tells Your Agent the values from the Oura app
**Method:** Supabase REST API (direct insert)

### Prompt:

```
When I share my sleep data from Oura, insert the following records into the `dashboard_records` table via the Supabase REST API. Each metric should be its own separate record.

Use these exact field values for each record:
- agent_id: "your-agent"
- user_id: (my user UUID)
- category: "health"
- type: "measurement"
- display_hint: "chart"
- pinned: false

Insert these 4 records:

1. **Sleep Duration**
   - title: "Sleep Duration"
   - data: {"metric": "sleep_duration", "value": <total_sleep_hours>, "unit": "hrs", "timestamp": "<ISO8601 of sleep end time>"}

2. **Deep Sleep**
   - title: "Deep Sleep"
   - data: {"metric": "deep_sleep", "value": <deep_sleep_hours>, "unit": "hrs", "timestamp": "<ISO8601 of sleep end time>"}

3. **Lowest Sleep Heart Rate**
   - title: "Lowest Sleep HR"
   - data: {"metric": "lowest_sleep_hr", "value": <lowest_hr_bpm>, "unit": "bpm", "timestamp": "<ISO8601 of sleep end time>"}

4. **Average Sleep HRV**
   - title: "Sleep HRV"
   - data: {"metric": "avg_sleep_hrv", "value": <avg_hrv_ms>, "unit": "ms", "timestamp": "<ISO8601 of sleep end time>"}

Convert all durations to hours (e.g., 7h 23m = 7.38). Round to 2 decimal places.
```

---

## 2. Daily Calories Tracking (Updated Throughout Day)

**Agent:** Your Agent
**Trigger:** Every time the user logs food in chat
**Source:** Conversation with the user (food logging)
**Method:** Supabase REST API (upsert — update if today's record exists, insert if first entry)

### Prompt:

```
When I tell you what I've eaten, upsert my daily calorie record in the `dashboard_records` table via the Supabase REST API.

Upsert (update if exists for today, insert if first entry):
- agent_id: "your-agent"
- user_id: (my user UUID)
- category: "health"
- type: "measurement"
- display_hint: "progress_gauge"
- title: "Daily Calories"
- data: {
    "metric": "daily_calories",
    "value": <total_calories_consumed_today>,
    "unit": "kcal",
    "target": <my_daily_calorie_target>,
    "context": "<today's date YYYY-MM-DD>"
  }

IMPORTANT:
- Set the target based on my current nutrition plan (you know my goals from our conversations)
- Accumulate calories throughout the day — each update should reflect the TOTAL for today
- If I haven't told you my target, use 2200 kcal as default and ask me to confirm
```

---

## 3. Daily Macros Tracking (Updated Throughout Day)

**Agent:** Your Agent
**Trigger:** Updated alongside calories when food is logged
**Source:** Conversation with the user (food logging)
**Method:** Supabase REST API (upsert alongside calories)

### Prompt:

```
When updating my daily calories, also upsert my macronutrient record in `dashboard_records` via the Supabase REST API.

Upsert for today's date:
- agent_id: "your-agent"
- user_id: (my user UUID)
- category: "health"
- type: "measurement"
- display_hint: "macros_bar"
- title: "Daily Macros"
- data: {
    "protein": <grams_protein_today>,
    "protein_target": <daily_protein_target>,
    "carbs": <grams_carbs_today>,
    "carbs_target": <daily_carbs_target>,
    "fat": <grams_fat_today>,
    "fat_target": <daily_fat_target>,
    "date": "<today YYYY-MM-DD>"
  }

IMPORTANT:
- Set targets based on my current nutrition plan
- Accumulate macros throughout the day
- Default targets if not set: protein 180g, carbs 250g, fat 70g
```

---

## 4. Body Composition Data (from InBody / Manual)

**Agent:** Your Agent
**Trigger:** When the user shares InBody results or manual measurements
**Source:** Conversation with the user
**Method:** Supabase REST API (direct insert)

### Prompt:

```
When I share body composition data (InBody scan, manual measurements, etc.), insert records into `dashboard_records` via the Supabase REST API.

1. **Skeletal Muscle Mass**
   - title: "Skeletal Muscle Mass"
   - data: {"metric": "smm", "value": <kg>, "unit": "kg"}
   - display_hint: "chart"

2. **Body Fat Percentage**
   - title: "Body Fat %"
   - data: {"metric": "body_fat_pct", "value": <percentage>, "unit": "%"}
   - display_hint: "chart"

All records: agent_id "your-agent", category "health", type "measurement".
```

---

## 5. Delivery Tracking

IMPORTANT CONTRACT UPDATE:

- `dashboard_records` is still the generic card/event/measurement feed.
- New tracked packages should NOT be created in `dashboard_records` by default.
- The canonical tracked-delivery model is now `orders` + `shipments`.
- Only write legacy `dashboard_records` delivery rows if a specific compatibility surface still requires them.

**Agent:** Your Agent (orders/deliveries)
**Trigger:** When the user shares a tracking number or asks for delivery updates
**Source:** Tracking numbers from conversation
**Method:** Supabase REST API (insert new deliveries, update status on existing ones)

### Prompt:

```
When I share a tracking number or delivery update, write tracked deliveries to the dedicated `orders` and `shipments` tables, not `dashboard_records`.

Create or upsert one `orders` row:

- user_id: (my user UUID)
- merchant_name: "<merchant or carrier name>"
- normalized_merchant: lowercase normalized merchant/carrier name
- order_number: "<order number or tracking number if no order number exists>"
- status: "<ordered | processing | shipped_partial | shipped | delivered | cancelled | issue>"
- source_email_ids: array; use a synthetic source like ["manual_tracking_entry"] if there is no email
- confidence_score: 1.0 for explicit manual tracking entries

Then create or upsert one `shipments` row linked to that order:

- tracking_number: "<full tracking number>"
- carrier: "<carrier name>"
- status: "<unknown | label_created | in_transit | out_for_delivery | delivered | exception>"
- latest_checkpoint: "<latest human-readable checkpoint or null>"
- shipped_at: "<ISO8601 or null>"
- delivered_at: "<ISO8601 or null>"
- source_email_ids: array; use ["manual_tracking_entry"] if needed
- confidence_score: 1.0 for explicit manual tracking entries

Use lowercase snake_case status values.
If you also need a legacy delivery card for temporary compatibility, say so explicitly and treat it as a secondary mirror, not the source of truth.
```

---

## 6. Calendar Events

**Agent:** Your Agent (calendar)
**Trigger:** When the user asks to sync calendar events or mentions upcoming events
**Source:** Google Calendar API, conversation
**Method:** Supabase REST API (insert new events, update changed ones)

### Prompt:

```
When I ask you to sync my calendar or mention events, insert records into `dashboard_records` via the Supabase REST API.

- agent_id: "calendario"
- user_id: (my user UUID)
- category: "calendar"
- type: "event"
- display_hint: "timeline"
- title: "<event title>"
- data: {
    "title": "<event title>",
    "start": "<ISO8601 start datetime>",
    "end": "<ISO8601 end datetime>",
    "location": "<location or null>",
    "agent_notes": "<any context or prep notes you want to add>"
  }

IMPORTANT:
- Sync events for the next 7 days
- Add agent_notes with useful context (e.g., "Prepare Q1 report for this meeting")
- Update existing events if they change (match by title + start time)
- Remove cancelled events
```

---

## 7. Admin: Gateway Status & Crons

**Agent:** Your Agent (system task)
**Trigger:** When the user asks for a system status update, or periodically as part of a health check
**Method:** Supabase REST API (upsert status records)

### Prompt for Gateway Status:

```
Write a gateway status snapshot to `dashboard_records` via the Supabase REST API.

- agent_id: "your-agent"
- category: "admin"
- type: "status"
- display_hint: "single_value"
- title: "Gateway Status"
- data: {
    "is_running": true,
    "active_models": [
      {"model_id": "anthropic/claude-opus-4-7", "job_count": 3},
      {"model_id": "ollama/qwen2.5:14b", "job_count": 5}
    ],
    "active_session_count": <number of active sessions>,
    "active_hourly": [<24 integers, one per hour, counting events>],
    "peak_hour": <hour with most activity, 0-23>
  }
```

### Prompt for Upcoming Crons:

```
For each active cron job in OpenClaw, write a record to `dashboard_records` via the Supabase REST API.

- agent_id: "your-agent"
- category: "admin"
- type: "status"
- display_hint: "status_list"
- title: "<cron job name>"
- data: {
    "name": "<human-readable name>",
    "schedule": "<cron expression>",
    "model": "<model used>",
    "next_run_at": "<ISO8601 next run time>",
    "last_run_at": "<ISO8601 last run time or null>",
    "enabled": true
  }

Update these records periodically to keep next_run_at accurate.
```

---

## Schema Setup SQL (Run Once in Supabase SQL Editor)

These are the one-time SQL statements the user needs to run manually. Your Agent should generate these when setting up new table structures:

```sql
-- The dashboard_records table (if not already created)
CREATE TABLE IF NOT EXISTS dashboard_records (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    agent_id text NOT NULL,
    user_id uuid REFERENCES auth.users(id),
    category text NOT NULL,      -- 'health', 'deliveries', 'calendar', 'admin', 'legal', 'bookmarks'
    type text NOT NULL,           -- 'measurement', 'delivery', 'event', 'status', 'checklist', 'bookmark', 'cost_summary'
    display_hint text,            -- 'chart', 'status_list', 'timeline', 'single_value', 'progress_gauge', 'macros_bar'
    title text NOT NULL,
    data jsonb DEFAULT '{}'::jsonb,
    pinned boolean DEFAULT false,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);

-- Index for fast category lookups
CREATE INDEX IF NOT EXISTS idx_records_category ON dashboard_records(category);
CREATE INDEX IF NOT EXISTS idx_records_user_category ON dashboard_records(user_id, category);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_updated_at
    BEFORE UPDATE ON dashboard_records
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at();
```

---

## SQL to Check/Verify Data

Run these in the Supabase SQL Editor to verify records were inserted correctly:

```sql
-- Check what health records exist
SELECT title, data->>'metric' as metric, data->>'value' as value, created_at
FROM dashboard_records
WHERE category = 'health'
ORDER BY created_at DESC
LIMIT 20;

-- Check delivery records
SELECT title, data->>'status' as status, data->>'carrier' as carrier, created_at
FROM dashboard_records
WHERE category = 'deliveries'
ORDER BY created_at DESC;

-- Check admin records
SELECT title, type, display_hint, created_at
FROM dashboard_records
WHERE category = 'admin'
ORDER BY created_at DESC;

-- Check for today's calories (useful for upsert verification)
SELECT id, title, data->>'value' as calories, data->>'target' as target, created_at
FROM dashboard_records
WHERE category = 'health'
  AND data->>'metric' = 'daily_calories'
  AND created_at::date = CURRENT_DATE;
```
