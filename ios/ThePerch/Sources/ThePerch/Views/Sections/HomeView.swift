import SwiftUI

/// The dashboard-of-dashboards (first swipeable page).
/// Features: Quick Glance summary, global search, smart-ordered cards by urgency.
/// Reads all records from DashboardViewModel (single-fetch architecture).
struct HomeView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = HomeViewModel()
    @State private var showSettings = false
    @State private var searchText = ""
    @State private var cardsAppeared = false
    @State private var ambience = AmbienceManager.shared

    private let freshnessTracker = DataFreshnessTracker.shared

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Compact header: greeting + date + settings
                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Text(greetingText)
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(ambience.ambientColor)

                        Text("·")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textTertiary)

                        Text(shortDateString)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)

                        Spacer()

                        Button(action: { showSettings = true }) {
                            Image(systemName: "gear")
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(PerchTheme.cardBackground)
                                .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.top, PerchTheme.Spacing.small)

                    // Dual clock (shows when traveling to a different timezone)
                    if let clock = viewModel.dualClockInfo {
                        dualClockView(clock)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // Search bar
                    searchBar
                        .padding(.horizontal, PerchTheme.Spacing.large)

                    // Error banner
                    if let loadError = viewModel.loadError {
                        ErrorBanner(
                            message: loadError,
                            retryAction: { Task { await dashboardViewModel.loadDashboard(forceRefresh: true) } },
                            onDismiss: { viewModel.loadError = nil }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    if !searchText.isEmpty {
                        // Search results
                        SearchView(searchText: $searchText, records: viewModel.records)
                    } else if dashboardViewModel.isLoading && viewModel.records.isEmpty {
                        SkeletonCardsSection(count: 3)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    } else if viewModel.records.isEmpty {
                        EmptyStateView(
                            icon: "tray",
                            title: "No data yet",
                            subtitle: "Pull to refresh or tap below to try syncing again.",
                            actionTitle: "Refresh"
                        ) {
                            Task { await dashboardViewModel.loadDashboard(forceRefresh: true) }
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        // Quick Glance summary bar
                        quickGlanceBar
                            .padding(.horizontal, PerchTheme.Spacing.large)



                        // Travel card (contextual — only appears when trip is upcoming/active)
                        TravelHomeCard(records: viewModel.records)

                        // Modular cards in time-of-day order
                        VStack(spacing: PerchTheme.Spacing.medium) {
                            let orderedCards = HomeCardOrdering.orderedCards()
                            let isCompactHealth = HomeCardOrdering.isHealthCompact()
                            ForEach(Array(orderedCards.enumerated()), id: \.element) { index, cardType in
                                homeCard(for: cardType, compactHealth: isCompactHealth)
                                    // Hero accent line removed — cards have enough visual separation
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
                await dashboardViewModel.refreshRecords()
                PerchHaptics.success()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
        }
        .onChange(of: dashboardViewModel.allRecords) { _, newRecords in
            viewModel.updateRecords(newRecords)
        }
        .onAppear {
            // Feed initial records if dashboard already loaded
            if !dashboardViewModel.allRecords.isEmpty {
                viewModel.updateRecords(dashboardViewModel.allRecords)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.steel)

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
        .background(PerchTheme.cardInnerBackground)
        .cornerRadius(PerchTheme.Card.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                .stroke(PerchTheme.focusRing, lineWidth: 1)
        )
        .perchGlow(.attention)
    }

    // MARK: - Quick Glance Bar

    /// Items to display in the Quick Glance bar, filtering out zero-value entries.
    private var quickGlanceItems: [(icon: String, value: String, label: String, colorKey: String)] {
        var items: [(icon: String, value: String, label: String, colorKey: String)] = []

        if let travelText = viewModel.travelQuickGlanceText {
            items.append((icon: "airplane", value: travelText, label: "Travel", colorKey: "accent"))
        }

        let calText = viewModel.caloriesPercentText
        if calText != "--%" {
            items.append((icon: "flame.fill", value: calText, label: "Calories", colorKey: viewModel.caloriesColor))
        }

        let eventText = viewModel.nextEventTimeText
        if eventText != "None" {
            items.append((icon: "calendar", value: eventText, label: "Next event", colorKey: "accent"))
        }

        let count = viewModel.activeDeliveryCount
        if count > 0 {
            items.append((icon: "shippingbox.fill", value: "\(count)", label: count == 1 ? "Delivery" : "Deliveries", colorKey: "success"))
        }

        return items
    }

    private func colorForKey(_ key: String) -> Color {
        switch key {
        case "error": return PerchTheme.error
        case "success": return PerchTheme.success
        case "accent": return PerchTheme.accent
        default: return PerchTheme.textTertiary
        }
    }

    private var quickGlanceBar: some View {
        let items = quickGlanceItems
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { divider }
                    quickGlanceItem(
                        icon: item.icon,
                        value: item.value,
                        label: item.label,
                        color: colorForKey(item.colorKey)
                    )
                }
            }
            .padding(.vertical, PerchTheme.Spacing.medium)

            if let timeStr = freshnessTracker.relativeTimeString(for: "all_records") {
                Rectangle()
                    .fill(PerchTheme.divider)
                    .frame(height: 0.5)
                    .padding(.horizontal, PerchTheme.Spacing.medium)

                HStack(spacing: 4) {
                    if freshnessTracker.isStale("all_records") {
                        Circle()
                            .fill(PerchTheme.warning)
                            .frame(width: 4, height: 4)
                    }
                    Text(timeStr)
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(
                            freshnessTracker.isStale("all_records")
                                ? PerchTheme.warning
                                : PerchTheme.textTertiary
                        )
                }
                .padding(.vertical, 6)
            }
        }
        .background(
            LinearGradient(
                colors: [PerchTheme.accent.opacity(0.03), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .cardStyle()
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

    // MARK: - Modular Card Builder

    @ViewBuilder
    private func homeCard(for cardType: HomeCardType, compactHealth: Bool) -> some View {
        switch cardType {
        case .healthSummary:
            HealthSummaryHomeCard(records: viewModel.records, compact: compactHealth)
        case .calendarToday:
            CalendarTodayCard(records: viewModel.records)
        case .calendarTomorrow:
            CalendarTomorrowCard(records: viewModel.records)
        case .nutrition:
            NutritionHomeCard(records: viewModel.records)
        case .deliveries:
            DeliveryHomeCard(records: viewModel.records)
        case .medications:
            MedicationsCard(records: viewModel.records)
        case .weather:
            WeatherCompactCard(records: viewModel.records)
        case .emailSummary:
            EmailSummaryCard(records: viewModel.records)
        }
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

    /// "Sun Mar 8" — short weekday + date for the compact header.
    private var shortDateString: String {
        PerchFormatters.shortWeekdayDate.string(from: Date.now)
    }

    // MARK: - Dual Clock

    @ViewBuilder
    private func dualClockView(_ clock: (homeTz: String, destTz: String, homeLabel: String, destLabel: String)) -> some View {
        let homeTz = TimeZone(identifier: clock.homeTz) ?? .current
        let destTz = TimeZone(identifier: clock.destTz) ?? .current

        let homeFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            f.timeZone = homeTz
            return f
        }()

        let destFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            f.timeZone = destTz
            return f
        }()

        HStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "clock")
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)

            HStack(spacing: 4) {
                Text(clock.homeLabel)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                Text(homeFormatter.string(from: .now))
                    .font(PerchTheme.Font.captionNumeric)
                    .foregroundColor(PerchTheme.textSecondary)
            }

            Text("·")
                .foregroundColor(PerchTheme.textTertiary)

            HStack(spacing: 4) {
                Text(clock.destLabel)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)
                Text(destFormatter.string(from: .now))
                    .font(PerchTheme.Font.captionNumeric)
                    .foregroundColor(PerchTheme.accent)
            }

            Spacer()
        }
    }
}

// MARK: - Hero Card Conditional Modifier

/// Applies hero card treatment only to the first card in the stack.
private struct HeroIfFirstModifier: ViewModifier {
    let isFirst: Bool
    let ambientColor: Color

    func body(content: Content) -> some View {
        if isFirst {
            content.heroCard(ambientColor: ambientColor)
        } else {
            content
        }
    }
}

// MARK: - Preview

#Preview {
    HomeView()
        .environment(DashboardViewModel())
}
