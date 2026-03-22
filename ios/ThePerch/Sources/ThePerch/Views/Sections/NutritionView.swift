import SwiftUI

/// Nutrition section showing the daily summary and recent meal analysis cards.
struct NutritionView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel

    @State private var viewModel = NutritionViewModel()
    @State private var cardsAppeared = false
    @State private var showingInputSheet = false

    private var nutritionRecords: [Record] {
        dashboardViewModel.recordsBySlug[RecordCategory.nutrition.rawValue] ?? []
    }

    private var submissionUserId: String {
        nutritionRecords.first?.userId.uuidString ?? AppConfig.defaultUserID.uuidString
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    SectionHeader(title: "Nutrition", freshnessKey: "nutrition")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    if let error = viewModel.error {
                        ErrorBanner(
                            message: error,
                            retryAction: { Task { await dashboardViewModel.refreshRecords(forceRefresh: true) } },
                            onDismiss: { viewModel.error = nil }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    content

                    Color.clear
                        .frame(height: 0)
                        .onAppear {
                            PerchMotion.withOptionalAnimation { cardsAppeared = true }
                        }

                    Spacer()
                        .frame(height: 96)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.refreshRecords(forceRefresh: true)
                PerchHaptics.success()
            }

            addMealButton
        }
        .onChange(of: dashboardViewModel.allRecords) { _, newRecords in
            viewModel.loadMeals(from: newRecords)
        }
        .onAppear {
            viewModel.loadMeals(from: dashboardViewModel.allRecords)
        }
        .sheet(isPresented: $showingInputSheet) {
            MealInputSheet(isSubmitting: viewModel.isAnalyzing) { text, image in
                await viewModel.logMeal(text: text, image: image, userId: submissionUserId)
                await dashboardViewModel.refreshRecords(forceRefresh: true)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var content: some View {
        if dashboardViewModel.isLoading && viewModel.meals.isEmpty {
            VStack(spacing: PerchTheme.Spacing.medium) {
                DailySummaryBar.shimmer
                ForEach(0..<3, id: \.self) { index in
                    MealCard.shimmer
                        .cardAppear(index: index + 1, appeared: cardsAppeared)
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        } else if viewModel.meals.isEmpty {
            EmptyStateView(
                icon: "fork.knife",
                title: "No meals logged",
                subtitle: "Add your first meal to start tracking calories and macros for the day.",
                actionTitle: "Log a meal",
                action: { showingInputSheet = true }
            )
            .padding(.horizontal, PerchTheme.Spacing.large)
        } else {
            VStack(spacing: PerchTheme.Spacing.medium) {
                DailySummaryBar(summary: viewModel.dailySummary)
                    .cardAppear(index: 0, appeared: cardsAppeared)

                ForEach(Array(viewModel.meals.enumerated()), id: \.element.id) { index, record in
                    MealCard(meal: MealRecord(from: record))
                        .cardAppear(index: index + 1, appeared: cardsAppeared)
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        }
    }

    private var addMealButton: some View {
        Button {
            showingInputSheet = true
        } label: {
            HStack(spacing: PerchTheme.Spacing.small) {
                Image(systemName: "plus")
                    .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                Text("Log Meal")
                    .font(PerchTheme.Font.body)
                    .fontWeight(.semibold)
            }
            .foregroundColor(PerchTheme.accentForeground)
            .padding(.horizontal, PerchTheme.Spacing.medium)
            .padding(.vertical, PerchTheme.Spacing.small)
            .background(
                Capsule()
                    .fill(PerchTheme.accent)
            )
            .shadow(color: PerchTheme.accent.opacity(0.28), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.trailing, PerchTheme.Spacing.large)
        .padding(.bottom, PerchTheme.Spacing.large)
    }
}

#Preview {
    NutritionView()
        .environment(DashboardViewModel())
}
