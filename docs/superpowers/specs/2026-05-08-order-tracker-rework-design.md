# Order Tracker Rework — "Where's My Stuff" — Design

**Status:** Approved design, pre-implementation
**Date:** 2026-05-08
**Goal:** Turn the order tracker from ignored noise into a reliable "where's my stuff" surface — only physical packages in motion, no duplicates, no digital clutter, accurate ETAs, and a self-extinguishing learning loop so it never re-asks about a merchant it has already learned.

---

## 1. Problem (data-grounded)

The tracker is treated as noise and has become a dead feature. Live-data diagnosis (Supabase `cgmaotzmeoiueyzlchaz`, 161 orders / 62 shipments) shows **four distinct failure modes**, not one:

| Symptom | Root cause | Scale (measured) |
|---|---|---|
| Digital / non-shippable clutter | LLM `is_purchase_confirmation` over-fires on flights, restaurants, SaaS, statements; `detectPhysicalVsDigital` not catching them (zero `status='digital'` rows exist) | 106 / 161 orders have no shipment |
| "Duplicates" | 44% of orders have **null `order_number`** → dedup key `(merchant, order_number)` collapses → 1 email = 1 new row | 71 null; 11 same-merchant-same-day clusters |
| Fragmented merchants | `normalized_merchant` doesn't collapse TLD/name variants | Amazon / .es / .nl; TAP ×3; Vista Alegre ×2 |
| Frozen / un-updating shipments | (a) phantom rows with empty `tracking_number`; (b) malformed multi-piece strings (`"A / B"`) filtered out of every poll; (c) duplicate tracking rows; (d) ETA almost never populated | 7 empty-tracking frozen rows; 1 known-unhandled multi-piece; `JD0146…` duplicated; **only 1 of 10 in-transit shipments has an ETA** |
| Manual cleanup tax | User dismisses noise by hand | 37 `dismissed_by_user` (23% of all orders) |

The update path is partially alive (a launchd poller runs every 30 min and succeeds) but structurally broken: it can only ever touch a subset because empty/malformed tracking numbers are silently skipped and freeze at creation time forever.

## 2. Product decisions (locked)

Three decisions, taken with the user, anchor the whole design:

1. **Purpose:** A **"where's my stuff" tracker** — inbound *physical* packages only. A purchase with no package is not something the tracker surfaces. Flights, restaurants, SaaS, App Store, statements never appear (not "dismissed" — never surfaced).

2. **Pre-shipment state:** A **persistent quiet "Expected" shelf** — physical orders confirmed but awaiting tracking sit in a muted secondary zone, graduate to the live view when tracking lands, and persist until tracking arrives or the user dismisses (no auto-expiry).

3. **When unsure:** A **one-tap review queue that self-extinguishes via learning.** The hard requirement from the user: *it must not ask twice from the same source.* One confirmation writes a `merchant_rule` and the queue never re-asks about that merchant. The queue is busy week one, then goes quiet.

## 3. Architecture: the inversion

The single conceptual change that kills most of the noise mechanically:

> **Today:** the *purchase confirmation* is the primary object; a shipment is an optional attachment.
> **New:** *a package in motion* is the primary object; a purchase with no package is not a tracked thing.

Consequences that fall out for free:
- Dedup moves from `order_number` (44% null, unreliable) → `tracking_number` (reliable, one per package).
- Digital / flights / restaurants / SaaS never create a tracked row because they never produce a tracking number.
- The confirmation + shipped + delivered emails collapse onto one tracking number instead of spawning rows.

The existing tables (`orders`, `shipments`, `merchant_rules`, `review_items`, `order_corrections`) are **reused with sharpened semantics** — no new primary tables. (Approach B of the three considered; A was a band-aid that left duplicates intact, C was an unnecessary rewrite.)

---

## 4. Component 1 — Classification cascade & the self-extinguishing learning loop

Every inbound commerce email runs a decision cascade; **first hit wins**; expensive/fuzzy steps run only when cheap/deterministic ones don't fire.

1. **Carrier short-circuit.** If the sender is a known carrier (DHL, UPS, FedEx, CTT, GLS, …) and the body has a tracking number → route to *shipment-matching*, not merchant-order creation. (Kills the "DHL Express became a merchant" bug class.)

2. **Learned-rule lookup (`merchant_rules`).** Check sender-email → sender-domain → normalized-merchant for an existing rule: `always_physical`, `always_digital`, or `skip_purchase`. If found, apply **silently**. **This is the "never ask twice" guarantee.**

3. **Hard category excludes.** Built-in never-shippable categories — airlines, hotels, restaurant/reservation, ride-share, brokerage/bank statements, telecom/utilities, domains/hosting, streaming/SaaS, app stores. Matched on sender-domain patterns + LLM category. Resolve to "digital, never surface" without user teaching (user can still override).

4. **LLM classification — repurposed.** The existing extractor's question changes from *"is this a purchase confirmation?"* to *"is this a physical, shippable purchase — physical / digital / unsure, and how confident?"* Returns `{ classification, confidence }`.

5. **Confidence banding.**
   - High-confidence physical → create/update an **Expected** order, or match to an in-transit shipment.
   - High-confidence digital/non-physical → written but `hidden` (never surfaced; retained for the learning loop + audit).
   - Mid-band *unsure* AND no learned rule → create **one** `review_item` ("Package from X?").

**The learning loop (self-extinguishing):**
- Answering a review item **immediately** writes a `merchant_rule` on the most specific reliable signal (sender-email if the merchant uses a consistent from-address, else sender-domain, else normalized-merchant).
- **One confirmation is enough** for the physical/digital axis (lower stakes than `skip_purchase`, which keeps its 3-correction promotion threshold).
- The rule **retroactively sweeps** pending sibling review items from the same sender — confirm "Peak Design = physical" once → all queued + future Peak Design items resolve silently.
- **Content-pattern learning** ("emails that say Y are physical") is a *softer second layer*: confirmed examples feed back into the LLM prompt as few-shot reinforcement (the same feedback-injection pattern BioChecha uses), shrinking the unsure band over time. The *deterministic* guarantee comes from the sender/merchant rules, not the fuzzy content match.

**Files (anticipated):**
- `skill/dashboard-sync/src/orders-autopilot.ts` — cascade orchestration in `processEmail`.
- `skill/dashboard-sync/src/llm-extractor.ts` — repurpose the prompt; add `classification` + `confidence`.
- `skill/dashboard-sync/src/physical-vs-digital.ts` — hard-category list + carrier short-circuit helpers.
- `skill/dashboard-sync/src/merchant-rules.ts` — extend lookup + write for `always_physical` / `always_digital`.

## 5. Component 2 — Data-model semantics, dedup, tracking normalization, ETA ladder, merchant normalization

**Semantic split (existing two tables, sharpened):**
- **`shipments` = real trackable packages only.** Enforced invariant: a shipment row exists **only** with a non-empty, well-formed `tracking_number`. Empty/malformed → never written as a shipment.
- **`orders` = purchases.** Physical + no shipment = **Expected**. Physical + ≥1 shipment = **In Transit / Delivered**. Digital/non-physical = `hidden` (retained, never surfaced).

**Dedup, fixed at the root:**
- Shipments: **unique `(user_id, tracking_number)`** partial index (where `tracking_number` is non-empty). The confirmation/shipped/delivered emails upsert onto the one row.
- Orders: keep `(merchant, order_number)`; add a fallback for the null-order-number case — dedup on `(normalized_merchant, order_date::date, total_amount)` so a null-number merchant doesn't spawn a row per email.

**Tracking-number normalization at ingest** (new pure function, `normalize-tracking.ts`):
- Split multi-piece strings (`"A / B"`, `"A, B"`) into N tracking numbers → N shipment rows, each pollable.
- Reject empty/junk before any shipment row is created (they remain Expected orders).
- Retroactively un-freezes the DHL multi-piece class.

**ETA priority ladder** (first available wins; higher tier overwrites lower):
1. **Email-parsed ETA** — extracted from the shipping email at ingest ("arriving May 12 / Tuesday"). New extraction field; the source 17track keeps missing.
2. **17track `estimated_delivery_date`** — on poll.
3. **Carrier default-transit heuristic** — by service level, as a last-resort estimate clearly marked as approximate.

**Merchant normalization pass** (new, small): collapse TLD variants (`amazon.es`/`.nl` → `amazon`) + a learned-alias map (TAP ×3 → one). Lives next to `normalized_merchant`; feeds both dedup and display.

## 6. Component 3 — The repaired poll / update path

- **Selection:** poll every shipment with a valid `tracking_number` that is non-terminal (not delivered/cancelled) and whose `updated_at` is older than the poll interval. Nothing valid is ever skipped; phantom empties no longer exist post-backfill.
- **Registration:** unchanged (idempotent 17track register-before-poll), but fed only valid numbers post-normalization.
- **ETA on each poll:** apply the 3-tier ladder; never blank an existing higher-tier ETA with a lower-tier null.
- **Trigger:** keep the launchd poller (`com.theperch.poll-shipments.plist`, 30 min) as primary. The openclaw cron `orders-autopilot-17track-poll` (6 h, on `claude-haiku-4-5`) stays as backstop. **Audit both** for the rejected-`zai/glm-5` model class of bug before close (the BioChecha rotation incident showed this failure mode is real on this machine).
- **Performance:** the existing N+1 in the per-shipment update loop (`getShipmentsForOrder` + `updateOrderStatus` per row) is acceptable at current N (<20 in-transit). Batch only if N grows; not in scope now (YAGNI).

## 7. Component 4 — The two-zone iOS surface & learning interactions

The HubTab Orders surface (today a flat list) becomes two ranked zones + a third that renders only when non-empty.

**Zone 1 — In Transit** (top, daily-glance hero)
- Shipments with a real tracking number, not yet delivered.
- Row leads with **ETA, not status**: "Peak Design · **Arrives Tue**". Carrier + checkpoint secondary.
- Sorted by ETA ascending (soonest first).
- Delivered shows "Delivered ✓" for 48 h, then archives out of view.

**Zone 2 — Expected** (below, muted)
- Physical orders confirmed, no tracking yet: "Notino · ordered 3d ago, awaiting tracking."
- Persists; auto-graduates to In Transit when tracking lands; dismissable.
- Quiet visual weight.

**Zone 3 — Needs your call** (bottom, **renders only when non-empty**)
- The review queue. When learning catches up, the section is *gone* — no zero-state, no nag. This is the anti-dead-feature guarantee made visual.
- Each item: merchant + subject + classifier guess. Three taps:
  - **"Yes, track it"** → `always_physical`; graduates to Expected/In Transit.
  - **"Not a package"** → `skip_purchase`; vanishes.
  - **"Bought it, but nothing ships"** → `always_digital`; teaches the digital nuance.
- Answering one **retroactively sweeps** siblings from the same sender.

**Corrections on live rows** (existing long-press menu, kept): "Not my package" / "Wrong tracking" / "Already delivered" — feed the *same* `merchant_rules` loop.

**Today tab (`DeliveryHomeCard`)** — tightened to the **next 1–2 imminent arrivals** only ("Peak Design arrives tomorrow"). Hides entirely when nothing's in transit. The cross-domain "package arriving while traveling" BioChecha insight keys off the now-reliable ETAs.

**Leaves the UI completely:** digital/non-physical orders; the flat order list.

**Files (anticipated):**
- `ios/.../Views/App/HubTab.swift` — the two/three-zone Orders surface.
- `ios/.../Views/Cards/OrderCard.swift`, `DeliveryCard.swift` — ETA-led row layout.
- `ios/.../Views/Cards/DeliveryHomeCard.swift` — imminent-arrivals-only + hide-when-empty.
- new review-queue view + the three-way answer action wired to `order_corrections` / `merchant_rules`.
- `ios/.../Services/OrdersService.swift` — zone queries (in-transit / expected / review / hidden).

## 8. Component 5 — Backfill

**Governing decision:** history is **auto-sorted, not triaged**. Do not dump a triage pile on day one — that recreates the chore. The review queue is **forward-looking only**; it starts empty and fills from new mail.

One-shot script (idempotent, dry-run-first, reversible):
1. **Re-classify the 161 orders** via the new cascade using merchant + category + hard-exclude list (no email re-fetch for the obvious ones — TAP, Noma, CleanCloud, GoDaddy, Schwab, Apple-digital resolve from merchant alone). Digital/excluded → `hidden`; physical → keep; **uncertain history → archived, not queued**.
2. **Repair shipments:** delete the 7 phantom empty-tracking rows (order falls back to Expected if physical); split malformed multi-piece strings; collapse duplicate tracking rows; **then** add the unique index (after dedup, so it doesn't fail).
3. **Merchant normalization sweep** — Amazon variants, TAP ×3, Vista Alegre ×2.
4. **Re-derive order status** from cleaned shipments.
5. **ETAs self-heal** on the next poll (no special backfill).

**Safety rails:**
- **Dry-run first** — prints "would keep N, hide M, merge K, split J" for eyeball approval.
- **Hidden, never deleted** — a `hidden_reason` column flags noise; fully reversible; an Admin/audit view shows what was hidden and why, with un-hide.
- Live run only after dry-run approval.

**After backfill:** In Transit = the handful of actually-moving packages with ETAs; Expected = physical awaiting tracking; Needs-your-call = empty; everything else = quietly archived, recoverable.

---

## 9. Data-model / migration changes

- `orders`: add `hidden boolean default false`, `hidden_reason text`, `classification text` (`physical` / `digital` / `unsure`). Merchant normalization writes the canonical value **directly into the existing `normalized_merchant`** — no per-order alias column.
- `shipments`: add partial unique index `(user_id, tracking_number) where tracking_number <> ''`; add `eta_source text` (`email` / `17track` / `heuristic`).
- `merchant_rules`: extend `action` enum with `always_physical`, `always_digital`. Lower the promotion threshold to 1 correction for these two actions (keep 3 for `skip_purchase`).
- `merchant_aliases` (new small table, optional): `variant text`, `canonical text`, `user_id` — holds learned brand collapses (TAP ×3 → one) beyond the static TLD-stripping rule. Seeded by the backfill; appendable as new variants appear. If this proves unnecessary in practice (static TLD rule covers most), it can fold into a code-side static map — decide during implementation.
- All migrations follow the repo convention (`supabase/migrations/<timestamp>_*.sql`), idempotent, `IF NOT EXISTS` / `IF EXISTS` guards. Apply to prod via MCP `apply_migration` AND commit the file (the R9–R14 audits showed dashboard-only changes drift).

## 10. Testing strategy

- **Classification cascade:** unit tests per layer (carrier short-circuit, learned-rule hit, hard-category exclude, confidence banding) with fixture emails covering the real failure cases (Noma, TAP, CleanCloud, DHL multi-piece, a real Peak Design confirmation, an Amazon order).
- **Tracking normalization:** pure-function unit tests — multi-piece split, empty/junk rejection, valid passthrough.
- **Dedup:** integration test — same tracking number across confirmation+shipped+delivered emails yields one shipment row; null-order-number merchant across two emails yields one order row.
- **ETA ladder:** unit tests — email ETA beats 17track; 17track beats heuristic; no tier blanks a higher one.
- **Learning loop:** integration — answering a review item writes the rule, sweeps siblings, and the next same-sender email skips the queue.
- **Backfill:** run dry-run against a snapshot of prod data; assert the kept/hidden/merged/split counts; verify reversibility (un-hide restores).
- **iOS:** zone queries return correct partitions; review-queue section hides when empty; xcodebuild clean.

## 11. Out of scope (YAGNI)

- New `tracked_packages` table (Approach C) — existing tables suffice.
- Direct carrier API integrations beyond 17track — 17track is the aggregation layer; not worth per-carrier auth.
- Push notifications on delivery — separate feature; the Live Activity path already exists.
- Re-triaging historical uncertain orders — explicitly archived, not queued.
- pollShipments N+1 batching — acceptable at current scale.
- Multi-user / shared-tracking — single-tenant model holds.

## 12. Rollout order (informs the implementation plan)

1. Migrations (schema + indexes + merchant_rules actions).
2. Tracking normalization + dedup (stops new duplicates/phantoms immediately).
3. Classification cascade + learning-rule read/write (stops new digital noise).
4. Poll-path repair + ETA ladder (fixes updates going forward).
5. Backfill script (dry-run → live) (cleans history).
6. iOS two-zone surface + review queue (surfaces the now-clean data).

Each step produces a working, shippable state on its own.
