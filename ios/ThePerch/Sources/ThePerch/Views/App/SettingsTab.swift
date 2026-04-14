import SwiftUI

/// Settings tab — configuration, integrations, and admin tools.
/// Evolves from SettingsView, absorbing AdminView content (integrations, debug, advanced).
struct SettingsTab: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AuthViewModel.self) var authViewModel
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @State private var isSigningOut = false
    @State private var showChangeBackend = false
    @State private var editableSections: [Section] = []
    @State private var isSavingSections = false
    @State private var selectedAdminSection: AdminSubSection? = nil

    enum AdminSubSection: String, CaseIterable, Identifiable {
        var id: String { rawValue }
        case integrations = "Integrations"
        case debug = "Debug & Advanced"
    }

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                    LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                        // User profile section
                        profileSection
                            .padding(.horizontal, PerchTheme.Spacing.large)

                        // Preferences section
                        preferencesSection
                            .padding(.horizontal, PerchTheme.Spacing.large)

                        // Section management — toggle visibility and reorder
                        sectionManagementSection
                            .padding(.horizontal, PerchTheme.Spacing.large)

                        // Admin tools
                        adminToolsSection
                            .padding(.horizontal, PerchTheme.Spacing.large)

                        // Backend section
                        backendSection
                            .padding(.horizontal, PerchTheme.Spacing.large)
                            .sheet(isPresented: $showChangeBackend) {
                                OnboardingView {
                                    showChangeBackend = false
                                }
                            }

                        // About section
                        aboutSection
                            .padding(.horizontal, PerchTheme.Spacing.large)

                        // Sign out button
                        signOutSection
                            .padding(.horizontal, PerchTheme.Spacing.large)

                        Spacer()
                            .frame(height: PerchTheme.TabBar.contentInsetHeight)
                    }
                }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: PerchTheme.TabBar.contentInsetHeight)
            }
            .onAppear {
                editableSections = dashboardViewModel.sections
                    .filter { $0.slug != "legal" }
                    .sorted { $0.sortOrder < $1.sortOrder }
            }
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            Text("Profile")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

            CardContainer {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                    HStack {
                        Text("Display Name")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                        Spacer()
                        Text(authViewModel.displayName.isEmpty ? "Not set" : authViewModel.displayName)
                            .font(PerchTheme.Font.body)
                            .fontWeight(.medium)
                            .foregroundColor(PerchTheme.textPrimary)
                    }

                    Divider()

                    HStack {
                        Text("Email")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textTertiary)
                        Spacer()
                        Text(authViewModel.email.isEmpty ? "Not set" : authViewModel.email)
                            .font(PerchTheme.Font.body)
                            .fontWeight(.medium)
                            .foregroundColor(PerchTheme.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("Preferences")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

            CardContainer {
                VStack(spacing: 0) {
                    HStack {
                        Text("Dark Mode")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)

                        Spacer()

                        Toggle("", isOn: $darkModeEnabled)
                    }
                    .padding(PerchTheme.Spacing.small)
                }
            }
        }
    }

    // MARK: - Section Management

    private var sectionManagementSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            HStack {
                Text("Tabs")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)
                Spacer()
                if isSavingSections {
                    ProgressView().scaleEffect(0.8)
                }
            }

            Text("Toggle tabs on/off or drag to reorder.")
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)

            CardContainer {
                List {
                    ForEach($editableSections) { $section in
                        HStack(spacing: PerchTheme.Spacing.medium) {
                            Text(section.displayName)
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textPrimary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { section.isVisible },
                                set: { newValue in
                                    section.isVisible = newValue
                                    Task { await saveSections() }
                                }
                            ))
                                .labelsHidden()
                                .tint(PerchTheme.accent)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .onMove { from, to in
                        editableSections.move(fromOffsets: from, toOffset: to)
                        Task { await saveSections() }
                    }
                }
                .listStyle(.plain)
                .frame(height: CGFloat(editableSections.count) * 52)
                .environment(\.editMode, .constant(.active))
            }
        }
    }

    // MARK: - Admin Tools Section

    private var adminToolsSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("Admin Tools")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

            CardContainer {
                VStack(spacing: 0) {
                    AdminToolRow(
                        icon: "link.circle.fill",
                        title: "Integrations",
                        subtitle: "Manage connected services and API keys"
                    ) {
                        selectedAdminSection = .integrations
                    }

                    Divider()
                        .padding(.leading, 52)

                    AdminToolRow(
                        icon: "ant.fill",
                        title: "Debug & Advanced",
                        subtitle: "Gateway status, agents, crons, costs"
                    ) {
                        selectedAdminSection = .debug
                    }
                }
            }
            .sheet(item: $selectedAdminSection) { section in
                NavigationStack {
                    switch section {
                    case .integrations:
                        IntegrationsView()
                    case .debug:
                        DebugAdminView()
                    }
                }
            }
        }
    }

    // MARK: - Backend Section

    private var backendSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("Backend")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

            CardContainer {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Mode")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                            Text(KeychainService.shared.load()?.backendMode == .managedCloud ? "ThePerch Cloud" : "Self-hosted (Supabase)")
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textPrimary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(PerchTheme.success)
                    }

                    Divider().padding(.vertical, PerchTheme.Spacing.xSmall)

                    Button {
                        showChangeBackend = true
                    } label: {
                        HStack {
                            Text("Change backend")
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.error)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(PerchTheme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("About")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

            CardContainer {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                    HStack {
                        Text("App Version")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)

                        Spacer()

                        Text(appVersion)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                    }

                    Divider()
                        .padding(.vertical, PerchTheme.Spacing.xSmall)

                    HStack {
                        Text("Build")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)

                        Spacer()

                        Text("1")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                    }
                }
            }
        }
    }

    // MARK: - Sign Out

    private var signOutSection: some View {
        Button(action: { handleSignOut() }) {
            ZStack {
                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                    .fill(PerchTheme.error.opacity(0.1))

                HStack(spacing: PerchTheme.Spacing.small) {
                    if isSigningOut {
                        ProgressView()
                            .tint(PerchTheme.error)
                    }

                    Text("Sign Out")
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.error)
                }
            }
        }
        .frame(height: 50)
        .disabled(isSigningOut)
        .opacity(isSigningOut ? 0.6 : 1)
    }

    private func handleSignOut() {
        isSigningOut = true
        Task {
            await authViewModel.signOut()
            isSigningOut = false
        }
    }

    private func saveSections() async {
        isSavingSections = true
        var updated = editableSections
        for i in updated.indices {
            updated[i].sortOrder = i
        }
        await dashboardViewModel.reorderSections(updated)
        isSavingSections = false
    }
}

// ProfileField reused from SettingsView.swift

// MARK: - Admin Tool Row

private struct AdminToolRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: PerchTheme.Spacing.medium) {
                Image(systemName: icon)
                    .font(PerchTheme.Font.icon(PerchTheme.Icon.large))
                    .foregroundColor(PerchTheme.accent)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textPrimary)

                    Text(subtitle)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(PerchTheme.textTertiary)
            }
            .padding(PerchTheme.Spacing.small)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Integrations View

private struct IntegrationsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                Text("Connected services and API keys are managed via environment variables and the OpenClaw gateway configuration.")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
                    .padding(.horizontal, PerchTheme.Spacing.large)

                VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                    Text("Health Sources")
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)

                    CardContainer {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                            integrationRow(name: "Apple Health", connected: true)
                            integrationRow(name: "Oura Ring", connected: true)
                        }
                    }
                }
                .padding(.horizontal, PerchTheme.Spacing.large)

                VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                    Text("Data Integrations")
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)

                    CardContainer {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                            integrationRow(name: "Supabase", connected: true)
                            integrationRow(name: "TripIt", connected: true)
                            integrationRow(name: "OpenFoodFacts", connected: true)
                            integrationRow(name: "Karakeep", connected: true)
                            integrationRow(name: "Paperless", connected: true)
                        }
                    }
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
            }
            .padding(.top, PerchTheme.Spacing.large)
        }
        .background(PerchTheme.background.ignoresSafeArea())
        .navigationTitle("Integrations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .foregroundColor(PerchTheme.accent)
            }
        }
    }

    private func integrationRow(name: String, connected: Bool) -> some View {
        HStack {
            Text(name)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(connected ? PerchTheme.success : PerchTheme.textTertiary)
                    .frame(width: 8, height: 8)
                Text(connected ? "Connected" : "Not configured")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(connected ? PerchTheme.success : PerchTheme.textTertiary)
            }
        }
        .padding(.vertical, PerchTheme.Spacing.xxSmall)
    }
}

// MARK: - Debug Admin View (absorbed from AdminView)

private struct DebugAdminView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var viewModel = AdminViewModel()
    @State private var showRestartConfirmation = false
    @State private var showDoctorFixConfirmation = false
    @State private var isRefreshingGatewayStatus = false
    @State private var selectedAgent: Agent?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                // Gateway status + heartbeat
                HStack(spacing: PerchTheme.Spacing.medium) {
                    gatewayStatusCard
                        .cardStyle()

                    heartbeatCard
                        .cardStyle()
                }
                .padding(.horizontal, PerchTheme.Spacing.large)

                // Remote controls
                remoteControlsSection
                    .padding(.horizontal, PerchTheme.Spacing.large)

                // Active models
                if let status = viewModel.gatewayStatus, let models = status.activeModels, !models.isEmpty {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                        Text("Active Models")
                            .font(PerchTheme.Font.heading)
                            .foregroundColor(PerchTheme.textPrimary)
                        activeModelsCard(models: models)
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)
                }

                // Agent status
                agentsSection
                    .padding(.horizontal, PerchTheme.Spacing.large)

                // Upcoming crons
                if !viewModel.cronRecords.isEmpty {
                    upcomingCronsSection
                        .padding(.horizontal, PerchTheme.Spacing.large)
                }

                // Cost summary
                if let costRecord = viewModel.costRecords.first,
                   let costData = costRecord.asCostSummary() {
                    costSection(costData: costData)
                        .padding(.horizontal, PerchTheme.Spacing.large)
                }

                Spacer()
                    .frame(height: PerchTheme.Spacing.large)
            }
            .padding(.top, PerchTheme.Spacing.medium)
        }
        .background(PerchTheme.background.ignoresSafeArea())
        .navigationTitle("Debug & Advanced")
        .navigationBarTitleDisplayMode(.inline)
        .task {
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

    private var gatewayStatusCard: some View {
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
                    .background(Capsule().fill(PerchTheme.accent.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(isRefreshingGatewayStatus)
            }
        }
        .padding(PerchTheme.Card.padding)
    }

    private var heartbeatCard: some View {
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
    }

    private var remoteControlsSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("Remote Controls")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

            HStack(spacing: PerchTheme.Spacing.medium) {
                commandButton(icon: "arrow.clockwise.circle.fill", label: "Restart Gateway", state: viewModel.restartState, isDestructive: true) {
                    PerchHaptics.medium()
                    showRestartConfirmation = true
                }

                commandButton(icon: "stethoscope.circle.fill", label: "Run Doctor Fix", state: viewModel.doctorFixState, isDestructive: false) {
                    PerchHaptics.medium()
                    showDoctorFixConfirmation = true
                }
            }

            if !viewModel.canSendCommand {
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Image(systemName: "clock")
                        .font(PerchTheme.Font.micro)
                    Text("Rate limited — wait \(viewModel.rateLimitRemainingSeconds)s")
                        .font(PerchTheme.Font.micro)
                }
                .foregroundColor(PerchTheme.textTertiary)
            }

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
    }

    private var agentsSection: some View {
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
    }

    private var upcomingCronsSection: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            Text("Upcoming Crons")
                .font(PerchTheme.Font.heading)
                .foregroundColor(PerchTheme.textPrimary)

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

    private func costSection(costData: CostSummaryData) -> some View {
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
                    detailRow(label: "Last check-in", value: agent.lastHeartbeat?.relativeTime ?? "No recent check-in")
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

    private func commandButton(icon: String, label: String, state: AdminViewModel.CommandExecutionState, isDestructive: Bool, action: @escaping () -> Void) -> some View {
        let isExecuting: Bool = {
            if case .executing = state { return true }
            return false
        }()

        return Button(action: action) {
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
            .background(RoundedRectangle(cornerRadius: 4).fill(commandStatusColor(status).opacity(0.15)))
    }

    private func commandStatusColor(_ status: AdminCommandData.CommandStatus) -> Color {
        switch status {
        case .completed: return PerchTheme.success
        case .failed: return PerchTheme.error
        case .pending, .executing: return PerchTheme.warning
        }
    }

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

    private var heartbeatStatusColor: Color {
        guard let heartbeat = viewModel.latestHeartbeat else { return PerchTheme.error }
        let hours = Date.now.timeIntervalSince(heartbeat) / 3600
        if hours < 2 { return PerchTheme.success }
        if hours < 12 { return PerchTheme.warning }
        return PerchTheme.error
    }

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
        case .possiblyOffline: return "Check Now"
        case .offline: return "Reconnect"
        case .fresh, .stale: return nil
        }
    }

    private var gatewayRefreshActionIcon: String {
        switch viewModel.gatewayFreshness {
        case .offline: return "arrow.clockwise.circle"
        case .fresh, .stale, .possiblyOffline: return "arrow.clockwise"
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
}

// MARK: - Preview

#Preview {
    SettingsTab()
        .environment(AuthViewModel())
        .environment(DashboardViewModel())
}
