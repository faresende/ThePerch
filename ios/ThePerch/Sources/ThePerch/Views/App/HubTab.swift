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
    @Environment(\.perchPalette) private var palette
    @State private var travelViewModel = TravelViewModel()
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
                    hubPage { OrdersSectionContent() }
                        .tag(HubSegment.orders)

                    hubPage { BookmarksSectionContent() }
                        .tag(HubSegment.bookmarks)

                    hubPage { CalendarSectionContent() }
                        .tag(HubSegment.calendar)

                    if travelViewModel.currentTrip != nil {
                        hubPage { TravelSectionContent() }
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
    @State private var viewModel = OrdersViewModel()

    private var active: [OrderWithShipments] { viewModel.activeOrders }
    private var issues: [OrderWithShipments] { viewModel.issueOrders }

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
                    OrderCardV2(order: order, featured: order.id == active.first?.id)
                }

                ForEach(issues) { order in
                    OrderCardV2(order: order, featured: false)
                }

                if !viewModel.deliveredOrders.isEmpty {
                    Button {
                        // Past-orders drill-in not yet wired; no-op for now.
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
        .task {
            guard viewModel.orders.isEmpty else { return }
            await viewModel.loadOrders()
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "MMM d"
        let date = order.displayDate
        if order.effectiveStatus == "delivered" {
            return "Arrived \(f.string(from: date))"
        }
        return "Updated \(f.string(from: date))"
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
            HStack(alignment: .firstTextBaseline) {
                PerchKicker(order.order.merchant.uppercased())
                Spacer()
                Text(etaText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.muted)
            }
            .padding(.bottom, 8)

            Text(itemsSummary(order))
                .font(.system(size: featured ? 22 : 18, weight: .medium, design: .serif).italic())
                .foregroundStyle(palette.ink)
                .tracking(-0.3)
                .lineLimit(3)
                .padding(.bottom, 6)

            PerchNum(priceText, size: featured ? 22 : 18)
                .padding(.bottom, 18)

            PerchStageStepper(
                stages: ["Ordered", "Shipped", "In transit", "Delivered"],
                currentIdx: stageIndex
            )
            .padding(.horizontal, 2)
            .padding(.bottom, 14)

            PerchSoftDivider()

            HStack {
                Text(trackingText)
                    .font(.system(size: 11.5, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(palette.muted)
                Spacer()
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
            }
            .padding(.top, 12)
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

    private var records: [Record] { dashboardViewModel.calendarRecords }

    private var events: [EventData] {
        records.compactMap { $0.asEvent() }.sorted { $0.start < $1.start }
    }

    private var dayEvents: [EventData] {
        let cal = Calendar.current
        return events.filter { cal.isDate($0.start, inSameDayAs: selectedDate) }
    }

    private var weekDates: [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        guard let start = cal.date(from: comps) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var kicker: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE · MMM d"
        return f.string(from: selectedDate).uppercased()
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return "Next at\n\(f.string(from: upcoming.start))"
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
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(kicker: kicker, title: title, aside: nextEventAside)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weekDates, id: \.self) { date in
                        PerchDayChip(
                            date: date,
                            eventCount: events.filter { Calendar.current.isDate($0.start, inSameDayAs: date) }.count,
                            isActive: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                            action: { selectedDate = Calendar.current.startOfDay(for: date) }
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
                                isToday: Calendar.current.isDateInToday(selectedDate))
            }

            Color.clear.frame(height: PerchTheme.TabBar.shellContentInsetHeight)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 20)
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEEE"
        return f.string(from: date)
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return "NOW · \(f.string(from: Date.now))"
    }

    var body: some View {
        PerchSectionCard(padding: 18) {
            ForEach(Array(events.enumerated()), id: \.offset) { i, event in
                CalendarEventRow(event: event)
                if i < events.count - 1 {
                    PerchSoftDivider()
                }
            }

            if isToday {
                // Thin dashed "now" line rendered inside the card at its
                // natural position in the row flow — placed after the
                // first past event as a visual cue.
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
                .padding(.top, 4)
            }
        }
    }
}

private struct CalendarEventRow: View {
    @Environment(\.perchPalette) private var palette

    let event: EventData

    private var isPast: Bool { event.end < Date.now }

    private var startStr: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return f.string(from: event.start)
    }

    private var endStr: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return f.string(from: event.end)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(startStr)
                    .font(.system(size: 11, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(palette.muted)
                Text(endStr)
                    .font(.system(size: 10, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(palette.faint)
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
    @State private var viewModel = TravelViewModel()

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
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE MMM d"

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
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "MMM d"
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
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.dateFormat = "EEE · MMM d"
            return f.string(from: e.sortDate)
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
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
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
        if let dep = segment.departure, let arr = segment.arrival {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.dateFormat = "HH:mm"
            return "\(f.string(from: dep)) – \(f.string(from: arr))"
        }
        if let addr = segment.address { return addr }
        if let check = segment.checkIn {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.dateFormat = "HH:mm"
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
}
