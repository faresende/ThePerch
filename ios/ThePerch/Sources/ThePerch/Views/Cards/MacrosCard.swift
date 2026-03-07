import SwiftUI

/// Displays daily macronutrient intake with gradient-filled progress bars toward targets.
struct MacrosCard: View {
    let protein: Double
    let proteinTarget: Double?
    let carbs: Double
    let carbsTarget: Double?
    let fat: Double
    let fatTarget: Double?
    let lastUpdated: Date?

    @State private var animateProgress = false

    private static let proteinGradient = [Color(red: 0.2, green: 0.6, blue: 0.35), Color(red: 0.3, green: 0.85, blue: 0.5)]
    private static let carbsGradient = [Color(red: 0.25, green: 0.55, blue: 0.9), Color(red: 0.4, green: 0.7, blue: 1.0)]
    private static let fatGradient = [Color(red: 0.9, green: 0.7, blue: 0.2), Color(red: 1.0, green: 0.85, blue: 0.3)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Daily Macros")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

            // Macro rows with gradient colors
            macroRow(
                label: "Protein",
                value: protein,
                target: proteinTarget,
                color: Color(red: 0.3, green: 0.75, blue: 0.45),
                gradient: Self.proteinGradient
            )

            macroRow(
                label: "Carbs",
                value: carbs,
                target: carbsTarget,
                color: Color(red: 0.35, green: 0.6, blue: 0.95),
                gradient: Self.carbsGradient
            )

            macroRow(
                label: "Fat",
                value: fat,
                target: fatTarget,
                color: Color(red: 0.95, green: 0.8, blue: 0.25),
                gradient: Self.fatGradient
            )

            // Summary row
            HStack {
                if let updated = lastUpdated {
                    Text("Updated \(updated.relativeTime)")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                Spacer()
                let total = protein + carbs + fat
                Text("\(Int(total))g total")
                    .font(PerchTheme.Font.captionNumeric)
                    .foregroundColor(PerchTheme.textSecondary)
            }
        }
        .padding(PerchTheme.Spacing.large)
        .cardStyle()
        .onAppear {
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
                animateProgress = true
            }
        }
    }

    @ViewBuilder
    private func macroRow(label: String, value: Double, target: Double?, color: Color, gradient: [Color] = []) -> some View {
        let isOver = target.map { $0 > 0 && value > $0 } ?? false

        VStack(spacing: 6) {
            HStack {
                // Color dot + label
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(label)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textPrimary)
                }

                Spacer()

                // Value / target with over-target warning
                if let target {
                    HStack(spacing: 4) {
                        if isOver {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(PerchTheme.error)
                        }
                        Text("\(Int(value))")
                            .font(PerchTheme.Font.bodyNumeric)
                            .foregroundColor(isOver ? PerchTheme.error : PerchTheme.textPrimary)
                        + Text(" / \(Int(target))g")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                    }
                } else {
                    Text("\(Int(value))g")
                        .font(PerchTheme.Font.bodyNumeric)
                        .foregroundColor(PerchTheme.textPrimary)
                }
            }

            // Gradient-filled progress bar with animation
            GeometryReader { geometry in
                let ratio: CGFloat = {
                    guard let target, target > 0 else { return 0 }
                    return CGFloat(value / target)
                }()
                let clampedProgress = min(ratio, 1.0)
                let animatedWidth = animateProgress ? geometry.size.width * clampedProgress : 0

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PerchTheme.cardInnerBackground)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            isOver
                                ? AnyShapeStyle(PerchTheme.error)
                                : AnyShapeStyle(
                                    LinearGradient(
                                        colors: gradient.isEmpty ? [color, color] : gradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .frame(width: animatedWidth, height: 8)
                        .shadow(color: (isOver ? PerchTheme.error : color).opacity(0.4), radius: 4)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        MacrosCard(
            protein: 120, proteinTarget: 180,
            carbs: 180, carbsTarget: 250,
            fat: 45, fatTarget: 70,
            lastUpdated: Date.now.addingTimeInterval(-600)
        )

        MacrosCard(
            protein: 85, proteinTarget: nil,
            carbs: 120, carbsTarget: nil,
            fat: 30, fatTarget: nil,
            lastUpdated: nil
        )
    }
    .padding()
    .background(PerchTheme.background)
}
