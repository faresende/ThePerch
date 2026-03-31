# Orders Autopilot Foundation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first real Orders Autopilot foundation in the dashboard-sync pipeline by introducing canonical Order/Shipment/ReviewItem models, splitting email-vs-shipment extraction, and adding deterministic linking rules.

**Architecture:** The first shippable slice belongs in `skill/dashboard-sync`, not iOS. The current system only knows generic `delivery` records and naïve text parsing. We will extend the sync skill with explicit order/shipment domain types and extraction helpers, while preserving existing delivery behavior. The first milestone is pipeline correctness and testability, not UI.

**Tech Stack:** TypeScript, dashboard-sync skill, Supabase, Vitest/Jest-style node tests (depending on repo tooling), 17track-ready domain modeling

---

## File map

### Existing files to modify
- Modify: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/types.ts`
  - extend canonical record/data types for orders, shipments, and review items
- Modify: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/index.ts`
  - validate new types/categories/display hints and expose new helpers if needed
- Modify: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/auto-capture.ts`
  - split extraction into order extraction, shipment extraction, and linking-safe helpers
- Modify: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/supabase.ts`
  - only if helper queries/upserts become necessary for the first slice

### New files to create
- Create: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/orders.ts`
  - canonical order/shipment/review item domain helpers
- Create: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/matching.ts`
  - deterministic linking and ambiguity handling
- Create: `~/Documents/Apps/ThePerch/skill/dashboard-sync/test/orders.test.ts`
  - order/shipment model and extraction tests
- Create: `~/Documents/Apps/ThePerch/skill/dashboard-sync/test/matching.test.ts`
  - deterministic linking tests and review fallback tests

### Supporting files to inspect before coding
- Inspect: `~/Documents/Apps/ThePerch/skill/dashboard-sync/package.json`
- Inspect: `~/Documents/Apps/ThePerch/supabase/` schema files if we need new categories or downstream storage support

---

## Chunk 1: Canonical domain model

### Task 1: Extend dashboard-sync types for orders and shipments

**Files:**
- Modify: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/types.ts`
- Test: `~/Documents/Apps/ThePerch/skill/dashboard-sync/test/orders.test.ts`

- [ ] **Step 1: Inspect package/test setup**

Run:
```bash
cd ~/Documents/Apps/ThePerch/skill/dashboard-sync && cat package.json
```
Expected: confirm test runner and script names.

- [ ] **Step 2: Write the failing domain-shape tests**

Create tests covering:
- order payload shape
- shipment payload shape
- review item payload shape
- supported record type/category validation expectations

- [ ] **Step 3: Run the tests to confirm failure**

Run the repo’s test command for the new file.
Expected: fail because the new types do not exist yet.

- [ ] **Step 4: Add minimal types**

In `src/types.ts`, add:
- `RecordType` support for `order`, `shipment`, `review_item` if appropriate for this skill layer
- `RecordCategory` support for a new canonical category, likely `commerce` or `orders`
- `OrderData`
- `ShipmentData`
- `ReviewItemData`

Keep fields narrow:
- `OrderData`: merchant_name, normalized_merchant, order_number, order_date, total_amount, currency, source_email_ids, confidence_score, status
- `ShipmentData`: order_id, tracking_number, carrier, provider, status, latest_checkpoint, shipped_at, delivered_at, source_email_ids, confidence_score
- `ReviewItemData`: type, reason, suggested_action, confidence_score, related_order_id, related_shipment_id

- [ ] **Step 5: Update validation in `src/index.ts`**

Allow the new types/categories/hints without breaking existing ones.

- [ ] **Step 6: Run the tests again**

Expected: new domain-shape tests pass.

- [ ] **Step 7: Commit**

```bash
cd ~/Documents/Apps/ThePerch
git add skill/dashboard-sync/src/types.ts skill/dashboard-sync/src/index.ts skill/dashboard-sync/test/orders.test.ts
git commit -m "feat(sync): add canonical order and shipment types"
```

---

## Chunk 2: Extraction split

### Task 2: Separate order extraction from shipment extraction

**Files:**
- Modify: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/auto-capture.ts`
- Create: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/orders.ts`
- Test: `~/Documents/Apps/ThePerch/skill/dashboard-sync/test/orders.test.ts`

- [ ] **Step 1: Write failing extraction tests**

Add fixtures/tests for texts like:
- purchase confirmation with merchant + order number + total but no tracking
- shipment email with carrier + tracking number + status
- ambiguous text that should not silently create both

- [ ] **Step 2: Run tests to confirm failure**

Expected: current `parseDeliveryStatus` is too primitive and there is no order extraction path.

- [ ] **Step 3: Create `src/orders.ts`**

Implement focused helpers:
- `extractOrderCandidate(text: string)`
- `extractShipmentCandidate(text: string)`
- `normalizeMerchantName(name: string)`

Keep the heuristics deterministic and modest. Do not attempt magical NLP.

- [ ] **Step 4: Refactor `auto-capture.ts`**

Preserve existing helpers, but split the commerce logic into:
- order extraction
- shipment extraction
- no auto-linking yet

- [ ] **Step 5: Run tests again**

Expected: extraction tests pass.

- [ ] **Step 6: Commit**

```bash
cd ~/Documents/Apps/ThePerch
git add skill/dashboard-sync/src/auto-capture.ts skill/dashboard-sync/src/orders.ts skill/dashboard-sync/test/orders.test.ts
git commit -m "feat(sync): split order and shipment extraction"
```

---

## Chunk 3: Deterministic matching and review fallback

### Task 3: Add exact-match linking rules and ambiguity handling

**Files:**
- Create: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/matching.ts`
- Test: `~/Documents/Apps/ThePerch/skill/dashboard-sync/test/matching.test.ts`

- [ ] **Step 1: Write failing matcher tests**

Cover these cases:
- exact merchant + exact order number links shipment to order
- exact tracking number links shipment updates to existing shipment
- merchant-only ambiguity creates review item instead of auto-linking
- missing order with valid tracking becomes standalone shipment + review item

- [ ] **Step 2: Run tests to confirm failure**

Expected: no matcher exists yet.

- [ ] **Step 3: Implement `src/matching.ts`**

Add small pure functions such as:
- `matchShipmentToOrder(...)`
- `buildReviewItem(...)`
- `deriveOrderStatusFromShipments(...)` (minimal first pass)

Rule order:
1. exact tracking
2. exact merchant + exact order number
3. ambiguity => review item

- [ ] **Step 4: Run tests again**

Expected: matcher tests pass.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/Apps/ThePerch
git add skill/dashboard-sync/src/matching.ts skill/dashboard-sync/test/matching.test.ts
git commit -m "feat(sync): add deterministic order shipment matching"
```

---

## Chunk 4: Persistence-ready pipeline hooks

### Task 4: Prepare the sync skill to emit canonical records

**Files:**
- Modify: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/index.ts`
- Modify: `~/Documents/Apps/ThePerch/skill/dashboard-sync/src/supabase.ts` (only if needed)
- Test: existing/new tests in `skill/dashboard-sync/test/`

- [ ] **Step 1: Write a failing integration-style test**

Expected behavior:
- given a purchase email text, the pipeline can produce an order record payload
- given a shipment email text, the pipeline can produce a shipment record payload
- ambiguous matches produce review item payloads rather than unsafe merges

- [ ] **Step 2: Run test to confirm failure**

- [ ] **Step 3: Implement minimal emission path**

Do not build the full UI or 17track refresh yet.
Only make the skill capable of producing canonical records cleanly.

- [ ] **Step 4: Run the full dashboard-sync test suite**

Expected: green.

- [ ] **Step 5: Commit**

```bash
cd ~/Documents/Apps/ThePerch
git add skill/dashboard-sync/src/index.ts skill/dashboard-sync/src/supabase.ts skill/dashboard-sync/test
git commit -m "feat(sync): emit canonical commerce records"
```

---

## Out of scope for this first implementation slice

Do not do these in the first build block unless the earlier chunks are already solid:
- 17track live refresh integration
- ThePerch iOS orders UI
- Gmail OAuth/ingestion plumbing if it is not already present
- broad merchant-specific parsing
- returns / refunds
- OCR or attachment parsing

These belong to follow-on sub-issues once the domain model and extraction pipeline are real.

---

## Immediate backlog decomposition recommendation

Turn #29 into these executable child issues:
1. Canonical Order / Shipment / ReviewItem model in dashboard-sync
2. Email extraction split: purchase vs shipment
3. Deterministic linker + review fallback
4. 17track normalization and live shipment refresh
5. ThePerch unified Orders UI

---

## Verification commands

- [ ] `cd ~/Documents/Apps/ThePerch/skill/dashboard-sync && cat package.json`
- [ ] `cd ~/Documents/Apps/ThePerch/skill/dashboard-sync && <repo-test-command>`
- [ ] `cd ~/Documents/Apps/ThePerch/skill/dashboard-sync && <repo-test-command> -- orders.test.ts`
- [ ] `cd ~/Documents/Apps/ThePerch/skill/dashboard-sync && <repo-test-command> -- matching.test.ts`

---

Plan complete and saved to `docs/superpowers/plans/2026-03-21-orders-autopilot-foundation.md`. Ready to execute?