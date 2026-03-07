import SwiftUI

/// Displays daily calorie intake as a circular progress gauge toward a target.
/// Features animated fill ring and count-up number animation.
struct CaloriesCard: View {
    let consumed: Double
    let target: Double
    let unit: String
    let lastUpdated: Date?

    @State private var animatedProgress: Double = 0
    @State private var animatedConsumed: Double = 0

    private var progress: Double {
        guard target > 0 else { return 0 }
        return min(consumed / target, 1.5) // cap at 150% for overflow display
    }

    private var remaining: Double {
        max(target - consumed, 0)
    }

    private var progressColor: Color {
        if consumed > target * 1.1 {
            return PerchTheme.error
        } else if consumed > target * 0.9 {
            return PerchTheme.success
        }
        return PerchTheme.accent
    }

    var body: some View {
        HStack(spacing: 20) {
            // Circular gauge
            ZStack {
                // Background ring
                Circle()
                    .stroke(PerchTheme.border, lineWidth: 8)

                // Progress ring with gradient
                Circle()
                    .trim(from: 0, to: min(animatedProgress, 1.0))
                    .stroke(
                        AngularGradient(
                            colors: [progressColor.opacity(0.5), progressColor],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * min(progress, 1.0))
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: progressColor.opacity(0.4), radius: 6)

                // Center text with count-up
                VStack(spacing: 2) {
                    Text("\(Int(animatedConsumed))")
                        .contentTransition(.numericText())
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(PerchTheme.textPrimary)
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }
            .frame(width: 90, height: 90)

            // Stats
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily Calories")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(PerchTheme.textPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Target")
                            .font(.system(size: 13))
                            .foregroundColor(PerchTheme.textSecondary)
                        Spacer()
                        Text("\(Int(target)) \(unit)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(PerchTheme.textPrimary)
                    }

                    HStack {
                        Text("Remaining")
                            .font(.system(size: 13))
                            .foregroundColor(PerchTheme.textSecondary)
                        Spacer()
                        Text("\(Int(remaining)) \(unit)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(remaining > 0 ? PerchTheme.accent : PerchTheme.error)
                    }

                    // Percentage
                    Text("\(Int(min(animatedProgress, 1.0) * 100))%")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(progressColor)
                        .padding(.top, 2)
                }

                if let updated = lastUpdated {
                    Text("Updated \(updated.relativeTime)")
                        .font(.system(size: 10))
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }

            Spacer()
        }
        .padding(PerchTheme.Spacing.large)
        .cardStyle()
        .onAppear {
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                animatedProgress = progress
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                animatedConsumed = consumed
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        CaloriesCard(consumed: 1450, target: 2200, unit: "kcal", lastUpdated: Date.now.addingTimeInterval(-1800))
        CaloriesCard(consumed: 2100, target: 2200, unit: "kcal", lastUpdated: Date.now.addingTimeInterval(-300))
    }
    .padding()
    .background(PerchTheme.background)
}
