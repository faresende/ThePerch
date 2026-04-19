import SwiftUI

/// Today tab — the smart front page.
/// Evolves from HomeView. Cards start at safe area (no more top offset for pill bar).
/// Reads all records from DashboardViewModel (single-fetch architecture).
struct TodayTab: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = HomeViewModel()
    @State private var searchText = ""
    // Default to `true` so cards are visible from the first render. The
    // previous default of `false` + a `.onAppear` flip was unreliable —
    // SwiftUI's AttributeGraph could finish a render pass before .onAppear
    // fired, leaving every card at .opacity(0) indefinitely (the "Today
    // tab blank below header" bug). Staggered fade-in is nice-to-have;
    // cards being visible is non-negotiable.
    @State private var cardsAppeared = true
    @State private var ambience = AmbienceManager.shared

    let onOpenProfile: () -> Void

    private let freshnessTracker = DataFreshnessTracker.shared

    init(onOpenProfile: @escaping () -> Void = {}) {
        self.onOpenProfile = onOpenProfile
    }

    var body: some View {
        ZStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.cardStack) {
                    // Gentler Perch header: small sage perch-bird glyph next to
                    // the greeting, date underneath. The bird is a placeholder
                    // using SF Symbols — swap to Image("perch-bird-small") once
                    // the custom illustration asset is added to the asset catalog.
                    HStack(alignment: .center, spacing: PerchTheme.Spacing.small) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: PerchTheme.Spacing.xSmall) {
                                // PLACEHOLDER — replace with Image("perch-bird-small")
                                // once the custom illustration is in Assets.xcassets.
                                // Sized to sit optically inline with the title cap height.
                                Image(systemName: "bird.fill")
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundColor(PerchTheme.wellness)
                                    .accessibilityHidden(true)

                                Text(greetingText)
                                    .font(PerchTheme.Font.title)
                                    .foregroundColor(PerchTheme.textPrimary)

                                // Whisper-thin "refreshing in background" cue —
                                // visible only during the brief cache→network
                                // reconciliation window.
                                if dashboardViewModel.isShowingCachedData {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .tint(PerchTheme.textTertiary)
                                        .transition(.opacity)
                                }
                            }

                            Text(shortDateString)
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                                .lineLimit(1)
                                // Align date under the greeting text, not the bird.
                                .padding(.leading, 22 + PerchTheme.Spacing.xSmall)
                        }

                        Spacer()

                        todayProfileEntry
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.top, PerchTheme.Spacing.small)
                    .animation(
                        PerchMotion.prefersReduced ? .none : .easeInOut(duration: 0.2),
                        value: dashboardViewModel.isShowingCachedData
                    )

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

                    // ── Data source: always read from dashboardViewModel directly ──
                    // Use dashboardViewModel.allRecords everywhere for rendering
                    // to avoid the .onChange → viewModel.records timing gap.
                    let records = dashboardViewModel.allRecords
                    let deliveries = dashboardViewModel.trackedDeliveries

                    if !searchText.isEmpty {
                        // Search results
                        SearchView(searchText: $searchText, records: records, deliveries: deliveries)
                    } else if dashboardViewModel.isLoading && records.isEmpty {
                        // Skeletons stay as long as the fetch is in flight. Error
                        // banner above covers the failure case — no timeout needed.
                        SkeletonCardsSection(count: 3)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    } else if records.isEmpty && deliveries.isEmpty {
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
                        quickGlanceBar
                            .padding(.horizontal, PerchTheme.Spacing.large)

                        // Travel card (contextual — only appears when trip is upcoming/active)
                        TravelHomeCard(records: records, deliveries: deliveries)

                        // Modular cards in time-of-day order
                        VStack(spacing: PerchTheme.Spacing.medium) {
                            let orderedCards = HomeCardOrdering.orderedCards()
                            let isCompactHealth = HomeCardOrdering.isHealthCompact()
                            ForEach(Array(orderedCards.enumerated()), id: \.element) { index, cardType in
                                homeCard(for: cardType, compactHealth: isCompactHealth, records: records, deliveries: deliveries)
                                    .cardAppear(index: index, appeared: cardsAppeared)
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        // NOTE: cardsAppeared is flipped to true in the outer .onAppear
                        // (on TodayTab itself) — doing it here was unreliable because
                        // the content branch may not re-trigger .onAppear if data
                        // arrives between body evaluations, leaving cards at opacity 0.
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
        .onChange(of: dashboardViewModel.allRecords) { _, _ in
            // Sync to HomeViewModel for Quick Glance computed properties
            viewModel.updateRecords(dashboardViewModel.allRecords, trackedDeliveries: dashboardViewModel.trackedDeliveries)
        }
        .onChange(of: dashboardViewModel.trackedDeliveries) { _, _ in
            viewModel.updateRecords(dashboardViewModel.allRecords, trackedDeliveries: dashboardViewModel.trackedDeliveries)
        }
        .onAppear {
            viewModel.updateRecords(dashboardViewModel.allRecords, trackedDeliveries: dashboardViewModel.trackedDeliveries)
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

    /// Horizontal row of at-a-glance chips (next event, deliveries, weather).
    /// Collapses to nothing when no chips qualify — no reserved empty space.
    @ViewBuilder
    private var quickGlanceBar: some View {
        let chips = quickGlanceChips
        if !chips.isEmpty {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(chips.enumerated()), id: \.element.id) { index, chip in
                    glanceChipView(chip: chip)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Thin vertical rule between chips — editorial separator,
                    // no card chrome. Skipped after the last chip.
                    if index < chips.count - 1 {
                        Rectangle()
                            .fill(PerchTheme.border)
                            .frame(width: 1, height: 36)
                            .padding(.horizontal, PerchTheme.Spacing.xSmall)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func glanceChipView(chip: GlanceChip) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chip.label.uppercased())
                .font(PerchTheme.Font.micro)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundColor(PerchTheme.textTertiary)
                .lineLimit(1)

            Text(chip.value)
                .font(PerchTheme.Font.heading)
                .foregroundColor(chip.accent ? PerchTheme.accent : PerchTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    // MARK: - Modular Card Builder

    @ViewBuilder
    private func homeCard(for cardType: HomeCardType, compactHealth: Bool, records: [Record], deliveries: [DeliveryData]) -> some View {
        switch cardType {
        case .healthSummary:
            HealthSummaryHomeCard(records: records, compact: compactHealth)
        case .calendarToday:
            CalendarTodayCard(records: records)
        case .calendarTomorrow:
            CalendarTomorrowCard(records: records)
        case .nutrition:
            NutritionHomeCard(records: records)
        case .deliveries:
            DeliveryHomeCard(deliveries: deliveries)
        case .medications:
            MedicationsCard(records: records)
        case .weather:
            WeatherCompactCard(records: records)
        case .emailSummary:
            EmailSummaryCard(records: records)
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
