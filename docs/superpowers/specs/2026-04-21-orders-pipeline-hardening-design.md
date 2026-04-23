# Orders/Deliveries Pipeline Hardening — Design

**Date:** 2026-04-21
**Status:** Approved in principle; proceeding to implementation.

## Context

The orders/deliveries pipeline is felt-unreliable. Ground-truth inventory: four parallel cron jobs and a 468-line TypeScript classifier that nobody calls.

| Job | Status | What it does |
|---|---|---|
| `orders-autopilot-fastmail-ingest` | ✅ (since yesterday) | Python script, stateless, content-based detection. Re-scans 72h window every 30min. |
| `orders-autopilot-17track-poll` | ❌ disabled | Would poll 17track for shipment statuses. Script the cron references doesn't exist on disk. |
| `delivery-tracker` (08:55 + 20:55) | ✅ | Reads SQLite (`~/.openclaw/data/deliveries.db`) → Supabase. Legacy. |
| `Nightly Delivery Tracker` (03:00) | ✅ | Agent-driven, opens browser tabs to scrape carrier pages. Fragile. |

Additionally discovered:
- **`listener.py`** (374 lines) already runs as a LaunchAgent, polling Fastmail JMAP `Email/changes` every 10s. Maintains JMAP state tokens. Currently **only drives Telegram notifications** — has dead `ALIAS_RULES.extract_tracking` config wired to nothing.
- **`skill/dashboard-sync/src/orders-autopilot.ts`** (468 lines) has a proper classifier (purchase_confirmation vs shipping_notification), per-email handling, review items for ambiguous cases, 17track integration — but **nothing calls it**.

## Goals

1. **Detection quality.** Replace content-keyword Python detection with the TS classifier that has proper purchase/shipping discrimination and merchant matching.
2. **Latency.** From "every 30min" to "≤20s" via the already-running JMAP listener.
3. **Status updates.** Re-enable shipment status polling. (17track token dependency deferred — user will drop key on return.)
4. **Single source of truth.** One state file, one canonical classifier, one write path.

## Non-Goals

- Rewriting the TS classifier. It's adequate.
- Killing the SQLite-based `delivery-tracker` / `Nightly Delivery Tracker`. Parked for the 10X pass — they may still be useful for manual entries.
- Fixing the unrelated `listener.py` Telegram-notification bug (template string in bot token reference). Note in wrap-up, don't fix.

## Architecture

```
             ┌─────────────────────────────────────────────────────────┐
             │  listener.py  (runs continuously, 10s poll)             │
             │                                                         │
             │    Fastmail JMAP ──► Email/changes ──► new emails       │
             │                                               │         │
             │                                               ▼         │
             │  ┌───────────────────────────────────────────────────┐ │
             │  │  For each new email:                              │ │
             │  │    1. existing Telegram notify logic (unchanged)  │ │
             │  │    2. NEW: feed to ingest processor (below)       │ │
             │  └───────────────────────────────────────────────────┘ │
             └─────────────────────────────────────────────────────────┘
                                    │
                                    │ spawn subprocess, fire-and-forget
                                    │ stdin = email JSON
                                    ▼
             ┌─────────────────────────────────────────────────────────┐
             │  node cli.js process-email                              │
             │    reads email JSON from stdin                          │
             │    calls processEmail() from orders-autopilot.ts        │
             │    writes result JSON to stdout                         │
             │    exit code reflects success/failure                   │
             └─────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                       ┌────────────────────────┐
                       │  TS classifier runs:   │
                       │    classify → extract  │
                       │    → upsert orders    │
                       │    → upsert shipments │
                       │    → derive status    │
                       │    → push to iOS      │
                       └────────────────────────┘

  CATCHUP SAFETY NET
  ──────────────────
  cron: orders-ingest-catchup (every 12h at 05:00 + 17:00)
    python orders_ingest_catchup.py
      fetches emails from last 24h via jmap_client.py
      for each not in state.processed_ids:
        spawn node cli.js process-email
        record result in state
      reports summary
```

## State file (single source of truth)

Location: `~/.openclaw/workspace/state/orders-ingest-state.json`

```json
{
  "version": 1,
  "processed": {
    "<jmap-email-id>": {
      "at": "2026-04-21T23:10:00Z",
      "type": "purchase_confirmation | shipping_notification | other",
      "action": "created_order | linked_shipment | created_review_item | skipped | error",
      "detail": "short description for debugging",
      "confidence": 0.87
    }
  },
  "lastCatchupAt": "2026-04-21T17:00:00Z"
}
```

- Keyed by JMAP email ID. Both listener and catchup check this before processing.
- Write is atomic (tmpfile + rename) so two writers don't corrupt.
- Entries don't expire automatically. State growth is bounded by real email volume (~20/day × 365 = 7k/year, trivial).

## Components to build

### 1. `skill/dashboard-sync/cli.js` — new `process-email` command

Reads one email JSON from stdin, calls `processEmail()`, writes result JSON to stdout. Exit 0 on `success: true`, exit 1 on `success: false`.

Input schema:
```json
{
  "id": "jmap-email-id",
  "subject": "…",
  "body": "…",
  "sender": "name <email>",
  "date": "2026-04-21T21:00:00Z"
}
```

### 2. `listener.py` — add ingest hook

Minimal additions to the main loop:
- After each `Email/get`, extract plaintext body (via an additional JMAP call: `bodyValues` + `textBody`). JMAP returns body structure separately from `preview`.
- For each new email, check state file. If already processed, skip.
- Spawn `node /path/to/cli.js process-email` subprocess. Feed email JSON on stdin. Don't block the polling loop — capture result async; log outcome.
- Update state file with the result.
- Errors in ingest MUST NOT break the listener. Log + continue.

### 3. `scripts/orders_ingest_catchup.py` — new Python catchup

Runs twice daily via cron. Fetches last 24h of email via existing `jmap_client.py`, filters out already-processed IDs from state, feeds the rest to the Node process-email command. Updates state with results.

### 4. Cron changes

- **Add:** `orders-ingest-catchup` → `0 5,17 * * *`, calls `bash ~/.openclaw/workspace/scripts/run_orders_ingest_catchup.sh`.
- **Disable (not delete):** `orders-autopilot-fastmail-ingest` (the current Python one, runs every 30min). Keep the cron record for a week as rollback.
- **Leave alone:** `orders-autopilot-17track-poll` (stays disabled), `delivery-tracker` (08:55 + 20:55), `Nightly Delivery Tracker` (03:00). Addressed in 10X pass.

### 5. 17track polling — preparation only

Cannot wire the poll without the API key. When the user returns and adds `SEVENTEEN_TRACK_API_KEY=…` to `~/.openclaw/secrets/perch.env`, the existing `pollShipments()` export in `orders-autopilot.ts` can be driven by a new CLI command `cli.js poll-shipments`. Ship the CLI command + cron entry (disabled) so it's one toggle for the user.

## Error handling

- **Listener ingest failure:** logged, state updated with `action: "error"`, detail = stderr. Listener continues polling.
- **JMAP state expired:** existing `fetch_changes` handles this; no change.
- **Classifier exception:** `processEmail()` already catches and returns `{ success: false, action: 'error' }`. Surfaces in state file.
- **State file corruption:** catchup script reseeds from "last 48h of email, classified" if file is unreadable. Tracked in wrap-up as a known recovery path.
- **Duplicate processing:** state file check prevents. If a race (listener + catchup run same email), the TS classifier's upserts are idempotent (ON CONFLICT on merchant+order_number, on tracking_number). No duplicates in DB.

## Testing plan

1. Unit: `cli.js process-email` with a known purchase-confirmation email → creates order in Supabase. Repeat with a shipping-notification → creates shipment. With a newsletter → `action: skipped`.
2. Manual: pick 5 recent order emails from Fastmail, feed each to `cli.js process-email`, compare the classifier's output to what the Python script did yesterday.
3. Integration: after listener.py changes, wait for one real shop email to arrive. Confirm: appears in state file, appears in Supabase `orders`, appears in iOS app.
4. Catchup: dry-run the catchup script. Confirm it finds only unprocessed emails.
5. Revert plan: if ingestion mis-behaves, re-enable the Python cron, the listener's ingest hook is safe to keep (double-write is idempotent).

## Migration / cut-over

1. Ship `cli.js process-email` (no behavior change yet).
2. Ship `orders_ingest_catchup.py` + its cron entry. Verify it processes correctly.
3. Modify `listener.py`. Restart the LaunchAgent. Verify.
4. Monitor for 24h. If stable, disable the old Python cron.
5. After 7 days of stability, delete the Python cron entirely.

## Rollback

Each change is independent:
- `cli.js process-email` — additive, no risk.
- Catchup cron — disable the entry.
- Listener change — revert the patch, restart daemon.
- Old Python cron — re-enable.

Worst case: disable listener ingest + re-enable old Python cron. Back to pre-session state in ~2 minutes.

## What's deferred to the 10X pass

- Retiring SQLite `delivery-tracker` + `Nightly Delivery Tracker` (or merging them with the email pipeline).
- Merchant-allowlist vs full-mailbox scan decision.
- iOS UX for review items (`review_item` records exist but the app has no UI for them).
- Batching / rate-limiting the listener → classifier pipeline during promo-email bursts.
- Carrier adapter expansion beyond 17track (DHL, CTT native APIs).
