import SwiftUI

/// Shows a workout session. Can be expanded (full details) or collapsed (summary).
/// Expanded: all exercises in performance order + stats + overload indicators.
/// Collapsed: top 1RM lift teaser + sets + cals.
struct WorkoutSessionFeedCard: View {
    let session: WorkoutSessionData
    let isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Header row — title + duration + chevron
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    let muscleLabel = session.muscleGroups.map { $0.capitalized }.joined(separator: " + ")
                    if let num = session.sessionNumber {
                        Text("Session \(num) — \(muscleLabel)")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)
                    } else {
                        Text(muscleLabel)
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)
                    }

                    if let date = session.dateParsed {
                        Text(date.relativeTime)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                    }
                }

                Spacer()

                HStack(spacing: PerchTheme.Spacing.small) {
                    if let dur = session.durationMin {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(PerchTheme.textTertiary)
                            Text("\(dur)m")
                                .font(PerchTheme.Font.captionNumeric)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                    }

                    // Chevron — the expand/collapse affordance
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
            }

            if isExpanded {
                // Stats row
                HStack(spacing: PerchTheme.Spacing.medium) {
                    if let cal = session.activeCalories {
                        statPill(icon: "flame", value: "\(cal) cal")
                    }
                    statPill(icon: "number", value: "\(session.totalSets) sets")
                    if let hr = session.avgHr {
                        statPill(icon: "heart", value: "\(hr) bpm")
                    }
                }

                // ALL exercises in performance order (not sorted by 1RM)
                if !session.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(session.exercises.enumerated()), id: \.offset) { _, exercise in
                            let heaviestSet = exercise.sets
                                .filter { ($0.weightKg ?? 0) > 0 && ($0.reps ?? 0) > 0 }
                                .max(by: { ($0.weightKg ?? 0) < ($1.weightKg ?? 0) })

                            HStack {
                                Text(exercise.name)
                                    .font(PerchTheme.Font.body)
                                    .foregroundColor(PerchTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                if let best = heaviestSet {
                                    Text("\(Int(best.weightKg ?? 0))kg × \(best.reps ?? 0)")
                                        .font(PerchTheme.Font.captionNumeric)
                                        .foregroundColor(PerchTheme.textSecondary)
                                } else {
                                    Text("\(exercise.sets.count) sets")
                                        .font(PerchTheme.Font.captionNumeric)
                                        .foregroundColor(PerchTheme.textTertiary)
                                }
                            }
                        }
                    }
                    .padding(PerchTheme.Spacing.small)
                    .background(PerchTheme.cardInnerBackground)
                    .cornerRadius(8)
                }

                // Progressive overload indicators
                if let overloads = session.progressiveOverload, !overloads.isEmpty {
                    HStack(spacing: PerchTheme.Spacing.small) {
                        ForEach(Array(overloads.enumerated()), id: \.offset) { _, ol in
                            HStack(spacing: 4) {
                                Image(systemName: overloadIcon(ol.status))
                                    .font(.caption2)
                                    .foregroundColor(overloadColor(ol.status))
                                Text(ol.exercise)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
            } else {
                // Collapsed teaser: top 1RM lift + sets + cals
                HStack(spacing: PerchTheme.Spacing.medium) {
                    statPill(icon: "number", value: "\(session.totalSets) sets")
                    if let cal = session.activeCalories {
                        statPill(icon: "flame", value: "\(cal) cal")
                    }
                    if let top = session.topLifts.first {
                        statPill(icon: "arrow.up.right", value: "\(top.name) \(Int(top.weight))kg")
                    }
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    private func statPill(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(PerchTheme.textTertiary)
            Text(value)
                .font(PerchTheme.Font.captionNumeric)
                .foregroundColor(PerchTheme.textSecondary)
        }
    }

    private func overloadIcon(_ status: String) -> String {
        switch status.lowercased() {
        case "progressing": return "arrow.up.right"
        case "stalled": return "arrow.right"
        case "regressed": return "arrow.down.right"
        default: return "circle"
        }
    }

    private func overloadColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "progressing": return PerchTheme.success
        case "stalled": return PerchTheme.warning
        case "regressed": return PerchTheme.error
        default: return PerchTheme.textTertiary
        }
    }
}
