import SwiftUI

/// OpenClaw admin dashboard with Helm-inspired widgets:
/// Gateway status, heartbeat, active models, agent list, upcoming crons, costs.
struct AdminView: View {
    @State private var agents: [Agent] = []
    @State private var costRecords: [Record] = []
    @State private var adminRecords: [Record] = []
    @State private var isLoading = true
    @State private var loadError: String?

    var activeAgents: [Agent] { agents.filter { $0.isActive } }

    /// Derive gateway running status from the most recent agent heartbeat.
    private var gatewayIsRunning: Bool {
        guard let latest = agents.compactMap({ $0.lastHeartbeat }).max() else { return false }
        return Date.now.timeIntervalSince(latest) < 300 // 5 minutes
    }

    /// Latest heartbeat across all agents.
    private var latestHeartbeat: Date? {
        agents.compactMap { $0.lastHeartbeat }.max()
    }

    /// Cron job records from admin category, sorted by next run time (nil pushed to end).
    private var cronRecords: [Record] {
        adminRecords.filter { $0.asCronJob() != nil }
            .sorted { r1, r2 in
                let d1 = r1.asCronJob()?.nextRunAt ?? .distantFuture
                let d2 = r2.asCronJob()?.nextRunAt ?? .distantFuture
                return d1 < d2
            }
    }

    /// Gateway status record (if available).
    private var gatewayStatus: GatewayStatusData? {
        adminRecords.compactMap { $0.asGatewayStatus() }.first
    }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            if isLoading && agents.isEmpty {
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
                    if let loadError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(PerchTheme.error)
                            Text(loadError)
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                            Spacer()
                            Button("Retry") {
                                Task { await loadData() }
                            }
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.accent)
                        }
                        .padding(PerchTheme.Spacing.medium)
                        .background(PerchTheme.error.opacity(0.1))
                        .cornerRadius(8)
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
                                    .fill(gatewayIsRunning ? PerchTheme.success : PerchTheme.error)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: (gatewayIsRunning ? PerchTheme.success : PerchTheme.error).opacity(0.6), radius: 4)
                            }

                            Text(gatewayIsRunning ? "Running" : "Offline")
                                .font(PerchTheme.Font.titleNumeric)
                                .fontWeight(.bold)
                                .foregroundColor(gatewayIsRunning ? PerchTheme.success : PerchTheme.error)

                            Text("\(activeAgents.count) of \(agents.count) agents active")
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

                            if let heartbeat = latestHeartbeat {
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
                    if let status = gatewayStatus, let models = status.activeModels, !models.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Active Models")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            activeModelsCard(models: models)
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // MARK: - Agent Status
                    if !agents.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Agents")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            VStack(spacing: PerchTheme.Spacing.small) {
                                ForEach(agents) { agent in
                                    AgentStatusCard(
                                        agent: agent,
                                        statusData: statusDataForAgent(agent)
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // MARK: - Upcoming Crons
                    if !cronRecords.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Upcoming Crons")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            upcomingCronsCard
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    // MARK: - Cost Summary
                    if let costRecord = costRecords.first,
                       let costData = costRecord.asCostSummary() {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Today's Costs")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            let items = costData.breakdown.map { agentId, cost in
                                CostBreakdownCard.AgentCost(
                                    id: agentId,
                                    agentId: agentId,
                                    agentEmoji: agentEmojiForId(agentId),
                                    agentName: agentNameForId(agentId),
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
                await loadData(forceRefresh: true)
                PerchHaptics.success()
            }
        }
        .task {
            await loadData()
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
            ForEach(Array(cronRecords.prefix(5).enumerated()), id: \.offset) { _, record in
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

                    if record.id != cronRecords.prefix(5).last?.id {
                        Divider()
                            .background(PerchTheme.border)
                    }
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    // MARK: - Data Loading

    private func loadData(forceRefresh: Bool = false) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            async let fetchedAgents = SupabaseService.shared.fetchAgents(forceRefresh: forceRefresh)
            async let fetchedCosts = SupabaseService.shared.fetchRecords(
                category: .admin,
                type: .costSummary,
                limit: 10,
                forceRefresh: forceRefresh
            )
            async let fetchedAdmin = SupabaseService.shared.fetchRecords(
                category: .admin,
                limit: 50,
                forceRefresh: forceRefresh
            )

            agents = try await fetchedAgents
            costRecords = try await fetchedCosts
            adminRecords = try await fetchedAdmin
            DataFreshnessTracker.shared.recordFetch(for: "admin")
        } catch {
            loadError = "Failed to load admin data"
            print("[AdminView] Failed to load: \(error)")
        }
    }

    // MARK: - Helpers

    private func statusDataForAgent(_ agent: Agent) -> StatusData {
        let state: String
        if agent.isActive && agent.isHealthy {
            state = "active"
        } else if agent.isActive {
            state = "idle"
        } else {
            state = "error"
        }

        let uptimeHours: Double
        if agent.lastHeartbeat != nil {
            uptimeHours = Date.now.timeIntervalSince(agent.createdAt) / 3600
        } else {
            uptimeHours = 0
        }

        return StatusData(
            state: state,
            uptimeHours: uptimeHours,
            lastActivity: agent.lastHeartbeat,
            currentTask: nil
        )
    }

    private func agentEmojiForId(_ agentId: String) -> String {
        if let agent = agents.first(where: { $0.id == agentId }), let emoji = agent.emoji {
            return emoji
        }
        switch agentId {
        case "claudinho": return "🤖"
        case "biochecha": return "💊"
        case "entregas": return "📦"
        case "calendario": return "📅"
        case "legal": return "⚖️"
        case "archie": return "📚"
        default: return "⚙️"
        }
    }

    private func agentNameForId(_ agentId: String) -> String {
        if let agent = agents.first(where: { $0.id == agentId }) {
            return agent.displayName
        }
        return agentId.capitalized
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
