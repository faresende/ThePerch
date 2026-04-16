import SwiftUI

/// Today tab — the smart front page.
/// Evolves from HomeView. Cards start at safe area (no more top offset for pill bar).
/// Reads all records from DashboardViewModel (single-fetch architecture).
struct TodayTab: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = HomeViewModel()
    @State private var searchText = ""
    @State private var cardsAppeared = false
    @State private var ambience = AmbienceManager.shared
    @State private var skeletonExpired = false

    let onOpenProfile: () -> Void

    private let freshnessTracker = DataFreshnessTracker.shared

    init(onOpenProfile: @escaping () -> Void = {}) {
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Compact header: greeting + date
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
                            .lineLimit(1)

                        Spacer()

                        todayProfileEntry
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
                    if let loadError = viewModel.loadError ?? dashboardViewModel.error?.errorDescription {
                        ErrorBanner(
                            message: loadError,
                            retryAction: { Task { await dashboardViewModel.loadDashboard(forceRefresh: true) } },
                            onDismiss: {
                                viewModel.loadError = nil
                                dashboardViewModel.clearError()
                            }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    if !searchText.isEmpty {
                        // Search results
                        SearchView(searchText: $searchText, records: viewModel.records, deliveries: viewModel.trackedDeliveries)
                    } else if dashboardViewModel.isLoading && viewModel.records.isEmpty && !skeletonExpired {
                        SkeletonCardsSection(count: 3)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                            .task {
                                try? await Task.sleep(for: .seconds(15))
                                guard dashboardViewModel.isLoading && viewModel.records.isEmpty else { return }
                                withAnimation { skeletonExpired = true }
                            }
                    } else if dashboardViewModel.allRecords.isEmpty && viewModel.records.isEmpty && viewModel.trackedDeliveries.isEmpty {
                        let _ = debugLogTodayTab("empty", allRecords: dashboardViewModel.allRecords.count, vmRecords: viewModel.records.count, deliveries: viewModel.trackedDeliveries.count, isLoading: dashboardViewModel.isLoading)
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
                        let _ = debugLogTodayTab("content", allRecords: dashboardViewModel.allRecords.count, vmRecords: viewModel.records.count, deliveries: viewModel.trackedDeliveries.count, isLoading: dashboardViewModel.isLoading)
                        quickGlanceBar
                            .padding(.horizontal, PerchTheme.Spacing.large)

                        // Travel card (contextual — only appears when trip is upcoming/active)
                        TravelHomeCard(records: viewModel.records, deliveries: viewModel.trackedDeliveries)

                        // Modular cards in time-of-day order
                        VStack(spacing: PerchTheme.Spacing.medium) {
                            let orderedCards = HomeCardOrdering.orderedCards()
                            let isCompactHealth = HomeCardOrdering.isHealthCompact()
                            ForEach(Array(orderedCards.enumerated()), id: \.element) { index, cardType in
                                homeCard(for: cardType, compactHealth: isCompactHealth)
                                    .cardAppear(index: index, appeared: cardsAppeared)
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .onAppear {
                            PerchMotion.withOptionalAnimation { cardsAppeared = true }
                        }
                    }

                    // Bottom padding for tab bar
                    Color.clear
                        .frame(height: PerchTheme.TabBar.shellContentInsetHeight)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.loadDashboard(forceRefresh: true)
                PerchHaptics.success()
            }
        }
        .onChange(of: dashboardViewModel.allRecords) { old, new in
            #if DEBUG
            print("[TodayTab] onChange(allRecords): \(old.count) → \(new.count)")
            #endif
            viewModel.updateRecords(dashboardViewModel.allRecords, trackedDeliveries: dashboardViewModel.trackedDeliveries)
        }
        .onChange(of: dashboardViewModel.trackedDeliveries) { _, _ in
            viewModel.updateRecords(dashboardViewModel.allRecords, trackedDeliveries: dashboardViewModel.trackedDeliveries)
        }
        .onAppear {
            #if DEBUG
            print("[TodayTab] onAppear: allRecords=\(dashboardViewModel.allRecords.count), isLoading=\(dashboardViewModel.isLoading), error=\(dashboardViewModel.error?.localizedDescription ?? "nil")")
            #endif
            if !dashboardViewModel.allRecords.isEmpty || !dashboardViewModel.trackedDeliveries.isEmpty {
                viewModel.updateRecords(dashboardViewModel.allRecords, trackedDeliveries: dashboardViewModel.trackedDeliveries)
            }
        }
        .onChange(of: dashboardViewModel.isLoading) { _, loading in
            #if DEBUG
            print("[TodayTab] onChange(isLoading): \(loading), allRecords=\(dashboardViewModel.allRecords.count), vm.records=\(viewModel.records.count)")
            #endif
            if !loading { skeletonExpired = false }
        }
    }

    @ViewBuilder
    private var todayProfileEntry: some View {
        ViewThatFits(in: .horizontal) {
            ProfileEntryButton(prominence: .prominent, action: onOpenProfile)
            ProfileEntryButton(prominence: .subtle, action: onOpenProfile)
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

    private struct GlanceChip: Identifiable {
        let id = UUID()
        let emoji: String
        let value: String
        let label: String
        let accent: Bool
    }

    private var quickGlanceChips: [GlanceChip] {
        var chips: [GlanceChip] = []

        // Chip 1: Next event (or travel countdown if no events)
        let eventText = viewModel.nextEventTimeText
        if eventText != "None", let nextTitle = viewModel.nextEventTitle {
            chips.append(GlanceChip(emoji: "🗓", value: eventText, label: nextTitle, accent: true))
        } else if let travelText = viewModel.travelQuickGlanceText {
            chips.append(GlanceChip(emoji: "✈️", value: travelText, label: "Travel", accent: true))
        }

        // Chip 2: Deliveries
        let count = viewModel.activeDeliveryCount
        if count > 0 {
            chips.append(GlanceChip(emoji: "📦", value: "\(count)", label: count == 1 ? "Delivery" : "Deliveries", accent: false))
        }

        // Chip 3: Weather (if available) or Sleep score
        if let weather = viewModel.weatherSummary {
            chips.append(GlanceChip(emoji: "🌤", value: weather.temp, label: weather.condition, accent: false))
        } else if let sleepText = viewModel.sleepScoreText {
            chips.append(GlanceChip(emoji: "😴", value: sleepText, label: "Sleep", accent: false))
        }

        return chips
    }

    private var quickGlanceBar: some View {
        let chips = quickGlanceChips

        return GeometryReader { geo in
            let spacing: CGFloat = PerchTheme.Spacing.small
            let chipCount = max(CGFloat(chips.count), 3)
            let totalSpacing = spacing * (chipCount - 1)
            let chipWidth = (geo.size.width - totalSpacing) / chipCount

            HStack(spacing: spacing) {
                ForEach(chips) { chip in
                    glanceChipView(chip: chip)
                        .frame(width: chipWidth)
                }
            }
        }
        .frame(height: 76)
    }

    @ViewBuilder
    private func glanceChipView(chip: GlanceChip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chip.emoji)
                .font(.system(size: 14))

            Text(chip.value)
                .font(PerchTheme.Font.heading)
                .fontWeight(.bold)
                .foregroundColor(PerchTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(chip.label)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(PerchTheme.Spacing.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .cardStyle()
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
            DeliveryHomeCard(deliveries: viewModel.trackedDeliveries)
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

// MARK: - Preview

#Preview {
    TodayTab()
        .environment(AuthViewModel())
        .environment(DashboardViewModel())
}

// MARK: - Debug Logging

@discardableResult
func debugLogTodayTab(_ branch: String, allRecords: Int, vmRecords: Int, deliveries: Int, isLoading: Bool) -> Void {
    #if DEBUG
    print("[TodayTab] branch=\(branch) allRecords=\(allRecords) vmRecords=\(vmRecords) deliveries=\(deliveries) isLoading=\(isLoading)")
    #endif
}
