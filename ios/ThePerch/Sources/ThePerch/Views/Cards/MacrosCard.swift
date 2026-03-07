import SwiftUI

/// Displays daily macronutrient intake with progress bars toward targets.
struct MacrosCard: View {
    let protein: Double
    let proteinTarget: Double?
    let carbs: Double
    let carbsTarget: Double?
    let fat: Double
    let fatTarget: Double?
    let lastUpdated: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Daily Macros")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(PerchTheme.textPrimary)

            // Macro rows
            macroRow(
                label: "Protein",
                value: protein,
                target: proteinTarget,
                color: Color(red: 0.3, green: 0.75, blue: 0.45) // green
            )

            macroRow(
                label: "Carbs",
                value: carbs,
                target: carbsTarget,
                color: PerchTheme.accent // amber
            )

            macroRow(
                label: "Fat",
                value: fat,
                target: fatTarget,
                color: Color(red: 0.85, green: 0.4, blue: 0.35) // red
            )

            // Summary row
            HStack {
                if let updated = lastUpdated {
                    Text("Updated \(updated.relativeTime)")
                        .font(.system(size: 10))
                        .foregroundColor(PerchTheme.textTertiary)
                }
                Spacer()
                let total = protein + carbs + fat
                Text("\(Int(total))g total")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(PerchTheme.textSecondary)
            }
        }
        .padding(PerchTheme.Card.padding + 4)
        .cardStyle()
    }

    @ViewBuilder
    private func macroRow(label: String, value: Double, target: Double?, color: Color) -> some View {
        let isOver = target.map { $0 > 0 && value > $0 } ?? false

        VStack(spacing: 6) {
            HStack {
                // Color dot + label
                HStack(spacing: 6) {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(PerchTheme.textPrimary)
                }

                Spacer()

                // Value / target with over-target warning
                if let target {
                    HStack(spacing: 4) {
                        if isOver {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(PerchTheme.error)
                        }
                        Text("\(Int(value))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(isOver ? PerchTheme.error : PerchTheme.textPrimary)
                        + Text(" / \(Int(target))g")
                            .font(.system(size: 12))
                            .foregroundColor(PerchTheme.textTertiary)
                    }
                } else {
                    Text("\(Int(value))g")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(PerchTheme.textPrimary)
                }
            }

            // Progress bar — shows overflow in red when over target
            GeometryReader { geometry in
                let ratio: CGFloat = {
                    guard let target, target > 0 else { return 0 }
                    return CGFloat(value / target)
                }()
                let clampedProgress = min(ratio, 1.0)
                let barColor = isOver ? PerchTheme.error : color

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(PerchTheme.cardInnerBackground)
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor)
                        .frame(width: geometry.size.width * clampedProgress, height: 8)
                        .shadow(color: barColor.opacity(0.3), radius: 4)
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
