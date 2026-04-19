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

    private var progressColor: Color {
        if consumed > target * 1.1 { return PerchTheme.error }
        if consumed > target * 0.9 { return PerchTheme.success }
        return PerchTheme.accent
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

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Tappable header
            Button {
                PerchHaptics.selection()
                PerchMotion.withOptionalAnimation(.easeInOut(duration: 0.3)) {
                    isCompact.toggle()
                }
            } label: {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Image(systemName: "fork.knife")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.accent)
                    Text(isMorning ? "YESTERDAY'S NUTRITION" : "NUTRITION")
                        .font(PerchTheme.Font.cardEyebrow)
                        .foregroundColor(PerchTheme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.8)
                    Spacer()
                    CardFreshnessLabel(date: latestUpdate)
                    Image(systemName: isCompact ? "chevron.down" : "chevron.up")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle())

            if !hasData {
                // Empty state
                HStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "fork.knife")
                        .font(PerchTheme.Font.icon(PerchTheme.Icon.large))
                        .foregroundColor(PerchTheme.textTertiary)
                    Text("No meals logged yet")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, PerchTheme.Spacing.small)
            } else if isCompact {
                // Compact: single-line summary
                Text(compactSummary)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
            } else {
                // Hero stats: big display-size kcal number on the left with
                // its unit, quiet target/remaining metadata on the right.
                // Progress ring is kept but sized down so the number leads.
                HStack(alignment: .center, spacing: PerchTheme.Spacing.medium) {
                    if caloriesData != nil {
                        calorieRing
                    } else {
                        // No ring → number takes the lead alone.
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(Int(consumed))")
                                .font(PerchTheme.Font.displayNumeric)
                                .foregroundColor(PerchTheme.textPrimary)
                            Text("kcal")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                    }

                    Spacer(minLength: PerchTheme.Spacing.small)

                    if target > 0 {
                        VStack(alignment: .trailing, spacing: 6) {
                            statsLine(label: "TARGET", value: "\(Int(target))", emphasise: false)
                            let remaining = max(target - consumed, 0)
                            statsLine(
                                label: remaining > 0 ? "REMAINING" : "OVER",
                                value: "\(Int(abs(target - consumed)))",
                                emphasise: true,
                                color: remaining > 0 ? PerchTheme.textPrimary : PerchTheme.error
                            )
                        }
                    }
                }

                // Macro bars — thinner (6pt), no track in light mode (just a
                // whisper in dark), single-line label + value inline.
                if let macros = macrosData {
                    VStack(spacing: PerchTheme.Spacing.small) {
                        macroBar(label: "Protein", value: macros.protein, target: macros.proteinTarget, color: Self.proteinColor)
                        macroBar(label: "Carbs",   value: macros.carbs,   target: macros.carbsTarget,   color: Self.carbsColor)
                        macroBar(label: "Fat",     value: macros.fat,     target: macros.fatTarget,     color: Self.fatColor)
                    }
                    .padding(.top, PerchTheme.Spacing.xSmall)
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .animation(
            PerchMotion.prefersReduced ? .none : .easeInOut(duration: 0.3),
            value: isCompact
        )
        .animation(
            PerchMotion.prefersReduced ? .none : .easeOut(duration: 0.25),
            value: hasData
        )
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

    // MARK: - Calorie Ring

    /// Editorial progress ring: thinner stroke (6pt), no glow shadow, big
    /// monospaced display number centred. Ring track uses the barely-there
    /// border colour so the filled portion reads as the primary signal.
    private var calorieRing: some View {
        ZStack {
            Circle()
                .stroke(PerchTheme.border, lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(animatedProgress, 1.0))
                .stroke(
                    animatedColor,
                    style: StrokeStyle(lineWidth: 6, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(Int(consumed))")
                    .font(PerchTheme.Font.titleNumeric)
                    .foregroundColor(PerchTheme.textPrimary)
                Text("kcal")
                    .font(PerchTheme.Font.micro)
                    .foregroundColor(PerchTheme.textTertiary)
            }
        }
        .frame(width: 104, height: 104)
        .scaleEffect(pulseScale)
    }

    /// One line of the right-hand stats column — small uppercase label
    /// on top, monospaced value below. Keeps the hero number dominant.
    @ViewBuilder
    private func statsLine(label: String, value: String, emphasise: Bool, color: Color? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(PerchTheme.Font.micro)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundColor(PerchTheme.textTertiary)
            Text(value)
                .font(emphasise ? PerchTheme.Font.headingNumeric : PerchTheme.Font.bodyNumeric)
                .foregroundColor(color ?? PerchTheme.textPrimary)
        }
    }

    // MARK: - Ring Animation

    private func animateRingTo(_ newProgress: Double, color: Color) {
        PerchMotion.withOptionalAnimation(.easeInOut(duration: 0.6)) {
            animatedProgress = newProgress
            animatedColor = color
        }
        // Pulse when reaching 100%
        if newProgress >= 1.0 && !didReachFull && !PerchMotion.prefersReduced {
            didReachFull = true
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                pulseScale = 1.05
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5).delay(0.3)) {
                pulseScale = 1.0
            }
        } else if newProgress < 1.0 {
            didReachFull = false
        }
    }

    // MARK: - Macro Bar

    /// Editorial macro row: label on the left, value on the right, thin
    /// 4pt progress bar beneath both. No coloured dot, no card-inner
    /// background — the coloured fill is the only visual accent.
    private func macroBar(label: String, value: Double, target: Double?, color: Color) -> some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)

                Spacer()

                if let target {
                    Text("\(Int(value))")
                        .font(PerchTheme.Font.captionNumeric)
                        .foregroundColor(PerchTheme.textPrimary)
                    + Text(" / \(Int(target))g")
                        .font(PerchTheme.Font.captionNumeric)
                        .foregroundColor(PerchTheme.textTertiary)
                } else {
                    Text("\(Int(value))g")
                        .font(PerchTheme.Font.captionNumeric)
                        .foregroundColor(PerchTheme.textPrimary)
                }
            }

            GeometryReader { geometry in
                let ratio: CGFloat = {
                    guard let target, target > 0 else { return 0 }
                    return CGFloat(min(value / target, 1.0))
                }()
                let animatedWidth = animateMacros ? geometry.size.width * ratio : 0

                ZStack(alignment: .leading) {
                    // Track — barely-there hairline
                    Capsule(style: .continuous)
                        .fill(PerchTheme.border)
                        .frame(height: 4)
                    // Fill — flat colour, no shadow
                    Capsule(style: .continuous)
                        .fill(color)
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
