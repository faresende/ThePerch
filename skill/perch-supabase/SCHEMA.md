# SCHEMA.md - The Perch Supabase Schema

## Tables

### `sections`

Controls which tabs appear in the app and their display order.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `uuid_generate_v4()` | Primary key |
| `user_id` | UUID | NO | — | References `auth.users(id)`, cascade delete |
| `slug` | TEXT | NO | — | URL-safe identifier (e.g., `home`, `health`) |
| `display_name` | TEXT | NO | — | Human-readable tab name |
| `sort_order` | INTEGER | NO | `0` | Tab display order (ascending) |
| `is_visible` | BOOLEAN | NO | `true` | Whether tab is shown |
| `config` | JSONB | YES | — | Optional section configuration |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NO | `now()` | Last update timestamp (auto-updated) |

**Indexes**: `sections_user_id_idx` (user_id), `sections_user_slug_idx` UNIQUE (user_id, slug)

**Default sections** (seeded by `provision_new_user()`):
`home` (0), `health` (1), `workouts` (2), `deliveries` (3), `calendar` (4), `travel` (5, hidden), `bookmarks` (6, hidden), `admin` (7, hidden), `legal` (8, hidden)

---

### `dashboard_records`

Core data table. All agent-written data lives here. This is the primary table used by the iOS app to display cards.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `uuid_generate_v4()` | Primary key |
| `user_id` | UUID | NO | — | References `auth.users(id)`, cascade delete |
| `agent_id` | TEXT | NO | — | Agent that created the record. Seed migration ships these IDs: `main`, `biochecha` (health), `calendario` (calendar), `entregas` (orders), `legal`. |
| `type` | TEXT | NO | — | Record type: `measurement`, `delivery`, `event`, `status`, `reminder`, `text_note`, `checklist`, `cost_summary`, `bookmark`, `order`, `shipment`, `meal` |
| `category` | TEXT | NO | — | Logical category: `health`, `deliveries`, `calendar`, `admin`, `legal`, `nutrition`, `workouts`, `bookmarks`, `commerce` |
| `title` | TEXT | NO | `''` | Human-readable title |
| `data` | JSONB | NO | `'{}'` | Type-specific payload (structure varies by type) |
| `display_hint` | TEXT | NO | `'single_value'` | UI rendering hint |
| `annotations` | JSONB | YES | — | Metadata for filtering/sorting |
| `pinned` | BOOLEAN | NO | `false` | If true, prioritized in dashboard UI |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NO | `now()` | Last update (auto-updated via trigger) |
| `expires_at` | TIMESTAMPTZ | YES | — | Auto-delete timestamp (app-level enforcement) |

**Indexes**: `dashboard_records_user_id_idx`, `dashboard_records_type_idx`, `dashboard_records_category_idx`, `dashboard_records_created_at_idx` (desc)

**Data payload examples**:
- **measurement**: `{ value: 82.5, unit: "kg", notes: "Morning weigh-in" }`
- **delivery**: `{ carrier: "DHL", tracking_number: "1234567890", status: "in_transit" }`
- **event**: `{ start_time: "2026-04-20T09:00:00+01:00", end_time: "2026-04-20T10:00:00+01:00", location: "Lisbon" }`
- **checklist**: `{ items: [{ text: "Pack passport", completed: false }], progress: 0.5 }`
- **bookmark**: `{ url: "https://...", tags: ["swiftui"], status: "processed" }`

---

### `orders`

Commerce order tracking. Created by the orders autopilot pipeline from email ingestion.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `uuid_generate_v4()` | Primary key |
| `user_id` | UUID | NO | — | References `auth.users(id)`, cascade delete |
| `merchant` | TEXT | NO | — | Raw merchant identifier |
| `merchant_name` | TEXT | NO | — | Display name for the merchant |
| `normalized_merchant` | TEXT | YES | — | Lowercase, stripped merchant name for matching |
| `order_number` | TEXT | YES | — | Order number from the email |
| `total_amount` | DECIMAL | YES | — | Order total |
| `currency` | TEXT | YES | `'EUR'` | Currency code |
| `status` | TEXT | NO | `'ordered'` | Status: `ordered`, `processing`, `shipped`, `shipped_partial`, `out_for_delivery`, `in_transit`, `delivered`, `cancelled`, `issue` |
| `source_email_ids` | TEXT[] | YES | — | JMAP email IDs that contributed to this order |
| `source_email_id` | TEXT | YES | — | Primary source email ID (legacy) |
| `confidence_score` | DOUBLE | YES | — | 0-1 confidence from email classification |
| `manual_delivered_at` | TIMESTAMPTZ | YES | — | User-set delivery timestamp (overrides automated status) |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NO | `now()` | Last update |

---

### `shipments`

Package tracking records. Linked to orders via `order_id`.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | `uuid_generate_v4()` | Primary key |
| `order_id` | UUID | NO | — | References `orders(id)` |
| `user_id` | UUID | NO | — | References `auth.users(id)` |
| `tracking_number` | TEXT | NO | — | Carrier tracking number |
| `carrier` | TEXT | YES | — | Carrier name (DHL, UPS, FedEx, etc.) |
| `tracking_url` | TEXT | YES | — | Direct tracking URL |
| `status` | TEXT | NO | — | Status: `label_created`, `in_transit`, `out_for_delivery`, `delivered`, `exception` |
| `latest_checkpoint` | TEXT | YES | — | Last known location/event |
| `seventeen_track_id` | TEXT | YES | — | 17track.net registration ID |
| `shipped_at` | TIMESTAMPTZ | YES | — | When shipment was dispatched |
| `delivered_at` | TIMESTAMPTZ | YES | — | When shipment was delivered |
| `source_email_ids` | TEXT[] | YES | — | Source email IDs |
| `confidence_score` | DOUBLE | YES | — | Match confidence |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Creation timestamp |

---

### `profiles`

User profiles. Auto-created on signup via trigger.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | UUID | NO | — | Primary key, references `auth.users(id)` |
| `display_name` | TEXT | YES | — | User's display name |
| `tier` | TEXT | NO | `'free'` | Subscription tier: `free`, `pro`, `team` |
| `created_at` | TIMESTAMPTZ | NO | `now()` | Creation timestamp |
| `updated_at` | TIMESTAMPTZ | NO | `now()` | Last update |

---

### Views

#### `user_usage`

Aggregated usage metrics per user for rate limiting.

| Column | Type | Description |
|--------|------|-------------|
| `user_id` | UUID | User ID |
| `total_records` | BIGINT | Total records ever created |
| `records_today` | BIGINT | Records created in last 24 hours |
| `records_this_month` | BIGINT | Records created in last 30 days |
| `last_record_at` | TIMESTAMPTZ | Timestamp of most recent record |

---

## RLS Policies

All user-scoped tables have four RLS policies:

```sql
-- Example for dashboard_records:
ALTER TABLE public.dashboard_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read their own records"
  ON public.dashboard_records FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own records"
  ON public.dashboard_records FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own records"
  ON public.dashboard_records FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own records"
  ON public.dashboard_records FOR DELETE
  USING (auth.uid() = user_id);
```

**Service role bypass**: Connections using the service role key bypass all RLS. This is how agents write data on behalf of users.

## Helper Functions

### `set_updated_at()`

Trigger function that auto-updates `updated_at` on row modification. Applied to all tables with `updated_at` columns.

### `handle_new_user()`

Trigger on `auth.users` that auto-creates a `profiles` row on signup.

### `provision_new_user(p_user_id UUID)`

Seeds default sections for a new user. Called from server-side after signup.
