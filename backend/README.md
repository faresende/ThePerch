# ThePerch Backend

Self-hosted backend setup for ThePerch. Uses [Supabase](https://supabase.com).

## Prerequisites

- A [Supabase](https://supabase.com) project (free tier works)

## Setup

### 1. Run the migrations

In the Supabase dashboard, open **SQL Editor** and run the migrations in order:

1. `migrations/001_initial_schema.sql` — creates tables and indexes
2. `migrations/002_rls_policies.sql` — enables Row Level Security

### 2. Seed default sections

Edit `seed/demo_sections.sql` and replace `<YOUR_USER_UUID>` with your Supabase auth user UUID (found in **Authentication > Users**). Then run it in the SQL Editor.

### 3. Get your credentials

In the Supabase dashboard, go to **Settings > API**:
- **Project URL** — looks like `https://yourproject.supabase.co`
- **Anon Key** — the `anon` / `public` key (safe to use in the app)

### 4. Connect the iOS app

Launch ThePerch on first install. You'll see the onboarding screen. Enter your **Project URL** and **Anon Key**. The app will test the connection and save credentials securely in the system Keychain.

## Architecture

| Table | Purpose |
|-------|---------|
| `sections` | Tab configuration (which tabs appear, their order and visibility) |
| `dashboard_records` | All data displayed in the app (health metrics, deliveries, events, workouts, etc.) |

Agents write to `dashboard_records` using the **service_role key** (bypasses RLS). The iOS app reads using the **anon key** (respects RLS — users only see their own data).
