# Order Tracker Rework ("Where's My Stuff") Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the order tracker around "a physical package in motion" as the primary object so it surfaces only trackable inbound packages — no digital clutter, no duplicates, accurate ETAs — with a self-extinguishing learning loop that never re-asks about a merchant it has learned.

**Architecture:** Reuse the existing `orders` / `shipments` / `merchant_rules` / `review_items` tables with sharpened semantics. A front-of-pipeline classification cascade (carrier short-circuit → learned-rule lookup → hard-category excludes → repurposed LLM → confidence banding) decides physical/digital/unsure. Dedup moves to `tracking_number`. A 3-tier ETA ladder fills the "when's it arriving" gap. iOS renders two ranked zones (In Transit / Expected) plus a review queue that only appears when non-empty.

**Tech Stack:** TypeScript skill (`skill/dashboard-sync`, tested via `node:test` on compiled `dist/`), Supabase Postgres (migrations in `supabase/migrations/`), Swift 6 / SwiftUI iOS app. Spec: `docs/superpowers/specs/2026-05-08-order-tracker-rework-design.md`.

---

## File Structure

**TypeScript (skill/dashboard-sync/src/):**
- `normalize-tracking.ts` *(new)* — pure functions: split multi-piece tracking strings, validate/reject. One responsibility: turn a raw tracking string into 0..N valid tracking numbers.
- `normalize-tracking.test.ts` *(new)* — unit tests for the above.
- `classification-cascade.ts` *(new)* — the ordered decision cascade returning `{ classification, confidence, reason }`. Depends on: carrier list, merchant-rules lookup, hard-category list, the LLM extractor.
- `classification-cascade.test.ts` *(new)* — per-layer tests with the real failure-case fixtures.
- `physical-vs-digital.ts` *(modify)* — add the hard-category exclude list + `categoryOf(senderDomain, llmCategory)`. Keep the existing phrase heuristic as one input.
- `carriers.ts` *(new)* — known-carrier sender list + `isCarrierSender(email)`. Extracted so both the cascade and the existing `normalizeCarrierForTracker` can share it.
- `eta-ladder.ts` *(new)* — `resolveETA(tiers)` pure function implementing email → 17track → heuristic precedence.
- `eta-ladder.test.ts` *(new)* — unit tests.
- `merchant-normalize.ts` *(new)* — `canonicalMerchant(name)` collapsing TLD/alias variants.
- `merchant-normalize.test.ts` *(new)* — unit tests.
- `orders-autopilot.ts` *(modify)* — wire the cascade into `processEmail`; route tracking through `normalize-tracking`; repair `pollShipments` selection + ETA.
- `merchant-rules.ts` *(modify)* — read/write `always_physical` / `always_digital`; the retroactive-sweep helper.
- `backfill-tracker.ts` *(new)* — one-shot dry-run-able backfill CLI subcommand.

**SQL (supabase/migrations/):**
- `<ts>_order_tracker_rework_schema.sql` *(new)* — orders columns, shipments index + eta_source, merchant_rules action enum + threshold.

**Swift (ios/ThePerch/Sources/ThePerch/):**
- `Services/OrdersService.swift` *(modify)* — zone-partitioned queries (in-transit / expected / review / hidden).
- `Views/App/HubTab.swift` *(modify)* — the two/three-zone Orders surface.
- `Views/Cards/OrderCard.swift` + `Views/Cards/DeliveryCard.swift` *(modify)* — ETA-led row layout.
- `Views/Cards/DeliveryHomeCard.swift` *(modify)* — imminent-arrivals-only, hide when empty.
- `Views/App/ReviewQueueSection.swift` *(new)* — the Zone-3 review UI + three-way answer.

**Test fixtures (skill/dashboard-sync/test/fixtures/):**
- `classification/noma.json`, `tap.json`, `cleancloud.json`, `dhl-multipiece.json`, `peak-design.json`, `amazon.json` *(new)* — the real failure cases.

---

## Phase 1 — Migrations (schema is the foundation; nothing else compiles against it otherwise)

### Task 1.1: Schema migration — orders columns, shipments index, merchant_rules actions

**Files:**
- Create: `supabase/migrations/20260508120000_order_tracker_rework_schema.sql`

- [ ] **Step 1: Write the migration file**

```sql
-- 20260508120000_order_tracker_rework_schema.sql
-- Order Tracker Rework: package-primary model.
-- Spec: docs/superpowers/specs/2026-05-08-order-tracker-rework-design.md

BEGIN;

-- ── orders: classification + hide-not-delete ──────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS classification text,
  ADD COLUMN IF NOT EXISTS hidden boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS hidden_reason text;

-- classification ∈ physical | digital | unsure (nullable for pre-existing rows
-- until backfill runs). Constraint is permissive on NULL.
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_classification_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_classification_check
  CHECK (classification IS NULL OR classification IN ('physical','digital','unsure'));

-- Index the common surface filter (visible physical orders).
CREATE INDEX IF NOT EXISTS orders_user_visible_idx
  ON public.orders (user_id, hidden, classification)
  WHERE hidden = false;

-- ── shipments: real-tracking-only invariant + eta source ──────────────
ALTER TABLE public.shipments
  ADD COLUMN IF NOT EXISTS eta_source text;
ALTER TABLE public.shipments
  DROP CONSTRAINT IF EXISTS shipments_eta_source_check;
ALTER TABLE public.shipments
  ADD CONSTRAINT shipments_eta_source_check
  CHECK (eta_source IS NULL OR eta_source IN ('email','17track','heuristic'));

-- Partial unique index: one row per (user, tracking number), only for
-- non-empty tracking numbers. NOTE: this will FAIL if duplicate or empty
-- rows exist — the backfill (Phase 5) cleans those first, so this index
-- is created THERE, not here. Left documented for reference:
--   CREATE UNIQUE INDEX shipments_user_tracking_uniq
--     ON public.shipments (user_id, tracking_number)
--     WHERE tracking_number <> '';

-- ── merchant_rules: new physical/digital actions ──────────────────────
ALTER TABLE public.merchant_rules
  DROP CONSTRAINT IF EXISTS merchant_rules_action_check;
ALTER TABLE public.merchant_rules
  ADD CONSTRAINT merchant_rules_action_check
  CHECK (action IN ('skip_purchase','always_physical','always_digital'));

COMMIT;
```

- [ ] **Step 2: Apply to prod via MCP**

Use the Supabase MCP `apply_migration` tool with project_id `cgmaotzmeoiueyzlchaz`, name `order_tracker_rework_schema`, and the SQL body above (minus the `BEGIN`/`COMMIT` — apply_migration wraps its own transaction).

Expected: `{"success": true}`

- [ ] **Step 3: Verify columns landed**

Use MCP `execute_sql`:
```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='orders'
  AND column_name IN ('classification','hidden','hidden_reason');
```
Expected: 3 rows.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260508120000_order_tracker_rework_schema.sql
git commit -m "feat(orders): schema for tracker rework — classification, hidden, eta_source, merchant_rules actions"
```

---

## Phase 2 — Tracking normalization + dedup (stops new duplicates/phantoms immediately)

### Task 2.1: Pure tracking-number normalizer

**Files:**
- Create: `skill/dashboard-sync/src/normalize-tracking.ts`
- Test: `skill/dashboard-sync/src/normalize-tracking.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// skill/dashboard-sync/src/normalize-tracking.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeTrackingNumbers } from './normalize-tracking';

test('rejects empty / whitespace', () => {
  assert.deepEqual(normalizeTrackingNumbers(''), []);
  assert.deepEqual(normalizeTrackingNumbers('   '), []);
  assert.deepEqual(normalizeTrackingNumbers(null), []);
  assert.deepEqual(normalizeTrackingNumbers(undefined), []);
});

test('passes a single valid number through, trimmed', () => {
  assert.deepEqual(normalizeTrackingNumbers('1Z999AA10123456784'), ['1Z999AA10123456784']);
  assert.deepEqual(normalizeTrackingNumbers('  9882676775 '), ['9882676775']);
});

test('splits multi-piece strings on / and ,', () => {
  assert.deepEqual(
    normalizeTrackingNumbers('7197712620 / 001959496839433548'),
    ['7197712620', '001959496839433548'],
  );
  assert.deepEqual(
    normalizeTrackingNumbers('JD0146, JD0147'),
    ['JD0146', 'JD0147'],
  );
});

test('drops junk pieces that are too short/long after split', () => {
  // "12" too short (<6), keep the valid one
  assert.deepEqual(normalizeTrackingNumbers('12 / 1Z999AA10123456784'), ['1Z999AA10123456784']);
});

test('dedups identical pieces within one string', () => {
  assert.deepEqual(normalizeTrackingNumbers('JD0146 / JD0146'), ['JD0146']);
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 normalize-tracking
```
Expected: FAIL — `Cannot find module './normalize-tracking'`.

- [ ] **Step 3: Implement**

```typescript
// skill/dashboard-sync/src/normalize-tracking.ts
/**
 * Turn a raw tracking string from an email into 0..N valid tracking
 * numbers. Multi-piece shipments arrive as "A / B" or "A, B"; the old
 * pipeline filtered these out entirely (the freeze bug). Empty/junk
 * pieces are rejected so a phantom shipment row never gets created.
 */
const MIN_LEN = 6;
const MAX_LEN = 40;
const BAD_CHARS = /[\s,/\\]/;

function isValidPiece(p: string): boolean {
  return p.length >= MIN_LEN && p.length <= MAX_LEN && !BAD_CHARS.test(p);
}

export function normalizeTrackingNumbers(raw: string | null | undefined): string[] {
  if (!raw) return [];
  const pieces = raw
    .split(/[/,]/)
    .map(s => s.trim())
    .filter(s => s.length > 0);
  const valid = pieces.filter(isValidPiece);
  return [...new Set(valid)];
}
```

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 normalize-tracking
```
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add skill/dashboard-sync/src/normalize-tracking.ts skill/dashboard-sync/src/normalize-tracking.test.ts
git commit -m "feat(orders): pure tracking-number normalizer (split multi-piece, reject junk)"
```

### Task 2.2: Route shipment creation through the normalizer + dedup on tracking number

**Files:**
- Modify: `skill/dashboard-sync/src/orders-autopilot.ts` (`handleShippingNotification` at ~L553, and the shipment-upsert path)

- [ ] **Step 1: Write the failing test**

```typescript
// add to skill/dashboard-sync/src/orders.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { shipmentRowsForTracking } from './orders-autopilot';

test('a multi-piece tracking string yields N shipment rows, deduped', () => {
  const rows = shipmentRowsForTracking('7197712620 / 001959496839433548', 'DHL');
  assert.equal(rows.length, 2);
  assert.deepEqual(rows.map(r => r.tracking_number), ['7197712620', '001959496839433548']);
});

test('an empty tracking string yields zero shipment rows (no phantom)', () => {
  assert.deepEqual(shipmentRowsForTracking('', 'DHL'), []);
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "shipment rows"
```
Expected: FAIL — `shipmentRowsForTracking is not a function`.

- [ ] **Step 3: Implement the helper + use it**

Add the exported helper to `orders-autopilot.ts`:

```typescript
import { normalizeTrackingNumbers } from './normalize-tracking';

/** Expand a raw tracking string into 0..N shipment row stubs. Empty →
 *  no rows (the order stays "Expected" instead of becoming a phantom
 *  shipment that can never be polled). */
export function shipmentRowsForTracking(
  raw: string | null | undefined,
  carrier: string | null,
): Array<{ tracking_number: string; carrier: string | null }> {
  return normalizeTrackingNumbers(raw).map(tn => ({ tracking_number: tn, carrier }));
}
```

In `handleShippingNotification`, replace the single-tracking-number path so it iterates `shipmentRowsForTracking(fields.trackingNumber, fields.carrier)` and upserts each. When the result is empty, skip shipment creation entirely (do not create a `pending` phantom). Upsert keyed on `(user_id, tracking_number)` — `onConflict: 'user_id,tracking_number'` once the Phase 5 unique index exists; until then, pre-check existence by tracking number (the existing `select ... eq('tracking_number')` guard at ~L601 already does this — keep it).

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "shipment rows"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skill/dashboard-sync/src/orders-autopilot.ts skill/dashboard-sync/src/orders.test.ts
git commit -m "feat(orders): expand multi-piece tracking into N rows; never create empty-tracking phantoms"
```

### Task 2.3: Merchant normalization (collapse TLD/alias variants)

**Files:**
- Create: `skill/dashboard-sync/src/merchant-normalize.ts`
- Test: `skill/dashboard-sync/src/merchant-normalize.test.ts`
- Modify: `skill/dashboard-sync/src/orders-autopilot.ts` (the `normalized_merchant` assignment in the order-upsert path)

- [ ] **Step 1: Write the failing test**

```typescript
// skill/dashboard-sync/src/merchant-normalize.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { canonicalMerchant } from './merchant-normalize';

test('collapses Amazon TLD variants', () => {
  assert.equal(canonicalMerchant('Amazon'), 'amazon');
  assert.equal(canonicalMerchant('Amazon.es'), 'amazon');
  assert.equal(canonicalMerchant('Amazon.nl'), 'amazon');
  assert.equal(canonicalMerchant('amazon.co.uk'), 'amazon');
});

test('collapses known brand aliases', () => {
  assert.equal(canonicalMerchant('TAP Air Portugal'), 'tap');
  assert.equal(canonicalMerchant('TAP Portugal'), 'tap');
  assert.equal(canonicalMerchant('Transportes Aéreos Portugueses'), 'tap');
  assert.equal(canonicalMerchant('Vista Alegre Atlantis'), 'vista alegre');
});

test('lowercases + trims unknown merchants unchanged', () => {
  assert.equal(canonicalMerchant('  Peak Design '), 'peak design');
  assert.equal(canonicalMerchant('Notino'), 'notino');
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "canonical\|merchant-normalize"
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```typescript
// skill/dashboard-sync/src/merchant-normalize.ts
/** Collapse the same brand fragmented by TLD ("Amazon.es") or name
 *  variant ("TAP Air Portugal" / "Transportes Aéreos Portugueses") to a
 *  single canonical key. Feeds both dedup and display. */

// Alias map: variant substrings → canonical. Checked before TLD stripping.
const ALIASES: ReadonlyArray<[RegExp, string]> = [
  [/^tap\b|transportes a[eé]reos portugueses|^tap air|^tap portugal/i, 'tap'],
  [/^vista alegre/i, 'vista alegre'],
];

function stripDiacritics(s: string): string {
  return s.normalize('NFD').replace(/[̀-ͯ]/g, '');
}

export function canonicalMerchant(name: string): string {
  const base = stripDiacritics(name).toLowerCase().trim();
  for (const [re, canonical] of ALIASES) {
    if (re.test(base)) return canonical;
  }
  // Strip a trailing TLD-ish suffix: "amazon.es" / "amazon.co.uk" → "amazon".
  const tldStripped = base.replace(/\.(com|co\.uk|co|es|nl|de|fr|it|pt|eu)$/i, '');
  return tldStripped;
}
```

In `orders-autopilot.ts`, set `normalized_merchant = canonicalMerchant(fields.merchant_name)` wherever the order row's `normalized_merchant` is currently assigned (replacing any ad-hoc lowercase).

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "canonical"
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add skill/dashboard-sync/src/merchant-normalize.ts skill/dashboard-sync/src/merchant-normalize.test.ts skill/dashboard-sync/src/orders-autopilot.ts
git commit -m "feat(orders): canonical merchant normalization (collapse TLD + brand-alias variants)"
```

The Phase-5 backfill sweep (Task 5.2) reuses `canonicalMerchant` to collapse the existing fragmented rows (`amazon.es`/`amazon.nl` → `amazon`, TAP ×3 → `tap`).

---

## Phase 3 — Classification cascade + self-extinguishing learning loop

### Task 3.1: Carrier-sender detection

**Files:**
- Create: `skill/dashboard-sync/src/carriers.ts`
- Test: `skill/dashboard-sync/src/carriers.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// skill/dashboard-sync/src/carriers.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { isCarrierSender } from './carriers';

test('recognizes known carrier sender domains', () => {
  assert.equal(isCarrierSender('noreply@dhl.com'), true);
  assert.equal(isCarrierSender('track@ups.com'), true);
  assert.equal(isCarrierSender('info@ctt.pt'), true);
});

test('does not flag a merchant as a carrier', () => {
  assert.equal(isCarrierSender('orders@peakdesign.com'), false);
  assert.equal(isCarrierSender('hello@noma.dk'), false);
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 carrier
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```typescript
// skill/dashboard-sync/src/carriers.ts
/** Sender domains that are shipping carriers (not merchants). A carrier
 *  email with a tracking number is a shipping NOTIFICATION, routed to
 *  shipment-matching — never a new merchant order. */
const CARRIER_DOMAINS: ReadonlyArray<string> = [
  'dhl.com', 'dhl.de', 'dpdhl.com',
  'ups.com', 'fedex.com', 'usps.com',
  'ctt.pt', 'gls-group.com', 'gls-group.eu',
  'dpd.com', 'tnt.com', 'aramex.com', 'royalmail.com',
  'correos.es', 'seur.com', 'mrw.es',
];

export function isCarrierSender(senderEmail: string | null | undefined): boolean {
  if (!senderEmail) return false;
  const at = senderEmail.lastIndexOf('@');
  if (at < 0) return false;
  const domain = senderEmail.slice(at + 1).toLowerCase().trim();
  return CARRIER_DOMAINS.some(d => domain === d || domain.endsWith(`.${d}`));
}
```

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 carrier
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skill/dashboard-sync/src/carriers.ts skill/dashboard-sync/src/carriers.test.ts
git commit -m "feat(orders): carrier-sender detection for the classification short-circuit"
```

### Task 3.2: Hard-category excludes

**Files:**
- Modify: `skill/dashboard-sync/src/physical-vs-digital.ts` (add `hardCategoryExclude`)
- Test: add to a new `skill/dashboard-sync/src/physical-vs-digital.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// skill/dashboard-sync/src/physical-vs-digital.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { hardCategoryExclude } from './physical-vs-digital';

test('excludes airlines, restaurants, SaaS, brokerage by sender domain', () => {
  assert.equal(hardCategoryExclude('booking@flytap.com'), 'airline');
  assert.equal(hardCategoryExclude('reservations@noma.dk'), 'restaurant');
  assert.equal(hardCategoryExclude('billing@godaddy.com'), 'domains');
  assert.equal(hardCategoryExclude('statements@schwab.com'), 'financial');
  assert.equal(hardCategoryExclude('receipts@cleancloud.com'), 'service');
});

test('returns null for a real physical merchant', () => {
  assert.equal(hardCategoryExclude('orders@peakdesign.com'), null);
  assert.equal(hardCategoryExclude('shop@notino.com'), null);
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "hard"
```
Expected: FAIL — `hardCategoryExclude` not exported.

- [ ] **Step 3: Implement (append to physical-vs-digital.ts)**

```typescript
/** Sender-domain → never-shippable category. Returns the category name
 *  when the sender is in a hard-excluded class, else null. Deterministic
 *  first line of defense before the LLM. */
const HARD_CATEGORY_DOMAINS: ReadonlyArray<[RegExp, string]> = [
  [/(^|\.)(flytap|tap|ryanair|lufthansa|united|aa|delta|iberia)\.com$/i, 'airline'],
  [/(^|\.)flytap\.com$/i, 'airline'],
  [/(^|\.)(noma\.dk|opentable\.com|thefork\.com|resy\.com)$/i, 'restaurant'],
  [/(^|\.)(godaddy|namecheap|cloudflare|gandi)\.com$/i, 'domains'],
  [/(^|\.)(schwab|fidelity|vanguard|revolut|wise|amex|americanexpress)\.com$/i, 'financial'],
  [/(^|\.)(cleancloud|notion|figma|slack|zoom|spotify|netflix)\.com$/i, 'service'],
  [/(^|\.)(uber|lyft|bolt)\.com$/i, 'rideshare'],
];

export function hardCategoryExclude(senderEmail: string | null | undefined): string | null {
  if (!senderEmail) return null;
  const at = senderEmail.lastIndexOf('@');
  if (at < 0) return null;
  const domain = senderEmail.slice(at + 1).toLowerCase().trim();
  for (const [re, cat] of HARD_CATEGORY_DOMAINS) {
    if (re.test(domain)) return cat;
  }
  return null;
}
```

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "hard"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skill/dashboard-sync/src/physical-vs-digital.ts skill/dashboard-sync/src/physical-vs-digital.test.ts
git commit -m "feat(orders): hard-category excludes (airlines, restaurants, SaaS, financial, rideshare)"
```

### Task 3.3: The classification cascade (fixture-driven)

**Files:**
- Create: `skill/dashboard-sync/src/classification-cascade.ts`
- Test: `skill/dashboard-sync/src/classification-cascade.test.ts`
- Create fixtures: `skill/dashboard-sync/test/fixtures/classification/{noma,tap,cleancloud,dhl-multipiece,peak-design,amazon}.json`

- [ ] **Step 1: Write the fixtures**

Each fixture: `{ "label", "input": { "subject", "body", "senderEmail", "senderName" }, "expected": { "classification": "physical"|"digital"|"unsure" } }`. Capture realistic bodies. Examples:

```json
// test/fixtures/classification/noma.json
{
  "label": "noma-reservation",
  "input": {
    "subject": "Your reservation at Noma is confirmed",
    "body": "We look forward to welcoming you on May 14 at 19:00. Your table for two is reserved. This is a non-refundable booking.",
    "senderEmail": "reservations@noma.dk",
    "senderName": "Noma"
  },
  "expected": { "classification": "digital" }
}
```
```json
// test/fixtures/classification/peak-design.json
{
  "label": "peak-design-order",
  "input": {
    "subject": "Your Peak Design order is confirmed",
    "body": "Thanks for your order! We're preparing your Everyday Backpack 20L for shipment to your address. Items: Everyday Backpack 20L x1. Total: EUR 279.95. We'll email tracking when it ships.",
    "senderEmail": "orders@peakdesign.com",
    "senderName": "Peak Design"
  },
  "expected": { "classification": "physical" }
}
```
Repeat for `tap.json` (airline → digital), `cleancloud.json` (laundry SaaS → digital), `dhl-multipiece.json` (carrier sender + "A / B" tracking → physical/shipment path), `amazon.json` (physical).

- [ ] **Step 2: Write the failing test**

```typescript
// skill/dashboard-sync/src/classification-cascade.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import * as fs from 'node:fs';
import * as path from 'node:path';
import { classifyForTracking } from './classification-cascade';

const dir = path.join(__dirname, '..', 'test', 'fixtures', 'classification');

for (const file of fs.readdirSync(dir).filter(f => f.endsWith('.json'))) {
  const fx = JSON.parse(fs.readFileSync(path.join(dir, file), 'utf8'));
  test(`classifies ${fx.label} as ${fx.expected.classification}`, async () => {
    // The cascade's deterministic layers (carrier, hard-category) must
    // resolve these fixtures WITHOUT the LLM. Pass a stub LLM that throws
    // so a test reaching it is a failure of the deterministic layers.
    const result = await classifyForTracking(fx.input, {
      lookupRule: async () => null,           // no learned rules in test
      llm: async () => { throw new Error('LLM should not be reached for these fixtures'); },
    });
    assert.equal(result.classification, fx.expected.classification);
  });
}
```

- [ ] **Step 3: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 classifies
```
Expected: FAIL — module not found.

- [ ] **Step 4: Implement the cascade**

```typescript
// skill/dashboard-sync/src/classification-cascade.ts
import { isCarrierSender } from './carriers';
import { hardCategoryExclude } from './physical-vs-digital';
import type { LLMExtractedFields } from './llm-extractor';

export type Classification = 'physical' | 'digital' | 'unsure';

export interface ClassifyInput {
  subject: string;
  body: string;
  senderEmail?: string;
  senderName?: string;
}

export interface ClassifyResult {
  classification: Classification;
  confidence: number;
  reason: string;
}

export interface CascadeDeps {
  /** Returns 'always_physical' | 'always_digital' | 'skip_purchase' | null. */
  lookupRule: (input: ClassifyInput) => Promise<string | null>;
  /** The repurposed LLM call (Task 3.4). */
  llm: (input: ClassifyInput) => Promise<{ classification: Classification; confidence: number }>;
}

const UNSURE_LOW = 0.45;
const UNSURE_HIGH = 0.75;

export async function classifyForTracking(
  input: ClassifyInput,
  deps: CascadeDeps,
): Promise<ClassifyResult> {
  // 1. Carrier short-circuit — handled upstream (routed to shipment match),
  //    but if a carrier email lands here, treat as physical (it has a package).
  if (isCarrierSender(input.senderEmail)) {
    return { classification: 'physical', confidence: 0.99, reason: 'carrier-sender' };
  }

  // 2. Learned rule.
  const rule = await deps.lookupRule(input);
  if (rule === 'always_physical') return { classification: 'physical', confidence: 1, reason: 'learned-rule' };
  if (rule === 'always_digital' || rule === 'skip_purchase')
    return { classification: 'digital', confidence: 1, reason: 'learned-rule' };

  // 3. Hard-category exclude.
  const cat = hardCategoryExclude(input.senderEmail);
  if (cat) return { classification: 'digital', confidence: 0.95, reason: `hard-category:${cat}` };

  // 4. LLM.
  const llm = await deps.llm(input);
  // 5. Confidence banding.
  if (llm.classification === 'physical' && llm.confidence >= UNSURE_HIGH)
    return { classification: 'physical', confidence: llm.confidence, reason: 'llm-high' };
  if (llm.classification === 'digital' && llm.confidence >= UNSURE_HIGH)
    return { classification: 'digital', confidence: llm.confidence, reason: 'llm-high' };
  if (llm.confidence < UNSURE_LOW)
    return { classification: llm.classification, confidence: llm.confidence, reason: 'llm-lowconf' };
  return { classification: 'unsure', confidence: llm.confidence, reason: 'llm-midband' };
}
```

- [ ] **Step 5: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 classifies
```
Expected: PASS — all fixtures resolve via deterministic layers (the throwing LLM stub is never hit).

- [ ] **Step 6: Commit**

```bash
git add skill/dashboard-sync/src/classification-cascade.ts skill/dashboard-sync/src/classification-cascade.test.ts skill/dashboard-sync/test/fixtures/classification/
git commit -m "feat(orders): classification cascade (carrier → rule → category → llm → banding) + failure-case fixtures"
```

### Task 3.4: Repurpose the LLM extractor for physical/digital/unsure

**Files:**
- Modify: `skill/dashboard-sync/src/llm-extractor.ts` (`SYSTEM_PROMPT` at L60; `LLMExtractedFields` at L37)

- [ ] **Step 1: Write the failing test**

```typescript
// add to skill/dashboard-sync/src/orders.test.ts
import { parseClassificationFromLLM } from './llm-extractor';

test('parses physical/digital/confidence from LLM JSON', () => {
  const a = parseClassificationFromLLM('{"classification":"physical","confidence":0.91}');
  assert.deepEqual(a, { classification: 'physical', confidence: 0.91 });
  const b = parseClassificationFromLLM('{"classification":"digital","confidence":0.4}');
  assert.deepEqual(b, { classification: 'digital', confidence: 0.4 });
});

test('falls back to unsure on unparseable LLM output', () => {
  assert.deepEqual(parseClassificationFromLLM('not json'), { classification: 'unsure', confidence: 0 });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "classification from LLM"
```
Expected: FAIL — `parseClassificationFromLLM` not exported.

- [ ] **Step 3: Implement + update the prompt**

Add to `llm-extractor.ts`:
```typescript
export function parseClassificationFromLLM(raw: string): { classification: 'physical'|'digital'|'unsure'; confidence: number } {
  try {
    const o = JSON.parse(raw);
    const c = o.classification;
    if (c === 'physical' || c === 'digital' || c === 'unsure') {
      const conf = typeof o.confidence === 'number' ? Math.min(1, Math.max(0, o.confidence)) : 0;
      return { classification: c, confidence: conf };
    }
  } catch { /* fall through */ }
  return { classification: 'unsure', confidence: 0 };
}
```

Update `SYSTEM_PROMPT` to ask, in addition to the existing extraction, for a top-level `"classification": "physical"|"digital"|"unsure"` and `"confidence"`, with the rule: *physical = a tangible item will be shipped/delivered to a postal address; digital = nothing ships (downloads, subscriptions, reservations, tickets, statements, in-store receipts); unsure = genuinely ambiguous.* Keep the existing `is_purchase_confirmation` field for backward-compat during the transition (the cascade reads `classification`; legacy callers still read `is_purchase_confirmation`). Keep the R8/R10 `sanitizeForPrompt` + `<user-input>` wrapping for sender/subject/body.

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "classification from LLM"
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skill/dashboard-sync/src/llm-extractor.ts skill/dashboard-sync/src/orders.test.ts
git commit -m "feat(orders): LLM returns physical/digital/unsure + confidence; keep legacy field during transition"
```

### Task 3.5: Learning loop — write rule on review answer + retroactive sweep

**Files:**
- Modify: `skill/dashboard-sync/src/merchant-rules.ts`
- Test: extend `skill/dashboard-sync/src/orders.test.ts`

- [ ] **Step 1: Write the failing test (pure helper)**

```typescript
// add to skill/dashboard-sync/src/orders.test.ts
import { ruleFromReviewAnswer } from './merchant-rules';

test('maps a review answer to a merchant_rule spec on the most specific signal', () => {
  const r = ruleFromReviewAnswer(
    { senderEmail: 'orders@peakdesign.com', normalizedMerchant: 'peak design' },
    'yes_track',
  );
  assert.deepEqual(r, { match_kind: 'sender_email', match_value: 'orders@peakdesign.com', action: 'always_physical' });
});

test('no_package answer writes skip_purchase', () => {
  const r = ruleFromReviewAnswer(
    { senderEmail: null, normalizedMerchant: 'cleancloud' },
    'no_package',
  );
  assert.deepEqual(r, { match_kind: 'normalized_merchant', match_value: 'cleancloud', action: 'skip_purchase' });
});

test('bought_but_digital answer writes always_digital', () => {
  const r = ruleFromReviewAnswer(
    { senderEmail: 'do@apple.com', normalizedMerchant: 'apple' },
    'bought_but_digital',
  );
  assert.deepEqual(r, { match_kind: 'sender_email', match_value: 'do@apple.com', action: 'always_digital' });
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "review answer"
```
Expected: FAIL — `ruleFromReviewAnswer` not exported.

- [ ] **Step 3: Implement**

```typescript
// skill/dashboard-sync/src/merchant-rules.ts (append)
export type ReviewAnswer = 'yes_track' | 'no_package' | 'bought_but_digital';

export interface ReviewSubject {
  senderEmail: string | null;
  normalizedMerchant: string;
}

export interface MerchantRuleSpec {
  match_kind: 'sender_email' | 'sender_domain' | 'normalized_merchant';
  match_value: string;
  action: 'always_physical' | 'always_digital' | 'skip_purchase';
}

/** One review answer → one merchant_rule on the most specific reliable
 *  signal (sender email > domain > normalized merchant). One confirmation
 *  is enough for the physical/digital axis — the queue self-extinguishes. */
export function ruleFromReviewAnswer(subj: ReviewSubject, answer: ReviewAnswer): MerchantRuleSpec {
  const action: MerchantRuleSpec['action'] =
    answer === 'yes_track' ? 'always_physical'
    : answer === 'bought_but_digital' ? 'always_digital'
    : 'skip_purchase';

  if (subj.senderEmail) {
    return { match_kind: 'sender_email', match_value: subj.senderEmail.toLowerCase(), action };
  }
  return { match_kind: 'normalized_merchant', match_value: subj.normalizedMerchant, action };
}
```

Then add a DB function `applyReviewAnswer(userId, reviewItemId, answer)` that: (1) writes the rule via the existing `merchant_rules` insert path, (2) resolves the answered review item, (3) **retroactively sweeps** sibling `review_items` matching the same sender/merchant to `resolved`. This is the integration layer — exercise it through the existing `orders.test.ts` integration harness if one exists, else cover the pure `ruleFromReviewAnswer` here and verify the sweep manually against prod in Task 6.x.

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "review answer"
```
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add skill/dashboard-sync/src/merchant-rules.ts skill/dashboard-sync/src/orders.test.ts
git commit -m "feat(orders): one-answer learning — review answer → merchant_rule + retroactive sweep"
```

---

## Phase 4 — Poll-path repair + 3-tier ETA ladder

### Task 4.1: ETA ladder (pure)

**Files:**
- Create: `skill/dashboard-sync/src/eta-ladder.ts`
- Test: `skill/dashboard-sync/src/eta-ladder.test.ts`

- [ ] **Step 1: Write the failing test**

```typescript
// skill/dashboard-sync/src/eta-ladder.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveETA } from './eta-ladder';

test('email ETA beats 17track and heuristic', () => {
  const r = resolveETA({ email: '2026-05-12', seventeenTrack: '2026-05-15', heuristic: '2026-05-20' });
  assert.deepEqual(r, { eta_at: '2026-05-12', eta_source: 'email' });
});

test('17track used when email absent', () => {
  const r = resolveETA({ email: null, seventeenTrack: '2026-05-15', heuristic: '2026-05-20' });
  assert.deepEqual(r, { eta_at: '2026-05-15', eta_source: '17track' });
});

test('heuristic used when both absent', () => {
  const r = resolveETA({ email: null, seventeenTrack: null, heuristic: '2026-05-20' });
  assert.deepEqual(r, { eta_at: '2026-05-20', eta_source: 'heuristic' });
});

test('null when nothing available — never blanks anything', () => {
  assert.equal(resolveETA({ email: null, seventeenTrack: null, heuristic: null }), null);
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 ETA
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement**

```typescript
// skill/dashboard-sync/src/eta-ladder.ts
export interface ETATiers {
  email: string | null;          // parsed from shipping email
  seventeenTrack: string | null; // 17track estimated_delivery_date
  heuristic: string | null;      // carrier default-transit estimate
}

export interface ResolvedETA {
  eta_at: string;
  eta_source: 'email' | '17track' | 'heuristic';
}

/** First available tier wins. Returns null when no tier has a date —
 *  the caller must NOT blank an existing ETA on null (the poll path
 *  spreads `...(etaUpdate ?? {})`, so null = no-op). */
export function resolveETA(tiers: ETATiers): ResolvedETA | null {
  if (tiers.email) return { eta_at: tiers.email, eta_source: 'email' };
  if (tiers.seventeenTrack) return { eta_at: tiers.seventeenTrack, eta_source: '17track' };
  if (tiers.heuristic) return { eta_at: tiers.heuristic, eta_source: 'heuristic' };
  return null;
}
```

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 ETA
```
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add skill/dashboard-sync/src/eta-ladder.ts skill/dashboard-sync/src/eta-ladder.test.ts
git commit -m "feat(orders): 3-tier ETA ladder (email > 17track > heuristic), never blanks a higher tier"
```

### Task 4.2: Repair pollShipments selection + wire ETA ladder

**Files:**
- Modify: `skill/dashboard-sync/src/orders-autopilot.ts` (`getUndeliveredShipments`, `pollShipments` at L870, the `resolve17trackETA` call at L940)

- [ ] **Step 1: Write the failing test (selection predicate)**

```typescript
// add to skill/dashboard-sync/src/orders.test.ts
import { isPollable } from './orders-autopilot';

test('pollable = valid tracking, non-terminal status', () => {
  assert.equal(isPollable({ tracking_number: '1Z999AA10123456784', status: 'in_transit' }), true);
  assert.equal(isPollable({ tracking_number: '', status: 'in_transit' }), false);          // empty → never
  assert.equal(isPollable({ tracking_number: '1Z999AA10123456784', status: 'delivered' }), false); // terminal
  assert.equal(isPollable({ tracking_number: '7197712620 / 0019', status: 'in_transit' }), false);  // malformed (split upstream)
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 pollable
```
Expected: FAIL — `isPollable` not exported.

- [ ] **Step 3: Implement + use**

```typescript
// orders-autopilot.ts
const TERMINAL_STATUSES = new Set(['delivered', 'cancelled']);
const TRACKING_OK = /^[A-Za-z0-9]{6,40}$/;

export function isPollable(s: { tracking_number: string | null; status: string }): boolean {
  return !!s.tracking_number && TRACKING_OK.test(s.tracking_number) && !TERMINAL_STATUSES.has(s.status);
}
```

In `pollShipments`, replace the ad-hoc `isValidTrackingNumber` filter with `undelivered.filter(isPollable)` so terminal + malformed + empty are excluded uniformly (malformed should no longer exist post-Phase-2/5, but the guard is defense-in-depth). At the ETA step (~L940), build the `ETATiers` — `email` from the shipment's stored email-parsed ETA (new field read), `seventeenTrack` from `trackerData.eta_at`, `heuristic` from a carrier-transit helper — and call `resolveETA(tiers)`; pass `{ eta_at, eta_source }` into `updateShipmentFromTracker`. Keep the `...(etaUpdate ?? {})` spread so a null resolution never blanks an existing ETA.

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 pollable
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skill/dashboard-sync/src/orders-autopilot.ts skill/dashboard-sync/src/orders.test.ts
git commit -m "fix(orders): poll selection covers all valid non-terminal shipments; wire ETA ladder"
```

---

## Phase 5 — Backfill (clean the history; clean cut, not triage pile)

### Task 5.1: Backfill classifier for existing orders (dry-run)

**Files:**
- Create: `skill/dashboard-sync/src/backfill-tracker.ts`
- Test: `skill/dashboard-sync/src/backfill-tracker.test.ts`
- Modify: `skill/dashboard-sync/cli.js` (register `backfill-tracker --dry-run|--apply`)

- [ ] **Step 1: Write the failing test (the pure planning function)**

```typescript
// skill/dashboard-sync/src/backfill-tracker.test.ts
import test from 'node:test';
import assert from 'node:assert/strict';
import { planOrderBackfill } from './backfill-tracker';

test('hides hard-excluded merchants, keeps physical, archives unsure history', () => {
  const orders = [
    { id: '1', merchant_name: 'TAP Air Portugal', normalized_merchant: 'tap', sender: 'booking@flytap.com' },
    { id: '2', merchant_name: 'Peak Design', normalized_merchant: 'peak design', sender: 'orders@peakdesign.com' },
    { id: '3', merchant_name: 'Mystery Co', normalized_merchant: 'mystery co', sender: 'hi@mystery.io' },
  ];
  const plan = planOrderBackfill(orders);
  assert.equal(plan.find(p => p.id === '1')!.action, 'hide');     // airline
  assert.equal(plan.find(p => p.id === '2')!.action, 'keep');     // physical merchant
  assert.equal(plan.find(p => p.id === '3')!.action, 'archive');  // unsure history → archived, NOT queued
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 backfill
```
Expected: FAIL — module not found.

- [ ] **Step 3: Implement `planOrderBackfill`**

```typescript
// skill/dashboard-sync/src/backfill-tracker.ts
import { hardCategoryExclude } from './physical-vs-digital';

export interface BackfillOrder {
  id: string;
  merchant_name: string;
  normalized_merchant: string;
  sender: string | null;
}
export interface BackfillAction {
  id: string;
  action: 'keep' | 'hide' | 'archive';
  reason: string;
}

// A small allowlist of merchants we KNOW are physical (seed; grows via
// learned rules in steady state). Backfill keeps these; everything not
// hard-excluded and not known-physical is archived (history, not queued).
const KNOWN_PHYSICAL: ReadonlySet<string> = new Set([
  'peak design', 'notino', 'dak coffee roasters', 'lofree', 'mukama',
  'amazon', 'vista alegre', 'oura',
]);

export function planOrderBackfill(orders: BackfillOrder[]): BackfillAction[] {
  return orders.map(o => {
    const cat = hardCategoryExclude(o.sender);
    if (cat) return { id: o.id, action: 'hide', reason: `hard-category:${cat}` };
    if (KNOWN_PHYSICAL.has(o.normalized_merchant)) return { id: o.id, action: 'keep', reason: 'known-physical' };
    return { id: o.id, action: 'archive', reason: 'unsure-history' };
  });
}
```

The CLI subcommand fetches all orders, runs `planOrderBackfill`, and in `--dry-run` prints the counts (`keep N / hide M / archive K`); in `--apply` writes `hidden=true, hidden_reason=...` for hide+archive (archive uses `hidden_reason='archived_history'` so it's distinguishable + reversible). Never deletes.

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 backfill
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skill/dashboard-sync/src/backfill-tracker.ts skill/dashboard-sync/src/backfill-tracker.test.ts skill/dashboard-sync/cli.js
git commit -m "feat(orders): backfill planner — hide excluded, keep physical, archive unsure history (reversible)"
```

### Task 5.2: Shipment repair + unique index (run order matters)

**Files:**
- Modify: `skill/dashboard-sync/src/backfill-tracker.ts` (add `repairShipments`)
- Create: `supabase/migrations/20260508130000_shipments_unique_tracking.sql`

- [ ] **Step 1: Write the failing test (dedup/split planning)**

```typescript
// add to skill/dashboard-sync/src/backfill-tracker.test.ts
import { planShipmentRepair } from './backfill-tracker';

test('plans: delete empty-tracking, split multipiece, collapse dupes', () => {
  const ships = [
    { id: 'a', tracking_number: '' },
    { id: 'b', tracking_number: '7197712620 / 001959496839433548' },
    { id: 'c', tracking_number: 'JD0146' },
    { id: 'd', tracking_number: 'JD0146' },
  ];
  const plan = planShipmentRepair(ships);
  assert.equal(plan.deleteEmpty.length, 1);             // 'a'
  assert.equal(plan.split.length, 1);                   // 'b' → 2 numbers
  assert.deepEqual(plan.split[0].into, ['7197712620', '001959496839433548']);
  assert.equal(plan.collapseDupes.length, 1);           // {keep:'c', drop:['d']}
});
```

- [ ] **Step 2: Run to verify it fails**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "shipment repair\|plans:"
```
Expected: FAIL — `planShipmentRepair` not exported.

- [ ] **Step 3: Implement `planShipmentRepair` (uses `normalizeTrackingNumbers`)**

```typescript
import { normalizeTrackingNumbers } from './normalize-tracking';

export interface RepairShipment { id: string; tracking_number: string; }
export interface RepairPlan {
  deleteEmpty: { id: string }[];
  split: { id: string; into: string[] }[];
  collapseDupes: { keep: string; drop: string[] }[];
}

export function planShipmentRepair(ships: RepairShipment[]): RepairPlan {
  const deleteEmpty: { id: string }[] = [];
  const split: { id: string; into: string[] }[] = [];
  const byNumber = new Map<string, string[]>(); // tracking → [ids]

  for (const s of ships) {
    const norm = normalizeTrackingNumbers(s.tracking_number);
    if (norm.length === 0) { deleteEmpty.push({ id: s.id }); continue; }
    if (norm.length > 1) { split.push({ id: s.id, into: norm }); continue; }
    const arr = byNumber.get(norm[0]) ?? [];
    arr.push(s.id);
    byNumber.set(norm[0], arr);
  }

  const collapseDupes: { keep: string; drop: string[] }[] = [];
  for (const ids of byNumber.values()) {
    if (ids.length > 1) collapseDupes.push({ keep: ids[0], drop: ids.slice(1) });
  }
  return { deleteEmpty, split, collapseDupes };
}
```

The `--apply` path executes: delete empties → split (delete original, insert N) → collapse dupes (delete drops) → **then** apply the unique-index migration. The migration:

```sql
-- 20260508130000_shipments_unique_tracking.sql
-- Run ONLY after backfill-tracker --apply has de-duplicated + removed
-- empty-tracking shipment rows, else this index creation fails.
CREATE UNIQUE INDEX IF NOT EXISTS shipments_user_tracking_uniq
  ON public.shipments (user_id, tracking_number)
  WHERE tracking_number <> '';
```

- [ ] **Step 4: Run to verify pass**

```bash
cd skill/dashboard-sync && npm run build && npm test 2>&1 | grep -A2 "plans:"
```
Expected: PASS.

- [ ] **Step 5: Run the live backfill (operator step, after dry-run review)**

```bash
cd skill/dashboard-sync && npm run build
node cli.js backfill-tracker --dry-run    # eyeball counts
node cli.js backfill-tracker --apply      # then apply
```
Then apply the unique-index migration via MCP `apply_migration` (name `shipments_unique_tracking`). Verify: `SELECT count(*) FROM shipments WHERE tracking_number=''` → 0.

- [ ] **Step 6: Commit**

```bash
git add skill/dashboard-sync/src/backfill-tracker.ts skill/dashboard-sync/src/backfill-tracker.test.ts supabase/migrations/20260508130000_shipments_unique_tracking.sql
git commit -m "feat(orders): shipment repair (delete empties, split multipiece, collapse dupes) + unique index"
```

---

## Phase 6 — iOS two-zone surface

### Task 6.1: Zone-partitioned queries in OrdersService

**Files:**
- Modify: `ios/ThePerch/Sources/ThePerch/Services/OrdersService.swift` (`fetchOrdersTable` L90 filters out `hidden`; add zone partitioning)

- [ ] **Step 1: Write the failing test**

```swift
// ios/ThePerch/Tests/... (match the repo's existing iOS test target; if none,
// test via a pure partition function on OrderWithShipments)
func testZonePartition() {
    let inTransit = makeOWS(classification: "physical", trackingNumbers: ["1Z..."], status: "in_transit")
    let expected = makeOWS(classification: "physical", trackingNumbers: [], status: "ordered")
    let hidden = makeOWS(classification: "digital", trackingNumbers: [], status: "ordered", hidden: true)
    let zones = OrderZones.partition([inTransit, expected, hidden])
    XCTAssertEqual(zones.inTransit.count, 1)
    XCTAssertEqual(zones.expected.count, 1)
    XCTAssertTrue(zones.hidden.contains { $0.id == hidden.id })
}
```

- [ ] **Step 2: Run to verify it fails**

```bash
xcodebuild -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch -destination 'generic/platform=iOS Simulator' test 2>&1 | grep -i "OrderZones\|testZonePartition"
```
Expected: FAIL — `OrderZones` undefined. *(If the project has no test target, implement `OrderZones.partition` and verify via a `#Preview` + a debug assertion; note this deviation.)*

- [ ] **Step 3: Implement `OrderZones`**

```swift
// in OrdersService.swift or a new Models/OrderZones.swift
enum OrderZones {
    struct Zones { let inTransit: [OrderWithShipments]; let expected: [OrderWithShipments]; let hidden: [OrderWithShipments] }
    static func partition(_ all: [OrderWithShipments]) -> Zones {
        var inTransit: [OrderWithShipments] = []
        var expected: [OrderWithShipments] = []
        var hidden: [OrderWithShipments] = []
        for o in all {
            if o.order.hidden == true { hidden.append(o); continue }
            let hasLiveShipment = o.shipments.contains {
                !$0.trackingNumber.isEmpty && $0.status != "delivered" && $0.status != "cancelled"
            }
            if hasLiveShipment { inTransit.append(o) }
            else if o.order.classification == "physical" { expected.append(o) }
            // digital/unsure with no shipment → neither zone (never surfaced)
        }
        // In Transit sorted by soonest ETA first.
        inTransit.sort { ($0.primaryShipment?.eta ?? .distantFuture) < ($1.primaryShipment?.eta ?? .distantFuture) }
        return Zones(inTransit: inTransit, expected: expected, hidden: hidden)
    }
}
```

Add `hidden` + `classification` to the `Order` Codable model (matching the new columns). `fetchOrdersTable` adds `.eq("hidden", value: false)` for the default surface fetch (hidden rows only fetched by the Admin/audit view).

- [ ] **Step 4: Run to verify pass** — same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/ThePerch/Sources/ThePerch/Services/OrdersService.swift ios/ThePerch/Sources/ThePerch/Models/
git commit -m "feat(ios): zone-partitioned order queries (in-transit / expected / hidden)"
```

### Task 6.2: Two-zone Orders surface in HubTab + ETA-led rows

**Files:**
- Modify: `ios/ThePerch/Sources/ThePerch/Views/App/HubTab.swift` (Orders segment), `Views/Cards/OrderCard.swift`

- [ ] **Step 1: Implement the two zones**

Replace the flat order list in the Orders segment with two sections driven by `OrderZones.partition`: **In Transit** (header "In Transit", rows ETA-led) and **Expected** (header "Expected", muted styling). Use the R12 `PerchFormatters.currency` cache for any totals and the R12/R13 `ExternalURLOpener.openExternal` for tracking-link taps. Row layout leads with ETA: `Text(etaText).font(...)` where `etaText` = "Arrives Tue" / "Arrives in 2 days" derived from `shipment.eta`. Delivered rows show "Delivered ✓" and are excluded after 48h (filter `delivered_at > now - 48h`).

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch -configuration Debug -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ThePerch/Sources/ThePerch/Views/App/HubTab.swift ios/ThePerch/Sources/ThePerch/Views/Cards/OrderCard.swift
git commit -m "feat(ios): two-zone Orders surface (In Transit ETA-led + Expected muted)"
```

### Task 6.3: Review queue (Zone 3, renders only when non-empty) + three-way answer

**Files:**
- Create: `ios/ThePerch/Sources/ThePerch/Views/App/ReviewQueueSection.swift`
- Modify: `ios/ThePerch/Sources/ThePerch/Services/OrdersService.swift` (answer write), `Views/App/HubTab.swift` (mount the section)

- [ ] **Step 1: Implement**

`ReviewQueueSection` takes `[ReviewItem]` and renders **nothing** (`EmptyView()`) when the array is empty — the anti-dead-feature guarantee. When non-empty: a "Needs your call (N)" header + per-item card with the merchant/subject + three buttons: **Yes, track it** (`yes_track`), **Not a package** (`no_package`), **Bought it, but nothing ships** (`bought_but_digital`). Each calls `OrdersService.answerReview(itemId, answer)`, which POSTs to the merchant-rules write + resolves the item + sweeps siblings (server-side via the Phase-3.5 `applyReviewAnswer`; iOS just calls the RPC/endpoint and optimistically removes the item + its siblings from the local list).

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch -configuration Debug -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ThePerch/Sources/ThePerch/Views/App/ReviewQueueSection.swift ios/ThePerch/Sources/ThePerch/Services/OrdersService.swift ios/ThePerch/Sources/ThePerch/Views/App/HubTab.swift
git commit -m "feat(ios): review queue (renders only when non-empty) with three-way learning answer"
```

### Task 6.4: DeliveryHomeCard — imminent arrivals only, hide when empty

**Files:**
- Modify: `ios/ThePerch/Sources/ThePerch/Views/Cards/DeliveryHomeCard.swift`

- [ ] **Step 1: Implement**

Filter to the next 1–2 In-Transit shipments by soonest ETA. If none, return `EmptyView()` (card hides entirely — no empty state). Lead copy: "Peak Design arrives tomorrow." Reuse `OrderZones.partition(...).inTransit.prefix(2)`.

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch -configuration Debug -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -3
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add ios/ThePerch/Sources/ThePerch/Views/Cards/DeliveryHomeCard.swift
git commit -m "feat(ios): DeliveryHomeCard shows next 1-2 arrivals, hides when nothing in transit"
```

---

## Final verification (after all phases)

- [ ] `cd skill/dashboard-sync && npm run build && npm test` — all green.
- [ ] `xcodebuild -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch -configuration Debug -destination 'generic/platform=iOS Simulator' build` — `** BUILD SUCCEEDED **`, zero warnings.
- [ ] `cd /Users/faresende/Developer/ThePerch && gitleaks detect --no-banner --redact` — no leaks.
- [ ] Supabase MCP `get_advisors` (security) — unchanged 5-WARN baseline.
- [ ] Live sanity: `SELECT count(*) FROM shipments WHERE tracking_number=''` → 0; `SELECT count(*) FROM orders WHERE hidden=true` → the archived/hidden noise; the in-transit set has ETAs after the next poll cycle.
- [ ] Trigger one poll: `node cli.js poll-shipments --user_id <PERCH_USER_ID>` → updates land, ETA coverage improves.

---

## Self-Review (run by the plan author)

**Spec coverage:**
- §4 classification cascade → Tasks 3.1–3.4 ✓
- §4 learning loop / self-extinguish → Task 3.5 ✓
- §5 shipment-real-tracking invariant + dedup → Tasks 2.1, 2.2, 5.2 ✓
- §5 tracking normalization → Task 2.1 ✓
- §5 ETA ladder → Tasks 4.1, 4.2 ✓
- §5 merchant normalization → Task 2.3 ✓ (added during self-review)
- §6 poll repair → Task 4.2 ✓
- §7 two-zone surface + review queue + DeliveryHomeCard → Tasks 6.1–6.4 ✓
- §8 backfill (clean-cut, dry-run, hide-not-delete) → Tasks 5.1, 5.2 ✓
- §9 migrations → Tasks 1.1, 5.2 ✓

**Placeholder scan:** the iOS test steps hedge "if the project has no test target" — that's a real branch, not a placeholder; concrete fallback given. No TBDs.

**Type consistency:** `Classification` (`physical|digital|unsure`) consistent across cascade, LLM parse, backfill. `ReviewAnswer` (`yes_track|no_package|bought_but_digital`) consistent between Task 3.5 and Task 6.3. `eta_source` (`email|17track|heuristic`) consistent between migration, ETA ladder, poll. `merchant_rules.action` (`skip_purchase|always_physical|always_digital`) consistent between migration and Task 3.5.
