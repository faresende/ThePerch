import SwiftUI

/// Shows a workout session. Can be expanded (full details) or collapsed (summary).
/// Expanded: all exercises in performance order + stats + overload indicators.
/// Collapsed: top 1RM lift teaser + sets + cals.
struct WorkoutSessionFeedCard: View {
    @Environment(\.perchPalette) private var palette

    struct SummaryStat: Equatable {
        let icon: String
        let value: String
    }

    let session: WorkoutSessionData
    let isExpanded: Bool

    static func summaryStats(for session: WorkoutSessionData, isExpanded: Bool) -> [SummaryStat] {
        var stats: [SummaryStat] = [
            SummaryStat(icon: "number", value: "\(session.totalSets) sets")
        ]

        if let cal = session.activeCalories {
            stats.append(SummaryStat(icon: "flame", value: "\(cal) cal"))
        }

        if isExpanded {
            if let hr = session.avgHr {
                stats.append(SummaryStat(icon: "heart", value: "\(hr) bpm"))
            }
        } else if let top = session.topLifts.first {
            stats.append(SummaryStat(icon: "arrow.up.right", value: "\(top.name) \(Int(top.weight))kg"))
        }

        return stats
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Header row — title + duration + chevron
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    let muscleLabel = session.muscleGroups.map { $0.capitalized }.joined(separator: " + ")
                    if let num = session.sessionNumber {
                        Text("Session \(num) — \(muscleLabel)")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(palette.ink)
                    } else {
                        Text(muscleLabel)
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(palette.ink)
                    }

                    if let date = session.dateParsed {
                        Text(date.relativeTime)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(palette.faint)
                    }
                }

                Spacer()

                HStack(spacing: PerchTheme.Spacing.small) {
                    if let dur = session.durationMin {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundColor(palette.faint)
                            Text("\(dur)m")
                                .font(PerchTheme.Font.captionNumeric)
                                .foregroundColor(palette.muted)
                        }
                    }

                    // Chevron — the expand/collapse affordance
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(palette.faint)
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
            }

            if isExpanded {
                // Stats row
                HStack(spacing: PerchTheme.Spacing.medium) {
                    ForEach(Self.summaryStats(for: session, isExpanded: true), id: \.value) { stat in
                        statPill(icon: stat.icon, value: stat.value)
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
                                    .foregroundColor(palette.ink)
                                    .lineLimit(1)
                                Spacer()
                                if let best = heaviestSet {
                                    Text("\(Int(best.weightKg ?? 0))kg × \(best.reps ?? 0)")
                                        .font(PerchTheme.Font.captionNumeric)
                                        .foregroundColor(palette.muted)
                                } else {
                                    Text("\(exercise.sets.count) sets")
                                        .font(PerchTheme.Font.captionNumeric)
                                        .foregroundColor(palette.faint)
                                }
                            }
                        }
                    }
                    .padding(PerchTheme.Spacing.small)
                    .background(palette.chipBg)
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
                                    .foregroundColor(palette.muted)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                }
            } else {
                // Collapsed teaser: same primary order as expanded, then top lift
                HStack(spacing: PerchTheme.Spacing.medium) {
                    ForEach(Self.summaryStats(for: session, isExpanded: false), id: \.value) { stat in
                        statPill(icon: stat.icon, value: stat.value)
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
                .foregroundColor(palette.faint)
            Text(value)
                .font(PerchTheme.Font.captionNumeric)
                .foregroundColor(palette.muted)
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
        case "progressing": return palette.wellness
        case "stalled": return palette.kinetic
        case "regressed": return palette.error
        default: return palette.faint
        }
    }
}
