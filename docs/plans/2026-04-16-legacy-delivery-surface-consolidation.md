# Legacy Delivery Surface Consolidation Plan

> For Hermes: implement this in small steps; the goal is to eliminate `dashboard_records` delivery dependence from app-facing delivery UX.

Goal: make `orders` + `shipments` the only source of truth for tracked deliveries in the app.

Architecture:
- keep `dashboard_records` for generic cards
- introduce a shared delivery summary adapter derived from `OrderWithShipments`
- migrate home / widget / search / live-activity compatibility logic off `Record.asDelivery()` where possible
- only delete legacy `dashboard_records` delivery behavior after UI parity is verified

Tech stack:
- SwiftUI
- `OrdersService` / `OrdersViewModel`
- Supabase `orders` + `shipments`

---

## Phase 1: Introduce a shared adapter

1. Add a small adapter model that converts `OrderWithShipments` into a lightweight app-facing delivery summary.
2. Put it near `OrderModels.swift` or in a dedicated delivery-summary file.
3. Include:
   - id
   - title / merchant
   - carrier
   - tracking number
   - status
   - tracking URL
   - display date
   - item summary

## Phase 2: Migrate Home delivery surfaces

1. Update `HomeViewModel` active-delivery count to use `OrdersService`-backed summaries instead of `Record.asDelivery()`.
2. Update `DeliveryHomeCard` to accept the new summary model.
3. Verify Today/Home still renders active packages correctly.

## Phase 3: Migrate live activity sync

1. Replace `DashboardViewModel.deliveryRecords`-driven delivery live activity sync with an `orders`/`shipments`-derived path.
2. Keep status normalization in one place.
3. Verify only active non-delivered shipments create/update live activities.

## Phase 4: Migrate search/travel helpers

1. Audit `SearchView.swift` delivery-specific rendering and move it to the new summary model.
2. Audit travel-related delivery alerts that still rely on `Record.asDelivery()`.
3. Decide whether those alerts should remain generic-card based or become order-summary based.

## Phase 5: Remove legacy compatibility logic

1. Once app surfaces no longer depend on `dashboard_records` delivery rows, remove delivery-only compatibility branches.
2. Stop keeping `deliveryRecords` as a first-class `DashboardViewModel` property if it is no longer needed.
3. Remove remaining delivery-specific docs that still point agents at `dashboard_records`.

## Verification

- Build command:
  - `xcodebuild -project ios/ThePerch/ThePerch.xcodeproj -scheme ThePerch -configuration Debug -sdk iphonesimulator -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build`
- Manual checks:
  - Hub > Orders still shows tracked packages
  - Today/Home active delivery card matches Hub orders
  - search metadata still shows carrier/status
  - live activities update from orders/shipment state
  - no new tracking action requires `dashboard_records` delivery rows
