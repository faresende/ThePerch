---
name: perch-supabase
description: "Supabase backend schema, RLS policies, authentication, and service role setup for The Perch iOS app."
version: 1.0.0
---

# perch-supabase

## Trigger

Any task that reads from, writes to, or modifies the Supabase backend for The Perch. This includes queries, migrations, schema changes, RLS policy updates, and debugging data issues. Always read this skill first when working with any Perch data pipeline.

## What it does

The Supabase backend is the single source of truth for all data displayed in The Perch iOS app. It holds user records, orders, shipments, sections, agent health, and token usage. All agent-written data flows through here, and the iOS app reads from it in real time.

Each install runs against a single Supabase project. Agents write data using the service role key (server-side only), which bypasses Row Level Security (RLS). The iOS app reads data using the anon key with user-scoped RLS policies so each signed-in user only sees their own rows.

## Architecture

```
Agents (OpenClaw)                      iOS App
     │                                    │
     │  service_role key                  │  anon key + user auth
     │  (bypasses RLS)                    │  (RLS filters by user_id)
     ▼                                    ▼
┌──────────────────────────────────────────────┐
│              Supabase Postgres               │
│                                              │
│  tables:                                     │
│    dashboard_records  (agent-written data)   │
│    records            (agent-written data)   │
│    orders             (commerce tracking)    │
│    shipments          (package tracking)     │
│    sections           (tab configuration)    │
│    profiles           (user profiles)        │
│    agents             (agent health status)  │
│    token_usage        (cost tracking)        │
│                                              │
│  RLS:                                        │
│    Users see only their own rows             │
│    Service role bypasses all RLS             │
└──────────────────────────────────────────────┘
```

### Authentication

- **Service role key**: Used by agents (dashboard-sync, orders autopilot, etc.). Stored in environment variable `SUPABASE_SERVICE_ROLE_KEY`. Bypasses all RLS policies.
- **Anon key**: Used by the iOS app. RLS policies enforce `auth.uid() = user_id` filtering.
- **User auth**: Supabase Auth with email/password. On signup, a trigger auto-creates a `profiles` row and calls `provision_new_user()` to seed default sections.

### RLS Policies

All tables with `user_id` have RLS enabled with four policies per table:
- SELECT: `auth.uid() = user_id`
- INSERT: `auth.uid() = user_id` (with check)
- UPDATE: `auth.uid() = user_id`
- DELETE: `auth.uid() = user_id`

Service role connections bypass RLS entirely. This is intentional: agents write data on behalf of users.

## Data Schema

See [SCHEMA.md](./SCHEMA.md) for complete table definitions.

### Key Tables

| Table | Purpose | Primary Key | User-scoped |
|-------|---------|-------------|-------------|
| `dashboard_records` | Agent-written dashboard data | `id` (UUID) | Yes (`user_id`) |
| `records` | Agent-written structured data | `id` (UUID) | Yes (`user_id`) |
| `orders` | Commerce orders | `id` (UUID) | Yes (`user_id`) |
| `shipments` | Package tracking | `id` (UUID) | Yes (`user_id`) |
| `sections` | App tab configuration | `id` (UUID) | Yes (`user_id`) |
| `profiles` | User profiles | `id` (references auth.users) | Yes |

### Record Categories

The `RecordCategory` enum constrains the `category` field on records:
`health`, `nutrition`, `workouts`, `deliveries`, `calendar`, `admin`, `legal`, `bookmarks`, `travel`

### Display Hints

The `display_hint` field tells the iOS app how to render a record:
`chart`, `single_value`, `status_list`, `timeline`, `checklist`, `cost_breakdown`, `bookmark_card`, `bookmark_grid`, `progress_gauge`, `macros_bar`, `calendar_event`, `meal_log`, `order_card`, `shipment_timeline`

## Setup

### Environment Variables

```bash
SUPABASE_URL=https://<YOUR-PROJECT-REF>.supabase.co
SUPABASE_SERVICE_ROLE_KEY=<service-role-key>  # For agent writes
SUPABASE_ANON_KEY=<anon-key>                  # For iOS app reads
```

### Running Migrations

```bash
# Apply migrations in order. Two root-level files first, then the
# timestamp-ordered files under supabase/migrations/.
psql $DATABASE_URL -f supabase/001_initial_schema.sql
psql $DATABASE_URL -f supabase/002_seed_demo.sql        # seed agents (edit user UUID first)
for f in supabase/migrations/*.sql; do
  psql $DATABASE_URL -f "$f"
done
```

> The previous `backend/migrations/*.sql` and `backend/seed/*.sql` paths
> have been retired — see `docs/archive/backend-old/` for the historical
> snapshot. The canonical schema now lives entirely under `supabase/`.

### Example Queries

#### Query records (curl)
```bash
curl -G "https://<YOUR-PROJECT-REF>.supabase.co/rest/v1/dashboard_records" \
  -H "apikey: $SUPABASE_ANON_KEY" \
  -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  --data-urlencode "category=eq.health" \
  --data-urlencode "order=created_at.desc" \
  --data-urlencode "limit=10"
```

#### Insert record (curl with service role)
```bash
curl -X POST "https://<YOUR-PROJECT-REF>.supabase.co/rest/v1/dashboard_records" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d '{
    "user_id": "<YOUR_USER_UUID>",
    "agent_id": "claudinho",
    "type": "measurement",
    "category": "health",
    "title": "Morning Weight",
    "data": {"value": 82.5, "unit": "kg"},
    "display_hint": "single_value"
  }'
```

#### Query records (Python)
```python
import requests

BASE = "https://<YOUR-PROJECT-REF>.supabase.co/rest/v1"
HEADERS = {
    "apikey": SUPABASE_KEY,
    "Authorization": f"Bearer {SUPABASE_KEY}",
    "Content-Type": "application/json",
}

resp = requests.get(
    f"{BASE}/dashboard_records",
    params={"category": "eq.health", "order": "created_at.desc", "limit": 10},
    headers=HEADERS,
)
records = resp.json()
```

#### Query records (TypeScript via dashboard-sync)
```typescript
import { supabase } from './supabase';

const { data, error } = await supabase
  .from('dashboard_records')
  .select('*')
  .eq('category', 'health')
  .order('created_at', { ascending: false })
  .limit(10);
```

### How to Add a New Table

1. Create a migration file: `supabase/migrations/<timestamp>_your_table.sql` (filename timestamps sort lexicographically, so just keep using the existing `YYYYMMDDHHMMSS_…` pattern)
2. Define the table with `user_id uuid not null references auth.users(id) on delete cascade`
3. Add appropriate indexes (at minimum on `user_id`)
4. Enable RLS: `alter table public.your_table enable row level security;`
5. Add the four RLS policies (select, insert, update, delete) with `auth.uid() = user_id`
6. Add the `set_updated_at` trigger if the table has an `updated_at` column
7. Update this SKILL.md and SCHEMA.md with the new table

## Maintenance

### Debugging Data Issues

```bash
# Check recent records for a user
curl -G "$BASE/dashboard_records" \
  -H "apikey: $KEY" \
  --data-urlencode "user_id=eq.<YOUR_USER_UUID>" \
  --data-urlencode "order=created_at.desc" \
  --data-urlencode "limit=5"

# Check if RLS is blocking reads (use anon key)
# If you get empty results with anon but data with service role, RLS is filtering correctly
```

### Monitoring

- **Connection health**: `dashboard-sync` skill has a `verifyConnection()` function
- **Agent heartbeat**: Use the `dashboard_heartbeat` tool to check agent status
- **Usage limits**: Query the `user_usage` view for record counts per user

### Common Issues

- **Empty results in iOS app**: Usually RLS is correctly filtering. Verify the user is authenticated and their `auth.uid()` matches the `user_id` on the records.
- **Agent can't write data**: Check that `SUPABASE_SERVICE_ROLE_KEY` is set correctly in the agent's environment.
- **Stale data**: The `updated_at` trigger auto-updates on row change. If data seems stale, check the agent pipeline rather than the database.
