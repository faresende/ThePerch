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
                    LazyView { HealthOverviewSegment() }
                        .tag(HealthSegment.overview)

                    LazyView { WorkoutsSegment() }
                        .tag(HealthSegment.workouts)

                    LazyView { NutritionSegment() }
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
        PerchFormatters.agendaKicker.string(from: Date.now).uppercased()
    }

    /// "Apr 14 – 20" for the 7-day trend card.
    private var sevenDayRange: String {
        let cal = Calendar.current
        let now = Date.now
        let weekAgo = cal.date(byAdding: .day, value: -6, to: now) ?? now
        let f = PerchFormatters.shortDateUK
        return "\(f.string(from: weekAgo)) – \(f.string(from: now))"
    }

    /// "Updated\n5:42 am" — derived from the freshest record we have.
    /// Returns "—" if no records loaded yet.
    private var lastUpdatedAside: String {
        guard let latest = dashboardViewModel.healthRecords.map(\.updatedAt).max() else {
            return "Updated\n—"
        }
        return "Updated\n\(PerchFormatters.healthFreshness.string(from: latest))"
    }

    /// Most recent workout session, if any.
    private var latestWorkout: WorkoutSessionData? {
        dashboardViewModel.healthRecords
            .filter { $0.type == .workoutSession }
            .compactMap { $0.asWorkoutSession() }
            .max { ($0.dateParsed ?? .distantPast) < ($1.dateParsed ?? .distantPast) }
    }

    /// Title + subtitle for the Today card's workout row, derived from
    /// the most recent logged session. Falls back to a "no sessions"
    /// state until the user has any history.
    private var todayWorkoutRow: (title: String, subtitle: String) {
        guard let session = latestWorkout else {
            return ("No sessions yet", "Log your first workout")
        }
        let muscleLabel = session.muscleGroups.map { $0.capitalized }.joined(separator: " + ")
        let title: String = {
            if let num = session.sessionNumber {
                return "\(muscleLabel) · Session \(num)"
            }
            return muscleLabel.isEmpty ? "Workout session" : muscleLabel
        }()
        let when = session.dateParsed?.relativeTime ?? "recent"
        if let dur = session.durationMin {
            return (title, "\(when) · \(dur) min")
        }
        return (title, when)
    }

    /// Title + subtitle for the Today card's nutrition row, derived from
    /// today's NutritionTargets (calories/macros) and the meals logged
    /// so far today.
    private var todayNutritionRow: (title: String, subtitle: String) {
        // `dashboardViewModel.healthRecords` only collects `.health` and
        // `.workouts` categories — nutrition records live under
        // `.nutrition` and would silently come back empty here. Read
        // from the full record set so meal totals + targets-from-meals
        // resolve correctly.
        let records = dashboardViewModel.allRecords
        let targets = NutritionTargets.resolved(for: .now, records: records)

        let cal = Calendar.current
        let consumedCalories = records
            .filter { $0.category == .nutrition && $0.type == .meal }
            .map { MealRecord(from: $0) }
            .filter { cal.isDate($0.mealTime, inSameDayAs: .now) }
            .reduce(0.0) { $0 + $1.calories }

        let calTarget = Int(targets.calories.rounded())
        let p = Int(targets.protein.rounded())
        let c = Int(targets.carbs.rounded())
        let f = Int(targets.fat.rounded())
        let logged = Int(consumedCalories.rounded())
        let remaining = max(0, calTarget - logged)

        let title = "Target: \(calTarget.formatted()) kcal · \(p)P / \(c)C / \(f)F"
        let subtitle = "\(logged.formatted()) logged · \(remaining.formatted()) to go"
        return (title, subtitle)
    }

    var body: some View {
        // Real-data pulls against Oura records. Defaults match the handoff
        // mocks so the screen doesn't look broken while waiting for the
        // first sync of a given metric.
        let sleepHours = latest("sleep_duration") ?? 7.20
        let hrv = latest("avg_sleep_hrv") ?? 58
        let rhr = latest("lowest_sleep_hr") ?? 52
        // Readiness drives both the recovery ring and the "readiness" number.
        // Falls back to the mock value only when no record exists at all.
        let readiness = Int(latest("readiness_score") ?? 82)
        let recoveryPct = readiness
        // Deep-sleep-vs-average delta still mocked — needs a rolling-baseline
        // calculation that isn't wired yet. Left as mock until the trend
        // pipeline lands.
        let deepSleepDeltaMin = 12

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(
                    kicker: todayKicker,
                    title: "Well-rested. Ready when you are.",
                    aside: lastUpdatedAside
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

                    let workoutRow = todayWorkoutRow
                    let nutritionRow = todayNutritionRow
                    VStack(alignment: .leading, spacing: 14) {
                        TodayPlanRow(
                            symbol: "dumbbell",
                            title: workoutRow.title,
                            subtitle: workoutRow.subtitle
                        )
                        TodayPlanRow(
                            symbol: "leaf",
                            title: nutritionRow.title,
                            subtitle: nutritionRow.subtitle
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
                    .font(.fraunces(36).weight(.semibold))
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
                .font(.fraunces(15).weight(.medium))
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

/// Workouts — Sections v2.
/// Streak heatmap hero, 4-week volume bars per muscle group, last
/// session card with three-stat row + bi-lateral muscle figure, top
/// lifts table. Real data from WorkoutSessionData records where
/// available; deterministic-synthetic heatmap fills the card when
/// we don't have 14 weeks of history yet.
struct WorkoutsSegment: View {
    @Environment(\.perchPalette) private var palette
    @Environment(DashboardViewModel.self) var dashboardViewModel
    // Round 10: dropped a private `@State HealthViewModel` instance — its
    // only purpose was to mirror `dashboardViewModel.healthRecords` into
    // `viewModel.records`, but the recomputeMetricCaches it triggered was
    // never read here (we only use the workoutSession compactMap below).
    /// Which session is currently expanded in the feed (by session record id).
    /// Nil means all sessions are collapsed (summary view).
    @State private var expandedSessionId: UUID?
    /// How many sessions to render in the feed. Starts at 5 and grows in
    /// chunks of 5 as the user scrolls to the last visible card.
    @State private var visibleSessionCount: Int = 5

    /// Cached compactMap+sort of `viewModel.records`. Round 9 audit caught
    /// the prior `var workoutRecords {...}` computed-property running 6×
    /// per body render with N=300 sessions → ~50K comparisons per render.
    /// This @State snapshot is recomputed in `.onChange(of: viewModel.records)`
    /// instead of every body access.
    @State private var workoutRecords: [(record: Record, session: WorkoutSessionData)] = []
    /// Pre-computed 14×7 heatmap matrix. Same caching rationale as `workoutRecords`.
    @State private var heatmapCells: [Int] = Array(repeating: 0, count: 14 * 7)

    private var latestSession: WorkoutSessionData? {
        workoutRecords.first?.session
    }

    /// `sessionFeed` is now identical to `workoutRecords` (already labeled).
    /// Kept as a property to minimize the body-render diff.
    private var sessionFeed: [(record: Record, session: WorkoutSessionData)] {
        workoutRecords
    }

    /// Recompute the cached `workoutRecords` and `heatmapCells` from
    /// `dashboardViewModel.healthRecords`. Called from .onAppear and .onChange.
    private func recomputeWorkoutCaches() {
        let pairs = dashboardViewModel.healthRecords.compactMap { r -> (record: Record, session: WorkoutSessionData)? in
            guard r.type == .workoutSession, let ws = r.asWorkoutSession() else { return nil }
            return (record: r, session: ws)
        }
        workoutRecords = pairs.sorted {
            ($0.session.dateParsed ?? .distantPast) > ($1.session.dateParsed ?? .distantPast)
        }
        heatmapCells = Self.buildHeatmap(from: workoutRecords)
    }

    /// Build a 14-week × 7-day intensity matrix (0 = rest, 1–4 = level).
    /// When we have real sessions we stamp intensity at their dates;
    /// otherwise we fall back to the handoff's deterministic mock so
    /// the design still reads as designed. Static so it's cheap to call
    /// from `recomputeWorkoutCaches` outside body context.
    private static func buildHeatmap(from records: [(record: Record, session: WorkoutSessionData)]) -> [Int] {
        var cells = Array(repeating: 0, count: 14 * 7)

        // Attempt real fill first.
        if !records.isEmpty {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date.now)
            // Anchor column 13 on Monday of current week.
            let mondayThisWeek = cal.date(from: cal.dateComponents(
                [.yearForWeekOfYear, .weekOfYear],
                from: today
            )) ?? today

            for entry in records {
                guard let d = entry.session.dateParsed else { continue }
                let daysBack = cal.dateComponents([.day], from: d, to: mondayThisWeek).day ?? 0
                let weekOffset = daysBack / 7
                let dayOfWeek = (cal.component(.weekday, from: d) + 5) % 7 // Mon=0
                let col = 13 - weekOffset
                guard col >= 0, col < 14 else { continue }
                let idx = col * 7 + dayOfWeek
                // Intensity by duration. 0–30min = 1, 30–60 = 2, 60–90 = 3, 90+ = 4.
                let minutes = entry.session.durationMin ?? 45
                let intensity: Int = {
                    if minutes >= 90 { return 4 }
                    if minutes >= 60 { return 3 }
                    if minutes >= 30 { return 2 }
                    return 1
                }()
                cells[idx] = max(cells[idx], intensity)
            }
            // If we ended up with nothing stamped (records outside window),
            // fall through to the mock to keep the card populated.
            if cells.contains(where: { $0 > 0 }) { return cells }
        }

        // Deterministic mock fallback (matches handoff look).
        for w in 0..<14 {
            for d in 0..<7 {
                let seed = ((w * 7 + d) * 31) % 97
                var intensity = 0
                if d == 1 || d == 3 || d == 5 {
                    intensity = (seed % 4) + 1
                } else if seed > 70 {
                    intensity = (seed % 3) + 1
                }
                // Current week (13) only Mon+Tue filled — the "in progress" look.
                if w == 13 && d > 1 { intensity = 0 }
                cells[w * 7 + d] = intensity
            }
        }
        return cells
    }

    var body: some View {
        let heatmap = heatmapCells

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(
                    kicker: "THIS MONTH",
                    title: "Five weeks unbroken.",
                    aside: "12 sessions\n·  86 min avg"
                )

                // ── Streak heatmap ────────────────────────────────
                PerchSectionCard {
                    HStack(alignment: .lastTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            PerchNum("5", size: 42)
                            Text("weeks")
                                .font(.frauncesItalic(20).weight(.regular))
                                .foregroundStyle(palette.muted)
                        }
                        Spacer()
                        Text("Jan 13 → Apr 20")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(palette.muted)
                    }
                    .padding(.bottom, 4)

                    Text("At least 3 sessions every week since mid-January.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.muted)
                        .padding(.bottom, 18)

                    StreakHeatmap(cells: heatmap)

                    HStack {
                        Text("14 weeks ago")
                        Spacer()
                        HStack(spacing: 4) {
                            Text("less")
                            ForEach(0..<5, id: \.self) { v in
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(StreakHeatmap.intensityColor(v, ink: palette.ink))
                                    .frame(width: 8, height: 8)
                            }
                            Text("more")
                        }
                        Spacer()
                        Text("today")
                    }
                    .font(.system(size: 10.5))
                    .tracking(0.4)
                    .foregroundStyle(palette.faint)
                    .padding(.top, 14)
                }

                // ── Volume by muscle, last 4 weeks ─────────────────
                PerchSectionCard {
                    HStack {
                        PerchKicker("Volume · last 4 weeks")
                        Spacer()
                        Text("sets per week")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.muted)
                    }
                    .padding(.bottom, 14)

                    let volume: [(String, [Int])] = [
                        ("Chest",     [14, 16, 12, 16]),
                        ("Back",      [12, 10, 14, 12]),
                        ("Shoulders", [10, 12, 10, 14]),
                        ("Legs",      [8, 10, 8, 6]),
                        ("Arms",      [12, 14, 12, 12]),
                    ]
                    ForEach(Array(volume.enumerated()), id: \.offset) { _, row in
                        VolumeRow(muscle: row.0, weeks: row.1)
                    }
                }

                // ── Top lifts ─────────────────────────────────────
                PerchSectionCard {
                    PerchKicker("Top lifts")
                        .padding(.bottom, 8)

                    let lifts = topLifts(from: latestSession)
                    ForEach(Array(lifts.enumerated()), id: \.offset) { i, lift in
                        TopLiftRow(name: lift.name, sets: lift.sets, best: lift.best)
                        if i < lifts.count - 1 {
                            PerchSoftDivider()
                        }
                    }
                }

                // ── Session feed ──────────────────────────────────
                // Stacked list of past sessions, tap to expand in place.
                // Flat hierarchy — no nav push. Initially shows 5; more
                // load automatically when the user scrolls to the last.
                if !sessionFeed.isEmpty {
                    let visible = Array(sessionFeed.prefix(visibleSessionCount))
                    ForEach(Array(visible.enumerated()), id: \.element.record.id) { index, item in
                        let isExpanded = expandedSessionId == item.record.id
                        Button {
                            PerchHaptics.light()
                            PerchMotion.withOptionalAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                expandedSessionId = isExpanded ? nil : item.record.id
                            }
                        } label: {
                            WorkoutSessionFeedCard(session: item.session, isExpanded: isExpanded)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            // Auto-load more when the last visible card
                            // comes on screen.
                            if index == visible.count - 1, visibleSessionCount < sessionFeed.count {
                                visibleSessionCount = min(visibleSessionCount + 5, sessionFeed.count)
                            }
                        }
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
        .onChange(of: dashboardViewModel.healthRecords) { _, _ in
            recomputeWorkoutCaches()
        }
        .onAppear {
            recomputeWorkoutCaches()
        }
    }

    // MARK: - Derived helpers

    /// Map a session's muscle-groups list into the MuscleFigure intensity
    /// slots. Any group we don't recognise is ignored; missing groups
    /// render at intensity 0 (near-invisible).
    private func muscleLoads(from session: WorkoutSessionData?) -> MuscleFigure.Loads {
        guard let session else {
            // Spec default: chest + triceps + shoulders session.
            return MuscleFigure.Loads(
                chest: 4, triceps: 4, shoulders: 3, biceps: 1,
                abs: 2, traps: 0, lats: 0, back: 0
            )
        }
        let groups = Set(session.muscleGroups.map { $0.lowercased() })
        func level(_ keys: [String], high: Int = 3) -> Int {
            groups.contains(where: { g in keys.contains(where: g.contains) }) ? high : 0
        }
        return MuscleFigure.Loads(
            chest:     level(["chest", "pec"], high: 4),
            triceps:   level(["tricep"], high: 4),
            shoulders: level(["shoulder", "delt"], high: 3),
            biceps:    level(["bicep"], high: 3),
            abs:       level(["abs", "core"], high: 2),
            traps:     level(["trap", "upper back"], high: 3),
            lats:      level(["lat", "back"], high: 3),
            back:      level(["lower back", "back"], high: 3)
        )
    }

    private func topLifts(from session: WorkoutSessionData?) -> [(name: String, sets: String, best: String)] {
        if let session, !session.exercises.isEmpty {
            return session.exercises.prefix(5).map { ex in
                let setCount = ex.sets.count
                let heaviest = ex.sets
                    .filter { ($0.weightKg ?? 0) > 0 && ($0.reps ?? 0) > 0 }
                    .max(by: { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) })
                let best: String = {
                    guard let h = heaviest,
                          let w = h.weightKg,
                          let r = h.reps else { return "—" }
                    let weight = w.truncatingRemainder(dividingBy: 1) == 0
                        ? "\(Int(w))"
                        : String(format: "%.1f", w)
                    return "\(weight) × \(r)"
                }()
                return (ex.name, "\(setCount)", best)
            }
        }
        // Spec fallback.
        return [
            ("Bench press",      "4", "107 × 9"),
            ("Incline DB press", "3", "35 × 8"),
            ("Overhead press",   "3", "30 × 10"),
            ("Tricep rope",      "3", "30 × 8"),
            ("Dips",             "3", "BW × 12"),
        ]
    }

    private func relativeAgo(from date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date.now)
    }

    private func placeholderCard(title: String, emoji: String, hint: String) -> some View {
        VStack(spacing: PerchTheme.Spacing.small) {
            Text(emoji)
                .font(.system(size: 32))
            Text(title)
                .font(PerchTheme.Font.heading)
                .foregroundColor(palette.muted)
            Text(hint)
                .font(PerchTheme.Font.caption)
                .foregroundColor(palette.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(palette.card)
        .cornerRadius(PerchTheme.Card.cornerRadius)
        .padding(.horizontal, PerchTheme.Spacing.large)
    }
}

// MARK: - Nutrition Segment

/// Nutrition — Sections v2.
/// Calorie hero (big number, remaining, ink progress bar) + three
/// macro bars, meal timeline (mono time · name · P/C/F inline ·
/// serif kcal), and a single kinetic "Log a meal" CTA at the bottom
/// — the only kinetic thing on the screen. Meal logging + meal
/// suggestion flows are preserved.
struct NutritionSegment: View {
    @Environment(\.perchPalette) private var palette
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @Environment(NutritionViewModel.self) private var viewModel
    @State private var showingInputSheet = false
    @State private var showingSuggestionsSheet = false

    private var submissionUserId: String? {
        SupabaseService.shared.currentUserId
    }

    /// Today's section (or the most recent day we have meals for).
    private var todaySection: NutritionDaySection? {
        viewModel.daySections.first
    }

    private var todayKicker: String {
        PerchFormatters.todayKicker.string(from: Date.now).uppercased()
    }

    /// Phrase that reads the day by consumed-to-target ratio.
    private func dayPhrase(pct: Double) -> String {
        switch pct {
        case ..<0.3: return "The day is young."
        case ..<0.7: return "Light day so far."
        case ..<1.0: return "On track."
        case ..<1.1: return "Spot on."
        default: return "A bigger day."
        }
    }

    var body: some View {
        @Bindable var vm = viewModel
        let section = todaySection

        // Consumed + targets, with spec fallbacks when empty so the card
        // still reads as designed.
        let consumedCal  = section?.summary.consumed.calories ?? 0
        let targetCal    = section?.summary.targets.calories  ?? 2_900
        let consumedP    = section?.summary.consumed.protein  ?? 0
        let targetP      = section?.summary.targets.protein   ?? 190
        let consumedC    = section?.summary.consumed.carbs    ?? 0
        let targetC      = section?.summary.targets.carbs     ?? 350
        let consumedF    = section?.summary.consumed.fat      ?? 0
        let targetF      = section?.summary.targets.fat       ?? 80
        let pct          = targetCal > 0 ? consumedCal / targetCal : 0
        let remaining    = max(0, targetCal - consumedCal)

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = vm.error {
                    ErrorBanner(
                        message: error,
                        retryAction: { Task { await dashboardViewModel.refreshRecords(forceRefresh: true) } },
                        onDismiss: { vm.error = nil }
                    )
                }

                SectionTitle(
                    kicker: todayKicker,
                    title: dayPhrase(pct: pct),
                    aside: "\(Int(pct * 100))%\nof target"
                )

                // ── Calorie hero ───────────────────────────────────
                PerchSectionCard {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            PerchKicker("Calories")
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                PerchNum(Self.integerString(consumedCal), size: 40)
                                Text("/ \(Self.integerString(targetCal))")
                                    .font(.frauncesItalic(18).weight(.regular))
                                    .foregroundStyle(palette.muted)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("REMAINING")
                                .font(.system(size: 11, weight: .medium))
                                .tracking(0.4)
                                .foregroundStyle(palette.muted)
                            PerchNum(Self.integerString(remaining), size: 20)
                        }
                    }
                    .padding(.bottom, 14)

                    NutritionProgressBar(pct: min(pct, 1), height: 8)
                        .padding(.bottom, 18)

                    VStack(spacing: 14) {
                        NutritionMacroBar(label: "Protein", current: consumedP, target: targetP)
                        NutritionMacroBar(label: "Carbs",   current: consumedC, target: targetC)
                        NutritionMacroBar(label: "Fat",     current: consumedF, target: targetF)
                    }
                }

                // ── Today's meals ──────────────────────────────────
                if let section, !section.meals.isEmpty {
                    PerchSectionCard {
                        HStack {
                            PerchKicker("Today's meals")
                            Spacer()
                            Text("\(section.meals.count) logged")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.muted)
                        }
                        .padding(.bottom, 6)

                        ForEach(Array(section.meals.enumerated()), id: \.element.id) { i, meal in
                            NutritionMealRow(meal: meal)
                            if i < section.meals.count - 1 {
                                PerchSoftDivider()
                            }
                        }
                    }
                } else if !dashboardViewModel.isLoading {
                    PerchSectionCard {
                        VStack(alignment: .leading, spacing: 8) {
                            PerchKicker("Today's meals")
                            Text("Nothing logged yet — tap below to start the day.")
                                .font(.system(size: 13.5))
                                .foregroundStyle(palette.muted)
                                .padding(.top, 4)
                        }
                    }
                }

                // ── Kinetic CTA — the one action on the screen ────
                Button {
                    showingInputSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Log a meal")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(palette.kinetic)
                    )
                    .shadow(color: palette.kinetic.opacity(0.25), radius: 18, x: 0, y: 8)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                // Secondary "What should I eat?" — understated, sits
                // below the primary action so kinetic stays unique.
                Button {
                    showingSuggestionsSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13))
                        Text("What should I eat?")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(palette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                Color.clear
                    .frame(height: PerchTheme.TabBar.shellContentInsetHeight)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .refreshable {
            PerchHaptics.medium()
            await dashboardViewModel.refreshRecords(forceRefresh: true)
            PerchHaptics.success()
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

    private static func integerString(_ v: Double) -> String {
        PerchFormatters.integer.string(from: NSNumber(value: Int(v.rounded())))
            ?? "\(Int(v))"
    }
}

// MARK: - Nutrition sub-components

/// Full-width ink progress bar on a muted track. Used for the top-line
/// calorie summary inside the Nutrition hero card.
private struct NutritionProgressBar: View {
    @Environment(\.perchPalette) private var palette

    let pct: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(palette.ink.opacity(0.1))
                Capsule(style: .continuous)
                    .fill(palette.ink)
                    .frame(width: geo.size.width * CGFloat(max(0, min(pct, 1))))
            }
        }
        .frame(height: height)
    }
}

/// Individual macro bar (Protein / Carbs / Fat). Small uppercase label
/// + serif "current/target g" on the right, thin ink bar below.
private struct NutritionMacroBar: View {
    @Environment(\.perchPalette) private var palette

    let label: String
    let current: Double
    let target: Double

    var body: some View {
        let pct = target > 0 ? min(1, current / target) : 0
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(palette.muted)
                Spacer()
                HStack(spacing: 0) {
                    Text("\(Int(current.rounded()))")
                        .font(.fraunces(13.5).weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(palette.ink)
                    Text("/\(Int(target.rounded()))g")
                        .font(.fraunces(13.5))
                        .monospacedDigit()
                        .foregroundStyle(palette.muted)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.ink.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(palette.ink)
                        .frame(width: geo.size.width * CGFloat(pct))
                }
            }
            .frame(height: 6)
        }
    }
}

/// One row in the meal timeline. Mono time (eyebrow) · SF name (primary)
/// · mono P/C/F inline · serif kcal right.
private struct NutritionMealRow: View {
    @Environment(\.perchPalette) private var palette

    let meal: MealRecord

    private var timeString: String {
        PerchFormatters.time24h.string(from: meal.mealTime)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(timeString)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.muted)
                .padding(.top, 3)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(meal.mealName)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    NutritionMacroInline(key: "P", value: meal.protein)
                    NutritionMacroInline(key: "C", value: meal.carbs)
                    NutritionMacroInline(key: "F", value: meal.fat)
                }
            }

            Spacer(minLength: 8)

            Text("\(Int(meal.calories.rounded()))")
                .font(.fraunces(15.5).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
        }
        .padding(.vertical, 12)
    }
}

/// Inline macro fragment: faint "P" key + muted "62g" value.
private struct NutritionMacroInline: View {
    @Environment(\.perchPalette) private var palette

    let key: String
    let value: Double

    var body: some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.faint)
            Text("\(Int(value.rounded()))g")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.muted)
        }
    }
}

// MARK: - Nutrition Day Header (internal)

private struct NutritionDayHeader: View {
    @Environment(\.perchPalette) private var palette

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
                .foregroundColor(palette.muted)
                .tracking(0.8)

            Text(PerchFormatters.mediumDate.string(from: date))
                .font(PerchTheme.Font.micro)
                .foregroundColor(palette.faint)
        }
    }
}

// MARK: - Meal Suggestions Sheet (internal)

private struct MealSuggestionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.perchPalette) private var palette

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
                        .foregroundColor(palette.muted)

                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                        Text("Context")
                            .font(PerchTheme.Font.cardEyebrow)
                            .foregroundColor(palette.muted)

                        TextField("I'm at a food court", text: $context, axis: .vertical)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(palette.ink)
                            .lineLimit(2...4)
                            .padding(PerchTheme.Spacing.medium)
                            .background(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                    .fill(palette.chipBg)
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
                                    .tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(viewModel.mealSuggestions.isEmpty ? "Get suggestions" : "Refresh suggestions")
                                .fontWeight(.semibold)
                        }
                        .font(PerchTheme.Font.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, PerchTheme.Spacing.medium)
                        .background(
                            RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                .fill(palette.kinetic)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isLoadingSuggestions)

                    if !viewModel.mealSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Suggestions")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(palette.ink)

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
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle("What should I eat?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(palette.muted)
                }
            }
        }
    }
}

// MARK: - Suggestion Card (internal)

private struct SuggestionCard: View {
    @Environment(\.perchPalette) private var palette

    let suggestion: MealSuggestion
    let onLog: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                Text(suggestion.mealName)
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(palette.ink)

                Text(suggestion.analysisLine)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(palette.muted)
            }

            HStack(spacing: PerchTheme.Spacing.small) {
                SuggestionMacroPill(label: "Cal", value: "\(Int(suggestion.calories))", tint: palette.kinetic)
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
            .foregroundColor(palette.kinetic)
        }
        .padding(PerchTheme.Card.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .fill(palette.card.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .stroke(palette.line.opacity(0.8), lineWidth: 1)
        )
    }
}

private struct SuggestionMacroPill: View {
    @Environment(\.perchPalette) private var palette

    let label: String
    let value: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(PerchTheme.Font.micro)
                .foregroundColor(palette.muted)

            Text(value)
                .font(PerchTheme.Font.captionNumeric)
                .foregroundColor(palette.ink)
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

// PersonalRecordsCard reused from WorkoutView.swift - no local duplicate.
// Round 9 audit caught the duplicate `HealthTabPersonalRecordsCard` here
// (no call sites + un-fingerprinted O(N³) topLifts) — deleted.

// MARK: - Workouts sub-components

/// 14-week × 7-day training grid. 5 intensity levels mapped onto an
/// ink alpha ramp. Cells are 12pt squares with 3pt gap; day-of-week
/// letters labeled down the left at alternating rows.
private struct StreakHeatmap: View {
    @Environment(\.perchPalette) private var palette

    let cells: [Int] // length 14 * 7

    static let weeks = 14
    static let days = 7
    static let cell: CGFloat = 12
    static let gap: CGFloat = 3

    static func intensityColor(_ v: Int, ink: Color) -> Color {
        switch v {
        case 0: return ink.opacity(0.07)
        case 1: return ink.opacity(0.22)
        case 2: return ink.opacity(0.45)
        case 3: return ink.opacity(0.70)
        default: return ink
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Day-of-week column (M, _, W, _, F, _, S shown)
            VStack(spacing: Self.gap) {
                ForEach(0..<Self.days, id: \.self) { i in
                    Text(["M","T","W","T","F","S","S"][i])
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(palette.faint)
                        .frame(width: 10, height: Self.cell, alignment: .center)
                        .opacity(i % 2 == 0 ? 1 : 0)
                }
            }
            .padding(.top, 2)

            // 14 weeks × 7 days grid
            VStack(spacing: Self.gap) {
                ForEach(0..<Self.days, id: \.self) { row in
                    HStack(spacing: Self.gap) {
                        ForEach(0..<Self.weeks, id: \.self) { col in
                            let v = cells[col * Self.days + row]
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(Self.intensityColor(v, ink: palette.ink))
                                .frame(width: Self.cell, height: Self.cell)
                        }
                    }
                }
            }
        }
    }
}

/// One "volume per muscle" row: label · 4-bar mini chart (last week
/// solid ink, prior three weeks faded) · current-week sets number.
private struct VolumeRow: View {
    @Environment(\.perchPalette) private var palette

    let muscle: String
    let weeks: [Int]
    let maxV: CGFloat = 18

    var body: some View {
        HStack(spacing: 14) {
            Text(muscle)
                .font(.system(size: 13))
                .foregroundStyle(palette.ink)
                .frame(width: 78, alignment: .leading)

            HStack(spacing: 3) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { i, v in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(i == weeks.count - 1 ? palette.ink : palette.ink.opacity(0.3))
                        .frame(height: CGFloat(v) / maxV * 22)
                        .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 22, alignment: .bottom)

            Text("\(weeks.last ?? 0)")
                .font(.fraunces(14).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.vertical, 7)
    }
}

// `StatCell` removed (Round 9): had a single self-reference, no call sites.

/// Top lift row: exercise name left, sets · best weight×reps right.
private struct TopLiftRow: View {
    @Environment(\.perchPalette) private var palette

    let name: String
    let sets: String
    let best: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
                .font(.system(size: 14))
                .foregroundStyle(palette.ink)
            Spacer()
            Text("\(sets) sets")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.faint)
            Text(best)
                .font(.fraunces(15).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .padding(.leading, 10)
        }
        .padding(.vertical, 10)
    }
}

/// Bi-lateral torso silhouette. Front on the left, back on the right,
/// each with the same base grey body and per-group overlays tinted
/// by intensity (`palette.kinetic` at varying alpha).
///
/// Coordinates follow the SVG paths from the handoff. viewBox =
/// 220×160; each half is drawn into its own 100-wide offset group.
private struct MuscleFigure: View {
    @Environment(\.perchPalette) private var palette

    struct Loads: Equatable {
        var chest: Int = 0
        var triceps: Int = 0
        var shoulders: Int = 0
        var biceps: Int = 0
        var abs: Int = 0
        var traps: Int = 0
        var lats: Int = 0
        var back: Int = 0
    }

    let loads: Loads

    /// Intensity → opacity of `palette.kinetic`. 0 = near-invisible ink
    /// at 5% (the body base). 1–4 = kinetic 0.28 / 0.55 / 0.80 / 1.0.
    private func tint(_ v: Int) -> Color {
        switch v {
        case 0: return palette.ink.opacity(0.06)
        case 1: return palette.kinetic.opacity(0.28)
        case 2: return palette.kinetic.opacity(0.55)
        case 3: return palette.kinetic.opacity(0.80)
        default: return palette.kinetic
        }
    }

    var body: some View {
        GeometryReader { geo in
            // Fit 220×160 viewBox into the available width, preserving
            // aspect. Anchor top-leading so labels hit the expected spot.
            let scale = geo.size.width / 220
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    ctx.scaleBy(x: scale, y: scale)
                    drawBody(ctx: &ctx, frontOffset: 10,  isBack: false)
                    drawBody(ctx: &ctx, frontOffset: 120, isBack: true)
                }
                .frame(width: geo.size.width, height: 160 * scale)

                // Labels as SwiftUI Text so they pick up the palette muted
                // correctly without fighting Canvas' text metrics.
                Text("FRONT")
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.muted)
                    .frame(width: 100 * scale, alignment: .center)
                    .offset(x: 10 * scale, y: 128 * scale)
                Text("BACK")
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(palette.muted)
                    .frame(width: 100 * scale, alignment: .center)
                    .offset(x: 120 * scale, y: 128 * scale)
            }
        }
        .frame(height: 160)
    }

    private func drawBody(ctx: inout GraphicsContext, frontOffset: CGFloat, isBack: Bool) {
        let base = palette.ink.opacity(0.06)

        func move(_ p: Path, x: CGFloat) -> Path {
            // Translate an already-built path by x along the X axis.
            var out = Path()
            out.addPath(p, transform: .init(translationX: x, y: 0))
            return out
        }

        // Head
        let head = Path(ellipseIn: CGRect(x: 50 - 11, y: 20 - 11, width: 22, height: 22))
        ctx.fill(move(head, x: frontOffset), with: .color(base))

        // Neck
        let neck = Path(CGRect(x: 46, y: 30, width: 8, height: 6))
        ctx.fill(move(neck, x: frontOffset), with: .color(base))

        // Torso base
        var torso = Path()
        torso.move(to: CGPoint(x: 30, y: 38))
        torso.addQuadCurve(to: CGPoint(x: 50, y: 34), control: CGPoint(x: 40, y: 34))
        torso.addQuadCurve(to: CGPoint(x: 70, y: 38), control: CGPoint(x: 60, y: 34))
        torso.addLine(to: CGPoint(x: 74, y: 76))
        torso.addQuadCurve(to: CGPoint(x: 68, y: 106), control: CGPoint(x: 72, y: 92))
        torso.addLine(to: CGPoint(x: 50, y: 110))
        torso.addLine(to: CGPoint(x: 32, y: 106))
        torso.addQuadCurve(to: CGPoint(x: 26, y: 76), control: CGPoint(x: 28, y: 92))
        torso.closeSubpath()
        ctx.fill(move(torso, x: frontOffset), with: .color(base))

        // Left arm
        var armL = Path()
        armL.move(to: CGPoint(x: 30, y: 38))
        armL.addQuadCurve(to: CGPoint(x: 20, y: 58), control: CGPoint(x: 22, y: 42))
        armL.addQuadCurve(to: CGPoint(x: 22, y: 88), control: CGPoint(x: 18, y: 74))
        armL.addLine(to: CGPoint(x: 26, y: 88))
        armL.addQuadCurve(to: CGPoint(x: 28, y: 60), control: CGPoint(x: 26, y: 72))
        armL.closeSubpath()
        ctx.fill(move(armL, x: frontOffset), with: .color(base))

        // Right arm (mirrored)
        var armR = Path()
        armR.move(to: CGPoint(x: 70, y: 38))
        armR.addQuadCurve(to: CGPoint(x: 80, y: 58), control: CGPoint(x: 78, y: 42))
        armR.addQuadCurve(to: CGPoint(x: 78, y: 88), control: CGPoint(x: 82, y: 74))
        armR.addLine(to: CGPoint(x: 74, y: 88))
        armR.addQuadCurve(to: CGPoint(x: 72, y: 60), control: CGPoint(x: 74, y: 72))
        armR.closeSubpath()
        ctx.fill(move(armR, x: frontOffset), with: .color(base))

        if !isBack {
            // FRONT — chest L+R, shoulders L+R, biceps L+R, abs
            var chestL = Path()
            chestL.move(to: CGPoint(x: 34, y: 42))
            chestL.addQuadCurve(to: CGPoint(x: 49, y: 41), control: CGPoint(x: 42, y: 40))
            chestL.addLine(to: CGPoint(x: 49, y: 56))
            chestL.addQuadCurve(to: CGPoint(x: 34, y: 55), control: CGPoint(x: 40, y: 58))
            chestL.closeSubpath()
            ctx.fill(move(chestL, x: frontOffset), with: .color(tint(loads.chest)))

            var chestR = Path()
            chestR.move(to: CGPoint(x: 66, y: 42))
            chestR.addQuadCurve(to: CGPoint(x: 51, y: 41), control: CGPoint(x: 58, y: 40))
            chestR.addLine(to: CGPoint(x: 51, y: 56))
            chestR.addQuadCurve(to: CGPoint(x: 66, y: 55), control: CGPoint(x: 60, y: 58))
            chestR.closeSubpath()
            ctx.fill(move(chestR, x: frontOffset), with: .color(tint(loads.chest)))

            var shoulderL = Path()
            shoulderL.move(to: CGPoint(x: 30, y: 38))
            shoulderL.addQuadCurve(to: CGPoint(x: 24, y: 48), control: CGPoint(x: 24, y: 40))
            shoulderL.addLine(to: CGPoint(x: 30, y: 50))
            shoulderL.addQuadCurve(to: CGPoint(x: 34, y: 40), control: CGPoint(x: 32, y: 44))
            shoulderL.closeSubpath()
            ctx.fill(move(shoulderL, x: frontOffset), with: .color(tint(loads.shoulders)))

            var shoulderR = Path()
            shoulderR.move(to: CGPoint(x: 70, y: 38))
            shoulderR.addQuadCurve(to: CGPoint(x: 76, y: 48), control: CGPoint(x: 76, y: 40))
            shoulderR.addLine(to: CGPoint(x: 70, y: 50))
            shoulderR.addQuadCurve(to: CGPoint(x: 66, y: 40), control: CGPoint(x: 68, y: 44))
            shoulderR.closeSubpath()
            ctx.fill(move(shoulderR, x: frontOffset), with: .color(tint(loads.shoulders)))

            var bicepL = Path()
            bicepL.move(to: CGPoint(x: 22, y: 50))
            bicepL.addQuadCurve(to: CGPoint(x: 20, y: 72), control: CGPoint(x: 18, y: 60))
            bicepL.addLine(to: CGPoint(x: 24, y: 72))
            bicepL.addQuadCurve(to: CGPoint(x: 28, y: 54), control: CGPoint(x: 26, y: 62))
            bicepL.closeSubpath()
            ctx.fill(move(bicepL, x: frontOffset), with: .color(tint(loads.biceps)))

            var bicepR = Path()
            bicepR.move(to: CGPoint(x: 78, y: 50))
            bicepR.addQuadCurve(to: CGPoint(x: 80, y: 72), control: CGPoint(x: 82, y: 60))
            bicepR.addLine(to: CGPoint(x: 76, y: 72))
            bicepR.addQuadCurve(to: CGPoint(x: 72, y: 54), control: CGPoint(x: 74, y: 62))
            bicepR.closeSubpath()
            ctx.fill(move(bicepR, x: frontOffset), with: .color(tint(loads.biceps)))

            var absP = Path()
            absP.move(to: CGPoint(x: 40, y: 62))
            absP.addLine(to: CGPoint(x: 60, y: 62))
            absP.addLine(to: CGPoint(x: 58, y: 92))
            absP.addLine(to: CGPoint(x: 42, y: 92))
            absP.closeSubpath()
            ctx.fill(move(absP, x: frontOffset), with: .color(tint(loads.abs)))
        } else {
            // BACK — triceps L+R, traps, lats L+R, lower back
            var tricepL = Path()
            tricepL.move(to: CGPoint(x: 22, y: 50))
            tricepL.addQuadCurve(to: CGPoint(x: 20, y: 72), control: CGPoint(x: 18, y: 60))
            tricepL.addLine(to: CGPoint(x: 24, y: 72))
            tricepL.addQuadCurve(to: CGPoint(x: 28, y: 54), control: CGPoint(x: 26, y: 62))
            tricepL.closeSubpath()
            ctx.fill(move(tricepL, x: frontOffset), with: .color(tint(loads.triceps)))

            var tricepR = Path()
            tricepR.move(to: CGPoint(x: 78, y: 50))
            tricepR.addQuadCurve(to: CGPoint(x: 80, y: 72), control: CGPoint(x: 82, y: 60))
            tricepR.addLine(to: CGPoint(x: 76, y: 72))
            tricepR.addQuadCurve(to: CGPoint(x: 72, y: 54), control: CGPoint(x: 74, y: 62))
            tricepR.closeSubpath()
            ctx.fill(move(tricepR, x: frontOffset), with: .color(tint(loads.triceps)))

            var traps = Path()
            traps.move(to: CGPoint(x: 38, y: 36))
            traps.addQuadCurve(to: CGPoint(x: 62, y: 36), control: CGPoint(x: 50, y: 32))
            traps.addLine(to: CGPoint(x: 62, y: 44))
            traps.addQuadCurve(to: CGPoint(x: 38, y: 44), control: CGPoint(x: 50, y: 42))
            traps.closeSubpath()
            ctx.fill(move(traps, x: frontOffset), with: .color(tint(loads.traps)))

            var latL = Path()
            latL.move(to: CGPoint(x: 30, y: 46))
            latL.addQuadCurve(to: CGPoint(x: 36, y: 78), control: CGPoint(x: 30, y: 60))
            latL.addLine(to: CGPoint(x: 44, y: 78))
            latL.addLine(to: CGPoint(x: 42, y: 50))
            latL.closeSubpath()
            ctx.fill(move(latL, x: frontOffset), with: .color(tint(loads.lats)))

            var latR = Path()
            latR.move(to: CGPoint(x: 70, y: 46))
            latR.addQuadCurve(to: CGPoint(x: 64, y: 78), control: CGPoint(x: 70, y: 60))
            latR.addLine(to: CGPoint(x: 56, y: 78))
            latR.addLine(to: CGPoint(x: 58, y: 50))
            latR.closeSubpath()
            ctx.fill(move(latR, x: frontOffset), with: .color(tint(loads.lats)))

            var lower = Path()
            lower.move(to: CGPoint(x: 40, y: 80))
            lower.addLine(to: CGPoint(x: 60, y: 80))
            lower.addLine(to: CGPoint(x: 58, y: 96))
            lower.addLine(to: CGPoint(x: 42, y: 96))
            lower.closeSubpath()
            ctx.fill(move(lower, x: frontOffset), with: .color(tint(loads.back)))
        }
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
                // Bundled Fraunces at .medium ≈ the design's editorial
                // title weight (Fraunces 500).
                Text(title)
                    .font(.frauncesItalic(28).weight(.medium))
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
                .font(.fraunces(size).weight(size >= 26 ? .semibold : .medium))
                .monospacedDigit()
                .foregroundStyle(palette.ink)
                .tracking(size > 28 ? -0.8 : -0.3)
            if let suffix {
                Text(suffix)
                    .font(.fraunces(size * 0.5).weight(.regular))
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
        .environment(NutritionViewModel())
}
