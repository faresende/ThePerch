# ThePerch surface cleanup audit — 2026-04-16

## Goal

Reduce stale, redundant, and misleading surfaces across the app, Supabase contract, and agent instructions so delivery tracking has one clear source of truth.

## What I found

### 1. Delivery data is split across two live models

There are currently two parallel delivery systems:

1. `dashboard_records` rows with `type=delivery`
2. dedicated `orders` + `shipments` tables

This creates operator confusion because the app does not use them uniformly.

### 2. The current user-facing Orders surface reads `orders` + `shipments`

`OrdersService.swift` reads:
- `orders`
- `shipments`

`HubTab` renders orders via `OrdersSectionContent` / `OrdersViewModel`.

So when someone says “add this tracked package to the app,” the canonical tracked-package path is now:
- `orders`
- `shipments`

### 3. Legacy delivery compatibility still exists through `dashboard_records`

Several app surfaces still decode `DeliveryData` from `dashboard_records`, including:
- Home quick-glance delivery count
- `DeliveryHomeCard`
- search result decoration
- travel alerts for deliveries while away
- delivery live activity sync hooks

So `dashboard_records` deliveries are still a compatibility surface, but not the canonical tracked-package model.

### 4. Instructions were stale and actively misleading

Multiple docs still implied that all delivery tracking should be written to `dashboard_records`, including:
- `claudinho-prompts.md`
- `docs/agent-integration.md`
- `backend/README.md`
- architecture / quick-start docs that still described `DeliveriesView`

That mismatch is exactly how the Hermes manual UPS entry was first written to the wrong place.

### 5. There were unused app surfaces left behind

These Swift files were still in the target but had no live references:
- `Views/Sections/DeliveriesView.swift`
- `ViewModels/SectionViewModel.swift`

They were leftovers from the older section-based navigation architecture.

### 6. Supabase still contains older/legacy table surfaces

There are at least three database-era concepts present:
- `public.records` — legacy
- `public.dashboard_records` — current generic card feed
- `public.orders` + `public.shipments` — current tracked-package model

`public.records` is still referenced by some older migrations and food-memory foreign keys, so it should not be dropped casually.

## Cleanup decisions made in this pass

### App
- Remove unused `DeliveriesView.swift`
- Remove unused `SectionViewModel.swift`
- Update architecture docs to reflect current shell (`Today`, `Health`, `Hub`, `Settings/Capture`) instead of the old horizontal Deliveries section model

### Instructions / docs
- Delivery tracking guidance should now say:
  - use `orders` + `shipments` for tracked packages
  - do not default to `dashboard_records` for new tracked deliveries
  - only use legacy `dashboard_records` delivery rows when explicitly needed for compatibility

### Supabase contract
- Keep `orders` + `shipments` as the canonical tracked-package source
- Mark `dashboard_records` delivery usage as legacy/compatibility
- Mark `public.records` as legacy and non-authoritative for new features

## Recommended next cleanup pass

This pass fixes the biggest instruction/structure mismatch. The next worthwhile cleanup would be a deeper product refactor:

1. move Home delivery summaries / widget delivery counts to derive from `orders` + `shipments`
2. stop depending on `dashboard_records` delivery cards for live delivery status
3. backfill or delete legacy `dashboard_records` delivery rows once all app surfaces read from the orders model
4. optionally deploy or remove inactive edge-function code such as `orders-ingest` if it remains intentionally unused

## Bottom line

Canonical tracked deliveries now mean:
- write to `orders`
- write to `shipments`

`dashboard_records` remains the generic card/event/measurement feed.

For deliveries, it should be treated as legacy compatibility until the remaining Home/widget/search surfaces are migrated.
