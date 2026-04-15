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

    enum HealthSegment: String, CaseIterable {
        case overview = "Overview"
        case workouts = "Workouts"
        case nutrition = "Nutrition"
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    ProfileEntryButton(prominence: .subtle, action: onOpenProfile)
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.top, PerchTheme.Spacing.small)

                // Segmented picker at top
                Picker("Section", selection: $selectedSegment) {
                    ForEach(HealthSegment.allCases, id: \.self) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.vertical, PerchTheme.Spacing.small)
                .background(PerchTheme.background)

                // Segment content
                TabView(selection: $selectedSegment) {
                    HealthOverviewSegment()
                        .tag(HealthSegment.overview)

                    WorkoutsSegment()
                        .tag(HealthSegment.workouts)

                    NutritionSegment()
                        .tag(HealthSegment.nutrition)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
    }
}

// MARK: - Overview Segment

/// Health overview: body metrics, sleep score + readiness, trend charts.
/// Reuses existing HealthView content directly.
struct HealthOverviewSegment: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = HealthViewModel()
    @State private var selectedDetail: HealthDetailInfo?
    @State private var cardsAppeared = false

    struct HealthDetailInfo: Identifiable {
        let id = UUID()
        let title: String
        let records: [Record]
        let unit: String
        let formatAsTime: Bool
        let higherIsBetter: Bool
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                if viewModel.error != nil {
                    ErrorBanner(
                        message: "Failed to load health data",
                        retryAction: { Task { await dashboardViewModel.loadDashboard(forceRefresh: true) } },
                        onDismiss: { viewModel.clearError() }
                    )
                    .padding(.horizontal, PerchTheme.Spacing.large)
                }

                if dashboardViewModel.isLoading && viewModel.records.isEmpty {
                    SkeletonCardsSection(count: 3)
                        .padding(.horizontal, PerchTheme.Spacing.large)
                } else if viewModel.records.isEmpty {
                    EmptyStateView(
                        icon: "heart.text.square",
                        title: "No health data",
                        subtitle: viewModel.isHealthKitAvailable
                            ? "Connect Apple Health to start syncing your latest health metrics."
                            : "Health data will appear here once your sources start syncing.",
                        actionTitle: viewModel.isHealthKitAvailable ? "Connect Apple Health" : nil,
                        action: viewModel.isHealthKitAvailable ? { Task { await viewModel.syncWithHealthKit() } } : nil
                    )
                    .padding(.horizontal, PerchTheme.Spacing.large)
                } else {
                    // Daily calories card
                    if let (record, measurement) = viewModel.displayedDailyCalories,
                       let target = measurement.target {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                            CaloriesCard(
                                consumed: measurement.value,
                                target: target,
                                unit: measurement.unit,
                                lastUpdated: viewModel.isSyntheticNutritionRecord(record) ? nil : (measurement.timestamp ?? record.updatedAt)
                            )

                            if !viewModel.isSyntheticNutritionRecord(record) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Button {
                                        Task { await viewModel.saveDailyCaloriesToHealth() }
                                    } label: {
                                        HStack(spacing: 8) {
                                            if viewModel.isSavingToHealth {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle())
                                                    .scaleEffect(0.8)
                                            } else {
                                                Image(systemName: "square.and.arrow.down")
                                            }
                                            Text(viewModel.isSavingToHealth ? "Saving to Apple Health..." : "Save daily calories to Apple Health")
                                        }
                                        .font(PerchTheme.Font.caption)
                                        .foregroundColor(PerchTheme.accent)
                                    }
                                    .disabled(viewModel.isSavingToHealth)

                                    if let success = viewModel.healthExportSuccess {
                                        Text(success)
                                            .font(PerchTheme.Font.caption)
                                            .foregroundColor(PerchTheme.success)
                                    }

                                    if let error = viewModel.healthExportError {
                                        Text(error)
                                            .font(PerchTheme.Font.caption)
                                            .foregroundColor(PerchTheme.error)
                                    }
                                }
                                .padding(.horizontal, PerchTheme.Spacing.small)
                            }
                        }
                        .cardAppear(index: 0, appeared: cardsAppeared)
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    } else {
                        placeholderCard(title: "Daily Calories", emoji: "🔥", hint: "Log food with Claudinho")
                    }

                    // Daily macros card
                    if let (record, macros) = viewModel.displayedMacros {
                        MacrosCard(
                            protein: macros.protein,
                            proteinTarget: macros.proteinTarget,
                            carbs: macros.carbs,
                            carbsTarget: macros.carbsTarget,
                            fat: macros.fat,
                            fatTarget: macros.fatTarget,
                            lastUpdated: viewModel.isSyntheticNutritionRecord(record) ? nil : (macros.dateAsDate ?? record.updatedAt)
                        )
                        .cardAppear(index: 1, appeared: cardsAppeared)
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    } else {
                        placeholderCard(title: "Daily Macros", emoji: "🥩", hint: "Log food with Claudinho")
                    }

                    // Chart cards per metric
                    ForEach(Array(HealthViewModel.chartMetricOrder.enumerated()), id: \.element.key) { chartIndex, metricInfo in
                        let metricRecords = viewModel.recordsForMetric(metricInfo.key)
                        let isTimeBased = metricInfo.key == "sleep_duration" || metricInfo.key == "deep_sleep"
                        if !metricRecords.isEmpty {
                            Button {
                                PerchHaptics.light()
                                selectedDetail = HealthDetailInfo(
                                    title: metricInfo.title,
                                    records: metricRecords,
                                    unit: isTimeBased ? "" : metricInfo.unit,
                                    formatAsTime: isTimeBased,
                                    higherIsBetter: metricInfo.higherIsBetter
                                )
                            } label: {
                                ChartCard(
                                    title: metricInfo.title,
                                    records: metricRecords,
                                    unit: isTimeBased ? "" : metricInfo.unit,
                                    formatAsTime: isTimeBased,
                                    higherIsBetter: metricInfo.higherIsBetter
                                )
                            }
                            .buttonStyle(CardPressStyle())
                            .cardAppear(index: chartIndex + 4, appeared: cardsAppeared)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        } else {
                            placeholderCard(
                                title: metricInfo.title,
                                emoji: metricInfo.emoji,
                                hint: placeholderHint(for: metricInfo.key)
                            )
                        }
                    }
                }

                Color.clear
                    .frame(height: 0)
                    .onAppear {
                        PerchMotion.withOptionalAnimation { cardsAppeared = true }
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

    private func placeholderCard(title: String, emoji: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(emoji)
                    .font(PerchTheme.Font.title)
                Text(title.uppercased())
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)
            }

            Text("No data yet")
                .font(PerchTheme.Font.displayNumeric)
                .foregroundColor(PerchTheme.textTertiary)

            Text(hint)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .padding(.horizontal, PerchTheme.Spacing.large)
    }

    private func placeholderHint(for metricKey: String) -> String {
        switch metricKey {
        case "weight":
            return "Sync Apple Health or log with Claudinho"
        case "skeletal_muscle", "body_fat_mass":
            return "Share your InBody scan with Claudinho"
        case "sleep_duration", "deep_sleep", "lowest_sleep_hr", "avg_sleep_hrv":
            return "Share your Oura data with Claudinho"
        default:
            return "Ask Claudinho to log this metric"
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

// MARK: - Preview

#Preview {
    HealthTab()
        .environment(AuthViewModel())
        .environment(DashboardViewModel())
}
