import SwiftUI

/// Shows weekly training volume by muscle group as horizontal bars.
struct WeeklyVolumeCard: View {
    let records: [Record]

    private var thisWeekSessions: [WorkoutSessionData] {
        let calendar = Calendar.current
        let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: .now)) ?? .now

        return records.compactMap { r -> WorkoutSessionData? in
            guard r.type == .workoutSession, let ws = r.asWorkoutSession() else { return nil }
            guard let date = ws.dateParsed, date >= startOfWeek else { return nil }
            return ws
        }
    }

    private var volumeByGroup: [(group: String, sets: Int)] {
        var counts: [String: Int] = [:]
        for session in thisWeekSessions {
            let setsPerGroup = session.totalSets / max(session.muscleGroups.count, 1)
            for group in session.muscleGroups {
                counts[group.lowercased(), default: 0] += setsPerGroup
            }
        }
        return counts.sorted { $0.value > $1.value }.map { (group: $0.key, sets: $0.value) }
    }

    private var totalDuration: Int {
        thisWeekSessions.compactMap { $0.durationMin }.reduce(0, +)
    }

    var body: some View {
        if !thisWeekSessions.isEmpty {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                // Header
                HStack {
                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Image(systemName: "chart.bar.fill")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.accent)
                        Text("THIS WEEK")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                            .tracking(1)
                    }
                    Spacer()
                    Text("\(thisWeekSessions.count) sessions · \(totalDuration)m")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }

                // Horizontal bars by muscle group
                let maxSets = volumeByGroup.first?.sets ?? 1
                ForEach(volumeByGroup, id: \.group) { item in
                    HStack(spacing: PerchTheme.Spacing.small) {
                        Text(item.group.capitalized)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                            .frame(width: 80, alignment: .leading)

                        GeometryReader { geo in
                            let fraction = CGFloat(item.sets) / CGFloat(max(maxSets, 1))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(PerchTheme.accent)
                                .frame(width: geo.size.width * fraction)
                        }
                        .frame(height: 14)

                        Text("\(item.sets)")
                            .font(PerchTheme.Font.captionNumeric)
                            .foregroundColor(PerchTheme.textTertiary)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }
            .padding(PerchTheme.Card.padding)
            .cardStyle()
        }
    }
}
