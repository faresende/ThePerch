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
| `dashboard_records` | Generic dashboard/app card feed for measurements, meals, events, bookmarks, status, and similar content |
| `orders` | Canonical order-level model for tracked deliveries |
| `shipments` | Canonical shipment/tracking model for tracked deliveries |
| `records` | Legacy pre-`dashboard_records` table; do not use for new features |
| `sections` | Tab / section configuration |

Agents write generic dashboard content to `dashboard_records` using the **service_role key** (bypasses RLS). For tracked packages shown in the current Hub > Orders surface, agents should write to `orders` + `shipments`.
