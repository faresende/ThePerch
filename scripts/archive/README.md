# Archived scripts

These scripts are retained for reference but are no longer part of any live
pipeline. The current orders pipeline runs through the jmap-listener →
`skill/dashboard-sync/cli.js process-email` path (with the 12h catchup
cron as a safety net). See the pipeline hardening spec under
`docs/superpowers/specs/2026-04-21-orders-pipeline-hardening-design.md`
for the full migration story.

## Contents

| File | Retired | Replaced by |
|---|---|---|
| `orders_autopilot_ingest_fastmail.py` | 2026-04-23 | Listener (`sandbox/fastmail-jmap/orders_ingest_hook.py`) + `scripts/orders_ingest_catchup.py` |

Restore with `git mv` if you ever need the old behavior back.
