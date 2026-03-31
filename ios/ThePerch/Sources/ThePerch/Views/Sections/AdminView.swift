import SwiftUI

/// OpenClaw admin dashboard with Helm-inspired widgets:
/// Gateway status, heartbeat, active models, agent list, upcoming crons, costs.
/// Records come from DashboardViewModel; agents are fetched separately.
struct AdminView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = AdminViewModel()
    @State private var showRestartConfirmation = false
    @State private var showDoctorFixConfirmation = false
    @State private var isRefreshingGatewayStatus = false
    @State private var selectedAgent: Agent?

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {

                    // Section header with freshness
                    SectionHeader(title: "Admin", freshnessKey: "admin")
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    // MARK: - Error Banner
                    if let error = dashboardViewModel.error {
                        ErrorBanner(
                            message: error.localizedDescription,
                            retryAction: {
                                Task {
                                    await dashboardViewModel.loadDashboard(forceRefresh: true)
                                    await dashboardViewModel.loadAgents(forceRefresh: true)
                                }
                            },
                            onDismiss: { dashboardViewModel.clearError() }
                        )
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    if dashboardViewModel.isLoading && viewModel.agents.isEmpty && dashboardViewModel.adminRecords.isEmpty {
                        SkeletonCardsSection(count: 3)
                            .padding(.horizontal, PerchTheme.Spacing.large)
                    } else {

                    // MARK: - Gateway Status + Heartbeat row
                    HStack(spacing: PerchTheme.Spacing.medium) {
                        // Status card with freshness
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("OpenClaw")
                                    .font(PerchTheme.Font.body)
                                    .fontWeight(.bold)
                                    .foregroundColor(PerchTheme.textPrimary)
                                Spacer()
                                Circle()
                                    .fill(viewModel.gatewayFreshness.color)
                                    .frame(width: 10, height: 10)
                                    .shadow(color: viewModel.gatewayFreshness.color.opacity(0.6), radius: 4)
                            }

                            Text(gatewayStatusTitle)
                                .font(PerchTheme.Font.titleNumeric)
                                .fontWeight(.bold)
                                .foregroundColor(viewModel.gatewayFreshness.color)

                            Text(viewModel.gatewayFreshness.label)
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(PerchTheme.textTertiary)
                                .lineLimit(2)

                            if let actionLabel = gatewayRefreshActionLabel {
                                Button {
                                    Task { await refreshGatewayStatus() }
                                } label: {
                                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                                        if isRefreshingGatewayStatus {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: gatewayRefreshActionIcon)
                                                .font(PerchTheme.Font.micro)
                                        }

                                        Text(actionLabel)
                                            .font(PerchTheme.Font.caption)
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(PerchTheme.accent)
                                    .padding(.horizontal, PerchTheme.Spacing.small)
                                    .padding(.vertical, PerchTheme.Spacing.xSmall)
                                    .background(
                                        Capsule()
                                            .fill(PerchTheme.accent.opacity(0.12))
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(isRefreshingGatewayStatus)
                            }
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
                                let heartbeatColor = heartbeatStatusColor
                                Circle()
                                    .fill(heartbeatColor)
                                    .frame(width: 8, height: 8)
                                Image(systemName: "heart.fill")
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(heartbeatColor)
                            }

                            if let heartbeat = viewModel.latestHeartbeat {
                                Text(heartbeat.relativeTime)
                                    .font(PerchTheme.Font.heading)
                                    .foregroundColor(PerchTheme.textPrimary)
                            } else {
                                Text("No pulse")
                                    .font(PerchTheme.Font.heading)
                                    .foregroundColor(PerchTheme.error)
                            }

                            Text("Last check-in")
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                        .padding(PerchTheme.Card.padding)
                        .cardStyle()
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)

                    // MARK: - Remote Controls
                    remoteControlsSection
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
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                        Text("Agents")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)

                        if viewModel.agents.isEmpty {
                            EmptyStateView(
                                icon: "person.3",
                                title: "No agents connected",
                                subtitle: "Agent status will appear here when OpenClaw reports active workers."
                            )
                        } else {
                            VStack(spacing: PerchTheme.Spacing.small) {
                                ForEach(viewModel.agents) { agent in
                                    Button {
                                        PerchHaptics.selection()
                                        selectedAgent = agent
                                    } label: {
                                        AgentStatusCard(
                                            agent: agent,
                                            statusData: viewModel.statusDataForAgent(agent),
                                            displayName: viewModel.displayNameForAgent(agent),
                                            subtitle: agent.subtitleLine,
                                            showsDisclosure: true
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)

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

                    }

                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                PerchHaptics.medium()
                await dashboardViewModel.loadDashboard(forceRefresh: true)
                await dashboardViewModel.loadAgents(forceRefresh: true)
                PerchHaptics.success()
            }
        }
        .alert("Are you sure?", isPresented: $showRestartConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Restart", role: .destructive) {
                Task { await viewModel.executeCommand(.restartGateway) }
            }
        } message: {
            Text("Are you sure? This will restart the OpenClaw gateway. Active sessions may be interrupted.")
        }
        .alert("Are you sure?", isPresented: $showDoctorFixConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Run", role: .none) {
                Task { await viewModel.executeCommand(.doctorFix) }
            }
        } message: {
            Text("Are you sure? This will run diagnostics and attempt to fix common issues.")
        }
        .task {
            // Agents come from a different table — fetch separately
            await dashboardViewModel.loadAgents()
        }
        .onChange(of: dashboardViewModel.adminRecords) { _, newRecords in
            viewModel.updateRecords(newRecords)
        }
        .onChange(of: dashboardViewModel.agents) { _, newAgents in
            viewModel.agents = newAgents
        }
        .onAppear {
            if !dashboardViewModel.adminRecords.isEmpty {
                viewModel.updateRecords(dashboardViewModel.adminRecords)
            }
            if !dashboardViewModel.agents.isEmpty {
                viewModel.agents = dashboardViewModel.agents
            }
        }
        .sheet(item: $selectedAgent) { agent in
            NavigationStack {
                agentDetailView(for: agent)
            }
        }
    }

    // MARK: - Heartbeat Status Color

    private var heartbeatStatusColor: Color {
        guard let heartbeat = viewModel.latestHeartbeat else { return PerchTheme.error }
        let hours = Date.now.timeIntervalSince(heartbeat) / 3600
        if hours < 2 { return PerchTheme.success }
        if hours < 12 { return PerchTheme.warning }
        return PerchTheme.error
    }

    // MARK: - Gateway Status Title

    private var gatewayStatusTitle: String {
        switch viewModel.gatewayFreshness {
        case .fresh: return "Running"
        case .stale: return "Running"
        case .possiblyOffline: return "Unknown"
        case .offline: return "Offline"
        }
    }

    private var gatewayRefreshActionLabel: String? {
        switch viewModel.gatewayFreshness {
        case .possiblyOffline:
            return "Check Now"
        case .offline:
            return "Reconnect"
        case .fresh, .stale:
            return nil
        }
    }

    private var gatewayRefreshActionIcon: String {
        switch viewModel.gatewayFreshness {
        case .offline:
            return "arrow.clockwise.circle"
        case .fresh, .stale, .possiblyOffline:
            return "arrow.clockwise"
        }
    }

    @MainActor
    private func refreshGatewayStatus() async {
        guard !isRefreshingGatewayStatus else { return }

        isRefreshingGatewayStatus = true
        PerchHaptics.medium()

        await dashboardViewModel.refreshRecords(forceRefresh: true)
        await dashboardViewModel.loadAgents(forceRefresh: true)

        isRefreshingGatewayStatus = false
        PerchHaptics.success()
    }

    // MARK: - Remote Controls Section

    private var remoteControlsSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("Remote Controls")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

            // Command buttons
            HStack(spacing: PerchTheme.Spacing.medium) {
                // Restart Gateway button
                commandButton(
                    icon: "arrow.clockwise.circle.fill",
                    label: "Restart Gateway",
                    state: viewModel.restartState,
                    isDestructive: true
                ) {
                    PerchHaptics.medium()
                    showRestartConfirmation = true
                }

                // Doctor Fix button
                commandButton(
                    icon: "stethoscope.circle.fill",
                    label: "Run Doctor Fix",
                    state: viewModel.doctorFixState,
                    isDestructive: false
                ) {
                    PerchHaptics.medium()
                    showDoctorFixConfirmation = true
                }
            }

            // Rate limit indicator
            if !viewModel.canSendCommand {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Image(systemName: "clock")
                        .font(PerchTheme.Font.micro)
                    Text("Rate limited — wait \(viewModel.rateLimitRemainingSeconds)s")
                        .font(PerchTheme.Font.micro)
                }
                .foregroundColor(PerchTheme.textTertiary)
            }

            // Command history
            if !viewModel.recentCommands.isEmpty {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                    Text("Recent Commands")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)

                    ForEach(Array(viewModel.recentCommands.prefix(5))) { record in
                        if let cmd = record.asAdminCommand() {
                            commandHistoryRow(record: record, command: cmd)
                        }
                    }
                }
                .padding(.top, PerchTheme.Spacing.xSmall)
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    @ViewBuilder
    private func agentDetailView(for agent: Agent) -> some View {
        let statusData = viewModel.statusDataForAgent(agent)

        ScrollView {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                AgentStatusCard(
                    agent: agent,
                    statusData: statusData,
                    displayName: viewModel.displayNameForAgent(agent),
                    subtitle: agent.subtitleLine
                )

                VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                    Text("About")
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)

                    Text(agent.roleDescription)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)

                    detailRow(label: "Model", value: agent.model ?? "Not reported")
                    detailRow(
                        label: "Last check-in",
                        value: agent.lastHeartbeat?.relativeTime ?? "No recent check-in"
                    )
                    detailRow(label: "Created", value: PerchFormatters.mediumDate.string(from: agent.createdAt))
                }
                .padding(PerchTheme.Card.padding)
                .cardStyle()
            }
            .padding(PerchTheme.Spacing.large)
        }
        .background(PerchTheme.background.ignoresSafeArea())
        .navigationTitle(viewModel.displayNameForAgent(agent))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
            Text(label)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)
                .frame(width: 96, alignment: .leading)

            Text(value)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textPrimary)

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func commandButton(
        icon: String,
        label: String,
        state: AdminViewModel.CommandExecutionState,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isExecuting: Bool = {
            if case .executing = state { return true }
            return false
        }()

        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    switch state {
                    case .idle:
                        Image(systemName: icon)
                            .font(.system(size: 24))
                    case .confirming:
                        Image(systemName: icon)
                            .font(.system(size: 24))
                    case .executing(let message):
                        VStack(spacing: 4) {
                            ProgressView()
                                .tint(isDestructive ? PerchTheme.error : PerchTheme.accent)
                            Text(message)
                                .font(PerchTheme.Font.micro)
                                .lineLimit(1)
                        }
                    case .completed(let message):
                        VStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(PerchTheme.success)
                            Text(message)
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(PerchTheme.success)
                                .lineLimit(2)
                        }
                    case .failed(let message):
                        VStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(PerchTheme.error)
                            Text(message)
                                .font(PerchTheme.Font.micro)
                                .foregroundColor(PerchTheme.error)
                                .lineLimit(2)
                        }
                    }
                }
                .frame(height: 50)

                if case .idle = state {
                    Text(label)
                        .font(PerchTheme.Font.caption)
                        .fontWeight(.medium)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(PerchTheme.Spacing.medium)
            .background(
                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                    .fill(isDestructive ? PerchTheme.error.opacity(0.15) : PerchTheme.accent.opacity(0.15))
            )
            .foregroundColor(isDestructive ? PerchTheme.error : PerchTheme.accent)
        }
        .disabled(isExecuting || !viewModel.canSendCommand)
        .opacity(isExecuting || !viewModel.canSendCommand ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: state)
    }

    private func commandHistoryRow(record: Record, command: AdminCommandData) -> some View {
        HStack {
            Image(systemName: command.command.icon)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textSecondary)

            Text(command.command.displayName)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textPrimary)

            Spacer()

            Text(record.relativeTime)
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)

            commandStatusBadge(command.status)
        }
    }

    private func commandStatusBadge(_ status: AdminCommandData.CommandStatus) -> some View {
        Text(status.displayName)
            .font(PerchTheme.Font.micro)
            .fontWeight(.medium)
            .foregroundColor(commandStatusColor(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(commandStatusColor(status).opacity(0.15))
            )
    }

    private func commandStatusColor(_ status: AdminCommandData.CommandStatus) -> Color {
        switch status {
        case .completed: return PerchTheme.success
        case .failed: return PerchTheme.error
        case .pending, .executing: return PerchTheme.warning
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
        .environment(DashboardViewModel())
}
