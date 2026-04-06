import SwiftUI

struct WorkoutView: View {
    let dashboardViewModel: DashboardViewModel
    @State private var viewModel = HealthViewModel()
    @State private var cardsAppeared = false
    @State private var expandedSessionId: UUID?

    private var workoutRecords: [(Record, WorkoutSessionData)] {
        let records = viewModel.records.compactMap { r -> (Record, WorkoutSessionData)? in
            guard r.type == .workoutSession, let ws = r.asWorkoutSession() else { return nil }
            return (r, ws)
        }
        return records.sorted {
            let date1 = $0.1.dateParsed ?? .distantPast
            let date2 = $1.1.dateParsed ?? .distantPast
            return date1 > date2
        }
    }

        var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    SectionHeader(title: "Workouts", freshnessKey: "workouts")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    content
                }
                .padding(.bottom, PerchTheme.Spacing.large)
            }
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.loadDashboard(forceRefresh: true)
                PerchHaptics.success()
            }
        }
        .onChange(of: dashboardViewModel.healthRecords) { _, newRecords in
            viewModel.records = newRecords
        }
        .onAppear {
            if !dashboardViewModel.healthRecords.isEmpty {
                viewModel.records = dashboardViewModel.healthRecords
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                cardsAppeared = true
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if dashboardViewModel.isLoading && viewModel.records.isEmpty {
            SkeletonCardsSection(count: 3)
                .padding(.horizontal, PerchTheme.Spacing.large)
        } else if let error = dashboardViewModel.error {
            ErrorBanner(
                message: error.localizedDescription,
                retryAction: { Task { await dashboardViewModel.loadDashboard(forceRefresh: true) } },
                onDismiss: { dashboardViewModel.clearError() }
            )
            .padding(.horizontal, PerchTheme.Spacing.large)
        } else if workoutRecords.isEmpty {
            EmptyStateView(
                icon: "figure.strengthtraining.traditional",
                title: "No workouts yet",
                subtitle: "Log your first workout to start tracking your progress."
            )
            .padding(.horizontal, PerchTheme.Spacing.large)
        } else {
            WeeklyVolumeCard(records: viewModel.records)
                .cardAppear(index: 0, appeared: cardsAppeared)
                .padding(.horizontal, PerchTheme.Spacing.large)

            feedSection

            PersonalRecordsCard(sessions: workoutRecords.map { $0.1 })
                .cardAppear(index: workoutRecords.count + 1, appeared: cardsAppeared)
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private var feedSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("RECENT SESSIONS")
                .font(PerchTheme.Font.cardEyebrow)
                .foregroundColor(PerchTheme.textSecondary)
                .padding(.horizontal, PerchTheme.Spacing.large)

            ForEach(Array(workoutRecords.enumerated()), id: \.element.0.id) { index, item in
                let isExpanded = expandedSessionId == item.0.id || (index == 0 && expandedSessionId == nil)
                
                Button {
                    PerchMotion.withOptionalAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        if expandedSessionId == item.0.id {
                            expandedSessionId = nil // Collapse if already expanded
                        } else {
                            expandedSessionId = item.0.id
                        }
                    }
                } label: {
                    WorkoutSessionFeedCard(session: item.1, isExpanded: isExpanded)
                        .cardAppear(index: index + 1, appeared: cardsAppeared)
                        .padding(.horizontal, PerchTheme.Spacing.large)
                }
                .buttonStyle(PlainButtonStyle()) // remove default flash
            }
        }
    }

    private func placeholderCard(title: String, emoji: String, hint: String) -> some View {
        VStack(spacing: PerchTheme.Spacing.small) {
            Text(emoji)
                .font(.system(size: 32))
            Text(title)
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textSecondary)
            Text(hint)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(PerchTheme.cardBackground)
        .cornerRadius(PerchTheme.Card.cornerRadius)
        .padding(.horizontal, PerchTheme.Spacing.large)
    }
}

// MARK: - Personal Records Card
struct PersonalRecordsCard: View {
    let sessions: [WorkoutSessionData]
    
    struct PR {
        let name: String
        let weight: Double
        let reps: Int
    }
    
    private var topLifts: [PR] {
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
        
        return bests.map { PR(name: $0.key.capitalized, weight: $0.value.weight, reps: $0.value.reps) }
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
    }
}
