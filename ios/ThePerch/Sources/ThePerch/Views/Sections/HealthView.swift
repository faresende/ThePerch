import SwiftUI

/// Health section showing one chart card per metric, plus calories and macros cards.
struct HealthView: View {
    @State private var viewModel = HealthViewModel()
    @State private var selectedDetail: HealthDetailInfo?
    @State private var cardsAppeared = false

    struct HealthDetailInfo: Identifiable {
        let id = UUID()
        let title: String
        let records: [Record]
        let unit: String
        let formatAsTime: Bool
        let higherIsBetter: Bool
    }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Section header with freshness
                    SectionHeader(title: "Health", freshnessKey: "health")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    // NOTE: HealthKit sync button hidden for now — all data comes from Claudinho.
                    // Uncomment to re-enable Apple Health sync:
                    // if viewModel.isHealthKitAvailable {
                    //     syncSection
                    // }

                    // Error banner
                    if viewModel.error != nil {
                        ErrorBanner(
                            message: "Failed to load health data",
                            retryAction: { Task { await viewModel.loadRecords() } },
                            onDismiss: { viewModel.clearError() }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    if viewModel.isLoading && viewModel.records.isEmpty {
                        SkeletonHealthSection()
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    } else {
                        // Daily calories card
                        if let (record, measurement) = viewModel.latestByMetric["daily_calories"],
                           let target = measurement.target {
                            CaloriesCard(
                                consumed: measurement.value,
                                target: target,
                                unit: measurement.unit,
                                lastUpdated: measurement.timestamp ?? record.updatedAt
                            )
                            .cardAppear(index: 0, appeared: cardsAppeared)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        } else {
                            placeholderCard(title: "Daily Calories", emoji: "🔥", hint: "Log food with Claudinho")
                        }

                        // Daily macros card
                        if let (record, macros) = viewModel.latestMacros {
                            MacrosCard(
                                protein: macros.protein,
                                proteinTarget: macros.proteinTarget,
                                carbs: macros.carbs,
                                carbsTarget: macros.carbsTarget,
                                fat: macros.fat,
                                fatTarget: macros.fatTarget,
                                lastUpdated: macros.dateAsDate ?? record.updatedAt
                            )
                            .cardAppear(index: 1, appeared: cardsAppeared)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        } else {
                            placeholderCard(title: "Daily Macros", emoji: "🥩", hint: "Log food with Claudinho")
                        }

                        // One chart card per metric — tap to see full detail
                        ForEach(Array(HealthViewModel.chartMetricOrder.enumerated()), id: \.element.key) { chartIndex, metricInfo in
                            let metricRecords = viewModel.recordsForMetric(metricInfo.key)
                            let isTimeBased = metricInfo.key == "sleep_duration" || metricInfo.key == "deep_sleep"
                            if !metricRecords.isEmpty {
                                Button {
                                    PerchHaptics.light()
                                    selectedDetail = HealthDetailInfo(
                                        title: metricInfo.title,
                                        records: metricRecords,
                                        unit: isTimeBased ? "" : metricInfo.unit,
                                        formatAsTime: isTimeBased,
                                        higherIsBetter: metricInfo.higherIsBetter
                                    )
                                } label: {
                                    ChartCard(
                                        title: metricInfo.title,
                                        records: metricRecords,
                                        unit: isTimeBased ? "" : metricInfo.unit,
                                        formatAsTime: isTimeBased,
                                        higherIsBetter: metricInfo.higherIsBetter
                                    )
                                }
                                .buttonStyle(CardPressStyle())
                                .cardAppear(index: chartIndex + 2, appeared: cardsAppeared)
                                .padding(.horizontal, PerchTheme.Spacing.large)
                            } else {
                                placeholderCard(
                                    title: metricInfo.title,
                                    emoji: metricInfo.emoji,
                                    hint: placeholderHint(for: metricInfo.key)
                                )
                            }
                        }
                    }
                    Color.clear
                        .frame(height: 0)
                        .onAppear {
                            PerchMotion.withOptionalAnimation { cardsAppeared = true }
                        }

                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await viewModel.loadRecords(forceRefresh: true)
                PerchHaptics.success()
            }
        }
        .task {
            await viewModel.loadRecords()
        }
        .sheet(item: $selectedDetail) { detail in
            HealthDetailView(
                title: detail.title,
                records: detail.records,
                unit: detail.unit,
                formatAsTime: detail.formatAsTime,
                higherIsBetter: detail.higherIsBetter
            )
        }
    }

    // MARK: - Sync Section

    private var syncSection: some View {
        VStack(spacing: PerchTheme.Spacing.small) {
            Button {
                Task { await viewModel.syncWithHealthKit() }
            } label: {
                HStack(spacing: PerchTheme.Spacing.small) {
                    if viewModel.isSyncing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "heart.fill")
                            .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                    }
                    Text(viewModel.isSyncing ? "Syncing..." : "Sync with Apple Health")
                        .font(PerchTheme.Font.heading)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, PerchTheme.Spacing.medium)
                .background(
                    RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                        .fill(viewModel.isSyncing ? PerchTheme.textSecondary : PerchTheme.accent)
                )
            }
            .disabled(viewModel.isSyncing)

            HStack {
                if let lastSync = viewModel.lastSyncFormatted {
                    Text("Last synced \(lastSync)")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                Spacer()
                if viewModel.syncedCount > 0 {
                    Text("\(viewModel.syncedCount) new records")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.success)
                }
            }

            if let syncError = viewModel.syncError {
                Text(syncError)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.error)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, PerchTheme.Spacing.large)
        .padding(.top, PerchTheme.Spacing.small)
    }

    // MARK: - Placeholder Card

    private func placeholderCard(title: String, emoji: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(emoji)
                    .font(PerchTheme.Font.title)
                Text(title)
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)
            }

            Text("No data yet")
                .font(PerchTheme.Font.displayNumeric)
                .foregroundColor(PerchTheme.textTertiary)

            Text(hint)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .padding(.horizontal, PerchTheme.Spacing.large)
    }

    private func placeholderHint(for metricKey: String) -> String {
        switch metricKey {
        case "weight":
            return "Sync Apple Health or log with Claudinho"
        case "skeletal_muscle", "body_fat_mass":
            return "Share your InBody scan with Claudinho"
        case "sleep_duration", "deep_sleep", "lowest_sleep_hr", "avg_sleep_hrv":
            return "Share your Oura data with Claudinho"
        default:
            return "Ask Claudinho to log this metric"
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "heart.text.square")
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            Text("No health data yet")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textSecondary)

            if viewModel.isHealthKitAvailable {
                Text("Tap \"Sync with Apple Health\" to pull your latest health metrics.")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textTertiary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Health data will appear here once Claudinho starts syncing your Oura and nutrition data.")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(PerchTheme.Spacing.xxLarge)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview

#Preview {
    HealthView()
}
