# perch-orders TODO

## Phase 1.5 — Generalize orders autopilot

Migrate `scripts/orders_autopilot_ingest_fastmail.py` (at the repo root) into `skill/perch-orders/scripts/ingest.py` with the following changes. None of this should happen during infrastructure cleanup; it's a dedicated pass.

1. **`agent_id`:** replace the hardcoded `'claudinho'` with `PERCH_AGENT_ID` env var, defaulting to `orders-autopilot`.
2. **JMAP client:** drop the `sys.path` hack that imports from `<YOUR_OPENCLAW_WORKSPACE>/sandbox/fastmail-jmap/jmap_client`. Swap to the [`jmapc`](https://pypi.org/project/jmapc/) PyPI package. Add `jmapc` to a `requirements.txt` next to the script.
3. **Fastmail token:** expose via env var. Recommended name: `FASTMAIL_JMAP_TOKEN` (or provider-neutral `PERCH_JMAP_TOKEN`).
4. **Mailbox IDs:** replace the hardcoded `['P7V', 'P-F']` with `PERCH_JMAP_MAILBOX_IDS` env var, CSV. Document how to discover mailbox IDs in the README (one paragraph is enough; a JMAP `Mailbox/get` call with the account ID does it).
5. **`EXCLUDE_SENDERS` and carrier list:** leave hardcoded as sensible defaults. Call out in `skill/perch-orders/scripts/README.md` that they're fork-to-taste. No env var needed; editing Python is fair game for a reference script.
6. **Add `--help` / argparse.** Current `sys.argv` parsing is janky for public consumption.
7. **Update the cron entry** (see Phase 1 task #3) to point at the new path after this lands.
8. **Breadcrumb file:** after the move, leave a one-line `scripts/README.md` at the repo root pointing at the new location. Anyone used to the old path should find the new one in one click.

### Followups flagged during Phase 1 audit, not blockers

- Two `except: pass` blocks in `upsert_delivery_record` and the existing-record lookup. Reference scripts should at least `log.debug(...)` on swallowed exceptions.
- The script is ~464 lines and grew organically. Light refactor (pulling carrier detection out of `extract_tracking_number` into its own helper, folding `ORDER_SUBJECT_PATTERNS` + `STRONG_ORDER_SIGNALS` + `WEAK_ORDER_SIGNALS` into a single module-level table with tiers) would make the detection logic easier to audit. Nice to have.

### Out of scope for Phase 1.5

- Rewriting detection heuristics.
- Adding non-English languages beyond the existing EN/PT/NL/DE.
- Moving `scripts/` as a whole to per-skill homes for the rest of whatever shows up later. Evaluate case by case.
