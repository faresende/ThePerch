import SwiftUI

/// Displays an agent's status with emoji avatar, name, status dot, uptime, and current task.
/// Matches the React AgentStatusCard design.
struct AgentStatusCard: View {
    let agent: Agent
    let statusData: StatusData?

    private var agentState: AgentState {
        guard let state = statusData?.state.lowercased() else { return .idle }
        switch state {
        case "active", "running": return .active
        case "error", "failed": return .error
        default: return .idle
        }
    }

    private var uptimeText: String {
        guard let hours = statusData?.uptimeHours else { return "—" }
        if hours < 1 {
            return "\(Int(hours * 60))m"
        } else if hours < 24 {
            return String(format: "%.1fh", hours)
        } else {
            return String(format: "%.0fd", hours / 24)
        }
    }

    enum AgentState {
        case active
        case idle
        case error

        var color: Color {
            switch self {
            case .active: return PerchTheme.success
            case .idle: return PerchTheme.accent
            case .error: return PerchTheme.error
            }
        }

        var label: String {
            switch self {
            case .active: return "Active"
            case .idle: return "Idle"
            case .error: return "Error"
            }
        }
    }

    var body: some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            // Emoji avatar
            RoundedRectangle(cornerRadius: 14)
                .fill(PerchTheme.accentMuted)
                .frame(width: 44, height: 44)
                .overlay(
                    Text(agent.emoji ?? "🤖")
                        .font(PerchTheme.Font.title)
                )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                // Name + status dot
                HStack(spacing: 8) {
                    Text(agent.displayName)
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)

                    // Status indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(agentState.color)
                            .frame(width: 8, height: 8)
                            .shadow(
                                color: agentState == .active ? agentState.color.opacity(0.5) : .clear,
                                radius: 3
                            )

                        Text(agentState.label)
                            .font(PerchTheme.Font.micro)
                            .fontWeight(.semibold)
                            .foregroundColor(agentState.color)
                    }
                }

                // Uptime
                Text("Uptime: \(uptimeText)")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textTertiary)

                // Current task
                if let task = statusData?.currentTask, !task.isEmpty {
                    Text(task)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(PerchTheme.textSecondary.opacity(0.08))
                        .cornerRadius(8)
                        .padding(.top, 4)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: PerchTheme.Spacing.small) {
        AgentStatusCard(
            agent: Agent(
                id: "claudinho",
                displayName: "Claudinho",
                emoji: "🧠",
                model: "claude-opus-4-6",
                isActive: true,
                lastHeartbeat: Date.now.addingTimeInterval(-300),
                ownerId: UUID(),
                createdAt: Date.now.addingTimeInterval(-86400 * 30)
            ),
            statusData: StatusData(
                state: "active",
                uptimeHours: 48.5,
                lastActivity: Date.now.addingTimeInterval(-300),
                currentTask: "Processing health data sync"
            )
        )

        AgentStatusCard(
            agent: Agent(
                id: "archie",
                displayName: "Archie",
                emoji: "🔖",
                model: "claude-opus-4-6",
                isActive: true,
                lastHeartbeat: Date.now.addingTimeInterval(-600),
                ownerId: UUID(),
                createdAt: Date.now.addingTimeInterval(-86400 * 30)
            ),
            statusData: StatusData(
                state: "idle",
                uptimeHours: 12.3,
                lastActivity: nil,
                currentTask: nil
            )
        )

        AgentStatusCard(
            agent: Agent(
                id: "legal",
                displayName: "Legal",
                emoji: "⚖️",
                model: "claude-opus-4-6",
                isActive: false,
                lastHeartbeat: nil,
                ownerId: UUID(),
                createdAt: Date.now.addingTimeInterval(-86400 * 30)
            ),
            statusData: StatusData(
                state: "error",
                uptimeHours: 0,
                lastActivity: nil,
                currentTask: "API rate limit exceeded"
            )
        )
    }
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
