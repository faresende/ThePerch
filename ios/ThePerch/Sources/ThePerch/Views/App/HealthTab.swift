import SwiftUI

/// Health tab — container with Overview / Workouts / Nutrition segments.
/// Reads records from DashboardViewModel (single-fetch architecture).
struct HealthTab: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var selectedSegment: HealthSegment = .overview

    let onOpenProfile: () -> Void

    init(onOpenProfile: @escaping () -> Void = {}) {
        self.onOpenProfile = onOpenProfile
    }

    enum HealthSegment: String, CaseIterable, Hashable, Identifiable {
        case overview = "Overview"
        case workouts = "Workouts"
        case nutrition = "Nutrition"
        var id: HealthSegment { self }
    }

    @Environment(\.perchPalette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Sticky header block: ChromeRow + PillNav, both pinned to
                // the top. Status-bar area reserved by the ignoresSafeArea
                // below so content scrolls behind the status bar.
                VStack(spacing: 0) {
                    PerchChromeRow(onBack: nil, onAvatar: onOpenProfile)

                    PerchPillNav(
                        items: [
                            .init(option: .overview,  label: "Overview",  systemImage: "circle.dotted"),
                            .init(option: .workouts,  label: "Workouts",  systemImage: "dumbbell"),
                            .init(option: .nutrition, label: "Nutrition", systemImage: "leaf"),
                        ],
                        selection: $selectedSegment
                    )
                }
                .background(palette.bg)
                .padding(.top, 54) // reserve for Dynamic Island / status bar

                // Segment content.
                //
                // `.ignoresSafeArea(edges: .bottom)` lets this inner page
                // TabView extend under the main tab bar. Without it, the
                // inner TabView stops at the system tab bar's safe-area
                // inset, leaving a flat strip of `palette.bg` visible
                // through the tab bar's glass — which reads as a solid box
                // instead of glass. Each segment's ScrollView has a
                // `shellContentInsetHeight` bottom spacer so visible content
                // still ends above the tab bar; only scroll geometry
                // extends beneath it to feed the glass.
                TabView(selection: $selectedSegment) {
                    HealthOverviewSegment()
                        .tag(HealthSegment.overview)

                    WorkoutsSegment()
                        .tag(HealthSegment.workouts)

                    NutritionSegment()
                        .tag(HealthSegment.nutrition)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Overview Segment

/// Health overview — Sections v2.
/// Editorial opener, readiness ring + sleep/recovery stack, 7-day trend
/// table with sparklines + ink deltas, and a "Today" plan card. Colour
/// discipline: kinetic is reserved for the active pill-nav tab; all
/// emphasis here is in ink. Real data where available (sleep_duration,
/// avg_sleep_hrv, lowest_sleep_hr); readiness + trend deltas fall back
/// to spec-matching mocks until the Oura pipeline exposes them.
struct HealthOverviewSegment: View {
    @Environment(\.perchPalette) private var palette
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = HealthViewModel()
    @State private var selectedDetail: HealthDetailInfo?

    struct HealthDetailInfo: Identifiable {
        let id = UUID()
        let title: String
        let records: [Record]
        let unit: String
        let formatAsTime: Bool
        let higherIsBetter: Bool
    }

    // MARK: Data derivations

    /// Most recent measurement value for a metric key, or nil if we
    /// don't have it yet.
    private func latest(_ key: String) -> Double? {
        viewModel.latestByMetric[key]?.1.value
    }

    /// "7:12" style hours:minutes from a decimal-hour value (e.g. 7.2).
    private func formatSleepHours(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return String(format: "%d:%02d", h, m)
    }

    /// Last N measurement points for a metric, padded with the most
    /// recent value if we don't have enough history yet.
    private func sparkPoints(_ key: String, count: Int = 7) -> [Double] {
        let recent = viewModel.recordsForMetric(key)
            .suffix(count)
            .compactMap { $0.asMeasurement()?.value }
        if recent.count >= 2 { return Array(recent) }
        // Fall back so the sparkline still renders flat-ish.
        let v = recent.last ?? latest(key) ?? 0
        return Array(repeating: v, count: count)
    }

    /// Uppercase short weekday + date, e.g. "MON · APR 20".
    private var todayKicker: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE · MMM d"
        return f.string(from: Date.now).uppercased()
    }

    /// "Apr 14 – 20" for the 7-day trend card.
    private var sevenDayRange: String {
        let cal = Calendar.current
        let now = Date.now
        let weekAgo = cal.date(byAdding: .day, value: -6, to: now) ?? now
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "MMM d"
        return "\(f.string(from: weekAgo)) – \(f.string(from: now))"
    }

    var body: some View {
        // Real-data pulls. Defaults match the handoff mocks so the
        // screen reads as designed before the full Oura pipeline is wired.
        let sleepHours = latest("sleep_duration") ?? 7.20
        let hrv = latest("avg_sleep_hrv") ?? 58
        let rhr = latest("lowest_sleep_hr") ?? 52
        // Readiness + recovery aren't in chartMetricOrder yet; mocked.
        let readiness = 82
        let recoveryPct = 74
        let deepSleepDeltaMin = 12

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(
                    kicker: todayKicker,
                    title: "Well-rested. Ready when you are.",
                    aside: "Updated\n5:42 am"
                )

                // ── Readiness hero card ────────────────────────────
                PerchSectionCard {
                    HStack(alignment: .center, spacing: 22) {
                        ReadinessRing(value: readiness)

                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 2) {
                                PerchKicker("Sleep")
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    PerchNum(formatSleepHours(sleepHours), size: 24)
                                    Text("hrs")
                                        .font(.system(size: 12))
                                        .foregroundStyle(palette.muted)
                                }
                                Text("Deep +\(deepSleepDeltaMin)m vs avg")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.muted)
                                    .padding(.top, 2)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                PerchKicker("Recovery")
                                PerchNum("\(recoveryPct)", size: 24, suffix: "%")
                                Text("HRV \(Int(hrv)) · RHR \(Int(rhr))")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(palette.muted)
                                    .padding(.top, 2)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                }

                // ── 7-day trend card ────────────────────────────────
                PerchSectionCard {
                    HStack {
                        PerchKicker("Seven-day trend")
                        Spacer()
                        Text(sevenDayRange)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.muted)
                    }
                    .padding(.bottom, 4)

                    let trendRows: [OverviewTrendRow.Model] = [
                        .init(label: "Sleep",
                              current: formatSleepHours(sleepHours).appending("h"),
                              delta: "+22m",
                              points: sparkPoints("sleep_duration")),
                        .init(label: "Recovery",
                              current: "\(recoveryPct)%",
                              delta: "+4%",
                              points: sparkPoints("avg_sleep_hrv")),
                        .init(label: "Resting HR",
                              current: "\(Int(rhr)) bpm",
                              delta: "−2",
                              points: sparkPoints("lowest_sleep_hr"))
                    ]

                    ForEach(Array(trendRows.enumerated()), id: \.offset) { i, row in
                        OverviewTrendRow(model: row)
                        if i < trendRows.count - 1 {
                            PerchSoftDivider()
                        }
                    }
                }

                // ── Today's plan card ───────────────────────────────
                PerchSectionCard {
                    PerchKicker("Today")
                        .padding(.bottom, 10)

                    VStack(alignment: .leading, spacing: 14) {
                        TodayPlanRow(
                            symbol: "dumbbell",
                            title: "Chest & Triceps · Session 48",
                            subtitle: "Suggested · 18:00 · ~55 min"
                        )
                        TodayPlanRow(
                            symbol: "leaf",
                            title: "Target: 2,900 kcal · 190P / 350C / 80F",
                            subtitle: "1,331 logged · 1,569 to go"
                        )
                    }
                }

                Color.clear
                    .frame(height: PerchTheme.TabBar.shellContentInsetHeight)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 140)
        }
        .refreshable {
            PerchHaptics.medium()
            await dashboardViewModel.loadDashboard(forceRefresh: true)
            PerchHaptics.success()
        }
        .onChange(of: dashboardViewModel.healthRecords) { _, newRecords in
            viewModel.records = newRecords
        }
        .onAppear {
            if !dashboardViewModel.healthRecords.isEmpty {
                viewModel.records = dashboardViewModel.healthRecords
            }
        }
        .sheet(item: $selectedDetail) { detail in
            HealthDetailView(
                title: detail.title,
                records: detail.records,
                unit: detail.unit,
                formatAsTime: detail.formatAsTime,
                higherIsBetter: detail.higherIsBetter
            )
        }
    }
}

// MARK: - Overview sub-components

/// Big circular readiness ring: 130pt diameter, 6pt stroke, ink colour.
/// Number + "READY" cap sit centred. 82 is the spec default.
private struct ReadinessRing: View {
    @Environment(\.perchPalette) private var palette
    let value: Int

    var body: some View {
        let fraction = Double(max(0, min(100, value))) / 100.0
        ZStack {
            Circle()
                .stroke(palette.ink.opacity(0.12), lineWidth: 6)
                .frame(width: 130, height: 130)

            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(palette.ink,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 130, height: 130)

            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 36, weight: .semibold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
                    .tracking(-1)
                Text("READY")
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.6)
                    .foregroundStyle(palette.muted)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Readiness \(value) out of 100")
    }
}

/// One row in the "Seven-day trend" card: label · sparkline · current
/// value · coloured delta. Delta colour is `palette.good` for positive
/// moves; ink for neutral.
private struct OverviewTrendRow: View {
    @Environment(\.perchPalette) private var palette

    struct Model {
        let label: String
        let current: String
        let delta: String
        let points: [Double]
    }

    let model: Model

    var body: some View {
        HStack(spacing: 12) {
            // Fixed label column so the sparklines align between rows.
            Text(model.label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
                .frame(width: 78, alignment: .leading)

            // Spark flexes to fill the middle of the row.
            PerchSpark(points: model.points)
                .frame(maxWidth: .infinity)

            // Current + delta right-align and hug their content.
            Text(model.current)
                .font(.system(size: 15, weight: .medium, design: .serif))
                .monospacedDigit()
                .foregroundStyle(palette.ink)

            Text(model.delta)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.good)
                .frame(width: 38, alignment: .trailing)
        }
        .padding(.vertical, 10)
    }
}

/// Row inside the "Today" plan card: square ink-tinted icon badge +
/// title + subtitle. Icon uses SF Symbols in the active palette's ink.
private struct TodayPlanRow: View {
    @Environment(\.perchPalette) private var palette

    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.ink.opacity(0.08))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(palette.ink)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(palette.ink)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Workouts Segment

/// Workouts: weekly volume, recent sessions feed, personal records.
/// Reuses existing WorkoutView content directly.
struct WorkoutsSegment: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = HealthViewModel()
    @State private var cardsAppeared = false
    @State private var expandedSessionId: UUID?

    private var workoutRecords: [(Record, WorkoutSessionData)] {
        let records = viewModel.records.compactMap { r -> (Record, WorkoutSessionData)? in
            guard r.type == .workoutSession, let ws = r.asWorkoutSession() else { return nil }
            return (r, ws)
        }
        return records.sorted {
            let date1 = $0.1.dateParsed ?? .distantPast
            let date2 = $1.1.dateParsed ?? .distantPast
            return date1 > date2
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                if dashboardViewModel.isLoading && viewModel.records.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if workoutRecords.isEmpty {
                    placeholderCard(title: "No Workouts", emoji: "🏋️", hint: "Log your first workout")
                } else {
                    WeeklyVolumeCard(records: viewModel.records)
                        .cardAppear(index: 0, appeared: cardsAppeared)
                        .padding(.horizontal, PerchTheme.Spacing.large)

                    feedSection

                    HealthTabPersonalRecordsCard(sessions: workoutRecords.map { $0.1 })
                        .cardAppear(index: workoutRecords.count + 1, appeared: cardsAppeared)
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.bottom, 40)
                }

                Color.clear
                    .frame(height: PerchTheme.TabBar.shellContentInsetHeight)
            }
        }
        .refreshable {
            PerchHaptics.medium()
            await dashboardViewModel.loadDashboard(forceRefresh: true)
            PerchHaptics.success()
        }
        .onChange(of: dashboardViewModel.healthRecords) { _, newRecords in
            viewModel.records = newRecords
        }
        .onAppear {
            if !dashboardViewModel.healthRecords.isEmpty {
                viewModel.records = dashboardViewModel.healthRecords
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                cardsAppeared = true
            }
        }
    }

    @ViewBuilder
    private var feedSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("RECENT SESSIONS")
                .font(PerchTheme.Font.cardEyebrow)
                .foregroundColor(PerchTheme.textSecondary)
                .padding(.horizontal, PerchTheme.Spacing.large)

            ForEach(Array(workoutRecords.enumerated()), id: \.element.0.id) { index, item in
                let isExpanded = expandedSessionId == item.0.id || (index == 0 && expandedSessionId == nil)

                Button {
                    PerchMotion.withOptionalAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if expandedSessionId == item.0.id {
                            expandedSessionId = nil
                        } else {
                            expandedSessionId = item.0.id
                        }
                    }
                } label: {
                    WorkoutSessionFeedCard(session: item.1, isExpanded: isExpanded)
                        .cardAppear(index: index + 1, appeared: cardsAppeared)
                        .padding(.horizontal, PerchTheme.Spacing.large)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func placeholderCard(title: String, emoji: String, hint: String) -> some View {
        VStack(spacing: PerchTheme.Spacing.small) {
            Text(emoji)
                .font(.system(size: 32))
            Text(title)
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textSecondary)
            Text(hint)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(PerchTheme.cardBackground)
        .cornerRadius(PerchTheme.Card.cornerRadius)
        .padding(.horizontal, PerchTheme.Spacing.large)
    }
}

// MARK: - Nutrition Segment

/// Nutrition: daily summary bar, macros card, calories card, meal log.
/// Reuses existing NutritionView content directly.
struct NutritionSegment: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = NutritionViewModel()
    @State private var cardsAppeared = false
    @State private var showingInputSheet = false
    @State private var showingSuggestionsSheet = false

    private var submissionUserId: String? {
        SupabaseService.shared.currentUserId
    }

    var body: some View {
        @Bindable var vm = viewModel

        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    if let error = vm.error {
                        ErrorBanner(
                            message: error,
                            retryAction: { Task { await dashboardViewModel.refreshRecords(forceRefresh: true) } },
                            onDismiss: { vm.error = nil }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    content

                    Color.clear
                        .frame(height: 0)
                        .onAppear {
                            PerchMotion.withOptionalAnimation { cardsAppeared = true }
                        }

                    Spacer()
                        .frame(height: 148)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.refreshRecords(forceRefresh: true)
                PerchHaptics.success()
            }

            floatingActions
        }
        .onChange(of: dashboardViewModel.allRecords) { _, newRecords in
            vm.loadMeals(from: newRecords)
        }
        .onAppear {
            vm.loadMeals(from: dashboardViewModel.allRecords)
        }
        .sheet(isPresented: $showingInputSheet) {
            MealInputSheet(isSubmitting: vm.isAnalyzing) { text, image in
                guard let submissionUserId else {
                    vm.error = "You must be signed in to log a meal."
                    return false
                }
                let didSubmit = await vm.logMeal(text: text, image: image, userId: submissionUserId)
                if didSubmit {
                    await dashboardViewModel.refreshRecords(forceRefresh: true)
                }
                return didSubmit
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingSuggestionsSheet, onDismiss: {
            vm.clearSuggestions()
        }) {
            Group {
                if let submissionUserId {
                    MealSuggestionsSheet(
                        viewModel: vm,
                        userId: submissionUserId,
                        onLogSuggestion: { suggestion in
                            let didSubmit = await vm.logSuggestedMeal(suggestion, userId: submissionUserId)
                            if didSubmit {
                                await dashboardViewModel.refreshRecords(forceRefresh: true)
                                showingSuggestionsSheet = false
                            }
                            return didSubmit
                        }
                    )
                } else {
                    ContentUnavailableView(
                        "Sign in required",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        description: Text("You must be signed in to get or log meal suggestions.")
                    )
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        if dashboardViewModel.isLoading && viewModel.meals.isEmpty {
            VStack(spacing: PerchTheme.Spacing.medium) {
                DailySummaryBar.shimmer
                ForEach(0..<3, id: \.self) { index in
                    MealCard.shimmer
                        .cardAppear(index: index + 1, appeared: cardsAppeared)
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        } else if viewModel.meals.isEmpty {
            EmptyStateView(
                icon: "fork.knife",
                title: "No meals logged",
                subtitle: "Add your first meal to start tracking calories and macros for the day.",
                actionTitle: "Log a meal",
                action: { showingInputSheet = true }
            )
            .padding(.horizontal, PerchTheme.Spacing.large)
        } else {
            LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                ForEach(Array(viewModel.visibleSections.enumerated()), id: \.element.id) { index, section in
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                        NutritionDayHeader(date: section.date)
                        DailySummaryBar(summary: section.summary, title: summaryTitle(for: section.date))

                        ForEach(Array(section.meals.enumerated()), id: \.element.id) { mealIndex, meal in
                            MealCard(meal: meal, viewModel: viewModel)
                                .cardAppear(index: index + mealIndex + 1, appeared: cardsAppeared)
                        }
                    }
                    .onAppear {
                        viewModel.loadHistoryIfNeeded(for: section.date)
                    }
                }

                if viewModel.visibleSections.count < viewModel.daySections.count {
                    HStack {
                        Spacer()
                        ProgressView("Loading more days...")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                        Spacer()
                    }
                    .padding(.vertical, PerchTheme.Spacing.small)
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        }
    }

    private var floatingActions: some View {
        VStack(alignment: .trailing, spacing: PerchTheme.Spacing.small) {
            Button {
                showingSuggestionsSheet = true
            } label: {
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "sparkles")
                        .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                    Text("What should I eat?")
                        .font(PerchTheme.Font.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(PerchTheme.textPrimary)
                .padding(.horizontal, PerchTheme.Spacing.medium)
                .padding(.vertical, PerchTheme.Spacing.small)
                .background(
                    Capsule()
                        .fill(PerchTheme.cardBackground)
                )
                .overlay(
                    Capsule()
                        .stroke(PerchTheme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            Button {
                showingInputSheet = true
            } label: {
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "plus")
                        .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                    Text("Log Meal")
                        .font(PerchTheme.Font.body)
                        .fontWeight(.semibold)
                }
                .foregroundColor(PerchTheme.accentForeground)
                .padding(.horizontal, PerchTheme.Spacing.medium)
                .padding(.vertical, PerchTheme.Spacing.small)
                .background(
                    Capsule()
                        .fill(PerchTheme.accent)
                )
                .shadow(color: PerchTheme.accent.opacity(0.28), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.trailing, PerchTheme.Spacing.large)
        .padding(.bottom, PerchTheme.Spacing.large)
    }

    private func summaryTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "TODAY'S TOTAL"
        }
        if calendar.isDateInYesterday(date) {
            return "YESTERDAY'S TOTAL"
        }
        return "\(PerchFormatters.weekday.string(from: date).uppercased()) TOTAL"
    }
}

// MARK: - Nutrition Day Header (internal)

private struct NutritionDayHeader: View {
    let date: Date

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        return PerchFormatters.weekdayDate.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxxSmall) {
            Text(title.uppercased())
                .font(PerchTheme.Font.cardEyebrow)
                .foregroundColor(PerchTheme.textSecondary)
                .tracking(0.8)

            Text(PerchFormatters.mediumDate.string(from: date))
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)
        }
    }
}

// MARK: - Meal Suggestions Sheet (internal)

private struct MealSuggestionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let viewModel: NutritionViewModel
    let userId: String
    let onLogSuggestion: (MealSuggestion) async -> Bool

    @State private var context = ""

    private var trimmedContext: String? {
        let value = context.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    Text("Ask for meal ideas based on where you are, what you can cook, or what kind of meal fits right now.")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)

                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                        Text("Context")
                            .font(PerchTheme.Font.cardEyebrow)
                            .foregroundColor(PerchTheme.textSecondary)

                        TextField("I'm at a food court", text: $context, axis: .vertical)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                            .lineLimit(2...4)
                            .padding(PerchTheme.Spacing.medium)
                            .background(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                    .fill(PerchTheme.cardInnerBackground)
                            )
                    }

                    Button {
                        Task {
                            await viewModel.requestSuggestions(userId: userId, context: trimmedContext)
                        }
                    } label: {
                        HStack {
                            if viewModel.isLoadingSuggestions {
                                ProgressView()
                                    .tint(PerchTheme.accentForeground)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(viewModel.mealSuggestions.isEmpty ? "Get suggestions" : "Refresh suggestions")
                                .fontWeight(.semibold)
                        }
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.accentForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PerchTheme.Spacing.medium)
                        .background(
                            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                .fill(PerchTheme.accent)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoadingSuggestions)

                    if !viewModel.mealSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Suggestions")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            ForEach(viewModel.mealSuggestions.prefix(3)) { suggestion in
                                SuggestionCard(suggestion: suggestion) {
                                    let didLog = await onLogSuggestion(suggestion)
                                    if didLog {
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(PerchTheme.Spacing.large)
            }
            .background(PerchTheme.background.ignoresSafeArea())
            .navigationTitle("What should I eat?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(PerchTheme.textSecondary)
                }
            }
        }
    }
}

// MARK: - Suggestion Card (internal)

private struct SuggestionCard: View {
    let suggestion: MealSuggestion
    let onLog: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                Text(suggestion.mealName)
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                Text(suggestion.analysisLine)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
            }

            HStack(spacing: PerchTheme.Spacing.small) {
                SuggestionMacroPill(label: "Cal", value: "\(Int(suggestion.calories))", tint: PerchTheme.accent)
                SuggestionMacroPill(label: "P", value: "\(Int(suggestion.protein))g", tint: PerchTheme.macroProtein)
                SuggestionMacroPill(label: "C", value: "\(Int(suggestion.carbs))g", tint: PerchTheme.macroCarbs)
                SuggestionMacroPill(label: "F", value: "\(Int(suggestion.fat))g", tint: PerchTheme.macroFat)
            }

            Button("Log this") {
                Task {
                    await onLog()
                }
            }
            .font(PerchTheme.Font.caption)
            .fontWeight(.semibold)
            .foregroundColor(PerchTheme.accent)
        }
        .padding(PerchTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .fill(PerchTheme.cardBackground.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .stroke(PerchTheme.border.opacity(0.8), lineWidth: 1)
        )
    }
}

private struct SuggestionMacroPill: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textSecondary)

            Text(value)
                .font(PerchTheme.Font.captionNumeric)
                .foregroundColor(PerchTheme.textPrimary)
        }
        .padding(.horizontal, PerchTheme.Spacing.small)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(tint.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }
}

// PersonalRecordsCard reused from WorkoutView.swift - no local duplicate needed

// MARK: - Stub to satisfy usages (delegate to WorkoutView's PersonalRecordsCard)
private struct HealthTabPersonalRecordsCard: View {
    let sessions: [WorkoutSessionData]

    struct PR {
        let name: String
        let weight: Double
        let reps: Int
    }

    private var topLifts: [PR] {
        var bests: [String: (weight: Double, reps: Int)] = [:]

        for session in sessions {
            for exercise in session.exercises {
                for set in exercise.sets {
                    let w = set.weightKg ?? 0
                    let r = set.reps ?? 0
                    if w > 0 {
                        let lowerName = exercise.name.lowercased()
                        if let current = bests[lowerName] {
                            if w > current.weight || (w == current.weight && r > current.reps) {
                                bests[lowerName] = (w, r)
                            }
                        } else {
                            bests[lowerName] = (w, r)
                        }
                    }
                }
            }
        }

        return bests.map { PR(name: $0.key.capitalized, weight: $0.value.weight, reps: $0.value.reps) }
            .sorted { $0.weight > $1.weight }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            HStack(spacing: PerchTheme.Spacing.xSmall) {
                Image(systemName: "trophy.fill")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.accent)
                Text("PERSONAL RECORDS")
                    .font(PerchTheme.Font.cardEyebrow)
                    .foregroundColor(PerchTheme.textSecondary)
                    .tracking(0.8)
                Spacer()
            }

            if topLifts.isEmpty {
                Text("No records yet")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                    ForEach(Array(topLifts.enumerated()), id: \.offset) { index, pr in
                        HStack {
                            Text("\(index + 1).")
                                .font(PerchTheme.Font.captionNumeric)
                                .foregroundColor(PerchTheme.textTertiary)
                                .frame(width: 20, alignment: .leading)

                            Text(pr.name)
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textPrimary)

                            Spacer()

                            Text("\(Int(pr.weight))kg × \(pr.reps)")
                                .font(PerchTheme.Font.captionNumeric)
                                .foregroundColor(PerchTheme.textSecondary)
                        }

                        if index < topLifts.count - 1 {
                            Divider()
                                .background(PerchTheme.border)
                        }
                    }
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }
}

// MARK: - v2 Primitives
//
// Shared building blocks for the Sections v2 redesign. Used by the
// Health segments and the Hub sections. All read from
// @Environment(\.perchPalette) so the screens re-tint with the
// time-of-day palette like the rest of the app.

/// Screen-opening header: small uppercase kicker + italic Fraunces
/// title + optional right-aligned aside. One per screen.
/// e.g. `SectionTitle(kicker: "MON · APR 20", title: "Well-rested.
/// Ready when you are.", aside: "Updated\n5:42 am")`
struct SectionTitle: View {
    @Environment(\.perchPalette) private var palette

    let kicker: String?
    let title: String
    let aside: String?

    init(kicker: String? = nil, title: String, aside: String? = nil) {
        self.kicker = kicker
        self.title = title
        self.aside = aside
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                if let kicker {
                    Text(kicker)
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(palette.muted)
                        .textCase(.uppercase)
                }
                // SF serif (New York) is a touch lighter than Fraunces at
                // the same nominal weight. Bumping to .medium brings the
                // editorial title closer to the design's Fraunces 500.
                Text(title)
                    .font(.system(size: 28, weight: .medium, design: .serif).italic())
                    .foregroundStyle(palette.ink)
                    .tracking(-0.5)
                    .lineSpacing(-2) // → ~1.1 line-height
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let aside {
                Spacer(minLength: 0)
                Text(aside)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(1)
                    .fixedSize(horizontal: true, vertical: true)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 14)
        .padding(.horizontal, 4)
    }
}

/// 10.5pt uppercase tracked label. The small eyebrow above each card's
/// content. `accent` overrides the default muted tone (used when a
/// label wants to carry a kinetic/wellness dot).
struct PerchKicker: View {
    @Environment(\.perchPalette) private var palette

    let text: String
    var accent: Color? = nil

    init(_ text: String, accent: Color? = nil) {
        self.text = text
        self.accent = accent
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(accent ?? palette.muted)
            .textCase(.uppercase)
    }
}

/// Fraunces tabular-nums numeric. Used for every quantitative value
/// across the sections. `suffix` renders smaller + muted (e.g. "%" or
/// "kcal"). Sized via the `size` param.
struct PerchNum: View {
    @Environment(\.perchPalette) private var palette

    let value: String
    let size: CGFloat
    var suffix: String? = nil

    init(_ value: String, size: CGFloat = 32, suffix: String? = nil) {
        self.value = value
        self.size = size
        self.suffix = suffix
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            // .semibold for larger numerics (≥26pt) matches Fraunces 500
            // weight; smaller values stay .medium so inline metrics don't
            // feel clunky.
            Text(value)
                .font(.system(
                    size: size,
                    weight: size >= 26 ? .semibold : .medium,
                    design: .serif
                ))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .tracking(size > 28 ? -0.8 : -0.3)
            if let suffix {
                Text(suffix)
                    .font(.system(size: size * 0.5, weight: .regular, design: .serif))
                    .foregroundStyle(palette.muted)
            }
        }
    }
}

/// Card wrapper — 22pt radius, 20pt padding, palette card surface.
/// `tone: .dim` swaps to `palette.cardDim` for subordinate sub-panels
/// (used e.g. by the Travel FlightStrip inside its parent trip card).
///
/// IMPORTANT: content is wrapped in a VStack so multiple top-level
/// children are treated as a single block. Without this, a ViewBuilder
/// returning a TupleView causes `.background()` to be applied per-child
/// — every row renders its own card, which was the "broken trend card"
/// bug in the first pass.
struct PerchSectionCard<Content: View>: View {
    @Environment(\.perchPalette) private var palette

    enum Tone { case card, dim }

    let tone: Tone
    let padding: CGFloat
    let content: Content

    init(tone: Tone = .card, padding: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(tone == .dim ? palette.cardDim : palette.card)
        )
    }
}

/// Soft hairline divider inside a card (row separator).
struct PerchSoftDivider: View {
    @Environment(\.perchPalette) private var palette
    var body: some View {
        Rectangle()
            .fill(palette.lineSoft)
            .frame(height: 1)
    }
}

/// 4-stage stepper: Ordered → Shipped → In transit → Delivered.
/// Filled dot = done, larger filled dot with ink-haloed ring = active,
/// hollow ring = pending. Connector line: 1.5pt, ink@0.7 when the
/// preceding dot is done, faint@0.3 otherwise. Labels below each dot.
struct PerchStageStepper: View {
    @Environment(\.perchPalette) private var palette

    let stages: [String]
    let currentIdx: Int

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.offset) { i, label in
                dot(at: i, label: label)

                if i < stages.count - 1 {
                    Rectangle()
                        .fill(i < currentIdx ? palette.ink.opacity(0.7) : palette.faint.opacity(0.3))
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        // Line aligns with the dot's vertical center (≈5pt down)
                        .padding(.top, 5)
                }
            }
        }
    }

    @ViewBuilder
    private func dot(at i: Int, label: String) -> some View {
        let done = i < currentIdx
        let active = i == currentIdx
        let color: Color = (done || active) ? palette.ink : palette.faint

        VStack(spacing: 8) {
            ZStack {
                if active {
                    Circle()
                        .fill(palette.ink.opacity(0.12))
                        .frame(width: 20, height: 20)
                }
                Circle()
                    .fill(done || active ? color : Color.clear)
                    .frame(width: active ? 12 : 8, height: active ? 12 : 8)
                    .overlay(
                        Circle()
                            .strokeBorder(color, lineWidth: (done || active) ? 0 : 1.5)
                    )
            }
            .frame(width: 20, height: 20)

            Text(label)
                .font(.system(size: 10.5, weight: active ? .semibold : .regular))
                .tracking(0.2)
                .foregroundStyle(active ? palette.ink : palette.faint)
                .textCase(.uppercase)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(minWidth: 46)
    }
}

/// Tiny polyline sparkline. Fits in a row beside a label + value.
/// Width flexes to fill the HStack cell; height is fixed at 22pt.
/// Normalises the incoming series to its own min/max so the line
/// reads "trend up or down", not absolute scale.
struct PerchSpark: View {
    @Environment(\.perchPalette) private var palette

    let points: [Double]
    var height: CGFloat = 22
    var color: Color? = nil

    var body: some View {
        Canvas { ctx, size in
            guard points.count >= 2 else { return }
            let lo = points.min() ?? 0
            let hi = points.max() ?? 1
            let range = (hi - lo) == 0 ? 1 : (hi - lo)

            // Inset the stroke by half the line width so end-points
            // aren't clipped by the frame edges.
            let pad: CGFloat = 1.5
            let w = size.width - pad * 2
            let h = size.height - pad * 2

            var path = Path()
            for (i, v) in points.enumerated() {
                let x = pad + CGFloat(i) / CGFloat(points.count - 1) * w
                let y = pad + h - CGFloat((v - lo) / range) * h
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            ctx.stroke(
                path,
                with: .color(color ?? palette.ink),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
        }
        .frame(height: height)
    }
}

// MARK: - Preview

#Preview {
    HealthTab()
        .environment(AuthViewModel())
        .environment(DashboardViewModel())
}
