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

    private var isMorning: Bool {
        Calendar.current.component(.hour, from: .now) < 2
    }

    private var dateString: String {
        if isMorning {
            return PerchFormatters.isoDate.string(from: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
        }
        return PerchFormatters.isoDate.string(from: .now)
    }

    private var caloriesData: MeasurementData? {
        let caloriesRecords = records
            .filter { $0.asMeasurement()?.metric == "daily_calories" }

        // Try exact date match first (always pick most recently updated)
        let exactMatches = caloriesRecords.filter { $0.asMeasurement()?.context == dateString }
        if !exactMatches.isEmpty {
            return exactMatches.sorted(by: { $0.updatedAt > $1.updatedAt }).first?.asMeasurement()
        }

        // For today (afternoon), fall back to most recent
        if !isMorning {
            return caloriesRecords
                .sorted(by: { $0.updatedAt > $1.updatedAt })
                .first?.asMeasurement()
        }

        return nil
    }

    private var macrosData: MacrosData? {
        records
            .filter { $0.asMacros()?.date == dateString }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first?.asMacros()
    }

    private var hasData: Bool {
        caloriesData != nil || macrosData != nil
    }

    private var consumed: Double { caloriesData?.value ?? 0 }
    private var target: Double { caloriesData?.target ?? 0 }
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

    private var latestUpdate: Date? {
        records
            .filter { $0.asMeasurement()?.metric == "daily_calories" || $0.asMacros() != nil }
            .map(\.updatedAt)
            .max()
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
                    accent: palette.wellness,
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
            animateRingTo(progress, color: progressColor)
            PerchMotion.withOptionalAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                animateMacros = true
            }
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
    // 108×108, 6pt stroke, sage-colored arc on a line-colored track.
    // Center: big tabular serif number (30pt) + "kcal" faint caption.
    // Ring color flips to kinetic only when goal reached.

    private var calorieRing: some View {
        // Track = palette.line, progress = palette.wellness (→ palette.kinetic
        // on over-goal). Centre: Fraunces-style 28pt tabular num + faint "kcal".
        ZStack {
            Circle()
                .stroke(palette.line, lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(animatedProgress, 1.0))
                .stroke(
                    didReachFull ? palette.kinetic : palette.wellness,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text(Int(consumed).formatted(.number))
                    .font(PerchTheme.Font.displayNumeric)
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
        PerchMotion.withOptionalAnimation(.easeInOut(duration: 0.6)) {
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
    /// 4pt progress bar beneath. Fill color is wellness (sage) for all
    /// macros — per the Linen spec, macros share the wellness register
    /// so the card reads as a single unified "nutrition wellness" voice
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
                    Text("\(Int(value))")
                        .font(PerchTheme.Font.rowNumeric)
                        .foregroundColor(palette.ink)
                    + Text(" / \(Int(target))g")
                        .font(PerchTheme.Font.rowNumeric)
                        .foregroundColor(palette.muted)
                } else {
                    Text("\(Int(value))g")
                        .font(PerchTheme.Font.rowNumeric)
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
                        .fill(palette.wellness)
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
