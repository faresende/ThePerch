import SwiftUI

// `PersonalRecordsCard` is the only live struct that survived the
// R8 dead-code purge of `Views/Sections/WorkoutView`. HealthTab
// reuses it via the `HealthTabPersonalRecordsCard` stub. Don't
// reintroduce the WorkoutView body — the live workouts surface
// is `WorkoutsSegment` in `Views/App/HealthTab.swift`.

// MARK: - Personal Records Card
struct PersonalRecordsCard: View {
    let sessions: [WorkoutSessionData]

    struct PR {
        let name: String
        let weight: Double
        let reps: Int
    }

    /// `topLifts` was previously a computed property that ran a triple-
    /// nested loop (sessions × exercises × sets ≈ 1,400 iterations) on
    /// every body render — including every parent state change, scroll,
    /// expand/collapse tap, and realtime tick. Now: cached in @State,
    /// recomputed only when the input `sessions` array changes (cheap
    /// fingerprint check via .onChange).
    @State private var topLifts: [PR] = []

    private var sessionsFingerprint: String {
        // Cheap signature: count + last session date + last exercise count.
        let last = sessions.last
        return "\(sessions.count)|\(last?.date ?? "")|\(last?.exercises.count ?? 0)"
    }

    private static func computeTopLifts(_ sessions: [WorkoutSessionData]) -> [PR] {
        var bests: [String: (weight: Double, reps: Int)] = [:]
        for session in sessions {
            for exercise in session.exercises {
                for set in exercise.sets {
                    let w = set.weightKg ?? 0
                    let r = set.reps ?? 0
                    if w > 0 {
                        let lowerName = exercise.name.lowercased()
                        if let current = bests[lowerName] {
                            if w > current.weight || (w == current.weight && r > current.reps) {
                                bests[lowerName] = (w, r)
                            }
                        } else {
                            bests[lowerName] = (w, r)
                        }
                    }
                }
            }
        }
        return bests
            .map { PR(name: $0.key.capitalized, weight: $0.value.weight, reps: $0.value.reps) }
            .sorted { $0.weight > $1.weight }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            HStack(spacing: PerchTheme.Spacing.xSmall) {
                Image(systemName: "trophy.fill")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.accent)
                Text("PERSONAL RECORDS")
                    .font(PerchTheme.Font.cardEyebrow)
                    .foregroundColor(PerchTheme.textSecondary)
                    .tracking(0.8)
                Spacer()
            }
            
            if topLifts.isEmpty {
                Text("No records yet")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                    ForEach(Array(topLifts.enumerated()), id: \.offset) { index, pr in
                        HStack {
                            Text("\(index + 1).")
                                .font(PerchTheme.Font.captionNumeric)
                                .foregroundColor(PerchTheme.textTertiary)
                                .frame(width: 20, alignment: .leading)
                            
                            Text(pr.name)
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textPrimary)
                            
                            Spacer()
                            
                            Text("\(Int(pr.weight))kg × \(pr.reps)")
                                .font(PerchTheme.Font.captionNumeric)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                        
                        if index < topLifts.count - 1 {
                            Divider()
                                .background(PerchTheme.border)
                        }
                    }
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .onAppear { topLifts = Self.computeTopLifts(sessions) }
        .onChange(of: sessionsFingerprint) { _, _ in
            topLifts = Self.computeTopLifts(sessions)
        }
    }
}
