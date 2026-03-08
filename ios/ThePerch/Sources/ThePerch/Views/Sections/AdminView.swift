import SwiftUI

/// OpenClaw admin dashboard with Helm-inspired widgets:
/// Gateway status, heartbeat, active models, agent list, upcoming crons, costs.
struct AdminView: View {
    @State private var viewModel = AdminViewModel()

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.agents.isEmpty {
                VStack(spacing: PerchTheme.Spacing.medium) {
                    HStack(spacing: PerchTheme.Spacing.medium) {
                        SkeletonRect(height: 100, cornerRadius: PerchTheme.Card.cornerRadius)
                        SkeletonRect(height: 100, cornerRadius: PerchTheme.Card.cornerRadius)
                    }
                    SkeletonRect(height: 80, cornerRadius: PerchTheme.Card.cornerRadius)
                    SkeletonRect(height: 80, cornerRadius: PerchTheme.Card.cornerRadius)
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.top, 60)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {

                    // Section header with freshness
                    SectionHeader(title: "Admin", freshnessKey: "admin")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    // MARK: - Error Banner
                    if let error = viewModel.error {
                        ErrorBanner(
                            message: error.localizedDescription,
                            retryAction: { Task { await viewModel.refresh() } },
                            onDismiss: { viewModel.error = nil }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // MARK: - Gateway Status + Heartbeat row
                    HStack(spacing: PerchTheme.Spacing.medium) {
                        // Status card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("OpenClaw")
                                    .font(PerchTheme.Font.body)
                                    .fontWeight(.bold)
                                    .foregroundColor(PerchTheme.textPrimary)
                                Spacer()
                                Circle()
                                    .fill(viewModel.gatewayIsRunning ? PerchTheme.success : PerchTheme.error)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: (viewModel.gatewayIsRunning ? PerchTheme.success : PerchTheme.error).opacity(0.6), radius: 4)
                            }

                            Text(viewModel.gatewayIsRunning ? "Running" : "Offline")
                                .font(PerchTheme.Font.titleNumeric)
                                .fontWeight(.bold)
                                .foregroundColor(viewModel.gatewayIsRunning ? PerchTheme.success : PerchTheme.error)

                            Text("\(viewModel.activeAgents.count) of \(viewModel.agents.count) agents active")
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                        .padding(PerchTheme.Card.padding)
                        .cardStyle()

                        // Heartbeat card
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Heartbeat")
                                    .font(PerchTheme.Font.body)
                                    .fontWeight(.bold)
                                    .foregroundColor(PerchTheme.textPrimary)
                                Spacer()
                                Image(systemName: "heart.fill")
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.accent)
                            }

                            if let heartbeat = viewModel.latestHeartbeat {
                                Text(heartbeat.relativeTime)
                                    .font(PerchTheme.Font.heading)
                                    .foregroundColor(PerchTheme.textPrimary)
                            } else {
                                Text("No pulse")
                                    .font(PerchTheme.Font.heading)
                                    .foregroundColor(PerchTheme.textTertiary)
                            }

                            Text("Last gateway pulse")
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                        .padding(PerchTheme.Card.padding)
                        .cardStyle()
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)

                    // MARK: - Active Models
                    if let status = viewModel.gatewayStatus, let models = status.activeModels, !models.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Active Models")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            activeModelsCard(models: models)
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // MARK: - Agent Status
                    if !viewModel.agents.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Agents")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            VStack(spacing: PerchTheme.Spacing.small) {
                                ForEach(viewModel.agents) { agent in
                                    AgentStatusCard(
                                        agent: agent,
                                        statusData: viewModel.statusDataForAgent(agent)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // MARK: - Upcoming Crons
                    if !viewModel.cronRecords.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Upcoming Crons")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            upcomingCronsCard
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // MARK: - Cost Summary
                    if let costRecord = viewModel.costRecords.first,
                       let costData = costRecord.asCostSummary() {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Today's Costs")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            let items = costData.breakdown.map { agentId, cost in
                                CostBreakdownCard.AgentCost(
                                    id: agentId,
                                    agentId: agentId,
                                    agentEmoji: viewModel.agentEmojiForId(agentId),
                                    agentName: viewModel.agentNameForId(agentId),
                                    cost: cost
                                )
                            }

                            CostBreakdownCard(
                                totalCost: costData.totalCostUsd,
                                breakdown: items.sorted { $0.cost > $1.cost },
                                dateRange: "Today"
                            )
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await viewModel.refresh()
                PerchHaptics.success()
            }
        }
        .task {
            await viewModel.loadRecords()
        }
    }

    // MARK: - Active Models Card

    @ViewBuilder
    private func activeModelsCard(models: [ActiveModel]) -> some View {
        let maxJobs = models.map(\.jobCount).max() ?? 1

        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(models.prefix(5).enumerated()), id: \.offset) { _, model in
                HStack(spacing: 10) {
                    Text(model.modelId)
                        .font(PerchTheme.Font.captionMono)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    // Bar
                    GeometryReader { geo in
                        let barWidth = max(geo.size.width * CGFloat(model.jobCount) / CGFloat(maxJobs), 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(PerchTheme.accent)
                            .frame(width: barWidth, height: 14)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(width: 120, height: 14)
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    // MARK: - Upcoming Crons Card

    private var upcomingCronsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(viewModel.cronRecords.prefix(5).enumerated()), id: \.offset) { _, record in
                if let cron = record.asCronJob() {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cron.name)
                                .font(PerchTheme.Font.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(PerchTheme.textPrimary)
                                .lineLimit(1)

                            if let model = cron.model {
                                Text(model)
                                    .font(PerchTheme.Font.microMono)
                                    .foregroundColor(PerchTheme.textTertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        if let nextRun = cron.nextRunAt {
                            Text(nextRun.relativeTime)
                                .font(PerchTheme.Font.caption)
                                .fontWeight(.medium)
                                .foregroundColor(PerchTheme.accent)
                        }
                    }

                    if record.id != viewModel.cronRecords.prefix(5).last?.id {
                        Divider()
                            .background(PerchTheme.border)
                    }
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }
}

// MARK: - Health Metric Row

struct HealthMetricRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textSecondary)

            Spacer()

            HStack(spacing: PerchTheme.Spacing.xSmall) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(value)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textPrimary)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AdminView()
}
