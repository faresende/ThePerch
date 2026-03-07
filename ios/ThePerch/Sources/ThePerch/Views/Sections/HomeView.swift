import SwiftUI

/// The dashboard-of-dashboards (first swipeable page).
/// Features: Quick Glance summary, global search, smart-ordered cards by urgency.
struct HomeView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var showSettings = false
    @State private var records: [Record] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var cardsAppeared = false

    private let freshnessTracker = DataFreshnessTracker.shared

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Header with greeting and settings
                    HStack {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                            Text(greetingText)
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textSecondary)

                            Text("Fabio")
                                .font(PerchTheme.Font.display)
                                .foregroundColor(PerchTheme.textPrimary)
                        }

                        Spacer()

                        Button(action: { showSettings = true }) {
                            Image(systemName: "gear")
                                .font(PerchTheme.Font.title)
                                .foregroundColor(PerchTheme.textSecondary)
                                .frame(width: 40, height: 40)
                                .background(PerchTheme.cardBackground)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.top, PerchTheme.Spacing.medium)

                    // Search bar
                    searchBar
                        .padding(.horizontal, PerchTheme.Spacing.large)

                    if !searchText.isEmpty {
                        // Search results
                        SearchView(searchText: $searchText, records: records)
                    } else if isLoading {
                        SkeletonHomeSection()
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    } else if records.isEmpty {
                        VStack(spacing: PerchTheme.Spacing.medium) {
                            Image(systemName: "tray")
                                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                                .foregroundColor(PerchTheme.textTertiary)
                            Text("No data yet")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        // Quick Glance summary bar
                        quickGlanceBar
                            .padding(.horizontal, PerchTheme.Spacing.large)

                        // Freshness indicator
                        if let timeStr = freshnessTracker.relativeTimeString(for: "all_records") {
                            HStack(spacing: 4) {
                                if freshnessTracker.isStale("all_records") {
                                    Circle()
                                        .fill(PerchTheme.warning)
                                        .frame(width: 5, height: 5)
                                }
                                Text(timeStr)
                                    .font(PerchTheme.Font.micro)
                                    .foregroundColor(
                                        freshnessTracker.isStale("all_records")
                                            ? PerchTheme.warning
                                            : PerchTheme.textTertiary
                                    )
                            }
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }

                        // Smart-ordered highlights with staggered card appear
                        VStack(spacing: PerchTheme.Spacing.medium) {
                            ForEach(Array(smartOrderedRecords.enumerated()), id: \.element.id) { index, record in
                                WidgetRouter(record: record)
                                    .cardAppear(index: index, appeared: cardsAppeared)
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .onAppear {
                            withAnimation { cardsAppeared = true }
                        }
                    }

                    // Bottom padding
                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await loadData(forceRefresh: true)
                PerchHaptics.success()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textSecondary)

            TextField("Search everything...", text: $searchText)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(PerchTheme.Font.heading)
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
    }

    // MARK: - Quick Glance Bar

    private var quickGlanceBar: some View {
        HStack(spacing: 0) {
            // Calories %
            quickGlanceItem(
                icon: "flame.fill",
                value: caloriesPercentText,
                label: "Calories",
                color: caloriesColor
            )

            divider

            // Next event
            quickGlanceItem(
                icon: "calendar",
                value: nextEventTimeText,
                label: "Next event",
                color: PerchTheme.accent
            )

            divider

            // Active deliveries
            quickGlanceItem(
                icon: "shippingbox.fill",
                value: "\(activeDeliveryCount)",
                label: activeDeliveryCount == 1 ? "Delivery" : "Deliveries",
                color: activeDeliveryCount > 0 ? PerchTheme.success : PerchTheme.textTertiary
            )
        }
        .padding(.vertical, PerchTheme.Spacing.small)
        .background(PerchTheme.cardBackground)
        .cornerRadius(PerchTheme.Card.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                .stroke(PerchTheme.border, lineWidth: 1)
        )
        .staleBorder(tier: freshnessTracker.urgencyTier(for: "all_records"))
    }

    @ViewBuilder
    private func quickGlanceItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(PerchTheme.Font.micro)
                    .foregroundColor(color)
                Text(value)
                    .font(PerchTheme.Font.bodyNumeric)
                    .foregroundColor(PerchTheme.textPrimary)
            }
            Text(label)
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(PerchTheme.border)
            .frame(width: 1, height: 30)
    }

    // MARK: - Quick Glance Data

    private var caloriesPercentText: String {
        guard let record = todaysCaloriesRecord,
              let m = record.asMeasurement(),
              let target = m.target, target > 0 else { return "--%" }
        let pct = Int(min(m.value / target, 1.5) * 100)
        return "\(pct)%"
    }

    private var caloriesColor: Color {
        guard let record = todaysCaloriesRecord,
              let m = record.asMeasurement(),
              let target = m.target, target > 0 else { return PerchTheme.textTertiary }
        let ratio = m.value / target
        if ratio > 1.1 { return PerchTheme.error }
        if ratio > 0.9 { return PerchTheme.success }
        return PerchTheme.accent
    }

    private var nextEventTimeText: String {
        let futureEvents = records.compactMap { record -> (Record, EventData)? in
            guard let event = record.asEvent(), event.start > Date.now else { return nil }
            return (record, event)
        }.sorted { $0.1.start < $1.1.start }

        guard let next = futureEvents.first else { return "None" }
        let interval = next.1.start.timeIntervalSince(Date.now)
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    private var activeDeliveryCount: Int {
        records.filter {
            guard let d = $0.asDelivery() else { return false }
            let s = d.status.lowercased()
            return s != "delivered" && s != "cancelled"
        }.count
    }

    // MARK: - Smart Ordering

    /// Orders cards by urgency/relevance:
    /// 1. Deliveries that are out_for_delivery (most urgent)
    /// 2. Calendar events within 2 hours
    /// 3. Health alerts (missed targets)
    /// 4. Other active deliveries
    /// 5. Today's calories
    /// 6. Upcoming events
    /// 7. Recent bookmarks, checklists, cost summaries
    private var smartOrderedRecords: [Record] {
        var ordered: [Record] = []
        var usedIds = Set<UUID>()

        func addUnique(_ record: Record) {
            guard !usedIds.contains(record.id) else { return }
            usedIds.insert(record.id)
            ordered.append(record)
        }

        func addUniqueAll(_ records: [Record]) {
            for r in records { addUnique(r) }
        }

        // 1. Out-for-delivery (most urgent)
        let outForDelivery = records.filter {
            guard let d = $0.asDelivery() else { return false }
            return d.status.lowercased().replacingOccurrences(of: " ", with: "_") == "out_for_delivery"
        }
        addUniqueAll(outForDelivery)

        // 2. Calendar events within 2 hours
        let twoHoursFromNow = Date.now.addingTimeInterval(2 * 3600)
        let imminentEvents = records.filter {
            guard let e = $0.asEvent() else { return false }
            return e.start > Date.now && e.start <= twoHoursFromNow
        }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
        addUniqueAll(imminentEvents)

        // 3. Health alerts (calories over target by >10%)
        if let caloriesRecord = todaysCaloriesRecord,
           let m = caloriesRecord.asMeasurement(),
           let target = m.target, target > 0, m.value > target * 1.1 {
            addUnique(caloriesRecord)
        }

        // 4. Other active deliveries
        let otherActiveDeliveries = records.filter {
            guard let d = $0.asDelivery() else { return false }
            let s = d.status.lowercased()
            return s != "delivered" && s != "cancelled"
        }
        addUniqueAll(otherActiveDeliveries)

        // 5. Today's calories (if not already added as alert)
        if let caloriesRecord = todaysCaloriesRecord {
            addUnique(caloriesRecord)
        }

        // 6. Upcoming events (not imminent)
        let upcomingEvents = records.filter {
            guard let e = $0.asEvent() else { return false }
            return e.start > twoHoursFromNow
        }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
        addUniqueAll(Array(upcomingEvents.prefix(3)))

        // 7. Latest bookmark
        if let bookmark = records.first(where: { $0.type == .bookmark }) {
            addUnique(bookmark)
        }

        // 8. Checklist
        if let checklist = records.first(where: { $0.type == .checklist }) {
            addUnique(checklist)
        }

        // 9. Cost breakdown
        if let cost = records.first(where: { $0.type == .costSummary }) {
            addUnique(cost)
        }

        return ordered
    }

    // MARK: - Data Loading

    private func loadData(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            records = try await SupabaseService.shared.fetchRecords(limit: 50, forceRefresh: forceRefresh)
        } catch {
            print("[HomeView] Failed to load records: \(error)")
            records = []
        }
    }

    /// Find today's daily_calories record.
    private var todaysCaloriesRecord: Record? {
        let caloriesRecords = records.filter { $0.asMeasurement()?.metric == "daily_calories" }
        let todayString = {
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return fmt.string(from: Date.now)
        }()
        if let today = caloriesRecords.first(where: { $0.asMeasurement()?.context == todayString }) {
            return today
        }
        return caloriesRecords.sorted {
            let d0 = $0.asMeasurement()?.timestamp ?? $0.createdAt
            let d1 = $1.asMeasurement()?.timestamp ?? $1.createdAt
            return d0 > d1
        }.first
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date.now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Good night"
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environment(DashboardViewModel())
}
