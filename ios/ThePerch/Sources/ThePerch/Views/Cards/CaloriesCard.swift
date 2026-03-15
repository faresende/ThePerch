import SwiftUI
import UIKit

/// Displays daily calorie intake as a circular progress gauge toward a target.
/// Features animated fill ring and count-up number animation.
struct CaloriesCard: View {
    let consumed: Double
    let target: Double
    let unit: String
    let lastUpdated: Date?

    @State private var animatedProgress: Double = 0
    @State private var animatedConsumed: Double = 0
    @State private var hasCompletedGoal = false
    @State private var glowPulse = false
    @State private var percentageScale: CGFloat = 1.0

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
                        .font(PerchTheme.Font.titleNumeric)
                        .foregroundColor(PerchTheme.textPrimary)
                    Text(unit)
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }
            .frame(width: 90, height: 90)

            // Stats
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily Calories")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Target")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                        Spacer()
                        Text("\(Int(target)) \(unit)")
                            .font(PerchTheme.Font.captionNumeric)
                            .foregroundColor(PerchTheme.textPrimary)
                    }

                    HStack {
                        Text("Remaining")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                        Spacer()
                        Text("\(Int(remaining)) \(unit)")
                            .font(PerchTheme.Font.captionNumeric)
                            .foregroundColor(remaining > 0 ? PerchTheme.accent : PerchTheme.error)
                    }

                    // Percentage
                    Text("\(Int(min(animatedProgress, 1.0) * 100))%")
                        .font(PerchTheme.Font.captionNumeric)
                        .foregroundColor(progressColor)
                        .scaleEffect(percentageScale)
                        .padding(.top, 2)
                }

                if let updated = lastUpdated {
                    CardFreshnessLabel(date: updated)
                }
            }

            Spacer()
        }
        .padding(PerchTheme.Spacing.large)
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Calories: \(Int(consumed)) of \(Int(target)) consumed, \(Int(remaining)) remaining")
        .shadow(
            color: PerchTheme.accent.opacity(glowPulse ? 0.30 : 0.0),
            radius: glowPulse ? 12 : 0
        )
        .onAppear {
            PerchMotion.withOptionalAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                animatedProgress = progress
            }
            PerchMotion.withOptionalAnimation(.easeOut(duration: 0.8).delay(0.2)) {
                animatedConsumed = consumed
            }
        }
        .onChange(of: consumed) { _, newValue in
            PerchMotion.withOptionalAnimation(.easeOut(duration: 0.6)) {
                animatedConsumed = newValue
                animatedProgress = target > 0 ? min(newValue / target, 1.5) : 0
            }
        }
        .onChange(of: animatedProgress) { _, newValue in
            guard newValue >= 1.0, !hasCompletedGoal else { return }
            hasCompletedGoal = true
            triggerGoalFeedback()
        }
    }
    private func triggerGoalFeedback() {
        // Haptic
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        guard !PerchMotion.prefersReduced else { return }

        // Glow pulse: 0 → 0.30 → 0 over ~400ms
        withAnimation(.easeIn(duration: 0.2)) {
            glowPulse = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) {
                    glowPulse = false
                }
            }
        }

        // Percentage scale pop: 1.0 → 1.1 → 1.0
        withAnimation(.easeOut(duration: 0.15)) {
            percentageScale = 1.1
        }
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    percentageScale = 1.0
                }
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
