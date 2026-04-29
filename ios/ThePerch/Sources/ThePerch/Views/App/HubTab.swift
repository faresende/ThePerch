import SwiftUI

// MARK: - Travel Timeline Entry (file-scope to be accessible by dayEntries helper)
private struct HubTimelineEntry: Identifiable {
    let id: String
    let record: Record
    let segment: ItineraryData
    let sortDate: Date
}

/// Hub tab — operational tools: Orders, Bookmarks, Calendar, Travel.
/// Uses a top segmented picker + paged content, mirroring HealthTab layout.
struct HubTab: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @Environment(TravelViewModel.self) private var travelViewModel
    @Environment(\.perchPalette) private var palette
    @State private var selectedSegment: HubSegment = Self.initialSegment()

    let onOpenProfile: () -> Void

    init(onOpenProfile: @escaping () -> Void = {}) {
        self.onOpenProfile = onOpenProfile
    }

    enum HubSegment: String, CaseIterable, Hashable, Identifiable {
        case orders    = "Orders"
        case bookmarks = "Bookmarks"
        case calendar  = "Calendar"
        case travel    = "Travel"
        var id: HubSegment { self }
    }

    private static func initialSegment() -> HubSegment {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uiDebugHubSegment"), arguments.indices.contains(index + 1) {
            let candidate = arguments[index + 1].lowercased()
            return HubSegment.allCases.first(where: { $0.rawValue.lowercased() == candidate }) ?? .orders
        }
        #endif

        return .orders
    }

    /// Segments to display — Travel only appears when an active trip exists.
    private var visibleSegments: [HubSegment] {
        var segments: [HubSegment] = [.orders, .bookmarks, .calendar]
        if travelViewModel.currentTrip != nil {
            segments.append(.travel)
        }
        return segments
    }

    /// Icon for each Hub segment — minimal line icons (SF Symbol names
    /// chosen to match the handoff's glyph intent: box / bookmark /
    /// calendar grid / paper plane).
    private func icon(for segment: HubSegment) -> String {
        switch segment {
        case .orders:    return "shippingbox"
        case .bookmarks: return "bookmark"
        case .calendar:  return "calendar"
        case .travel:    return "paperplane"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Sticky header block: ChromeRow + PillNav
                VStack(spacing: 0) {
                    PerchChromeRow(onBack: nil, onAvatar: onOpenProfile)

                    PerchPillNav(
                        items: visibleSegments.map {
                            .init(option: $0, label: $0.rawValue, systemImage: icon(for: $0))
                        },
                        selection: $selectedSegment
                    )
                }
                .background(palette.bg)
                .padding(.top, 54)

                // Error banner — below pill nav so it doesn't break the sticky unit
                if dashboardViewModel.error != nil {
                    ErrorBanner(
                        message: "Failed to load hub data",
                        retryAction: { Task { await dashboardViewModel.loadDashboard(forceRefresh: true) } },
                        onDismiss: { dashboardViewModel.clearError() }
                    )
                    .padding(.horizontal, PerchTheme.Spacing.screenHorizontal)
                    .padding(.top, PerchTheme.Spacing.small)
                }

                // Paged segment content.
                //
                // `.ignoresSafeArea(edges: .bottom)` lets this inner page
                // TabView extend under the main tab bar. Without it, the
                // inner TabView stops at the system tab bar's safe-area
                // inset, leaving a flat strip of `palette.bg` visible
                // through the tab bar's glass — which reads as a solid box
                // instead of glass. Each `hubPage`'s ScrollView already has
                // a `shellContentInsetHeight` bottom spacer so visible
                // content stops above the tab bar; only scroll geometry
                // extends beneath it to feed the glass.
                TabView(selection: $selectedSegment) {
                    hubPage { LazyView { OrdersSectionContent() } }
                        .tag(HubSegment.orders)

                    hubPage { LazyView { BookmarksSectionContent() } }
                        .tag(HubSegment.bookmarks)

                    hubPage { LazyView { CalendarSectionContent() } }
                        .tag(HubSegment.calendar)

                    if travelViewModel.currentTrip != nil {
                        hubPage { LazyView { TravelSectionContent() } }
                            .tag(HubSegment.travel)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onChange(of: dashboardViewModel.travelRecords) { _, newRecords in
            travelViewModel.records = newRecords
            // If the active trip disappears while Travel is selected, fall back to Orders
            if travelViewModel.currentTrip == nil && selectedSegment == .travel {
                selectedSegment = .orders
            }
        }
        .onAppear {
            if !dashboardViewModel.travelRecords.isEmpty {
                travelViewModel.records = dashboardViewModel.travelRecords
            }
        }
    }

    /// Wraps section content in a refreshable ScrollView with the active
    /// palette's page background so sections inherit the time-of-day tint.
    @ViewBuilder
    private func hubPage<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            content()
            Color.clear.frame(height: PerchTheme.TabBar.shellContentInsetHeight)
        }
        .scrollContentBackground(.hidden)
        .background(palette.bg)
        .refreshable {
            PerchHaptics.medium()
            await dashboardViewModel.loadDashboard(forceRefresh: true)
            PerchHaptics.success()
        }
    }
}

// MARK: - Orders Section Content — Sections v2

/// One card per active shipment. Retailer kicker + italic item summary
/// + serif price + StageStepper hero + tracking footer with "Track →"
/// link. Delivered and issue orders collapse to a compact "Past
/// orders →" footer link for now.
private struct OrdersSectionContent: View {
    @Environment(\.perchPalette) private var palette
    @Environment(DashboardViewModel.self) private var dashboardViewModel
    @State private var viewModel = OrdersViewModel()
    /// ID of the currently-expanded order card. nil when no card is
    /// expanded. Mirrors the workout-card pattern: parent owns
    /// expansion state, only one card open at a time.
    @State private var expandedOrderId: UUID?
    /// Same shape, separate state for the review-queue cards. Order
    /// cards and review cards expand independently — collapsing one
    /// doesn't collapse the other.
    @State private var expandedReviewId: UUID?
    /// Modal sheet flag for the "Past orders →" drill-in. Presents
    /// the full OrdersView (which has Active / Issues / Delivered /
    /// Needs review sections) over the Hub.
    @State private var showingPastOrders = false

    private var active: [OrderWithShipments] { viewModel.activeOrders }
    private var issues: [OrderWithShipments] { viewModel.issueOrders }

    /// Toggle expansion for a given order. Tap an open card → close;
    /// tap a different card → move expansion there.
    private func toggleExpanded(_ order: OrderWithShipments) {
        PerchMotion.withOptionalAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if expandedOrderId == order.id {
                expandedOrderId = nil
            } else {
                expandedOrderId = order.id
            }
        }
    }

    /// Same pattern, separate state for review-queue cards.
    private func toggleExpandedReview(_ item: ReviewItem) {
        PerchMotion.withOptionalAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if expandedReviewId == item.id {
                expandedReviewId = nil
            } else {
                expandedReviewId = item.id
            }
        }
    }

    /// Sum of active order totals for the aside.
    private var inFlightLabel: String? {
        let totals = active.compactMap { $0.order.total }
        guard !totals.isEmpty else { return nil }
        let sum = totals.reduce(Decimal(0), +)
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = active.first?.order.currency ?? "EUR"
        fmt.maximumFractionDigits = 0
        return fmt.string(from: sum as NSDecimalNumber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                kicker: orderKicker,
                title: orderTitle,
                aside: inFlightLabel.map { "\($0)\nin flight" }
            )

            if viewModel.isLoading && viewModel.orders.isEmpty {
                SkeletonCardsSection(count: 2)
            } else if let error = viewModel.error, viewModel.orders.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "Orders backend unavailable",
                    subtitle: error
                )
            } else if active.isEmpty && issues.isEmpty && viewModel.orders.isEmpty {
                EmptyStateView(
                    icon: "cart",
                    title: "No orders yet",
                    subtitle: "Purchase confirmations and tracked shipments will show up here once Orders Autopilot has something to merge."
                )
            } else {
                ForEach(active) { order in
                    Button {
                        PerchHaptics.light()
                        toggleExpanded(order)
                    } label: {
                        OrderCardV2(
                            order: order,
                            featured: order.id == active.first?.id,
                            isExpanded: expandedOrderId == order.id,
                            onMarkDelivered: { order in
                                Task { await viewModel.markAsDelivered(order) }
                            },
                            onUndoDelivered: { order in
                                Task { await viewModel.undoDelivered(order) }
                            },
                            // Phase 1 corrections: long-press surfaces
                            // three correction items. Each calls the
                            // record_order_correction RPC via the
                            // viewModel and triggers the matching
                            // state transition.
                            onCorrection: { order, kind in
                                Task { await viewModel.recordCorrection(order, kind: kind) }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }

                ForEach(issues) { order in
                    Button {
                        PerchHaptics.light()
                        toggleExpanded(order)
                    } label: {
                        OrderCardV2(
                            order: order,
                            featured: false,
                            isExpanded: expandedOrderId == order.id,
                            onMarkDelivered: { order in
                                Task { await viewModel.markAsDelivered(order) }
                            },
                            onUndoDelivered: { order in
                                Task { await viewModel.undoDelivered(order) }
                            },
                            onCorrection: { order, kind in
                                Task { await viewModel.recordCorrection(order, kind: kind) }
                            }
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Inline review queue — emails the autopilot couldn't
                // confidently classify. Lives at the bottom of the
                // active orders list so the user sees pending decisions
                // alongside their tracked stuff. Hidden when empty.
                // Cards expand on tap to reveal the autopilot's reasoning,
                // best-guess fields, and a Fastmail deep-link.
                if !viewModel.reviewItems.isEmpty {
                    HubReviewQueueSection(
                        items: viewModel.reviewItems,
                        resolvingIds: viewModel.resolvingReviewIds,
                        expandedReviewId: expandedReviewId,
                        onToggleExpanded: { item in toggleExpandedReview(item) },
                        onConfirm: { item in Task { await viewModel.confirmReviewItem(item) } },
                        onDismiss: { item in Task { await viewModel.dismissReviewItem(item) } }
                    )
                    .padding(.top, 8)
                }

                if !viewModel.deliveredOrders.isEmpty {
                    Button {
                        PerchHaptics.light()
                        showingPastOrders = true
                    } label: {
                        Text("Past orders →")
                            .font(.system(size: 13))
                            .tracking(0.3)
                            .foregroundStyle(palette.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                }
            }

            Color.clear.frame(height: PerchTheme.TabBar.shellContentInsetHeight)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
        .sheet(isPresented: $showingPastOrders) {
            // Sheet-presents the full Orders surface (Active / Issues /
            // Delivered / Needs review). Wrapped in a NavigationStack
            // so we can hang an explicit X close button off the top
            // toolbar — drag-to-dismiss alone is too easy to miss when
            // the sheet's inner ScrollView is at the top of its
            // content. Reload on dismiss so the Hub reflects any
            // changes the user made (mark delivered, etc.).
            PastOrdersSheet(onDismiss: { showingPastOrders = false })
                .onDisappear { Task { await viewModel.loadOrders(forceRefresh: true) } }
        }
        // Hydrate from DashboardViewModel's already-fetched trackedOrders
        // instead of firing a fresh network call on first mount. Was the
        // main cause of the 1-2s first-tap lag when switching to the
        // Orders chip. Falls back to the VM's own loadOrders only if the
        // dashboard hasn't populated them yet (unlikely in practice).
        .task {
            if !dashboardViewModel.trackedOrders.isEmpty {
                viewModel.orders = dashboardViewModel.trackedOrders
            } else if viewModel.orders.isEmpty {
                await viewModel.loadOrders()
            }
        }
        .onChange(of: dashboardViewModel.trackedOrders) { _, new in
            viewModel.orders = new
        }
        // Phase 1 corrections: undo toast for `.notAnOrder` swipes.
        // Toast lives at the OrdersSectionContent root (not the row)
        // so it doesn't get clipped by the page TabView and stays
        // visible while the user scrolls the orders list.
        .undoCorrectionToast(receipt: viewModel.activeUndoReceipt) {
            Task { await viewModel.cancelActiveUndo() }
        }
    }

    private var orderKicker: String {
        let count = active.count + issues.count
        let word = count == 1 ? "shipment" : "shipments"
        return count == 0 ? "ORDERS" : "ACTIVE · \(count) \(word.uppercased())"
    }

    private var orderTitle: String {
        let count = active.count
        if count == 0 { return "Nothing in flight." }
        if count == 1 { return "One arriving soon." }
        if count == 2 { return "Two arriving this week." }
        return "\(count) shipments in flight."
    }
}

/// v2 Order card: retailer kicker · italic merchant-item line · serif
/// price · four-stage stepper · tracking + Track → footer. No nested
/// sub-cards (old design had a tracking card inside an order card);
/// the tracking strip now sits under a soft divider.
private struct OrderCardV2: View {
    @Environment(\.perchPalette) private var palette

    let order: OrderWithShipments
    let featured: Bool
    /// Whether the items section is expanded. Owned by the parent
    /// (HubTab) so only one card is expanded at a time, mirroring
    /// the workout-card pattern.
    var isExpanded: Bool = false
    /// Fires from the long-press context menu's "Mark as Delivered"
    /// action. Receives the canonical OrderWithShipments so the
    /// caller can hand it to the appropriate service. Optional so
    /// existing call sites that don't wire it stay compiling.
    ///
    /// (Was previously bound to a small checkmark icon in the footer
    /// — removed because the icon was too easy to false-tap; users
    /// were accidentally marking active orders delivered while
    /// scrolling. Long-press is the iOS-idiomatic affordance and
    /// requires deliberate intent.)
    var onMarkDelivered: ((OrderWithShipments) -> Void)? = nil
    /// Long-press action to undo a manual delivery override.
    var onUndoDelivered: ((OrderWithShipments) -> Void)? = nil
    /// Phase 1 corrections-and-rules: long-press to record a
    /// correction. Three kinds: not_an_order (destructive),
    /// wrong_tracking, already_delivered. Surfaced as menu items
    /// (rather than swipe) because the orders list lives inside
    /// HubTab's page TabView and its horizontal pan eats swipe
    /// gestures cleanly.
    var onCorrection: ((OrderWithShipments, CorrectionKind) -> Void)? = nil

    /// Phase 1 corrections: parse-trace debug peek presented from the
    /// long-press menu. Always available (works on any card).
    @State private var showingParseTrace = false

    private var stageIndex: Int {
        // Map effective status → stepper index (0=Ordered, 1=Shipped,
        // 2=In transit, 3=Delivered).
        switch order.effectiveStatus.lowercased() {
        case "ordered", "processing", "pending", "confirmed": return 0
        case "shipped", "label_created": return 1
        case "in_transit", "out_for_delivery", "transit": return 2
        case "delivered", "completed": return 3
        default: return 0
        }
    }

    private var etaText: String {
        let f = PerchFormatters.shortDateUK
        if order.effectiveStatus == "delivered" {
            return "Arrived \(f.string(from: order.displayDate))"
        }
        // Phase 1 ETA: prefer the real expected-delivery date (from
        // carrier-email regex / 17track polling) over the order's
        // last-updated timestamp. Locale-aware copy via ETAChipText.
        // Falls back to "Updated <date>" when no shipment has an ETA
        // yet (pre-shipping-email gap).
        if let eta = order.effectiveETA {
            return ETAChipText.text(for: eta)
        }
        return "Updated \(f.string(from: order.displayDate))"
    }

    /// Whether the current etaText represents a past-due ETA. Drives
    /// the muted-vs-quietly-muted color treatment so past-due reads
    /// as "informational, not actionable."
    private var etaIsPastDue: Bool {
        guard order.effectiveStatus != "delivered",
              let eta = order.effectiveETA else { return false }
        return ETAChipText.isPastDue(eta)
    }

    private var priceText: String {
        guard let total = order.order.total else { return "—" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.currencyCode = order.order.currency
        return fmt.string(from: total as NSDecimalNumber) ?? "\(total)"
    }

    private var trackingText: String {
        guard let shipment = order.primaryShipment else {
            return "Order \(order.order.orderNumber)"
        }
        return "\(shipment.carrier) · \(shipment.trackingNumber)"
    }

    var body: some View {
        PerchSectionCard(padding: featured ? 22 : 18) {
            // Hierarchy: merchant is the editorial hero (big serif
            // italic, ink color), total sits quietly underneath in
            // small mono muted. Mirrors Cards/OrderCard.swift on the
            // Orders tab so the visual treatment is consistent
            // app-wide. Was previously a small kicker + big italic
            // price, which read as "the price is the most important
            // thing about this order" — wrong; the merchant is what
            // the user thinks about first.
            HStack(alignment: .firstTextBaseline) {
                Text(order.order.merchant)
                    .font(.system(size: featured ? 26 : 22, weight: .semibold, design: .serif).italic())
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                Spacer(minLength: 8)
                Text(etaText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(etaIsPastDue ? palette.faint : palette.muted)
            }
            .padding(.bottom, 4)

            // Total price now reads as supporting detail rather than
            // headline. Keeps it visible (you do want to see it at a
            // glance) but it no longer dominates the merchant name.
            Text(priceText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(palette.muted)
                .padding(.bottom, 18)

            PerchStageStepper(
                stages: ["Ordered", "Shipped", "In transit", "Delivered"],
                currentIdx: stageIndex
            )
            .padding(.horizontal, 2)
            .padding(.bottom, 14)

            PerchSoftDivider()

            HStack(spacing: 12) {
                Text(trackingText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()

                // (Mark-as-delivered moved to long-press context menu —
                // the inline checkmark icon was too easy to false-tap.
                // See contextMenu modifier on the outer card body.)

                if let shipment = order.primaryShipment,
                   let url = shipment.resolvedTrackingURL {
                    Button {
                        UIApplication.shared.open(url)
                    } label: {
                        HStack(spacing: 5) {
                            Text("Track")
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.ink)
                    }
                    .buttonStyle(.plain)
                }

                // Chevron — discoverability hint for tap-to-expand.
                // Hidden when there are no items, since there's nothing
                // to reveal. Rotates 180° when expanded.
                if !order.items.isEmpty {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.faint)
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
            }
            .padding(.top, 12)

            // Expanded items section. Same content as Cards/OrderCard.swift
            // on the Orders tab — name on the left, qty × unit price on
            // the right, mono pricing for column alignment.
            if isExpanded && !order.items.isEmpty {
                PerchSoftDivider()
                    .padding(.top, 4)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("ITEMS")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(palette.muted)
                        Spacer()
                        Text("\(order.items.count)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.faint)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(order.items) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(item.displayQuantity)×")
                                    .font(.system(size: 13, design: .monospaced))
                                    .foregroundStyle(palette.muted)
                                    .frame(width: 24, alignment: .leading)

                                Text(item.name)
                                    .font(.system(size: 14, weight: .regular, design: .serif).italic())
                                    .foregroundStyle(palette.ink)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                if !item.displayUnitPrice.isEmpty {
                                    Text(item.displayUnitPrice)
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(palette.muted)
                                }
                            }
                        }
                    }

                    if !order.order.orderNumber.isEmpty {
                        HStack {
                            Text("ORDER #")
                                .font(.system(size: 10))
                                .tracking(0.6)
                                .foregroundStyle(palette.faint)
                            Text("#\(order.order.orderNumber)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(palette.muted)
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Long-press menu: the safe way to mark an order delivered or
        // undo a previous override. Replaces the inline checkmark icon
        // that lived in the footer — that icon was too easy to
        // false-tap (caught in the wild: 4 Amazon orders accidentally
        // marked delivered while the user was scrolling).
        .contextMenu {
            if order.order.isManuallyDelivered {
                if onUndoDelivered != nil {
                    Button(role: .destructive) {
                        onUndoDelivered?(order)
                    } label: {
                        Label("Undo Delivery Override", systemImage: "clock.arrow.circlepath")
                    }
                }
            } else if onMarkDelivered != nil {
                Button {
                    onMarkDelivered?(order)
                } label: {
                    Label("Mark as Delivered", systemImage: "checkmark.circle.fill")
                }
            }

            // Phase 1 corrections-and-rules: three menu items inline
            // (no Section — SwiftUI contextMenu builder doesn't accept
            // Section). Each calls record_order_correction RPC +
            // applies the matching state transition.
            if let onCorrection {
                Button {
                    onCorrection(order, .alreadyDelivered)
                } label: {
                    Label(CorrectionKind.alreadyDelivered.actionLabel,
                          systemImage: CorrectionKind.alreadyDelivered.actionSymbol)
                }
                Button {
                    onCorrection(order, .wrongTracking)
                } label: {
                    Label(CorrectionKind.wrongTracking.actionLabel,
                          systemImage: CorrectionKind.wrongTracking.actionSymbol)
                }
                Button(role: .destructive) {
                    onCorrection(order, .notAnOrder)
                } label: {
                    Label(CorrectionKind.notAnOrder.actionLabel,
                          systemImage: CorrectionKind.notAnOrder.actionSymbol)
                }
            }

            // Parse-trace debug peek. Always shown so the trace is
            // reachable on every card, not gated on delivery state.
            Button {
                showingParseTrace = true
            } label: {
                Label("Why this is an order?", systemImage: "questionmark.circle")
            }
        }
        .sheet(isPresented: $showingParseTrace) {
            ParseTraceSheet(
                orderId: order.id,
                orderMerchant: order.order.merchant
            )
        }
    }

    /// Produce the italic "items" line. We don't always have parsed
    /// items so we lean on merchant + order number as a fallback.
    private func itemsSummary(_ order: OrderWithShipments) -> String {
        let number = order.order.orderNumber
        if !number.isEmpty && number.count < 40 {
            return "Order \(number) from \(order.order.merchant)"
        }
        return order.order.merchant
    }
}


// MARK: - Hub Review Queue
//
// Sits at the bottom of the Hub's Orders section. Each row is a
// shared `ReviewItemCard` (Views/Cards/ReviewItemCard.swift) wrapped
// in a Button so the whole card is a tap target for expand/collapse.
// Tap-to-expand reveals the autopilot's reasoning, its best-guess
// fields, and a Fastmail deep-link.

private struct HubReviewQueueSection: View {
    @Environment(\.perchPalette) private var palette

    let items: [ReviewItem]
    let resolvingIds: Set<UUID>
    let expandedReviewId: UUID?
    let onToggleExpanded: (ReviewItem) -> Void
    let onConfirm: (ReviewItem) -> Void
    let onDismiss: (ReviewItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("NEEDS REVIEW")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(palette.muted)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.faint)
            }
            .padding(.horizontal, 4)

            VStack(spacing: 10) {
                ForEach(items) { item in
                    Button {
                        PerchHaptics.light()
                        onToggleExpanded(item)
                    } label: {
                        ReviewItemCard(
                            item: item,
                            isExpanded: expandedReviewId == item.id,
                            isResolving: resolvingIds.contains(item.id),
                            onConfirm: { onConfirm(item) },
                            onDismiss: { onDismiss(item) }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Past Orders Sheet
//
// Modal wrapper around OrdersView used by the Hub's "Past orders →"
// link. Adds an X close button in the top toolbar so users have an
// obvious way out — swipe-to-dismiss alone is too easy to miss when
// the inner ScrollView is at top.

private struct PastOrdersSheet: View {
    @Environment(\.perchPalette) private var palette

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            OrdersView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        // Plain "Done" text button — iOS-native for
                        // modal-sheet dismissal (CaptureSheet uses
                        // the same pattern). Lighter visual weight
                        // than xmark.circle.fill, scales with Dynamic
                        // Type, integrates with the toolbar
                        // typography system. Tinted in `palette.kinetic`
                        // to match the rest of the app's primary
                        // actions (Track →, Add as order).
                        Button {
                            PerchHaptics.light()
                            onDismiss()
                        } label: {
                            Text("Done")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.kinetic)
                        }
                        .accessibilityLabel("Close past orders")
                    }
                }
                .toolbarBackground(palette.bg, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Bookmarks Section Content — Sections v2

/// Subtle segmented control for source (Karakeep ↔ Paperless), then
/// all bookmarks stacked inside a single card with hairline dividers
/// between rows — not one card per bookmark.
private struct BookmarksSectionContent: View {
    @Environment(\.perchPalette) private var palette
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var source: BookmarkSource = .karakeep

    private var records: [Record] { dashboardViewModel.bookmarkRecords }

    private var bookmarks: [(Record, BookmarkData)] {
        records.compactMap { r -> (Record, BookmarkData)? in
            guard let b = r.asBookmark() else { return nil }
            guard (b.source ?? .karakeep) == source else { return nil }
            return (r, b)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                kicker: bookmarkKicker,
                title: bookmarkTitle,
                aside: unreadLabel
            )

            BookmarksSourceSwitch(source: $source,
                                   karakeepCount: countBySource(.karakeep),
                                   paperlessCount: countBySource(.paperless))

            if dashboardViewModel.isLoading && records.isEmpty {
                SkeletonCardsSection(count: 2)
            } else if bookmarks.isEmpty {
                EmptyStateView(
                    icon: source == .karakeep ? "bookmark" : "doc",
                    title: source == .karakeep ? "No bookmarks" : "No documents",
                    subtitle: source == .karakeep
                        ? "Share links from Safari to save them here."
                        : "Documents from Paperless will appear here once synced."
                )
            } else {
                PerchSectionCard {
                    ForEach(Array(bookmarks.enumerated()), id: \.element.0.id) { i, pair in
                        BookmarkRowV2(bookmark: pair.1, onTap: {
                            if let url = URL(string: pair.1.url) {
                                UIApplication.shared.open(url)
                            }
                        })
                        if i < bookmarks.count - 1 {
                            PerchSoftDivider()
                        }
                    }
                }
            }

            Color.clear.frame(height: PerchTheme.TabBar.shellContentInsetHeight)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
    }

    private var bookmarkKicker: String {
        let total = records.compactMap { $0.asBookmark() }.count
        return total == 0 ? "READING" : "READING · \(total) SAVED"
    }

    private var bookmarkTitle: String {
        source == .karakeep ? "Quiet finds, stacked." : "Papers in order."
    }

    private var unreadLabel: String? {
        let unread = bookmarks.count
        guard unread > 0 else { return nil }
        return "\(unread) unread\n\(max(1, unread * 7 / 60))h of reading"
    }

    private func countBySource(_ s: BookmarkSource) -> Int {
        records.compactMap { $0.asBookmark() }
            .filter { ($0.source ?? .karakeep) == s }.count
    }
}

/// Pill-segmented control. Not a second layer of PillNav — that's a
/// specifically-called-out anti-pattern in the handoff; this is a
/// low-emphasis switch sitting in its own tonal panel.
private struct BookmarksSourceSwitch: View {
    @Environment(\.perchPalette) private var palette

    @Binding var source: BookmarkSource
    let karakeepCount: Int
    let paperlessCount: Int

    var body: some View {
        HStack(spacing: 4) {
            tab(.karakeep, label: "Karakeep", count: karakeepCount)
            tab(.paperless, label: "Paperless", count: paperlessCount)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(palette.ink.opacity(0.06))
        )
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder
    private func tab(_ s: BookmarkSource, label: String, count: Int) -> some View {
        let active = s == source
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { source = s }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(palette.faint)
            }
            .foregroundStyle(active ? palette.ink : palette.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? palette.card : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

/// Single bookmark row inside the stacked card: domain kicker + "time
/// ago" right-aligned, italic title, body excerpt, read-time + tags
/// along the bottom.
private struct BookmarkRowV2: View {
    @Environment(\.perchPalette) private var palette

    let bookmark: BookmarkData
    let onTap: () -> Void

    private var domain: String {
        if let url = URL(string: bookmark.url), let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return "link"
    }

    private var ageText: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        let date = bookmark.processedAt ?? Date.now
        return f.localizedString(for: date, relativeTo: Date.now)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    PerchKicker(domain)
                    Spacer()
                    Text(ageText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.faint)
                }

                Text(bookmark.displayTitle)
                    .font(.system(size: 17, weight: .medium, design: .serif).italic())
                    .foregroundStyle(palette.ink)
                    .tracking(-0.2)
                    .lineLimit(2)

                if let summary = bookmark.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.muted)
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                if !bookmark.tags.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(bookmark.tags.prefix(3)), id: \.self) { tag in
                            Text(tag.uppercased())
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.3)
                                .foregroundStyle(palette.ink)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Calendar Section Content — Sections v2

/// Week strip with per-day event-count dots + agenda card with
/// timeline rail on the left, mono time column, italic event titles,
/// past events faded. A dashed kinetic "NOW · HH:mm" line cuts
/// across when the selected day is today.
private struct CalendarSectionContent: View {
    @Environment(\.perchPalette) private var palette
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var selectedDate = Calendar.current.startOfDay(for: Date.now)

    /// Cached merged events. Round 9 audit caught the prior `var events {...}`
    /// computed-property running ~11× per body render (title, dayEvents,
    /// nextEventAside, dayEvents.isEmpty, CalendarAgenda, plus 7 day-chip
    /// filter passes). Each pass did a compactMap + dedupe + sort over
    /// up to 200 calendar records — easily 80–200ms per body. Now
    /// recomputed only when the source arrays change.
    @State private var cachedEvents: [EventData] = []
    /// Pre-bucketed event counts per `Calendar.current.startOfDay(...)`.
    /// Replaces the 7×/render filter loop in the day-chip strip.
    @State private var eventsByDay: [Date: Int] = [:]
    /// Round 10 audit (M-4): also cache `dayEvents` so the four body
    /// reads (title, nextEventAside, isEmpty gate, CalendarAgenda)
    /// hit a single pre-filtered array instead of re-filtering
    /// `cachedEvents` per access. Recomputed on selectedDate change
    /// or when cachedEvents is rebuilt.
    @State private var cachedDayEvents: [EventData] = []

    private var records: [Record] { dashboardViewModel.calendarRecords }

    private var dayEvents: [EventData] { cachedDayEvents }

    /// Recompute `cachedEvents` and `eventsByDay` from the current sources.
    /// Called from .onAppear and .onChange. Static so it can be called
    /// without capturing self.
    private static func mergeEvents(supabaseRecords: [Record], deviceEvents: [EventData])
        -> (events: [EventData], byDay: [Date: Int])
    {
        let supabaseEvents = supabaseRecords.compactMap { $0.asEvent() }
        var seen = Set<String>()
        var merged: [EventData] = []
        for event in deviceEvents + supabaseEvents {
            let key = "\(event.title)|\(Int(event.start.timeIntervalSince1970 / 60))"
            if seen.insert(key).inserted {
                merged.append(event)
            }
        }
        let sorted = merged.sorted { $0.start < $1.start }
        let cal = Calendar.current
        var byDay: [Date: Int] = [:]
        for event in sorted {
            byDay[cal.startOfDay(for: event.start), default: 0] += 1
        }
        return (sorted, byDay)
    }

    private func refreshEventsCache() {
        let (events, byDay) = Self.mergeEvents(
            supabaseRecords: records,
            deviceEvents: dashboardViewModel.eventKitEvents
        )
        cachedEvents = events
        eventsByDay = byDay
        recomputeDayEvents()
    }

    private func recomputeDayEvents() {
        let cal = Calendar.current
        cachedDayEvents = cachedEvents.filter { cal.isDate($0.start, inSameDayAs: selectedDate) }
    }

    /// Round 10 audit (F3): single Hashable fingerprint covering both
    /// `calendarRecords` and `eventKitEvents` so we coalesce the two
    /// `.onChange` handlers into one. Cold start used to fire 3+
    /// passes (cached records, EventKit, network records); now fires
    /// at most once per logical change.
    private struct CalendarSourceFingerprint: Hashable {
        let recordsCount: Int
        let recordsMaxUpdated: TimeInterval
        let ekEventsCount: Int
        let ekEventsLastStart: TimeInterval

        static func from(records: [Record], ekEvents: [EventData]) -> CalendarSourceFingerprint {
            var maxUpd: TimeInterval = 0
            for r in records {
                let t = r.updatedAt.timeIntervalSince1970
                if t > maxUpd { maxUpd = t }
            }
            return CalendarSourceFingerprint(
                recordsCount: records.count,
                recordsMaxUpdated: maxUpd,
                ekEventsCount: ekEvents.count,
                ekEventsLastStart: ekEvents.last?.start.timeIntervalSince1970 ?? 0
            )
        }
    }

    private var weekDates: [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        guard let start = cal.date(from: comps) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var kicker: String {
        PerchFormatters.agendaKicker.string(from: selectedDate).uppercased()
    }

    private var title: String {
        let n = dayEvents.count
        if n == 0 { return "Nothing on the books." }
        if n == 1 { return "One on the day." }
        if n < 6 { return "Today, \(words(n)) things." }
        return "\(n) things on."
    }

    private var nextEventAside: String? {
        guard let upcoming = dayEvents.first(where: { $0.start > Date.now }) else { return nil }
        return "Next at\n\(PerchFormatters.time24h.string(from: upcoming.start))"
    }

    private func words(_ n: Int) -> String {
        switch n {
        case 2: return "two"
        case 3: return "three"
        case 4: return "four"
        case 5: return "five"
        default: return "\(n)"
        }
    }

    var body: some View {
        let cal = Calendar.current
        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(kicker: kicker, title: title, aside: nextEventAside)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weekDates, id: \.self) { date in
                        PerchDayChip(
                            date: date,
                            eventCount: eventsByDay[cal.startOfDay(for: date), default: 0],
                            isActive: cal.isDate(date, inSameDayAs: selectedDate),
                            action: { selectedDate = cal.startOfDay(for: date) }
                        )
                    }
                }
            }
            .padding(.bottom, 6)

            if dayEvents.isEmpty {
                PerchSectionCard {
                    Text("A breezy one.")
                        .font(.system(size: 17, weight: .medium, design: .serif).italic())
                        .foregroundStyle(palette.muted)
                        .padding(.vertical, 10)
                }
            } else {
                CalendarAgenda(events: dayEvents,
                                isToday: cal.isDateInToday(selectedDate))
            }

            Color.clear.frame(height: PerchTheme.TabBar.shellContentInsetHeight)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
        .onAppear { refreshEventsCache() }
        .onChange(of: CalendarSourceFingerprint.from(
            records: records,
            ekEvents: dashboardViewModel.eventKitEvents
        )) { _, _ in refreshEventsCache() }
        .onChange(of: selectedDate) { _, _ in recomputeDayEvents() }
    }
}

/// Chip for a single weekday in the week strip. Active day gets an
/// inky filled background; inactive days are outlined pills. Event
/// count renders as small dots at the bottom (up to 4 visible).
private struct PerchDayChip: View {
    @Environment(\.perchPalette) private var palette

    let date: Date
    let eventCount: Int
    let isActive: Bool
    let action: () -> Void

    private var dayLetter: String {
        PerchFormatters.dayLetter.string(from: date)
    }

    private var dayNumber: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(dayLetter.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(isActive
                                     ? Color(red: 1, green: 0.96, blue: 0.90).opacity(0.75)
                                     : palette.ink.opacity(0.55))

                Text(dayNumber)
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(isActive
                                     ? Color(red: 1, green: 0.96, blue: 0.90)
                                     : palette.ink)
                    .tracking(-0.5)

                HStack(spacing: 2) {
                    ForEach(0..<min(eventCount, 4), id: \.self) { _ in
                        Circle()
                            .fill(isActive
                                  ? Color(red: 1, green: 0.96, blue: 0.90).opacity(0.85)
                                  : palette.kinetic)
                            .frame(width: 3, height: 3)
                    }
                }
                .frame(height: 4)
            }
            .frame(width: 40, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isActive ? palette.ink : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(isActive ? Color.clear : palette.ink.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// Agenda card: ink timeline rail on the left, event rows with mono
/// start/end times + italic titles + muted subtitle. If the displayed
/// day is today, a dashed kinetic "NOW · HH:mm" horizontal line
/// marks the current moment (currently positioned at a fixed
/// placeholder — production: compute from time + row layout).
private struct CalendarAgenda: View {
    @Environment(\.perchPalette) private var palette

    let events: [EventData]
    let isToday: Bool

    private var nowLabel: String {
        "NOW · \(PerchFormatters.time24h.string(from: Date.now))"
    }

    /// Index at which the NOW ruler should be inserted. Equal to the index
    /// of the first event whose start is after now (all-day events — which
    /// started at 00:00 — are ordered before and so sit above the ruler).
    /// Returns nil when today has no future events to precede; the caller
    /// renders the ruler at the end in that case.
    private var nowInsertIndex: Int? {
        guard isToday else { return nil }
        let now = Date.now
        return events.firstIndex(where: { $0.start > now })
    }

    @ViewBuilder
    private var nowRuler: some View {
        HStack(spacing: 6) {
            Text(nowLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(palette.kinetic)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(palette.card)
            Rectangle()
                .fill(palette.kinetic)
                .frame(height: 1)
                .opacity(0.8)
        }
        .padding(.vertical, 6)
    }

    var body: some View {
        PerchSectionCard(padding: 18) {
            ForEach(Array(events.enumerated()), id: \.offset) { i, event in
                if i == nowInsertIndex { nowRuler }
                CalendarEventRow(event: event)
                if i < events.count - 1 {
                    PerchSoftDivider()
                }
            }

            // If NOW falls after every event on today's timeline (e.g. the
            // last meeting wrapped up already), trail the ruler at the
            // bottom. Only show when there's at least one event so an empty
            // day doesn't get a naked ruler.
            if isToday, nowInsertIndex == nil, !events.isEmpty {
                nowRuler
            }
        }
    }
}

private struct CalendarEventRow: View {
    @Environment(\.perchPalette) private var palette

    let event: EventData

    private var isPast: Bool { event.end < Date.now }

    /// True when the event spans (effectively) the full day — starts at
    /// midnight and runs at least 23 hours. Catches both EventKit all-day
    /// events (00:00 → 23:59:59) and multi-day spans on the current day.
    private var isAllDay: Bool {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: event.start)
        let startsAtMidnight = cal.isDate(event.start, equalTo: startOfDay, toGranularity: .minute)
        let duration = event.end.timeIntervalSince(event.start)
        return startsAtMidnight && duration >= 23 * 3600
    }

    private var startStr: String {
        PerchFormatters.time24h.string(from: event.start)
    }

    private var endStr: String {
        PerchFormatters.time24h.string(from: event.end)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                if isAllDay {
                    Text("ALL")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(palette.muted)
                    Text("DAY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(palette.faint)
                } else {
                    Text(startStr)
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(0.2)
                        .foregroundStyle(palette.muted)
                    Text(endStr)
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(0.2)
                        .foregroundStyle(palette.faint)
                }
            }
            .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 17, weight: .medium, design: .serif).italic())
                    .foregroundStyle(palette.ink)
                    .tracking(-0.2)
                    .lineLimit(2)

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 16)
        .opacity(isPast ? 0.42 : 1)
    }
}


// MARK: - Travel Section Content — Sections v2

/// Trip hero (italic origin → destination + dates/nights/weather
/// triad), then a day-by-day timeline with a vertical rail, circle
/// markers per day, and stacked items (FlightStrip, hotel line,
/// meeting pins) beneath each day label.
private struct TravelSectionContent: View {
    @Environment(\.perchPalette) private var palette
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @Environment(TravelViewModel.self) private var viewModel

    private var displayTrip: (Record, TripData)? {
        viewModel.currentTrip ?? viewModel.pastTrips.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dashboardViewModel.isLoading && viewModel.records.isEmpty {
                SkeletonCardsSection(count: 2)
            } else if viewModel.trips.isEmpty {
                EmptyStateView(
                    icon: "airplane",
                    title: "No upcoming trips",
                    subtitle: "Forward your booking confirmations to TripIt and they'll appear here automatically."
                )
            } else if let (_, trip) = displayTrip {
                SectionTitle(
                    kicker: tripKicker(trip),
                    title: tripTitle(trip),
                    aside: tripAside(trip)
                )

                TripHeroCard(trip: trip)

                PerchKicker("Day by day")
                    .padding(.top, 4)

                TripTimeline(segments: viewModel.segments(for: trip.tripId))
            }

            Color.clear.frame(height: PerchTheme.TabBar.shellContentInsetHeight)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
        .onChange(of: dashboardViewModel.travelRecords) { _, new in
            viewModel.records = new
        }
        .onAppear {
            if !dashboardViewModel.travelRecords.isEmpty {
                viewModel.records = dashboardViewModel.travelRecords
            }
        }
    }

    private func tripKicker(_ trip: TripData) -> String {
        if let days = trip.daysUntilStart, days > 0 {
            return "NEXT TRIP · IN \(days) DAY\(days == 1 ? "" : "S")"
        }
        if trip.effectiveStatus == "active" {
            return "CURRENT TRIP"
        }
        return "TRIP"
    }

    private func tripTitle(_ trip: TripData) -> String {
        if let origin = trip.origin {
            return "\(origin) → \(trip.destination)."
        }
        return "\(trip.destination)."
    }

    private func tripAside(_ trip: TripData) -> String? {
        let f = PerchFormatters.shortWeekdayDate

        var parts: [String] = []
        if let start = trip.startDateParsed {
            parts.append(f.string(from: start))
        }
        if let total = trip.totalDays, total > 0 {
            parts.append("\(total) night\(total == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }
}

private struct TripHeroCard: View {
    @Environment(\.perchPalette) private var palette
    let trip: TripData

    private var dateRange: String {
        guard let start = trip.startDateParsed, let end = trip.endDateParsed else { return "—" }
        let f = PerchFormatters.shortDateUK
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }

    private var nightsText: String {
        if let n = trip.totalDays { return "\(n)" }
        return "—"
    }

    private var daysBadge: String? {
        if trip.effectiveStatus == "active" { return "NOW" }
        if let d = trip.daysUntilStart, d > 0 { return "IN \(d)D" }
        return nil
    }

    var body: some View {
        PerchSectionCard {
            HStack {
                PerchKicker("The trip")
                Spacer()
                if let badge = daysBadge {
                    HStack(spacing: 5) {
                        Image(systemName: "airplane")
                            .font(.system(size: 10, weight: .medium))
                        Text(badge)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(0.3)
                    }
                    .foregroundStyle(palette.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.ink.opacity(0.08))
                    )
                }
            }
            .padding(.bottom, 12)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.origin ?? "Home")
                        .font(.system(size: 28, weight: .medium, design: .serif).italic())
                        .foregroundStyle(palette.ink)
                        .tracking(-0.5)
                    Text("Home · \(trip.originTz?.prefix(3).uppercased() ?? "")")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.faint)
                    .padding(.bottom, 20)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(trip.destination)
                        .font(.system(size: 28, weight: .medium, design: .serif).italic())
                        .foregroundStyle(palette.ink)
                        .tracking(-0.5)
                    Text("Away · \(trip.destinationTz?.prefix(3).uppercased() ?? "")")
                        .font(.system(size: 11.5))
                        .foregroundStyle(palette.muted)
                }
            }

            PerchSoftDivider()
                .padding(.top, 18)
                .padding(.bottom, 16)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    PerchKicker("Dates")
                    Text(dateRange)
                        .font(.system(size: 14, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(palette.ink)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    PerchKicker("Nights")
                    Text(nightsText)
                        .font(.system(size: 14, design: .serif))
                        .monospacedDigit()
                        .foregroundStyle(palette.ink)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    PerchKicker("Status")
                    Text(trip.effectiveStatus.capitalized)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(palette.ink)
                }
            }
        }
    }
}

private struct TripTimeline: View {
    @Environment(\.perchPalette) private var palette
    let segments: [(Record, ItineraryData)]

    private var entries: [HubTimelineEntry] {
        segments.map { rec, seg in
            HubTimelineEntry(
                id: rec.id.uuidString,
                record: rec,
                segment: seg,
                sortDate: seg.departure ?? seg.checkIn ?? rec.createdAt
            )
        }.sorted { $0.sortDate < $1.sortDate }
    }

    private var grouped: [(label: String, items: [HubTimelineEntry])] {
        let groups = Dictionary(grouping: entries) { e -> String in
            PerchFormatters.agendaKicker.string(from: e.sortDate)
        }
        return groups.keys
            .sorted { k1, k2 in
                (groups[k1]?.first?.sortDate ?? .distantFuture) <
                (groups[k2]?.first?.sortDate ?? .distantFuture)
            }
            .map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(palette.lineSoft)
                .frame(width: 1.5)
                .offset(x: 17)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(grouped.enumerated()), id: \.offset) { _, day in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(day.label)
                                .font(.system(size: 16, weight: .medium, design: .serif).italic())
                                .foregroundStyle(palette.ink)
                                .tracking(-0.2)
                            Spacer()
                            PerchKicker(dayKicker(for: day.items))
                        }

                        ForEach(day.items) { entry in
                            TripSegmentView(segment: entry.segment, record: entry.record)
                        }
                    }
                    .padding(.leading, 42)
                    .overlay(alignment: .topLeading) {
                        Circle()
                            .fill(palette.bg)
                            .frame(width: 14, height: 14)
                            .overlay(
                                Circle().strokeBorder(palette.ink, lineWidth: 2)
                            )
                            .offset(x: 10, y: 4)
                    }
                }
            }
        }
    }

    /// A terse label summarising what happens that day — inferred from
    /// the mix of segment types (FLIGHTS / MEETINGS / PREP / STAY / RETURN).
    private func dayKicker(for items: [HubTimelineEntry]) -> String {
        let types = items.map { $0.segment.segmentType }
        if types.contains("flight") {
            if items.count == 1 { return "TRAVEL" }
            return "PREP"
        }
        if types.allSatisfy({ $0 == "hotel" }) { return "STAY" }
        if types.contains("restaurant") { return "MEETINGS" }
        return "DAY"
    }
}

private struct TripSegmentView: View {
    @Environment(\.perchPalette) private var palette
    let segment: ItineraryData
    let record: Record

    var body: some View {
        if segment.isFlight {
            TripFlightStrip(segment: segment)
        } else {
            TripPointStrip(segment: segment, record: record)
        }
    }
}

private struct TripFlightStrip: View {
    @Environment(\.perchPalette) private var palette
    let segment: ItineraryData

    private func time(_ date: Date?) -> String {
        guard let date else { return "—" }
        return PerchFormatters.time24h.string(from: date)
    }

    var body: some View {
        PerchSectionCard(tone: .dim, padding: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "airplane")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.ink)
                    Text(segment.flightLabel ?? "Flight")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                }
                Spacer()
                if let conf = segment.confirmation {
                    Text("Ref \(conf)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(palette.muted)
                }
            }
            .padding(.bottom, 10)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    PerchNum(time(segment.departure), size: 22)
                    Text(segment.origin ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(palette.muted)
                }
                Spacer()
                // Dashed arrow
                Canvas { ctx, size in
                    var path = Path()
                    path.move(to: CGPoint(x: 2, y: size.height / 2))
                    path.addLine(to: CGPoint(x: size.width - 4, y: size.height / 2))
                    ctx.stroke(
                        path,
                        with: .color(palette.faint),
                        style: StrokeStyle(lineWidth: 1.3, lineCap: .round, dash: [2, 2])
                    )
                    // Arrowhead
                    var head = Path()
                    head.move(to: CGPoint(x: size.width - 5, y: size.height / 2 - 4))
                    head.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    head.addLine(to: CGPoint(x: size.width - 5, y: size.height / 2 + 4))
                    ctx.stroke(head, with: .color(palette.faint), lineWidth: 1.3)
                }
                .frame(width: 40, height: 12)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    PerchNum(time(segment.arrival), size: 22)
                    Text(segment.destination ?? "—")
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(0.3)
                        .foregroundStyle(palette.muted)
                }
            }

            HStack {
                if let seat = segment.seat {
                    Text("Seat \(seat)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.muted)
                }
                Spacer()
                if let dep = segment.departure, let arr = segment.arrival {
                    let mins = Int(arr.timeIntervalSince(dep) / 60)
                    Text("\(mins / 60)h \(mins % 60)m")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.muted)
                }
            }
            .padding(.top, 10)
        }
    }
}

private struct TripPointStrip: View {
    @Environment(\.perchPalette) private var palette
    let segment: ItineraryData
    let record: Record

    private var iconName: String {
        switch segment.segmentType {
        case "hotel": return "bed.double"
        case "car_rental": return "car"
        case "restaurant": return "fork.knife"
        case "train": return "tram"
        default: return "mappin.and.ellipse"
        }
    }

    private var sub: String {
        let f = PerchFormatters.time24h
        if let dep = segment.departure, let arr = segment.arrival {
            return "\(f.string(from: dep)) – \(f.string(from: arr))"
        }
        if let addr = segment.address { return addr }
        if let check = segment.checkIn {
            return "Check-in \(f.string(from: check))"
        }
        return record.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 13))
                    .foregroundStyle(palette.ink)
                Text(segment.name ?? record.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(palette.ink)
            }
            Text(sub)
                .font(.system(size: 11.5, design: .monospaced))
                .tracking(0.2)
                .foregroundStyle(palette.muted)
                .padding(.leading, 22)
        }
    }
}



// MARK: - Preview

#Preview {
    HubTab()
        .environment(AuthViewModel())
        .environment(DashboardViewModel())
        .environment(TravelViewModel())
}
