import SwiftUI

/// Unified nutrition card combining calories and macros.
/// Morning (before 14:00): Shows yesterday's final tally.
/// Afternoon (14:00+): Shows today's live progress.
struct NutritionHomeCard: View {
    let records: [Record]

    @State private var animatedProgress: Double = 0
    @State private var animatedColor: Color = PerchTheme.accent
    @State private var animateMacros = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var didReachFull = false
    /// True for a few seconds after the calorie target is first hit, so a
    /// celebratory illustration overlays the card. Resets if consumption
    /// dips back below target (e.g. data correction).
    @State private var showGoalCelebration = false
    @AppStorage("card_compact_nutrition") private var isCompact = false

    /// Round 10 audit (F10): single-pass snapshot of nutrition derivations.
    /// Replaces 5+ redundant filter+map+filter+reduce passes per body
    /// render (displayedMeals × 5, latestUpdate × 1, targets × 2). With
    /// 500 records and ~30 meal records, this saves ~150 MealRecord
    /// allocations + 5 full-array filters per render.
    @State private var snapshot: Snapshot = .empty

    private struct Snapshot {
        var displayedMeals: [MealRecord]
        var consumed: Double
        var target: Double
        var macros: MacrosData?
        var latestUpdate: Date?
        var dateString: String
        var hasData: Bool

        static let empty = Snapshot(
            displayedMeals: [], consumed: 0, target: 0,
            macros: nil, latestUpdate: nil, dateString: "", hasData: false
        )

        @MainActor
        static func compute(from records: [Record]) -> Snapshot {
            let isMorning = Calendar.current.component(.hour, from: .now) < 2
            let referenceDate: Date = isMorning
                ? (Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
                : .now
            let dateString = PerchFormatters.isoDate.string(from: referenceDate)
            let targets = NutritionTargets.resolved(for: referenceDate, records: records)

            // Single pass: filter+decode meals, AND track latest update.
            var meals: [MealRecord] = []
            var latestUpdate: Date?
            for r in records {
                if r.updatedAt > (latestUpdate ?? .distantPast) {
                    if r.asMeasurement()?.metric == "daily_calories" || r.asMacros() != nil {
                        latestUpdate = r.updatedAt
                    }
                }
                guard r.category == .nutrition, r.type == .meal else { continue }
                let meal = MealRecord(from: r)
                if PerchFormatters.isoDate.string(from: meal.mealTime) == dateString {
                    meals.append(meal)
                }
            }

            let consumed = meals.reduce(0.0) { $0 + $1.calories }
            let macros: MacrosData? = meals.isEmpty ? nil : MacrosData(
                protein: meals.reduce(0) { $0 + $1.protein },
                proteinTarget: targets.protein,
                carbs: meals.reduce(0) { $0 + $1.carbs },
                carbsTarget: targets.carbs,
                fat: meals.reduce(0) { $0 + $1.fat },
                fatTarget: targets.fat,
                date: dateString
            )
            return Snapshot(
                displayedMeals: meals,
                consumed: consumed,
                target: targets.calories,
                macros: macros,
                latestUpdate: latestUpdate,
                dateString: dateString,
                hasData: !meals.isEmpty || targets.calories > 0
            )
        }
    }

    /// Hashable fingerprint that drives `.onChange(of:)` recompute.
    /// Counts nutrition meals + tracks max(updatedAt) over the relevant
    /// records. Keeps recompute cost at one short pass per render.
    private struct Fingerprint: Hashable {
        let mealCount: Int
        let maxUpdated: TimeInterval

        static func from(_ records: [Record]) -> Fingerprint {
            var c = 0
            var m: TimeInterval = 0
            for r in records {
                let isRelevant = (r.category == .nutrition && r.type == .meal)
                    || r.asMeasurement()?.metric == "daily_calories"
                    || r.asMacros() != nil
                guard isRelevant else { continue }
                c += 1
                let t = r.updatedAt.timeIntervalSince1970
                if t > m { m = t }
            }
            return Fingerprint(mealCount: c, maxUpdated: m)
        }
    }

    // Convenience accessors so the rest of the body reads unchanged.
    private var displayedMeals: [MealRecord] { snapshot.displayedMeals }
    private var consumed: Double             { snapshot.consumed }
    private var target: Double               { snapshot.target }
    private var macrosData: MacrosData?      { snapshot.macros }
    private var latestUpdate: Date?          { snapshot.latestUpdate }
    private var dateString: String           { snapshot.dateString }
    private var hasData: Bool                { snapshot.hasData }

    private var isMorning: Bool {
        Calendar.current.component(.hour, from: .now) < 2
    }

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(consumed / target, 1.5)
    }

    /// Ring colour: sage by default (wellness register), terracotta only
    /// when meaningfully over target. Previous logic shifted through three
    /// colours (tangerine → green → red) which read as "alert level rising".
    /// Gentler Perch keeps the ring calm until it's genuinely over.
    private var progressColor: Color {
        if consumed > target * 1.1 { return PerchTheme.error }
        return PerchTheme.wellness
    }

    /// Gentle interpretive phrase for the current nutrition state —
    /// "Light day", "On track", "A bigger day", etc. Rotates daily
    /// through a library of variants so the dashboard doesn't feel robotic.
    private var nutritionPhrase: String {
        PerchPhrase.nutritionPhrase(consumed: consumed, target: target)
    }

    // Macro colors
    private static let proteinColor = PerchTheme.macroProtein
    private static let carbsColor = PerchTheme.macroCarbs
    private static let fatColor = PerchTheme.macroFat

    /// Compact summary: "1,847 / 3,400 kcal · P: 79% C: 63% F: 56%"
    private var compactSummary: String {
        var parts: [String] = []
        parts.append("\(Int(consumed)) / \(Int(target)) kcal")
        if let m = macrosData {
            func pct(_ v: Double, _ t: Double?) -> String {
                guard let t, t > 0 else { return "--" }
                return "\(Int(v / t * 100))%"
            }
            parts.append("P: \(pct(m.protein, m.proteinTarget)) C: \(pct(m.carbs, m.carbsTarget)) F: \(pct(m.fat, m.fatTarget))")
        }
        return parts.joined(separator: " · ")
    }

    @Environment(\.perchPalette) private var palette

    var body: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 0) {
                TodayEyebrow(
                    label: isMorning ? "NUTRITION · YESTERDAY" : "NUTRITION · TRACKED",
                    accent: palette.kinetic,
                    freshness: freshnessText
                )
                TodayPhrase(text: nutritionPhrase)

                if !hasData {
                    emptyIllustration
                } else {
                    hero
                    if let macros = macrosData {
                        VStack(spacing: 11) {
                            macroBar(label: "Protein", value: macros.protein, target: macros.proteinTarget)
                            macroBar(label: "Carbs",   value: macros.carbs,   target: macros.carbsTarget)
                            macroBar(label: "Fat",     value: macros.fat,     target: macros.fatTarget)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .center) {
            // Goal-reached celebration overlay — brief moment when target
            // is first hit.
            if showGoalCelebration {
                Image("goal-reached")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 160, height: 160)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .animation(PerchMotion.prefersReduced ? .none : .easeOut(duration: 0.25), value: hasData)
        .onAppear {
            snapshot = Snapshot.compute(from: records)
            animateRingTo(progress, color: progressColor)
            PerchMotion.withOptionalAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32).delay(0.2)) {
                animateMacros = true
            }
        }
        .onChange(of: Fingerprint.from(records)) { _, _ in
            snapshot = Snapshot.compute(from: records)
        }
        .onChange(of: progress) { _, newProgress in
            animateRingTo(newProgress, color: progressColor)
        }
    }

    private var freshnessText: String {
        guard let latest = latestUpdate else { return "—" }
        let minutes = Int(Date.now.timeIntervalSince(latest) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        return "\(hours) hr"
    }

    @ViewBuilder
    private var emptyIllustration: some View {
        VStack(spacing: 8) {
            Image("empty-nutrition")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 130)
            Text("No meals logged yet")
                .font(PerchTheme.Font.caption)
                .foregroundColor(palette.faint)
        }
        .frame(maxWidth: .infinity)
    }

    /// Hero section: 108pt wellness-colored ring + Target/Remaining right column.
    @ViewBuilder
    private var hero: some View {
        HStack(alignment: .center, spacing: 26) {
            calorieRing
                .frame(width: 108, height: 108)

            if target > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    statsLine(label: "TARGET", value: "\(Int(target).formatted(.number)) kcal")
                    let remaining = max(target - consumed, 0)
                    statsLine(
                        label: remaining > 0 ? "REMAINING" : "OVER",
                        value: "\(Int(abs(target - consumed)).formatted(.number)) kcal",
                        color: remaining > 0 ? palette.ink : palette.error
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.bottom, 18)
    }

    // MARK: - Calorie Ring (Linen spec)
    //
    // 108×108, 6pt stroke, kinetic-colored arc on a line-colored track.
    // Center: big tabular serif number (23pt) + "kcal" faint caption.
    // Arc is kinetic throughout; didReachFull drives the celebration pulse only.

    private var calorieRing: some View {
        // Track = palette.line, progress = palette.kinetic.
        // Centre: Fraunces-style 23pt tabular num + faint "kcal".
        ZStack {
            Circle()
                .stroke(palette.line, lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(animatedProgress, 1.0))
                .stroke(
                    palette.kinetic,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text(Int(consumed).formatted(.number))
                    .font(.fraunces(23).weight(.medium).monospacedDigit())
                    .tracking(-0.8)
                    .foregroundColor(palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("kcal")
                    .font(.system(size: 10))
                    .tracking(0.4)
                    .foregroundColor(palette.ink.opacity(0.55))
            }
            .padding(.horizontal, 10)
        }
        .scaleEffect(pulseScale)
    }

    /// Uppercase faint label over serif 16pt ink value.
    @ViewBuilder
    private func statsLine(label: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10))
                .tracking(0.8)
                .foregroundColor(palette.faint)
            Text(value)
                .font(PerchTheme.Font.targetNumeric)
                .foregroundColor(color ?? palette.ink)
        }
    }

    // MARK: - Ring Animation

    private func animateRingTo(_ newProgress: Double, color: Color) {
        PerchMotion.withOptionalAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.32)) {
            animatedProgress = newProgress
            animatedColor = color
        }
        // Goal-reached moment: first time we cross 100% this session,
        // briefly celebrate. Scale pulse on the ring + a warmer overlay
        // illustration that fades in and out. Reduce Motion just skips
        // the animation but still triggers haptic via success color.
        if newProgress >= 1.0 && !didReachFull {
            didReachFull = true

            if !PerchMotion.prefersReduced {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    pulseScale = 1.05
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.3)) {
                    pulseScale = 1.0
                }

                // Illustration overlay — show for ~2s then gently fade out.
                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                    showGoalCelebration = true
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.easeOut(duration: 0.5)) {
                        showGoalCelebration = false
                    }
                }
            }
        } else if newProgress < 1.0 {
            didReachFull = false
        }
    }

    // MARK: - Macro Bar (Linen spec)

    /// Linen macro row: label + tabular numeric value / target inline,
    /// 4pt progress bar beneath. Fill color is kinetic for all
    /// macros — per the Linen spec, macros share one accent register
    /// so the card reads as a single unified "nutrition" voice
    /// rather than three separate traffic-light signals.
    private func macroBar(label: String, value: Double, target: Double?) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 12))
                    .tracking(0.3)
                    .foregroundColor(palette.muted)

                Spacer()

                if let target {
                    // Text(_:) `+` operator was deprecated in iOS 26 in
                    // favour of string interpolation. We need two different
                    // foreground colours on the two halves, so swap the
                    // concatenation for a tight HStack — visually identical.
                    HStack(spacing: 0) {
                        Text("\(Int(value))")
                            .font(.jbMono(11.5))
                            .foregroundColor(palette.ink)
                        Text(" / \(Int(target))g")
                            .font(.jbMono(11.5))
                            .foregroundColor(palette.muted)
                    }
                } else {
                    Text("\(Int(value))g")
                        .font(.jbMono(11.5))
                        .foregroundColor(palette.ink)
                }
            }

            GeometryReader { geometry in
                let ratio: CGFloat = {
                    guard let target, target > 0 else { return 0 }
                    return CGFloat(min(value / target, 1.0))
                }()
                let animatedWidth = animateMacros ? geometry.size.width * ratio : 0

                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(palette.line)
                        .frame(height: 4)
                    Capsule(style: .continuous)
                        .fill(palette.kinetic)
                        .frame(width: animatedWidth, height: 4)
                }
            }
            .frame(height: 4)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        NutritionHomeCard(records: [])
            .padding(PerchTheme.Spacing.large)
    }
    .background(PerchTheme.background)
}
