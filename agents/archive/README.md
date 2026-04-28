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
