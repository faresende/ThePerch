import SwiftUI
import WidgetKit

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
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Header with greeting and settings
                    HStack {
                        Text("\(greetingText), Fabio")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)

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
                        // Daily brief card
                        DailyBriefCard(records: records)
                            .padding(.horizontal, PerchTheme.Spacing.large)

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
                            PerchMotion.withOptionalAnimation { cardsAppeared = true }
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

    /// Items to display in the Quick Glance bar, filtering out zero-value entries.
    private var quickGlanceItems: [(icon: String, value: String, label: String, color: Color)] {
        var items: [(icon: String, value: String, label: String, color: Color)] = []

        // Calories — always show unless no data at all
        let calText = caloriesPercentText
        if calText != "--%" {
            items.append((icon: "flame.fill", value: calText, label: "Calories", color: caloriesColor))
        }

        // Next event — hide when there are none
        let eventText = nextEventTimeText
        if eventText != "None" {
            items.append((icon: "calendar", value: eventText, label: "Next event", color: PerchTheme.accent))
        }

        // Deliveries — hide when zero
        let count = activeDeliveryCount
        if count > 0 {
            items.append((icon: "shippingbox.fill", value: "\(count)", label: count == 1 ? "Delivery" : "Deliveries", color: PerchTheme.success))
        }

        return items
    }

    private var quickGlanceBar: some View {
        let items = quickGlanceItems
        return HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { divider }
                quickGlanceItem(
                    icon: item.icon,
                    value: item.value,
                    label: item.label,
                    color: item.color
                )
            }
        }
        .padding(.vertical, PerchTheme.Spacing.medium)
        .background(
            LinearGradient(
                colors: [PerchTheme.accent.opacity(0.03), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .background(PerchTheme.cardBackground)
        .cornerRadius(PerchTheme.Card.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                .stroke(PerchTheme.accent.opacity(0.3), lineWidth: 1)
        )
        .staleBorder(tier: freshnessTracker.urgencyTier(for: "all_records"))
    }

    @ViewBuilder
    private func quickGlanceItem(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(color)
                Text(value)
                    .font(PerchTheme.Font.titleNumeric)
                    .foregroundColor(PerchTheme.textPrimary)
            }
            Text(label)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(PerchTheme.border)
            .frame(width: 1, height: 40)
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

    /// Current time-of-day period for predictive content ordering.
    private enum TimePeriod {
        case morning    // 6-10am
        case midday     // 10am-4pm
        case evening    // 4-10pm (spec says 6-10pm but we use 4pm for smooth coverage)
        case night      // 10pm-6am

        static var current: TimePeriod {
            let hour = Calendar.current.component(.hour, from: Date.now)
            switch hour {
            case 6..<10: return .morning
            case 10..<16: return .midday
            case 16..<22: return .evening
            default: return .night
            }
        }
    }

    /// Orders cards by urgency/relevance with time-of-day weighting:
    /// - Morning: surface sleep data + today's calendar first
    /// - Midday: surface deliveries + calendar
    /// - Evening: surface nutrition summary + tomorrow's events
    /// - Night: surface sleep prep info
    /// Always-urgent items (out-for-delivery, imminent events) stay at top.
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

        let period = TimePeriod.current

        // === Always-urgent: out-for-delivery ===
        let outForDelivery = records.filter {
            guard let d = $0.asDelivery() else { return false }
            return d.status.lowercased().replacingOccurrences(of: " ", with: "_") == "out_for_delivery"
        }
        addUniqueAll(outForDelivery)

        // === Always-urgent: calendar events within 2 hours ===
        let twoHoursFromNow = Date.now.addingTimeInterval(2 * 3600)
        let imminentEvents = records.filter {
            guard let e = $0.asEvent() else { return false }
            return e.start > Date.now && e.start <= twoHoursFromNow
        }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
        addUniqueAll(imminentEvents)

        // === Time-of-day boosted content ===
        switch period {
        case .morning:
            // Surface sleep/health data first, then today's calendar
            let sleepRecords = records.filter {
                guard let m = $0.asMeasurement() else { return false }
                return m.metric.contains("sleep") || m.metric.contains("resting")
            }
            addUniqueAll(sleepRecords)

            // Today's events (sorted by start time)
            let todayEvents = records.filter {
                guard let e = $0.asEvent() else { return false }
                return Calendar.current.isDateInToday(e.start) && e.start > Date.now
            }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
            addUniqueAll(todayEvents)

        case .midday:
            // Surface deliveries + calendar
            let activeDeliveries = records.filter {
                guard let d = $0.asDelivery() else { return false }
                let s = d.status.lowercased()
                return s != "delivered" && s != "cancelled"
            }
            addUniqueAll(activeDeliveries)

            let todayEvents = records.filter {
                guard let e = $0.asEvent() else { return false }
                return e.start > Date.now && Calendar.current.isDateInToday(e.start)
            }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
            addUniqueAll(todayEvents)

        case .evening:
            // Surface nutrition summary + tomorrow's events
            if let caloriesRecord = todaysCaloriesRecord {
                addUnique(caloriesRecord)
            }
            let macrosRecords = records.filter { $0.displayHint == .macrosBar }
            addUniqueAll(macrosRecords)

            let tomorrowEvents = records.filter {
                guard let e = $0.asEvent() else { return false }
                return Calendar.current.isDateInTomorrow(e.start)
            }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
            addUniqueAll(tomorrowEvents)

        case .night:
            // Surface sleep prep: health data, then tomorrow's first events
            let healthRecords = records.filter {
                guard let m = $0.asMeasurement() else { return false }
                return m.metric.contains("sleep") || m.metric.contains("heart") || m.metric.contains("resting")
            }
            addUniqueAll(healthRecords)

            let tomorrowEvents = records.filter {
                guard let e = $0.asEvent() else { return false }
                return Calendar.current.isDateInTomorrow(e.start)
            }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
            addUniqueAll(Array(tomorrowEvents.prefix(2)))
        }

        // === Standard priority items (fill remaining) ===

        // Health alerts (calories over target by >10%)
        if let caloriesRecord = todaysCaloriesRecord,
           let m = caloriesRecord.asMeasurement(),
           let target = m.target, target > 0, m.value > target * 1.1 {
            addUnique(caloriesRecord)
        }

        // Other active deliveries
        let otherActiveDeliveries = records.filter {
            guard let d = $0.asDelivery() else { return false }
            let s = d.status.lowercased()
            return s != "delivered" && s != "cancelled"
        }
        addUniqueAll(otherActiveDeliveries)

        // Today's calories (if not already added)
        if let caloriesRecord = todaysCaloriesRecord {
            addUnique(caloriesRecord)
        }

        // Upcoming events (not imminent)
        let upcomingEvents = records.filter {
            guard let e = $0.asEvent() else { return false }
            return e.start > twoHoursFromNow
        }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
        addUniqueAll(Array(upcomingEvents.prefix(3)))

        // Latest bookmark
        if let bookmark = records.first(where: { $0.type == .bookmark }) {
            addUnique(bookmark)
        }

        // Checklist
        if let checklist = records.first(where: { $0.type == .checklist }) {
            addUnique(checklist)
        }

        // Cost breakdown
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
            updateWidgetData()
        } catch {
            print("[HomeView] Failed to load records: \(error)")
            records = []
        }
    }

    // MARK: - Widget Data

    private func updateWidgetData() {
        guard let defaults = UserDefaults(suiteName: "group.com.theperch.shared") else { return }

        // Calories percent
        defaults.set(caloriesPercentText, forKey: "widget_calories_percent")

        // Next event — title + time
        let futureEvents = records.compactMap { record -> EventData? in
            guard let event = record.asEvent(), event.start > .now else { return nil }
            return event
        }.sorted { $0.start < $1.start }

        if let next = futureEvents.first {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            defaults.set("\(next.title) \(fmt.string(from: next.start))", forKey: "widget_next_event")
        } else {
            defaults.set("No events", forKey: "widget_next_event")
        }

        // Active deliveries
        defaults.set(activeDeliveryCount, forKey: "widget_active_deliveries")

        // Last updated
        defaults.set(Date.now, forKey: "widget_last_updated")

        WidgetCenter.shared.reloadAllTimelines()
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
