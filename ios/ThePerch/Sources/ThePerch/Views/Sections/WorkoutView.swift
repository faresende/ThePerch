import SwiftUI

struct WorkoutView: View {
    let dashboardViewModel: DashboardViewModel
    @State private var viewModel = HealthViewModel()
    @State private var cardsAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: PerchTheme.Spacing.large) {
                    if dashboardViewModel.isLoading && viewModel.records.isEmpty {
                        ProgressView()
                            .padding(.top, 40)
                    } else if viewModel.records.isEmpty {
                        placeholderCard(title: "No Workouts", emoji: "🏋️", hint: "Log your first workout")
                    } else {
                        WeeklyVolumeCard(records: viewModel.records)
                            .cardAppear(index: 0, appeared: cardsAppeared)
                            .padding(.horizontal, PerchTheme.Spacing.large)

                        WorkoutCard(records: viewModel.records)
                            .cardAppear(index: 1, appeared: cardsAppeared)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    }
                }
                .padding(.vertical, PerchTheme.Spacing.large)
            }
            .background(PerchTheme.background.ignoresSafeArea())
            .navigationTitle("Workouts")
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.refreshRecords()
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
