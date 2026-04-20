# Personal Data Migrations

The files here are **NOT** part of the shared migration sequence. They were one-off SQL scripts applied to a specific user's Supabase project to fix or seed personal data.

If you are setting up The Perch fresh, you do not need to run any of these. They are idempotent no-ops against an empty database, but they reference a specific user UUID that will not exist in your setup.

They are kept here for historical reference only.

## Contents

| File | What it did |
|---|---|
| `20260415000000_backfill_order_ownership.sql` | Backfilled ownership of pre-auth order rows to a specific user UUID |
| `20260416141633_manual_ups_tracking_entry.sql` | Manually inserted one UPS tracking order + shipment for a specific user |

## If you want to write something similar

Copy one of these as a template, wrap it in `DO $$ ... END $$` with a guard like:

```sql
IF EXISTS (SELECT 1 FROM auth.users WHERE id = '<YOUR_USER_UUID>'::uuid) THEN
  -- your data mutations
END IF;
```

Then run it once against your own database via the Supabase SQL Editor. Do not place it in `supabase/migrations/` — migrations are for schema, not personal data.
