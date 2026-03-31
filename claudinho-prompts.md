# Claudinho Prompts for ThePerch Dashboard Data

These are instructions for OpenClaw agents to populate the Supabase `dashboard_records` table with data that ThePerch iOS app will display.

## How the Workflow Works

There are **two levels** of database operations:

### 1. Schema Setup (Fabio runs SQL manually — one-time)
Table creation, column changes, indexes, RLS policies — anything that changes the database *structure*. Claudinho generates the SQL, Fabio copies it into the **Supabase SQL Editor** and runs it.

### 2. Data Operations (Claudinho does directly via REST API)
Inserting, updating, and upserting *records* — Claudinho can do this autonomously using the **Supabase REST API** (PostgREST). He just needs:
- **Project URL:** `https://<project-ref>.supabase.co`
- **API Key:** the `anon` or `service_role` key from Supabase Settings → API
- **HTTP requests:** `POST` to insert, `PATCH` to update, with the table name in the URL path

So for day-to-day data entry (logging sleep, calories, deliveries, etc.), **Claudinho handles it directly** — no copy-pasting SQL needed.

### Example: Logging sleep data

> **Fabio:** "Log my sleep: 7h total, 1.5h deep, lowest HR 52, HRV 45"
>
> **Claudinho:** *(makes 4 POST requests to Supabase REST API and confirms)* "Done! Logged your sleep data — 7h total, 1.5h deep sleep, 52 bpm lowest HR, 45ms HRV."

### Example: Schema change (one-time)

> **Fabio:** "Add a new column for sleep scores"
>
> **Claudinho:** "Here's the SQL to run in the Supabase SQL Editor:"
> ```sql
> ALTER TABLE dashboard_records ADD COLUMN sleep_score integer;
> ```

---

## 1. Oura Ring Sleep Data (Daily)

**Agent:** Claudinho (or a dedicated sleep agent)
**Trigger:** When Fabio shares his Oura sleep data in chat
**Source:** Fabio tells Claudinho the values from the Oura app
**Method:** Supabase REST API (direct insert)

### Prompt:

```
When I share my sleep data from Oura, insert the following records into the `dashboard_records` table via the Supabase REST API. Each metric should be its own separate record.

Use these exact field values for each record:
- agent_id: "claudinho"
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

**Agent:** Claudinho
**Trigger:** Every time Fabio logs food in chat
**Source:** Conversation with Fabio (food logging)
**Method:** Supabase REST API (upsert — update if today's record exists, insert if first entry)

### Prompt:

```
When I tell you what I've eaten, upsert my daily calorie record in the `dashboard_records` table via the Supabase REST API.

Upsert (update if exists for today, insert if first entry):
- agent_id: "claudinho"
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

**Agent:** Claudinho
**Trigger:** Updated alongside calories when food is logged
**Source:** Conversation with Fabio (food logging)
**Method:** Supabase REST API (upsert alongside calories)

### Prompt:

```
When updating my daily calories, also upsert my macronutrient record in `dashboard_records` via the Supabase REST API.

Upsert for today's date:
- agent_id: "claudinho"
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

**Agent:** Claudinho
**Trigger:** When Fabio shares InBody results or manual measurements
**Source:** Conversation with Fabio
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

All records: agent_id "claudinho", category "health", type "measurement".
```

---

## 5. Delivery Tracking

**Agent:** Entregas
**Trigger:** When Fabio shares a tracking number or asks for delivery updates
**Source:** Tracking numbers from conversation
**Method:** Supabase REST API (insert new deliveries, update status on existing ones)

### Prompt:

```
When I share a tracking number or delivery update, insert or update records in `dashboard_records` via the Supabase REST API.

- agent_id: "entregas"
- user_id: (my user UUID)
- category: "deliveries"
- type: "delivery"
- display_hint: "status_list"
- title: "<item name or package description>"
- data: {
    "order_id": "<order_id or tracking_number>",
    "carrier": "<carrier name>",
    "tracking_number": "<full tracking number>",
    "status": "<one of: ordered, shipped, in_transit, out_for_delivery, delivered>",
    "eta": "<ISO8601 estimated delivery date or null>",
    "items": [{"name": "<item name>", "quantity": 1, "description": null}],
    "tracking_url": "<carrier tracking URL or null>"
  }

Update the status field as the package progresses. Use lowercase status values.
When a delivery is marked "delivered", keep the record for 7 days then let it expire.
```

---

## 6. Calendar Events

**Agent:** Calendario
**Trigger:** When Fabio asks to sync calendar events or mentions upcoming events
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

**Agent:** Claudinho (system task)
**Trigger:** When Fabio asks for a system status update, or periodically as part of a health check
**Method:** Supabase REST API (upsert status records)

### Prompt for Gateway Status:

```
Write a gateway status snapshot to `dashboard_records` via the Supabase REST API.

- agent_id: "claudinho"
- category: "admin"
- type: "status"
- display_hint: "single_value"
- title: "Gateway Status"
- data: {
    "is_running": true,
    "active_models": [
      {"model_id": "anthropic/claude-opus-4-6", "job_count": 3},
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

- agent_id: "claudinho"
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

These are the one-time SQL statements Fabio needs to run manually. Claudinho should generate these when setting up new table structures:

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
