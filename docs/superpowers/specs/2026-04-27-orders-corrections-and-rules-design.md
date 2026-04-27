# Orders Corrections & Rules — Design Spec

**Date:** 2026-04-27
**Status:** Approved, executing Phase 1 + 1.5
**Sequencing:** Phase 1 → 1.5 now; Phase 2 deferred until ~1mo of corrections data; Phase 3 only if Phase 2 rules don't catch enough.

## Motivation

Three concrete misclassifications in the orders pipeline exposed a structural gap: there's no path for "user disagrees with parser" to become durable system improvement. Today, fixes are one-off code patches and don't accumulate into pattern-aware rules.

The bugs:
1. **Apple digital purchase** classified as physical-goods order (no shipping signal).
2. **Topfoams customer-satisfaction reply** parsed as a new order (it quoted the original order # in body).
3. **Body & Fit shipment** has wrong tracking number (email contains DHL header with the real number; scanner picked a different number from elsewhere in body via first-match-wins).

Common thread: parser made a confident decision that the user can see is wrong, but there was no surface to record the disagreement, and no audit trail to explain why the parser picked what it picked. Phase 1 builds both surfaces.

## Architecture

Three-layer mental model. **Phase 1 ships only the bottom layer.**

```
Layer 3: Reason  (LLM low-confidence fallback)         ← Phase 3, deferred
Layer 2: Distill (merchant_rules + promotion logic)    ← Phase 2, after ~1mo data
Layer 1: Capture (order_corrections + parse_trace)     ← Phase 1, this work
```

### Phase 1 deliverables

1. New table `order_corrections`
2. New JSONB column `orders.parse_trace`
3. New column `orders.dismissed_at` (nullable timestamptz)
4. Two SECURITY DEFINER RPCs: `record_order_correction`, `cancel_order_correction`
5. Scanner populates `parse_trace` on every parse via a `ParseTraceBuilder` accumulator
6. iOS swipe actions on OrderCard: "Not an order" / "Wrong tracking" / "Already delivered"
7. State transitions: soft-delete (status='dismissed_by_user') / null-tracking / mark-delivered
8. Undo toast (5s) for `not_an_order` corrections only
9. Long-press contextMenu surfaces `ParseTraceSheet` debug peek
10. Apple-digital + Topfoams-quoted-reply hand-fixes in scanner (validates trace shape)

### Phase 1.5 deliverable (ships next)

Tracking-candidate priority-rank-wins replacement for first-match-wins in `extractShipmentFields()`. Body & Fit fix.

### Out of scope (do not let creep in)

- `merchant_rules` table — Phase 2
- Rule-promotion logic ("N corrections → suggest rule") — Phase 2
- LLM low-confidence fallback — Phase 3
- Generalization to BioChecha / calendar — revisit when those have real consumers
- Touching `learned_senders`, `review_items`, or `recordClassification()` — they keep working as-is

### Reuse claim disposition

Explicit. We build orders-specific. The first generalization (when a second consumer arrives, e.g. BioChecha metric corrections) will be informed by a working implementation, not by speculation. YAGNI.

## Schema

### `order_corrections` (new table)

```sql
create table public.order_corrections (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid references auth.users(id) on delete cascade not null,
  order_id             uuid references public.orders(id) on delete set null,
  kind                 text not null check (kind in ('not_an_order','wrong_tracking','already_delivered')),
  source_email_ids     text[],
  parse_trace_snapshot jsonb,
  notes                text,
  created_at           timestamptz default now()
);

create index order_corrections_user_kind_created_idx
  on public.order_corrections (user_id, kind, created_at desc);

alter table public.order_corrections enable row level security;

create policy "owner select" on public.order_corrections
  for select using (auth.uid() = user_id);
create policy "owner insert" on public.order_corrections
  for insert with check (auth.uid() = user_id);
create policy "owner delete" on public.order_corrections
  for delete using (auth.uid() = user_id);
```

`parse_trace_snapshot` is a **copy** of the order's `parse_trace` at correction time — insulates rule-engine training data from later parser re-runs that might overwrite the live row.

### `orders` (additive columns)

```sql
alter table public.orders add column parse_trace jsonb;
alter table public.orders add column dismissed_at timestamptz;
```

Status values extend (no DB constraint change — already free text):
- `'dismissed_by_user'` — soft-deleted via "Not an order" correction
- `'digital'` — Apple-bug fix; digital purchase, no shipment expected

### `parse_trace` JSONB shape

```json
{
  "version": 1,
  "parsed_at": "2026-04-27T14:30:00Z",
  "scanner_version": "orders-autopilot@<git-sha>",
  "classifier": {
    "tier1": { "matched_keywords": ["shipped", "tracking"], "confidence": 0.72 },
    "llm":   { "invoked": true, "is_purchase": true, "confidence": 0.81 },
    "learned_sender": { "matched": true, "merchant": "Apple" },
    "short_circuited_by": null,
    "merchant_rule_applied": null
  },
  "merchant": {
    "selected": "Apple",
    "source": "learned_sender",
    "candidates": ["Apple", "iTunes Store", "App Store"]
  },
  "physical_vs_digital": {
    "decision": "physical",
    "signals": {
      "shipping_address_in_body": false,
      "digital_phrases_found": ["available in your library"],
      "tangible_keywords": []
    }
  },
  "tracking_candidates": [
    { "number": "00340...", "carrier": "dhl", "source": "body_html_link", "selected": true,  "discarded_reason": null },
    { "number": "JD0299...", "carrier": "ups", "source": "body_text_regex", "selected": false, "discarded_reason": "lower_rank_than_selected" }
  ],
  "source_email_ids": ["jmap-id-abc"]
}
```

Three deliberate choices:
- **Snapshot, not reference** — `parse_trace_snapshot` on `order_corrections` is a copy.
- **`physical_vs_digital` exists in trace even though no `orders` column tracks it** — new signal needed for Apple bug; trace records decision + signals so rule engine can later detect "physical w/ digital phrases" mis-classifications.
- **`tracking_candidates` is an array with `selected` flag + `discarded_reason`** — Body & Fit picked wrong because first-match-wins; trace makes the bug visible and accumulates training data for the picker.

### RPCs

```sql
create or replace function public.record_order_correction(
  p_order_id uuid,
  p_kind     text
) returns uuid
language plpgsql security definer
as $$
declare
  v_correction_id uuid;
  v_user_id uuid;
  v_trace jsonb;
  v_source_emails text[];
begin
  if p_kind not in ('not_an_order','wrong_tracking','already_delivered') then
    raise exception 'invalid correction kind: %', p_kind;
  end if;

  select user_id, parse_trace, source_email_ids
    into v_user_id, v_trace, v_source_emails
    from public.orders where id = p_order_id;

  if v_user_id is null then raise exception 'order not found'; end if;
  if v_user_id <> auth.uid() then raise exception 'unauthorized'; end if;

  insert into public.order_corrections
    (user_id, order_id, kind, source_email_ids, parse_trace_snapshot)
    values (v_user_id, p_order_id, p_kind, v_source_emails, v_trace)
    returning id into v_correction_id;

  case p_kind
    when 'not_an_order' then
      update public.orders set status='dismissed_by_user', dismissed_at=now() where id=p_order_id;
    when 'wrong_tracking' then
      update public.shipments set tracking_number=null, carrier=null, tracking_url=null where order_id=p_order_id;
    when 'already_delivered' then
      update public.orders set manual_delivered_at=now() where id=p_order_id;
  end case;

  return v_correction_id;
end $$;
```

```sql
create or replace function public.cancel_order_correction(
  p_correction_id uuid
) returns void
language plpgsql security definer
as $$
declare
  v_correction record;
begin
  select * into v_correction from public.order_corrections where id=p_correction_id;
  if v_correction.user_id is null then raise exception 'correction not found'; end if;
  if v_correction.user_id <> auth.uid() then raise exception 'unauthorized'; end if;

  case v_correction.kind
    when 'not_an_order' then
      update public.orders set status='ordered', dismissed_at=null
        where id=v_correction.order_id;
    when 'already_delivered' then
      update public.orders set manual_delivered_at=null
        where id=v_correction.order_id;
    when 'wrong_tracking' then
      -- tracking can't be perfectly restored without a re-scan; leave nulled, user re-scans
      null;
  end case;

  delete from public.order_corrections where id=p_correction_id;
end $$;
```

## Scanner pipeline (`orders-autopilot.ts`)

### `ParseTraceBuilder` (new module ~80 LOC)

```typescript
// orders-autopilot/parse-trace.ts
export class ParseTraceBuilder {
  constructor(scannerVersion: string) { ... }
  recordClassifier(tier1, llm, learnedSender, shortCircuitedBy?) { ... }
  recordMerchant(selected, source, candidates) { ... }
  recordPhysicalDigital(decision, signals) { ... }
  addTrackingCandidate({number, carrier, source, selected, discardedReason}) { ... }
  build(): ParseTrace { ... }
}
```

Constructed once per `processEmail()` invocation. Passed as parameter to pipeline functions. `build()` invoked before `upsertOrder()`. Not a global — keeps fixture tests trivial.

### `detectPhysicalVsDigital(subject, body)` (Apple-bug fix, ~60 LOC)

Runs after `is_purchase=true`. Signals:
- `shipping_address_in_body` — regex for postal codes / "Ship to:" / "Delivery address:"
- `digital_phrases_found[]` — whitelist scan: "your download", "available in your library", "redeem your code", "subscription is active", "license key", "access your purchase"
- `tangible_keywords[]` — reuse existing tier1 hits ("shipped", "tracking", "delivery", "package")

Decision rule (tunable constant):
```
digital  if  digital_phrases_found.length >= 1
         AND shipping_address_in_body == false
         AND tangible_keywords.length == 0
physical otherwise (default — preserves current behavior)
```

Side-effect: digital orders write with `status='digital'`, no shipment row created, hidden from default Today/Orders queries.

### `detectQuotedPriorOrder(subject, body, userId, merchantNorm)` (Topfoams-bug fix, ~40 LOC)

Runs **before** purchase classification — short-circuits if matched:

```
if subject =~ /^(re|fwd|aw|tr):\s/i
   AND body =~ /\b(order|pedido|bestelling|commande|bestellung)[\s#:]*(\d{4,})/i  (capture X)
   AND exists orders row for (user, merchant, order_number=X)
then classify as 'other', record trace.classifier.short_circuited_by='quoted_prior_order'
```

### Phase 1.5 — Tracking-candidate ranking

Replace first-match-wins in `extractShipmentFields()`:

| Rank | Source | Example |
|---|---|---|
| 100 | `carrier_specific_header` | `X-DHL-Tracking-Number` |
| 80  | `url_in_carrier_owned_link` | URL on `dhl.com`, `ups.com` |
| 60  | `body_regex_near_tracking_kw` | "Tracking number: XYZ" within 30 chars |
| 40  | `body_regex_isolated` | matches carrier format, no context |
| 20  | `url_in_third_party_redirect` | parcel-tracker.com |

Ties: (a) appears-earlier-in-body, (b) longest match. Non-winners get `discarded_reason: 'lower_rank_than_selected'` in trace.

### Phase 2 + 3 hooks (interface-only — no code in this work)

- **Phase 2 slot:** no-op `applyMerchantRules?.(emailContext)` call before classifier in `processEmail`. Returns null in Phase 1; Phase 2 implements. Trace records `classifier.merchant_rule_applied` when fired.
- **Phase 3 slot:** when tier1 + tier2 both yield `confidence < 0.5`, scanner emits `low_confidence_classification` flag in `recordClassification()`. Phase 3 wires this to LLM fallback that reads `order_corrections` rows as few-shot context.

## iOS

### OrdersView container migration

Wrap top-level orders list in `List`. Neutralize List chrome:

```swift
List {
  ForEach(orders) { order in
    OrderCard(order)
      .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
      .orderSwipeActions(order, service: ordersService)
  }
}
.listStyle(.plain)
.scrollContentBackground(.hidden)
.background(Color.linenBackground)
```

`allowsFullSwipe: false` on swipeActions to prevent accidental destructive triggers. Visual diff dialed in via Xcode Preview against current screenshot.

### Swipe actions (new view extension)

```swift
extension View {
  func orderSwipeActions(_ order: Order, service: OrdersService) -> some View {
    self.swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(role: .destructive) {
        Task { await service.recordCorrection(order, kind: .notAnOrder) }
      } label: { Label("Not an order", systemImage: "xmark.bin") }

      Button {
        Task { await service.recordCorrection(order, kind: .wrongTracking) }
      } label: { Label("Wrong tracking", systemImage: "shippingbox.and.arrow.backward") }
        .tint(.orange)

      Button {
        Task { await service.recordCorrection(order, kind: .alreadyDelivered) }
      } label: { Label("Already delivered", systemImage: "checkmark.circle") }
        .tint(.green)
    }
  }
}
```

### Service layer (`OrdersService` adds two methods)

```swift
enum CorrectionKind: String, Codable {
  case notAnOrder        = "not_an_order"
  case wrongTracking     = "wrong_tracking"
  case alreadyDelivered  = "already_delivered"
}

struct CorrectionReceipt: Identifiable {
  let id: UUID
  let kind: CorrectionKind
  let order: Order
}

func recordCorrection(_ order: Order, kind: CorrectionKind) async throws -> CorrectionReceipt
func cancelCorrection(_ receiptID: UUID) async throws
```

`recordCorrection` calls Supabase RPC `record_order_correction(order_id, kind)`. `cancelCorrection` calls `cancel_order_correction(correction_id)`. RPC choice is for atomicity (insert + state mutation in one round-trip), server-side snapshot (iOS doesn't need to know parse_trace shape), and undo symmetry.

### UndoCorrectionToast (`not_an_order` only)

5-second bottom toast:

```
┌──────────────────────────────────┐
│ Order dismissed.       [Undo]    │
└──────────────────────────────────┘
```

State machine in `OrdersService`:
- `recordCorrection(.notAnOrder, ...)` returns `CorrectionReceipt` and starts 5s timer
- Toast subscribes to `service.activeUndo: CurrentValueSubject<CorrectionReceipt?, Never>`
- Tap "Undo" → `cancelCorrection(receipt.id)` + toast dismisses
- Timer expires → toast fades, receipt cleared. Correction permanent (still recoverable via Past Orders).

`wrong_tracking` and `already_delivered` don't show toast — recoverable via re-scan or repeat-swipe.

### Long-press contextMenu changes

Today's menu has "Mark as Delivered" + "Undo Delivery Override". Both removed (now on swipe).

New menu:
```swift
.contextMenu {
  Button { showingParseTraceSheet = true } label: {
    Label("Why this is an order?", systemImage: "questionmark.circle")
  }
}
```

`ParseTraceSheet.swift` — Editorial Linen styled, renders `parse_trace` JSONB in human form:
- Classifier path: which tier matched, confidence, learned-sender hit
- Merchant: selected + alternatives
- Physical/digital decision + signals
- Tracking candidates with `selected`/`discarded_reason`
- Source email IDs with "Open in Fastmail" buttons (reuse universal-link helper)
- Empty state for legacy NULL-trace rows: "No parse trace — order created before traces were captured."

### Past Orders integration

`status='dismissed_by_user'` rows surface in Past Orders sheet with a "Dismissed" pill and a "Restore" tap action (calls `cancel_order_correction`).

## Data flow — happy path (swipe "Not an order")

```
1. User swipes left on OrderCard
2. swipeActions reveals "Not an order" button (red)
3. Tap → service.recordCorrection(order, .notAnOrder) fires async
4. iOS optimistically removes card from list (List rebuilds)
5. RPC `record_order_correction(orderId, 'not_an_order')`:
     a) Snapshot parse_trace into order_corrections.parse_trace_snapshot
     b) Set orders.status='dismissed_by_user', dismissed_at=now()
     c) Returns correction_id
6. UndoCorrectionToast appears (bottom, 5s) with correction_id
7a. User taps "Undo" → cancel_order_correction RPC → row restored, toast dismisses
7b. Timer expires → toast fades, correction permanent (recoverable via Past Orders)
```

## Errors & edge cases

- **RPC fails:** snackbar "Couldn't save correction. Try again." Card returns to list. RPC is transactional — no partial state.
- **Offline:** *flagged for implementation plan to resolve.* Reuse review-queue offline pattern if it exists; v1 fallback is "show error, retry on tap."
- **Race (scanner re-parses while user swipes):** RPC reads `parse_trace` at its read time. Snapshot captures whatever's current. Acceptable.
- **Legacy rows with NULL `parse_trace`:** valid. UI handles via empty-state in `ParseTraceSheet`.

## Testing

**Scanner (Vitest):** extend `orders-autopilot/__tests__/` with three new fixtures:
- Apple digital purchase email — assert `physical_vs_digital.decision='digital'`, `status='digital'`, no shipment row
- Topfoams CS reply quoting prior order# — assert classified as `other`, no order row created
- Body & Fit DHL+UPS dual-tracking email (Phase 1.5) — assert DHL wins, UPS in `tracking_candidates` with `discarded_reason='lower_rank_than_selected'`
- All three: assert `parse_trace` shape conforms to TypeScript type

**iOS (Swift Testing):**
- Snapshot tests for OrderCard swipe states
- Service-layer unit tests for `recordCorrection` / `cancelCorrection` happy + error paths (mock Supabase client)
- State-machine test for `UndoCorrectionToast` timer + cancel

**Manual E2E:** brief checklist doc — walk three swipe actions on staging data, confirm DB rows + UI state.

## Rollout

Single deploy. No feature flag.

DB migration order:
1. `parse_trace jsonb` + `dismissed_at timestamptz` on `orders`
2. `order_corrections` table + RLS + index
3. RPCs `record_order_correction` + `cancel_order_correction`

iOS deploy: migration first (idempotent) → then app build → TestFlight smoke-test on device.

## Future-work breadcrumbs

- **Phase 2** (after ~1mo data): `merchant_rules` table + promotion logic + Phase 2 scanner slot wired up. UI: a "Suggested rules" inbox surfacing high-confidence promotions for user confirmation.
- **Phase 3** (only if Phase 2 insufficient): LLM fallback wired to Phase 3 scanner slot, reads `order_corrections` as few-shot context.
- **Generalization** (when 2nd consumer arrives): factor `corrections` + `parse_trace` into a generic primitive. Likely shape: `domain_corrections (domain, source_id, original_decision, corrected_decision, ...)`. Decision deferred until BioChecha or calendar produces a real demand.
