# Orders ETA — Design Spec

**Date:** 2026-04-27
**Status:** Approved, executing
**Builds on:** 2026-04-27-orders-corrections-and-rules-design.md (Phase 1 + 1.5 just shipped)

## Motivation

Orders today show carrier + status (in-transit, delivered, etc.) but no expected arrival date. The data is available — carrier shipping emails almost always say "Expected delivery: Tuesday, May 1", and 17track returns `estimated_delivery_date` for major carriers. Surfacing it transforms the OrderCard from "this is in flight somewhere" into "arrives Tuesday." Three concrete user moments improved:

1. Opening the Hub to see what's coming today/tomorrow without tapping each card.
2. Knowing when to start watching for a delivery (vs. ignoring a card that's still days out).
3. Spotting a problem early — "was due Tuesday, today is Thursday, where is it?"

## Architecture

ETA is sourced from two extractors and one polling integration. All three write to the same `shipments.eta_at` column via a shared resolver that applies a priority + recency rule.

```
Carrier shipping email      ┐
  → email-classifier regex   │
                             ├─→ resolveETAUpdate ─→ shipments.eta_at
17track per-shipment poll    │                       (+ eta_source, eta_recorded_at)
  → existing cron path       ┘
```

**Source priority** (highest first):
1. `17track` (live carrier-side data via API polling)
2. `carrier_email` (snapshot at email arrival, regex-extracted)

(`merchant_llm` from order-confirmation copy was scoped out — see "Out of scope" below.)

**Resolution rule:** higher priority always wins; same priority falls back to newer `eta_recorded_at`. Never overwrite non-null with null (handles 17track returning null for shipments where the carrier hasn't published an ETA).

**iOS rendering:** per-shipment `eta_at` is rolled up to a per-order display via a computed property — `OrderWithShipments.effectiveETA = earliest non-delivered ETA across this order's shipments`. Single chip on the OrderCard. Past ETAs render as "Was due Tuesday" (neutral past tense, no quantification, no red).

## Schema

Single migration, additive:

```sql
alter table public.shipments add column eta_at           timestamptz;
alter table public.shipments add column eta_source       text
  check (eta_source in ('17track', 'carrier_email'));
alter table public.shipments add column eta_recorded_at  timestamptz;

-- Partial index for the iOS rollup query.
create index shipments_active_eta_idx
  on public.shipments (order_id, eta_at)
  where eta_at is not null and delivered_at is null;
```

No new tables. The triplet on `shipments` carries everything.

## Out of scope

- **`merchant_llm` ETA extraction** from order-confirmation emails. Where it would have lived is awkward — purchase confirmations don't have shipments yet, so the ETA needs a row to attach to, and we agreed not to denormalize onto `orders`. Defer to Phase 1.5 if/when we want a placeholder-shipment pattern. Coverage drops from ~80% to ~70%; cleaner data flow.
- **Statistical-fallback projections** from historical "shipped→delivered" data. YAGNI. Honest empty-state beats a guess.
- **"Wrong ETA" correction surface** — Phase 2 of corrections-and-rules will fold this in alongside other rule-promotion logic.
- **Order-level rollup column** (`orders.eta_at`). iOS computed property is sufficient; denormalization deferred until performance demands it.

## Scanner pipeline

### `extract-eta.ts` (new module ~150 LOC)

Mirrors the shape of `tracking-candidates.ts`. Extracts ETA candidates from carrier email subject + body via regex; ranks each by source quality; `pickETA` returns the winner.

```typescript
export interface ETACandidate {
  date: Date;
  source: 'body_regex_near_keyword'    // matched within 30 chars of "delivery"/"arrival"
        | 'body_regex_isolated';        // bare date, no surrounding context
  rank: number;                          // 60 / 40 (mirrors tracking ranks)
  matchedText: string;
  bodyOffset: number;
}

export function extractETACandidates(subject: string, body: string): ETACandidate[];
export function pickETA(candidates: ETACandidate[], now: Date): ETACandidate | null;
```

**Patterns** (locale coverage matches existing scanner):
- EN: "Expected delivery: Tuesday, May 1" / "Estimated delivery: May 1, 2026" / "Arrives by May 1" / "Will arrive on May 1" / "Delivery date: 2026-05-01"
- PT: "estimada entrega"
- ES: "entrega prevista"
- DE: "lieferung am"
- FR: "livraison prévue"
- NL: "verwachte levering"

**Date parsing** uses native `Date.parse()` for English month-name and ISO formats. Multilingual months handled via a small lookup table (PT/ES/DE/FR/NL months → numeric).

**Sanity rejects:** any candidate parsing to a date >180 days in the future or already in the past relative to the email date. Stray order numbers / postal codes / prices misread as dates get filtered out.

### `resolveETAUpdate` (new module, shared resolver, ~30 LOC)

```typescript
const PRIORITY: Record<string, number> = {
  '17track': 100,
  'carrier_email': 50,
};

export function resolveETAUpdate(
  current: { eta_at: Date | null; eta_source: string | null; eta_recorded_at: Date | null },
  next:    { eta_at: Date;        eta_source: string;        eta_recorded_at: Date }
): typeof next | null {
  if (current.eta_source === null) return next;  // first-time write

  const newPri = PRIORITY[next.eta_source] ?? 0;
  const curPri = PRIORITY[current.eta_source] ?? 0;
  if (newPri > curPri) return next;
  if (newPri < curPri) return null;
  return next.eta_recorded_at > (current.eta_recorded_at ?? new Date(0)) ? next : null;
}
```

Returns `null` when no update should be written. Caller short-circuits the upsert.

### `extractShipmentFields()` adds `etaCandidates` to its return value (mirroring how Phase 1.5 added `trackingCandidates`):

```typescript
export function extractShipmentFields(...): {
  trackingNumber: string | null;
  carrier: string | null;
  status: string;
  shippedAt: Date | null;
  confidence: number;
  trackingCandidates: TrackingCandidate[];
  etaCandidates: ETACandidate[];   // NEW
}
```

### `handleShippingNotification` write path

```typescript
const shipmentETA = pickETA(fields.etaCandidates, now);
const next = shipmentETA ? {
  eta_at: shipmentETA.date,
  eta_source: 'carrier_email' as const,
  eta_recorded_at: now,
} : null;
const resolved = next ? resolveETAUpdate(currentShipment, next) : null;
await upsertShipment({ ..., ...(resolved ?? {}) });

// Trace: emit all candidates with selected/discarded markers.
for (const c of fields.etaCandidates) {
  trace.addETACandidate({
    date: c.date.toISOString(),
    source: c.source,
    selected: shipmentETA?.bodyOffset === c.bodyOffset,
    discarded_reason: shipmentETA?.bodyOffset === c.bodyOffset ? null : 'lower_rank_than_selected',
    matched_text: c.matchedText,
  });
}
```

### 17track polling (`pollAndUpdateShipment`)

After successful poll:

```typescript
const trackerETA = trackerResponse.estimated_delivery_date;
if (trackerETA) {
  const next = {
    eta_at: new Date(trackerETA),
    eta_source: '17track' as const,
    eta_recorded_at: new Date(),
  };
  const resolved = resolveETAUpdate(shipment, next);
  if (resolved) await updateShipmentFromTracker(shipment.id, { ...resolved, ... });
}
```

If 17track returns `null`, `resolveETAUpdate` returns null. Existing carrier-email ETA stays.

### `ParseTraceBuilder.addETACandidate` (Phase 1 extension)

`parse_trace.eta_candidates` array, mirrors `tracking_candidates`:

```typescript
eta_candidates: Array<{
  date: string;          // ISO
  source: string;
  selected: boolean;
  discarded_reason: string | null;
  matched_text: string;
}>;
```

iOS `ParseTraceSheet` walks the JSON dynamically — when `eta_candidates` appears in the trace, it renders automatically. No iOS changes for the sheet.

## iOS

### Shipment model

```swift
struct Shipment: Identifiable, Codable, Sendable, Equatable {
    // ... existing fields ...
    let etaAt: Date?

    enum CodingKeys: String, CodingKey {
        // ... existing keys ...
        case etaAt = "eta_at"
    }
}
```

`eta_source` and `eta_recorded_at` aren't surfaced in iOS — scanner-side bookkeeping only.

### Order rollup computed property

```swift
extension OrderWithShipments {
    var effectiveETA: Date? {
        shipments
            .filter { $0.status.lowercased() != "delivered" }
            .compactMap { $0.etaAt }
            .min()
    }
}
```

When all shipments are delivered, returns `nil` → no chip rendered (delivered status takes over).

### `ETACopy` formatter (~40 LOC)

```swift
func etaChipText(for date: Date, now: Date = .now) -> String { ... }
```

| Calendar day vs today | Future | Past |
|---|---|---|
| Today | "Arrives today" | "Arrives today" |
| ±1 day | "Arrives tomorrow" | "Was due yesterday" |
| 2-6 days | "Arrives Tuesday" | "Was due Tuesday" |
| 7+ days | "Arrives May 5" | "Was due May 5" |

(Today special-cased to "Arrives today" even when eta is technically slightly past — same calendar day = same day from user's POV.)

Locale-aware via `Calendar.autoupdatingCurrent` and `DateFormatter`.

### Chip placement (OrderCardV2 + OrderCard)

Inline with the status presentation row. Italic serif (Editorial Linen status copy style), color `palette.muted` for future ETAs, `palette.faint` for past ETAs (slightly more muted — informational, not actionable).

Example future: `Arrives Tuesday — DHL · in transit`
Example past:   `Was due Tuesday — DHL · in transit`

When `effectiveETA == nil`, the line just shows carrier + status as today. No "ETA pending" placeholder — quieter.

### OrdersService fetch

Verify the existing select either uses no-arg `.select()` (all columns, no change) or add `eta_at` to an explicit column list. Implementation-pass detail.

## Data flow — happy path

```
1. Carrier shipping email arrives (e.g. Body & Fit / DHL).
2. Scanner classifies as shipping_notification.
3. handleShippingNotification:
     a) extractShipmentFields → trackingCandidates + etaCandidates
     b) pickETA(etaCandidates, now) → winner candidate
     c) resolveETAUpdate(currentShipment, next) → resolved triplet
     d) upsertShipment with eta_at, eta_source='carrier_email', eta_recorded_at
     e) trace.addETACandidate for each candidate (selected + discards)
4. iOS next fetch: OrderWithShipments.effectiveETA computed → "Arrives Tuesday"
5. Cron: 17track polls 60min later. Returns estimated_delivery_date.
6. resolveETAUpdate(currentShipment, next='17track'): higher priority wins.
7. Shipment updated to 17track-sourced ETA.
8. iOS sees the updated date on next refresh.
```

## Errors & edge cases

- **Date parsing failure:** `extractETACandidates` skips candidates that can't be parsed. No throw.
- **Email date in the past:** sanity reject. Email parser doesn't propagate to candidate list.
- **17track returns same date repeatedly:** resolver's "newer recorded_at" rule still updates `eta_recorded_at` on each poll. Cheap; keeps freshness signal accurate. (Acceptable — could optimize later by skipping when `eta_at` is unchanged, but not worth the branching.)
- **Multi-shipment with one delivered + one pending:** `effectiveETA` filter excludes delivered, returns the pending one. Card shows the upcoming arrival. ✓
- **All shipments delivered:** `effectiveETA == nil`. No ETA chip. Status pill takes over. ✓
- **No ETA available for any shipment yet:** `effectiveETA == nil`. No chip. Card looks like today (carrier + status only).
- **Legacy shipments (eta_at NULL):** valid. Computed property handles via `compactMap`.

## Testing

**Scanner (Vitest / node:test):**
- Unit tests for `extractETACandidates`: 6 fixtures (1 per locale) + sanity-reject cases (>180 days, past dates).
- Unit tests for `resolveETAUpdate`: priority-up / priority-down / same-priority-newer / same-priority-older / first-write / null-overwrite-blocked.
- Integration: extend an existing carrier-email fixture with an ETA line; assert the resulting `parse_trace.eta_candidates` shape and the upserted `eta_at`/`eta_source`.

**iOS (Swift Testing):**
- `etaChipText` formatter: 6 cases (today/tomorrow/within-week-future/farther-future/yesterday/within-week-past).
- `OrderWithShipments.effectiveETA` rollup: 4 cases (single shipment, multi-shipment-mixed, all-delivered, none-set).

**Manual E2E:**
- Re-process a known carrier email through the autopilot tool; verify chip appears.
- Wait for 17track poll; verify chip updates if 17track has different ETA.

## Rollout

Single deploy. No feature flag.

DB migration first (idempotent — UI tolerates NULL `eta_at` via the computed-property `nil` fallback). Then app build → TestFlight smoke-test on device.

## Future-work breadcrumbs

- **Phase 1.5:** `merchant_llm` ETA extraction with placeholder-shipment pattern (creates a tracking-less shipment row at order time so the LLM-extracted ETA has somewhere to live).
- **Phase 2 (corrections-and-rules):** "Wrong ETA" correction action — folds into the existing corrections engine using `eta_candidates` from `parse_trace_snapshot`.
- **Optional polish:** subtle escalation copy when past-ETA + N days late (Q3's option C as a follow-up if user feedback says quantification helps).
