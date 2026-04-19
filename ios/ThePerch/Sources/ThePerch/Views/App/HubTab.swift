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

                // Paged segment content
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

// MARK: - Orders Section Content

private struct OrdersSectionContent: View {
    @State private var viewModel = OrdersViewModel()
    @State private var cardsAppeared = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
            if viewModel.isLoading && viewModel.orders.isEmpty {
                SkeletonCardsSection(count: 2)
                    .padding(.horizontal, PerchTheme.Spacing.large)
            } else if let error = viewModel.error, viewModel.orders.isEmpty {
                EmptyStateView(
                    icon: "shippingbox",
                    title: "Orders backend unavailable",
                    subtitle: error.contains("public.orders")
                        ? "This backend does have deliveries, but the new Orders view still cannot read the orders tables here."
                        : error
                )
                .padding(.horizontal, PerchTheme.Spacing.large)
            } else if viewModel.orders.isEmpty {
                EmptyStateView(
                    icon: "cart",
                    title: "No orders yet",
                    subtitle: "Purchase confirmations and tracked shipments will show up here once Orders Autopilot has something to merge."
                )
                .padding(.horizontal, PerchTheme.Spacing.large)
            } else {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    OrdersGroupSection(
                        title: "Active",
                        subtitle: "Ordered, processing, and in-flight shipments.",
                        icon: "shippingbox.fill",
                        tint: PerchTheme.accent,
                        orders: viewModel.activeOrders,
                        cardsAppeared: cardsAppeared,
                        onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                        onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                    )

                    if !viewModel.issueOrders.isEmpty {
                        OrdersGroupSection(
                            title: "Issues",
                            subtitle: "Exceptions and orders that need a closer look.",
                            icon: "exclamationmark.triangle.fill",
                            tint: PerchTheme.error,
                            orders: viewModel.issueOrders,
                            cardsAppeared: cardsAppeared,
                            startIndex: viewModel.activeOrders.count,
                            onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                            onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                        )
                    }

                    DeliveredOrdersSection(
                        orders: viewModel.deliveredOrders,
                        cardsAppeared: cardsAppeared,
                        startIndex: viewModel.activeOrders.count + viewModel.issueOrders.count,
                        onMarkDelivered: { order in Task { await viewModel.markAsDelivered(order) } },
                        onUndoDelivered: { order in Task { await viewModel.undoDelivered(order) } }
                    )
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
                .onAppear {
                    PerchMotion.withOptionalAnimation { cardsAppeared = true }
                }
            }
        }
        .task {
            guard viewModel.orders.isEmpty else { return }
            await viewModel.loadOrders()
        }
    }
}


// MARK: - Bookmarks Section Content

private struct BookmarksSectionContent: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
    @State private var selectedTab: BookmarkSource = .karakeep

    private var records: [Record] { dashboardViewModel.bookmarkRecords }

    private var bookmarkData: (
        allTags: [String],
        filtered: [Record],
        pending: [Record],
        processed: [Record]
    ) {
        var tabRecords: [(Record, BookmarkData)] = []
        for record in records {
            guard let bookmark = record.asBookmark() else { continue }
            let source = bookmark.source ?? .karakeep
            if source == selectedTab {
                tabRecords.append((record, bookmark))
            }
        }

        var tagSet = Set<String>()
        for (_, bookmark) in tabRecords {
            for tag in bookmark.tags { tagSet.insert(tag) }
        }
        let sortedTags = tagSet.sorted()

        var filtered: [Record] = []
        var pending: [Record] = []
        var processed: [Record] = []
        for (record, bookmark) in tabRecords {
            let matchesSearch = searchText.isEmpty ||
                bookmark.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                (bookmark.summary?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (bookmark.fileName?.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesTags = selectedTags.isEmpty ||
                selectedTags.allSatisfy { bookmark.tags.contains($0) }

            guard matchesSearch && matchesTags else { continue }
            filtered.append(record)

            if bookmark.status == .pending || bookmark.status == .processing {
                pending.append(record)
            } else if bookmark.status == .processed {
                processed.append(record)
            }
        }

        return (sortedTags, filtered, pending, processed)
    }

    var allTags: [String] { bookmarkData.allTags }
    var filteredBookmarks: [Record] { bookmarkData.filtered }
    var pendingBookmarks: [Record] { bookmarkData.pending }
    var processedBookmarks: [Record] { bookmarkData.processed }
    private var tabCount: Int { bookmarkData.filtered.count }

    private var tabHasRecords: Bool {
        records.contains { record in
            guard let bookmark = record.asBookmark() else { return false }
            return (bookmark.source ?? .karakeep) == selectedTab
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Tab picker + search
            VStack(spacing: PerchTheme.Spacing.small) {
                Picker("Source", selection: $selectedTab) {
                    Text("Karakeep").tag(BookmarkSource.karakeep)
                    Text("Paperless").tag(BookmarkSource.paperless)
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedTab) { _, _ in
                    selectedTags.removeAll()
                }

                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "magnifyingglass")
                        .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                        .foregroundColor(PerchTheme.textSecondary)

                    TextField(
                        selectedTab == .karakeep ? "Search bookmarks" : "Search documents",
                        text: $searchText
                    )
                    .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                    }
                }
                .padding(PerchTheme.Spacing.small)
                .background(PerchTheme.cardBackground)
                .cornerRadius(PerchTheme.Card.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                        .stroke(PerchTheme.border, lineWidth: 1)
                )

                // Tag filters
                if !allTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PerchTheme.Spacing.xSmall) {
                            ForEach(allTags, id: \.self) { tag in
                                Button(action: { toggleTag(tag) }) {
                                    Text(tag)
                                        .font(PerchTheme.Font.caption)
                                        .foregroundColor(
                                            selectedTags.contains(tag)
                                                ? .white
                                                : PerchTheme.accent
                                        )
                                        .padding(.horizontal, PerchTheme.Spacing.small)
                                        .padding(.vertical, PerchTheme.Spacing.xxSmall)
                                        .background(
                                            selectedTags.contains(tag)
                                                ? PerchTheme.accent
                                                : PerchTheme.accent.opacity(0.1)
                                        )
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)

            if dashboardViewModel.isLoading && records.isEmpty {
                SkeletonCardsSection(count: 2)
                    .padding(.horizontal, PerchTheme.Spacing.large)
            } else {
                if !filteredBookmarks.isEmpty {
                    Text("\(tabCount) \(selectedTab == .karakeep ? "bookmark" : "document")\(tabCount == 1 ? "" : "s")")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                        .padding(.horizontal, PerchTheme.Spacing.large)
                }

                // Pending/processing
                if !pendingBookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                        Text("Processing")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)

                        VStack(spacing: PerchTheme.Spacing.medium) {
                            ForEach(pendingBookmarks) { record in
                                if let bookmark = record.asBookmark() {
                                    bookmarkCardView(bookmark: bookmark)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)
                }

                // Processed
                if !processedBookmarks.isEmpty {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                        Text(selectedTab == .karakeep ? "Bookmarks" : "Documents")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)

                        VStack(spacing: PerchTheme.Spacing.medium) {
                            ForEach(processedBookmarks) { record in
                                if let bookmark = record.asBookmark() {
                                    bookmarkCardView(bookmark: bookmark)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)
                }

                if filteredBookmarks.isEmpty && !searchText.isEmpty {
                    emptySearchView
                } else if !tabHasRecords && !dashboardViewModel.isLoading {
                    emptyStateView
                }
            }

            Spacer()
                .frame(height: PerchTheme.Spacing.large)
        }
    }

    @ViewBuilder
    private func bookmarkCardView(bookmark: BookmarkData) -> some View {
        let tapAction = {
            if let url = URL(string: bookmark.url) {
                UIApplication.shared.open(url)
            }
        }

        if selectedTab == .paperless {
            PaperlessCard(bookmark: bookmark, onTap: tapAction)
        } else {
            BookmarkCard(bookmark: bookmark, onTap: tapAction)
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        EmptyStateView(
            icon: selectedTab == .karakeep ? "bookmark" : "doc",
            title: selectedTab == .karakeep ? "No bookmarks saved" : "No documents saved",
            subtitle: selectedTab == .karakeep
                ? "Share articles from Safari or the Share Sheet to save them here."
                : "Documents from Paperless will appear here once they sync."
        )
    }

    @ViewBuilder
    private var emptySearchView: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "magnifyingglass")
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text("No results")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                Text("Try different keywords or filters")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PerchTheme.Spacing.large)
    }

    private func toggleTag(_ tag: String) {
        PerchHaptics.selection()
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

// MARK: - Calendar Section Content

private struct CalendarSectionContent: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var cardsAppeared = false
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)

    private var records: [Record] { dashboardViewModel.calendarRecords }

    private var events: [EventData] {
        records
            .compactMap { record in record.asEvent() }
            .sorted { lhs, rhs in lhs.start < rhs.start }
    }

    private var selectedDayEvents: [EventData] {
        let calendar = Calendar.current
        return events.filter { event in
            calendar.isDate(event.start, equalTo: selectedDate, toGranularity: .day)
        }
    }

    private var upcomingEvents: [EventData] {
        Array(events.filter { $0.start > Date.now }.prefix(7))
    }

    private var weekDates: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)
        guard let startOfWeek = calendar.date(from: components) else { return [] }
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfWeek)
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
            if dashboardViewModel.isLoading && records.isEmpty {
                SkeletonCardsSection(count: 2)
                    .padding(.horizontal, PerchTheme.Spacing.large)
            } else {
                dayNavigationHeader
                weekOverview

                if selectedDayEvents.isEmpty {
                    EmptyStateView(
                        icon: "calendar",
                        title: "No events"
                    )
                    .background(PerchTheme.cardBackground)
                    .cornerRadius(PerchTheme.Card.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                            .stroke(PerchTheme.border, lineWidth: PerchTheme.Card.borderWidth)
                    )
                } else {
                    VStack(spacing: PerchTheme.Spacing.medium) {
                        ForEach(Array(selectedDayEvents.enumerated()), id: \.offset) { index, event in
                            EventCard(event: event, timezoneText: nil)
                                .cardAppear(index: index, appeared: cardsAppeared)
                        }
                    }
                    .onAppear {
                        PerchMotion.withOptionalAnimation { cardsAppeared = true }
                    }
                }

                if !upcomingEvents.isEmpty {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                        Text("UPCOMING")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                            .tracking(1)

                        VStack(spacing: PerchTheme.Spacing.small) {
                            ForEach(Array(upcomingEvents.enumerated()), id: \.offset) { index, event in
                                UpcomingEventRow(event: event, timezoneText: nil)
                                    .cardAppear(index: index + selectedDayEvents.count, appeared: cardsAppeared)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, PerchTheme.Spacing.large)
    }

    private var dayNavigationHeader: some View {
        let formatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.current
            f.setLocalizedDateFormatFromTemplate("EEE MMM d")
            return f
        }()

        let isToday = Calendar.current.isDateInToday(selectedDate)
        let selectedDayTitle = isToday
            ? "Today — \(formatter.string(from: selectedDate))"
            : formatter.string(from: selectedDate)

        return HStack(spacing: PerchTheme.Spacing.small) {
            Button(action: { shiftDate(by: -1) }) {
                Image(systemName: "chevron.left")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(PerchTheme.cardInnerBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Text(selectedDayTitle)
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)
                .frame(maxWidth: .infinity)

            Button(action: { shiftDate(by: 1) }) {
                Image(systemName: "chevron.right")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(PerchTheme.cardInnerBackground)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private var weekOverview: some View {
        let weekdayFormatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateFormat = "EEEEE"
            return f
        }()

        let calendar = Calendar.current

        return HStack(spacing: PerchTheme.Spacing.xSmall) {
            ForEach(weekDates, id: \.self) { date in
                let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                let isToday = calendar.isDateInToday(date)
                let hasEvents = events.contains { event in
                    calendar.isDate(event.start, equalTo: date, toGranularity: .day)
                }

                Button(action: { selectDate(date) }) {
                    VStack(spacing: 6) {
                        Text(weekdayFormatter.string(from: date).uppercased())
                            .font(PerchTheme.Font.micro)
                            .foregroundColor(isToday ? PerchTheme.accentForeground : PerchTheme.textTertiary)

                        Text("\(calendar.component(.day, from: date))")
                            .font(PerchTheme.Font.bodyNumeric)
                            .foregroundColor(isToday ? PerchTheme.accentForeground : PerchTheme.textPrimary)

                        Circle()
                            .fill(hasEvents ? (isToday ? PerchTheme.accentForeground : PerchTheme.accent) : Color.clear)
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, PerchTheme.Spacing.small)
                    .background(isToday ? PerchTheme.accent : (isSelected ? PerchTheme.cardBackground : PerchTheme.cardInnerBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isToday ? PerchTheme.accent : (isSelected ? PerchTheme.accent.opacity(0.35) : PerchTheme.border), lineWidth: isSelected && !isToday ? 1.5 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func shiftDate(by days: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectDate(newDate)
    }

    private func selectDate(_ date: Date) {
        PerchMotion.withOptionalAnimation {
            selectedDate = Calendar.current.startOfDay(for: date)
        }
    }
}

// MARK: - Travel Section Content

private struct TravelSectionContent: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = TravelViewModel()
    @State private var cardsAppeared = false

    private var displayTrip: (Record, TripData)? {
        viewModel.currentTrip ?? viewModel.pastTrips.first
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
            if dashboardViewModel.isLoading && viewModel.records.isEmpty {
                SkeletonCardsSection(count: 2)
                    .padding(.horizontal, PerchTheme.Spacing.large)
            } else if viewModel.trips.isEmpty {
                EmptyStateView(
                    icon: "airplane",
                    title: "No upcoming trips",
                    subtitle: "Forward your booking confirmations to TripIt and they'll appear here automatically."
                )
                .padding(.horizontal, PerchTheme.Spacing.large)
            } else {
                if let (_, trip) = displayTrip {
                    tripHeaderCard(trip: trip)
                        .cardAppear(index: 0, appeared: cardsAppeared)
                        .padding(.horizontal, PerchTheme.Spacing.large)

                    let alerts = viewModel.alerts(for: trip.tripId)
                    if !alerts.isEmpty {
                        alertsSection(alerts: alerts)
                            .cardAppear(index: 1, appeared: cardsAppeared)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    itineraryTimeline(tripId: trip.tripId)
                        .cardAppear(index: 2, appeared: cardsAppeared)
                        .padding(.horizontal, PerchTheme.Spacing.large)

                    let forecasts = viewModel.weatherForecasts(for: trip.tripId)
                    if !forecasts.isEmpty {
                        weatherSection(forecasts: forecasts)
                            .cardAppear(index: 3, appeared: cardsAppeared)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    }
                }
            }

            Color.clear
                .frame(height: 0)
                .onAppear {
                    PerchMotion.withOptionalAnimation { cardsAppeared = true }
                }

            Spacer()
                .frame(height: PerchTheme.Spacing.large)
        }
        .onChange(of: dashboardViewModel.travelRecords) { _, new in
            viewModel.records = new
        }
        .onAppear {
            if !dashboardViewModel.travelRecords.isEmpty {
                viewModel.records = dashboardViewModel.travelRecords
            }
        }
    }

    private func tripHeaderCard(trip: TripData) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(trip.destination)
                        .font(PerchTheme.Font.title)
                        .foregroundColor(PerchTheme.textPrimary)

                    if let origin = trip.origin {
                        HStack(spacing: PerchTheme.Spacing.xSmall) {
                            Text(origin)
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textTertiary)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(PerchTheme.textTertiary)
                            Text(trip.destination)
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                    }
                }

                Spacer()

                statusBadge(trip: trip)
            }

            if let start = trip.startDateParsed, let end = trip.endDateParsed {
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "calendar")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                    Text("\(PerchFormatters.shortWeekdayDate.string(from: start)) – \(PerchFormatters.shortWeekdayDate.string(from: end))")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)

                    if let total = trip.totalDays {
                        Text("· \(total) nights")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                    }
                }
            }

            if let destTz = trip.destinationTz, let originTz = trip.originTz, destTz != originTz {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Image(systemName: "clock")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                    Text(formatTimezoneOffset(origin: originTz, destination: destTz))
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }

            if let weather = viewModel.weatherSummary(for: trip.tripId) {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Text(weather.emoji)
                    Text("\(Int(weather.avgTemp))°C avg")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)
                    Text("· \(weather.condition.replacingOccurrences(of: "_", with: " ").localizedCapitalized)")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    private func alertsSection(alerts: [(Record, TravelAlertData)]) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            ForEach(alerts, id: \.0.id) { _, alert in
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: alert.isCritical ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(alert.isCritical ? PerchTheme.error : PerchTheme.warning)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.message)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)

                        if let flight = alert.flightNumber {
                            Text(flight)
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                    }

                    Spacer()
                }
                .padding(PerchTheme.Spacing.medium)
                .background(
                    (alert.isCritical ? PerchTheme.error : PerchTheme.warning).opacity(0.1)
                )
                .cornerRadius(10)
            }
        }
    }

    private func itineraryTimeline(tripId: String) -> some View {
        let segments = viewModel.segments(for: tripId)

        var entries: [HubTimelineEntry] = []
        for (record, segment) in segments {
            let date = segment.departure ?? segment.checkIn ?? record.createdAt
            entries.append(HubTimelineEntry(id: record.id.uuidString, record: record, segment: segment, sortDate: date))
        }
        entries.sort { $0.sortDate < $1.sortDate }

        let grouped = Dictionary(grouping: entries) { entry -> String in
            PerchFormatters.shortWeekdayDate.string(from: entry.sortDate)
        }
        let sortedDays = grouped.keys.sorted { k1, k2 in
            let d1 = grouped[k1]!.first?.sortDate ?? .distantFuture
            let d2 = grouped[k2]!.first?.sortDate ?? .distantFuture
            return d1 < d2
        }

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sortedDays.enumerated()), id: \.element) { dayIndex, dayLabel in
                HStack(spacing: PerchTheme.Spacing.small) {
                    Text(dayLabel)
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)
                    Spacer()
                }
                .padding(.vertical, PerchTheme.Spacing.small)
                .padding(.horizontal, PerchTheme.Spacing.small)

                ForEach(dayEntries(grouped, dayLabel)) { entry in
                    HStack(alignment: .top, spacing: PerchTheme.Spacing.medium) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(segmentStatusColor(entry.segment))
                                .frame(width: 10, height: 10)

                            if dayEntries(grouped, dayLabel).last?.id != entry.id || dayIndex < sortedDays.count - 1 {
                                Rectangle()
                                    .fill(PerchTheme.border)
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(width: 20)

                        segmentCard(record: entry.record, segment: entry.segment)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, PerchTheme.Spacing.small)
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    private func dayEntries(_ grouped: [String: [HubTimelineEntry]], _ dayLabel: String) -> [HubTimelineEntry] {
        grouped[dayLabel] ?? []
    }

    @ViewBuilder
    private func segmentCard(record: Record, segment: ItineraryData) -> some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
            Image(systemName: segmentIcon(segment))
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.accent)
                .frame(width: 18, alignment: .center)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                if segment.isFlight {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(segment.flightLabel ?? "Flight")
                            .font(PerchTheme.Font.body)
                            .fontWeight(.semibold)
                            .foregroundColor(PerchTheme.textPrimary)

                        if let origin = segment.origin, let dest = segment.destination {
                            Text("\(origin) → \(dest)")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                    }
                } else {
                    Text(segment.name ?? record.title)
                        .font(PerchTheme.Font.body)
                        .fontWeight(.semibold)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(2)
                }

                HStack {
                    if let dep = segment.departure {
                        Label(PerchFormatters.time24h.string(from: dep), systemImage: "arrow.up.right")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                    if let arr = segment.arrival {
                        Label(PerchFormatters.time24h.string(from: arr), systemImage: "arrow.down.right")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }

                    Spacer()

                    if let status = segment.status, status != "confirmed" && status != "on_time" {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(segmentStatusColor(segment))
                                .frame(width: 6, height: 6)
                            Text(status.replacingOccurrences(of: "_", with: " ").localizedCapitalized)
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(segmentStatusColor(segment))
                        }
                    }
                }

                let hasGate = segment.gate != nil
                let hasSeat = segment.seat != nil
                let hasConf = segment.confirmation != nil
                if hasGate || hasSeat || hasConf {
                    HStack(spacing: PerchTheme.Spacing.medium) {
                        if let gate = segment.gate {
                            Text("Gate \(gate)")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.accent)
                        }
                        if let seat = segment.seat {
                            Text("Seat \(seat)")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                        if let conf = segment.confirmation {
                            Text("Ref \(conf)")
                                .font(PerchTheme.Font.captionNumeric)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                    }
                }

                if let address = segment.address {
                    Text(address)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(PerchTheme.Spacing.medium)
        .background(PerchTheme.cardInnerBackground)
        .cornerRadius(10)
        .padding(.bottom, PerchTheme.Spacing.small)
    }

    private func weatherSection(forecasts: [(Record, WeatherForecastData)]) -> some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            Text("WEATHER")
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textSecondary)
                .tracking(1)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: PerchTheme.Spacing.small) {
                    ForEach(forecasts, id: \.0.id) { _, forecast in
                        VStack(spacing: 6) {
                            Text(forecast.conditionEmoji)
                                .font(PerchTheme.Font.title)

                            if let high = forecast.tempHigh, let low = forecast.tempLow {
                                Text("\(Int(high))°/\(Int(low))°")
                                    .font(PerchTheme.Font.captionNumeric)
                                    .foregroundColor(PerchTheme.textPrimary)
                            } else if let avg = forecast.tempAvg {
                                Text("\(Int(avg))°C")
                                    .font(PerchTheme.Font.captionNumeric)
                                    .foregroundColor(PerchTheme.textPrimary)
                            }

                            Text(String(forecast.date.suffix(5)))
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                        .frame(width: 60)
                        .padding(.vertical, PerchTheme.Spacing.small)
                        .background(PerchTheme.cardInnerBackground)
                        .cornerRadius(10)
                    }
                }
            }

            let hints = uniquePackingHints(from: forecasts)
            if !hints.isEmpty {
                Text("🎒 Pack: \(hints.joined(separator: ", "))")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                    .padding(.top, 2)
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    private func uniquePackingHints(from forecasts: [(Record, WeatherForecastData)]) -> [String] {
        var seen: Set<String> = []
        return forecasts
            .flatMap { $0.1.packingHints ?? [] }
            .filter { hint in
                let normalized = hint.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty, !seen.contains(normalized) else { return false }
                seen.insert(normalized)
                return true
            }
    }

    private func segmentIcon(_ seg: ItineraryData) -> String {
        switch seg.segmentType {
        case "flight": return "airplane"
        case "hotel": return "bed.double"
        case "train": return "tram"
        case "car_rental": return "car"
        case "restaurant": return "fork.knife"
        default: return "mappin.circle"
        }
    }

    private func segmentStatusColor(_ seg: ItineraryData) -> Color {
        switch seg.status?.lowercased() {
        case "confirmed", "on_time": return PerchTheme.success
        case "delayed": return PerchTheme.warning
        case "cancelled": return PerchTheme.error
        case "pending": return PerchTheme.textTertiary
        default: return PerchTheme.success
        }
    }

    private func statusBadge(trip: TripData) -> some View {
        let status = trip.effectiveStatus
        return HStack(spacing: 4) {
            Text(statusEmoji(status))
            if status == "active", let day = trip.currentTripDay, let total = trip.totalDays {
                Text("Day \(day)/\(total)")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.accent)
            } else if let days = trip.daysUntilStart, days > 0 {
                Text("in \(days)d")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
            } else {
                Text(status.capitalized)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(PerchTheme.cardInnerBackground)
        .cornerRadius(8)
    }

    private func statusEmoji(_ status: String) -> String {
        switch status {
        case "active": return "📍"
        case "upcoming": return "✈️"
        case "completed": return "✅"
        default: return "📌"
        }
    }

    private func formatTimezoneOffset(origin: String, destination: String) -> String {
        guard let originTz = TimeZone(identifier: origin),
              let destTz = TimeZone(identifier: destination) else { return "" }
        let diff = (destTz.secondsFromGMT() - originTz.secondsFromGMT()) / 3600
        if diff == 0 { return "Same timezone" }
        let sign = diff > 0 ? "+" : ""
        return "\(sign)\(diff)h from home"
    }
}

// MARK: - Preview

#Preview {
    HubTab()
        .environment(AuthViewModel())
        .environment(DashboardViewModel())
}
