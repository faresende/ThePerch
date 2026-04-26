# Order Review Queue UI — Design

**Date:** 2026-04-24
**Status:** Spec only. Implementation deferred to a focused next session.
**Related work:**
- `2026-04-21-orders-pipeline-hardening-design.md` — the underlying autopilot pipeline.
- `supabase/migrations/20260424000000_learned_senders.sql` — the table this UI writes to.
- `skill/dashboard-sync/src/learned-senders.ts` — the read/write helpers the iOS layer will call indirectly through the autopilot.

## Context

The orders-autopilot now has three tiers of order detection:

1. **Tier 1 (keyword).** Hardcoded merchant list + weighted purchase / shipping keywords + folder hints (Paper Trail boost, Newsletters penalty) + subject-only fast-path. Fires for ~90% of confirmed merchants we've seen.
2. **Tier 2 (LLM).** Local Ollama (`qwen2.5:14b`) with Anthropic Haiku fallback. Fires when Tier 1 returns "other" with confidence ≥ 0.4, or when the merchant resolution falls back to the weak `domainStem` last-resort branch.
3. **Tier 3 (this doc).** A user-curated `learned_senders` table. The autopilot consults it BEFORE Tier 1; resolution writes to it. The iOS surface is the Order Review queue: the user sees ambiguous classifications and either confirms / corrects / dismisses them, and that resolution teaches the system.

Without Tier 3, every new merchant goes through the cold-start path: keyword/LLM, possibly wrong, sometimes silently dropped. With Tier 3, the second email from a merchant the user has ever resolved is trusted ground-truth.

## Goals

1. **Make review-queue resolution feel cheap.** A single tap should be the common case. Two taps if the user wants to fix the merchant name. The user should not feel like they're filling out a form.
2. **Resolutions teach the system.** Every "yes, this is X" writes to `learned_senders` so the next email from that sender is auto-classified.
3. **Recoverable.** Misclick → undo within ~10s. The user shouldn't be afraid to triage fast.
4. **Hidden but findable.** Lives under Settings, not on the main Hub. This is plumbing, not a daily surface — but it should be one tap from anywhere.

## Non-Goals

- **Bulk-edit / batch resolution.** Resolutions are individually consequential (each writes to `learned_senders`). The list view will show counts, but the resolution path is one-row-at-a-time.
- **Rich email rendering.** Subject + sender + first ~100 chars of body is enough to triage. Full email view is out of scope (user can open Fastmail directly via a deep link if they need it).
- **Editing already-resolved rows.** Once resolved, rows are immutable. The user can revoke a learned mapping from a separate "Taught Senders" sub-screen, which removes the `learned_senders` row but does not retroactively re-run classification.

## Information Architecture

```
Settings
└── Order Autopilot               (new section)
    ├── Order Review (N)          → ReviewQueueListView
    │   └── tap a row             → ReviewItemView
    └── Taught Senders (M)        → LearnedSendersListView
        └── tap a row             → revoke
```

`N` is the count of unresolved `review_items` for the current user. Hidden when `N == 0`. (Surfaced as a badge on the Settings tab when `N >= 5` — TBD with the existing badge convention; default off.)

`M` is the count of `learned_senders` rows. The list is informational; the only action is "revoke this mapping."

### Why under Settings (not the Hub)

The Hub is for things the user actively engages with daily. Review-queue triage is a once-in-a-while housekeeping action — usually the day after a shopping run. Surfacing it on the Hub would either feel naggy when there's nothing to review, or get ignored when there is. Settings is the right home for plumbing the user occasionally services.

## Screens

### A. ReviewQueueListView

**Purpose:** show every unresolved `review_items` row, sorted by `created_at DESC`.

**Row layout** (one per `review_items` row):

```
┌─────────────────────────────────────────────────────────┐
│  [icon]  ⚡ Vulkit                     2d ago           │   ← kicker line
│          "Order #108984 confirmed"                      │   ← subject (1 line, truncated)
│          ⚠ Ambiguous classification — review            │   ← reason (1 line)
└─────────────────────────────────────────────────────────┘
```

- `[icon]` — color-coded by `type`:
  - `other` (Tier 2 ambiguous) → ⚪️ gray dot
  - `orphan_shipment` / `shipment_no_order` → 📦 amber
  - `duplicate_order` → 🔁 amber
  - `low_confidence_match` → ⚠️ amber
- `kicker` — best-guess merchant name (whatever the autopilot recorded). When the autopilot couldn't infer one, show the sender domain stem.
- `subject` — `review_items.reason` already embeds the email subject when relevant; for the list row we want the original email subject, not the reason. **TODO during implementation:** the autopilot currently embeds the subject in `reason`. We should denormalize the subject onto a column or extend the JSON `data` payload — see "Schema notes" below.
- `reason` — `review_items.reason` truncated to one line.
- `time` — relative formatting (`12m ago`, `2h ago`, `2d ago`).

**Empty state:** "No items to review. ✨" — the celebratory tone is intentional. An empty queue is a healthy queue.

**Top-right action:** "Sweep" button — opens `ReviewItemView` for the first row, then auto-advances to the next row on each resolution. Triage flow.

### B. ReviewItemView

**Purpose:** present one row at a time with the smallest possible decision surface.

```
┌─────────────────────────────────────────────────────────┐
│  ←  Review                                  1 of 6      │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ⚡ From  Body&Fit Customer Service                      │
│         <noreply@bodyandfit.com>                        │
│                                                         │
│  Subject  Your Body&Fit order is confirmed!             │
│                                                         │
│  Date     2 days ago                                    │
│                                                         │
│  ─── snippet ────────────────────────────               │
│  Hi Fábio, thanks for your order BF1429199. │
│  Total: €45.20. We'll let you know when it ships.       │
│  ─────────────────────────────────────────              │
│                                                         │
│  Suggested action                                       │
│  ┌────────────────────────────────────────────────┐    │
│  │  Merchant   [ Body&Fit            ]  edit      │    │
│  │  Order #    [ BF1429199           ]  edit      │    │
│  │  Total      [ €45.20              ]  edit      │    │
│  └────────────────────────────────────────────────┘    │
│                                                         │
│   ┌──────────────────────┐  ┌──────────────────────┐   │
│   │   Confirm & Teach    │  │      Not an order    │   │
│   └──────────────────────┘  └──────────────────────┘   │
│                                                         │
│              ▸ Open in Fastmail                         │
└─────────────────────────────────────────────────────────┘
```

#### Editable fields

The card pre-fills the fields the autopilot already extracted (or attempted to). The user taps "edit" to change any of them.

| Field | Source | Required | Notes |
|---|---|---|---|
| Merchant | `review_items.data.suggested_merchant` (autopilot fills) or sender domain | yes | Free text. On save, this is what gets written to `learned_senders.merchant_name`. |
| Order # | `review_items.data.suggested_order_number` (autopilot fills, may be null) | no | Free text. Saved to `orders.order_number`. |
| Total | `review_items.data.suggested_total_amount` + `currency` | no | Numeric input + 3-letter currency picker. Saved to `orders.total_amount` / `orders.currency`. |

The "edit" affordance is inline (tap-to-edit, no modal). Standard iOS form-edit patterns.

#### Primary action: "Confirm & Teach"

On tap:

1. Calls `resolveReviewWithLearnedSender({ userId, reviewItemId, senderEmail, merchantName })` (already exposed from `orders-autopilot.ts`). This:
   - upserts a `learned_senders` row,
   - sets `review_items.resolved_at = now()`.
2. Calls `upsertOrder` with the user-confirmed `merchant_name` / `order_number` / `total_amount` / `currency` / `source_email_ids: [originalEmailId]` / `confidence_score: 1.0` / `status: 'ordered'`.
3. Shows a 4-second toast at the bottom: **"✓ Body&Fit learned. Undo"**
4. Auto-advances to the next row (Sweep mode) or returns to the list view.

The undo toast is critical — it's the safety net for the one-tap path.

#### Secondary action: "Not an order"

On tap:

1. Resolves the `review_items` row WITHOUT writing a `learned_senders` mapping (we don't want to teach "this merchant is junk" — that's what the user's mail-rules layer is for). Calls `resolveReviewItem(reviewItemId)`.
2. Optionally writes a `learned_senders` row with a special sentinel `merchant_name` like `__not_a_purchase__` to suppress future review-queue entries from this sender. **Decision deferred** — the simplest first cut is "no learned write-back; the row will re-queue if the same sender sends another email matching the same heuristics, but that's tolerable for the first pass." Revisit if the user reports "the same junk keeps coming back."
3. Toast: "✓ Dismissed. Undo"
4. Auto-advances.

#### "Open in Fastmail"

Deep-link to the Fastmail web view of the original email, scoped to the message ID. (Fastmail's URL scheme: `https://app.fastmail.com/mail/Inbox/.{thread_id}`.) Falls back to the inbox root if we don't have a stable link. This is an escape hatch when the snippet isn't enough — out of the common path.

### C. Undo

The toast hosts a 10-second undo window:

- **For "Confirm & Teach":** undo deletes the `learned_senders` row and resets `review_items.resolved_at` to NULL. The newly-created `orders` row stays — undoing the order is a separate action ("Mark as not delivered" already exists). Rationale: the cost of an extra row in `orders` is tiny vs the cost of leaving a wrong learned mapping in place.
- **For "Not an order":** undo just resets `review_items.resolved_at` to NULL.

After 10s the toast dismisses and the action is permanent. (User can still revoke from "Taught Senders" later — undo is just the immediate-recovery hatch.)

### D. LearnedSendersListView

**Purpose:** show every `learned_senders` row, sorted by `updated_at DESC`. Read-mostly.

```
┌─────────────────────────────────────────────────────────┐
│  ⚡ Body&Fit                                            │
│     noreply@bodyandfit.com  •  taught 12d ago           │
└─────────────────────────────────────────────────────────┘
```

Tap → revoke confirmation:

> "Revoke the Body&Fit mapping?
> Future emails from noreply@bodyandfit.com will go through normal classification again. Existing orders are unaffected."
>
> [Revoke]   [Cancel]

On confirm: deletes the `learned_senders` row.

**Empty state:** "No taught mappings yet. As you resolve review items, they'll show up here."

## Data Flow

```
            ┌────────────────────────────────────────────────┐
            │  orders-autopilot.processEmail (TS)           │
            │                                                │
            │  1. lookupLearnedSender(user, sender)         │
            │  2. classifyEmail(...)                        │
            │  3. extractOrderFields(... learnedMerchant)   │
            │  4. if (ambiguous) createReviewItem(...)      │
            └────────────────────────────────────────────────┘
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │  Supabase                            │
         │  • orders                            │
         │  • shipments                         │
         │  • review_items   ◀──── unresolved   │
         │  • learned_senders  ◀──── teaches    │
         └──────────────────────────────────────┘
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │  iOS app                             │
         │                                      │
         │  Settings → Order Autopilot          │
         │   • Order Review (N)                 │
         │      tap row → resolve →             │
         │       resolveReviewWithLearnedSender │
         │   • Taught Senders (M)               │
         │      revoke → DELETE learned_sender  │
         └──────────────────────────────────────┘
```

## Schema notes (small follow-ups)

The current `review_items` schema doesn't carry the original email subject or the autopilot's pre-resolved suggested fields cleanly — they're stuffed into the `reason` text field. For the UI to render the row layout above without re-parsing strings, we want a small migration:

```sql
ALTER TABLE public.review_items
  ADD COLUMN IF NOT EXISTS source_email_id  text,
  ADD COLUMN IF NOT EXISTS source_subject   text,
  ADD COLUMN IF NOT EXISTS source_sender    text,
  ADD COLUMN IF NOT EXISTS data             jsonb DEFAULT '{}'::jsonb;
```

`data` carries the autopilot's `{ suggested_merchant, suggested_order_number, suggested_total_amount, suggested_currency }` so the UI can pre-fill the form without guessing. This migration is included in the implementation session, not now.

## iOS implementation notes

- **Architecture.** Mirror the existing pattern: a `ReviewQueueViewModel` (ObservableObject) owns the Supabase fetch + write paths; the views are thin SwiftUI wrappers.
- **Fetch strategy.** Pull on view appear + on app foregrounding. No realtime subscription for v1 — review-queue items are not time-sensitive.
- **Auth.** Reuse the existing Supabase client with the user's JWT. Writes hit RLS-protected tables; the migration above already grants `INSERT` / `UPDATE` for `auth.uid() = user_id`.
- **Networking.** Each "Confirm & Teach" tap is two writes (`learned_senders` + `orders`) plus a `review_items` update. Wrap in a `withTaskCancellationHandler` so undo can race the write if the user is fast.
- **Animation.** Row-out animation on resolve (slide left + fade) sells the "this is gone now" feeling without being slow. Auto-advance happens after the animation completes (~250ms).
- **Typography.** Reuse `PerchNum` / kicker styles from `OrderCardV2`. Don't introduce new type tokens.

## Implementation order (sketch for the next session)

1. Schema migration: extend `review_items` with `source_email_id` / `source_subject` / `source_sender` / `data` columns. Backfill is optional — old rows just won't pre-fill nicely.
2. Update `orders-autopilot.ts` to populate the new `review_items` columns whenever it creates a review item.
3. Build `ReviewQueueViewModel` + the three views (List, Item, LearnedSenders).
4. Wire the "Order Autopilot" entry into `SettingsView`.
5. End-to-end test: trigger an ambiguous email manually, watch it land in the queue, resolve it, verify `learned_senders` row exists, re-trigger the same sender → no review item.

## Open questions / deferred decisions

1. **"Not an order" suppression.** Should resolving as "not an order" write a sentinel `learned_senders` row to suppress re-queueing? Default: no for v1. Revisit if the same junk re-queues.
2. **Settings badge.** Should the Settings tab show a count badge when `N >= 5`? Default: no for v1 — the user finds it manually. Revisit if the queue grows faster than the user remembers to clear it.
3. **Multi-user.** The current single-user deployment uses `PERCH_USER_ID` everywhere. Multi-tenant is out of scope; the schema already supports it via `user_id` + RLS.
4. **Order-row creation on resolve — full or partial?** When the user confirms with no order_number, should we still create the orders row? Default: yes. Better to have an order with a missing order_number than to drop the merchant entirely; the next email (shipping confirmation) will often fill in the gap.
