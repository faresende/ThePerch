# Archived agents

One-shot scripts that have already done their job. Kept here for
reference and re-run if you ever set up The Perch on a fresh
backend that needs the same backfill.

## What's here

- **`backfill_eta_register.js`** — re-registers every undelivered
  shipment with 17track. Useful right after a fresh install where
  shipments exist in your DB (e.g. from a Supabase import) but
  haven't been registered with 17track yet.

- **`backfill_eta_emails.js`** — fetches the source carrier emails
  for every undelivered shipment via JMAP (Fastmail), runs them
  through `extract-eta`, and writes any ETAs found via the same
  resolver the live scanner uses. Macsophy quirk: reads JMAP token
  from macOS Keychain (`security find-generic-password -a
  'fastmail-jmap' -s 'fastmail-jmap-token' -w`), so it only runs on
  macOS without env-override.

- **`seed-demo-data.js`** — helper for swapping real data with
  screenshot-friendly demo data (and back). `seed` now
  auto-snapshots first, so you can't accidentally lose data:

  ```bash
  set -a && source ~/.openclaw/secrets/perch.env && set +a
  node agents/archive/seed-demo-data.js seed       # auto-snapshots, then replaces with demo
  # take screenshots
  node agents/archive/seed-demo-data.js restore    # put real data back
  ```

  `snapshot` is still available as a manual command if you want
  belt-and-suspenders before running anything.

  Snapshot file is `.demo-snapshot.json` (gitignored). Touches:
  orders, shipments, order_items, health_metrics, insights,
  order_corrections, plus the **nutrition slice** of
  dashboard_records. Other tables (bookmarks, calendar agent-fed
  records, workouts, travel) left alone.

  **Calendar entries on the iOS Today tab come from EventKit, not
  Supabase.** This script can't touch them. For clean screenshots,
  temporarily revoke calendar permission in iOS Settings → The
  Perch → Calendars before capturing.

  ### A note on the recovery sequence

  If you've extended the `TABLES` list (added a new table the
  script should snapshot/restore), don't run `restore` first
  with an OLD snapshot. The wipe in `restore` clears the new
  table's data, but the old snapshot has nothing to put back.
  Always re-snapshot before running anything destructive after
  a TABLES extension. The auto-snapshot in `seed` handles this
  for you in normal use.

## Running

Both scripts assume `~/.openclaw/secrets/perch.env` is sourced
(or env vars are otherwise present): `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`, `SEVENTEEN_TRACK_API_KEY`. They also
assume the `dashboard-sync` skill is installed at
`~/.openclaw/skills/dashboard-sync` — override with `SKILL_PATH=...`
if your layout differs.

```bash
set -a && source ~/.openclaw/secrets/perch.env && set +a
node agents/archive/backfill_eta_register.js
node agents/archive/backfill_eta_emails.js
```

You probably won't need either of these. They're here so the
operation is reproducible, not because the day-to-day pipeline
relies on them.
