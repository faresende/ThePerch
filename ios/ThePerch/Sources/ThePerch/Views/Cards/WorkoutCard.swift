import SwiftUI

/// Shows the most recent workout session summary.
/// Hides when no workout data exists.
struct WorkoutCard: View {
    let records: [Record]

    private var latestSession: (Record, WorkoutSessionData)? {
        records.compactMap { r -> (Record, WorkoutSessionData)? in
            guard r.type == .workoutSession, let ws = r.asWorkoutSession() else { return nil }
            return (r, ws)
        }
        .sorted { ($0.1.dateParsed ?? .distantPast) > ($1.1.dateParsed ?? .distantPast) }
        .first
    }

    var body: some View {
        if let (_, session) = latestSession {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                // Header
                HStack {
                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Image(systemName: "dumbbell.fill")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.accent)
                        Text("LAST WORKOUT")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                            .tracking(1)
                    }
                    Spacer()
                    if let date = session.dateParsed {
                        Text(date.relativeTime)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                    }
                }

                // Title: Session N — Muscle Groups
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

                // Stats row
                HStack(spacing: PerchTheme.Spacing.medium) {
                    if let dur = session.durationMin {
                        statPill(icon: "clock", value: "\(dur)m")
                    }
                    if let cal = session.activeCalories {
                        statPill(icon: "flame", value: "\(cal) cal")
                    }
                    statPill(icon: "number", value: "\(session.totalSets) sets")
                    if let hr = session.avgHr {
                        statPill(icon: "heart", value: "\(hr) bpm")
                    }
                }

                // Top lifts (up to 3)
                let topLifts = Array(session.topLifts.prefix(3))
                if !topLifts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(topLifts.enumerated()), id: \.offset) { _, lift in
                            HStack {
                                Text(lift.name)
                                    .font(PerchTheme.Font.body)
                                    .foregroundColor(PerchTheme.textPrimary)
                                Spacer()
                                Text("\(Int(lift.weight))kg × \(lift.reps)")
                                    .font(PerchTheme.Font.captionNumeric)
                                    .foregroundColor(PerchTheme.textSecondary)
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
            }
            .padding(PerchTheme.Card.padding)
            .cardStyle()
        }
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
