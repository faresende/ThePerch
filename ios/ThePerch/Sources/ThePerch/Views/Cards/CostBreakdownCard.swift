import SwiftUI

/// Displays token cost visualization with total and per-agent breakdown.
struct CostBreakdownCard: View {
    let totalCost: Double
    let breakdown: [AgentCost]
    let dateRange: String

    struct AgentCost: Identifiable {
        let id: String
        let agentId: String
        let agentEmoji: String
        let agentName: String
        let cost: Double

        var percent: Double {
            0 // Calculated based on total
        }
    }

    var maxCost: Double {
        breakdown.max(by: { $0.cost < $1.cost })?.cost ?? 1
    }

    private var accessibilitySummary: String {
        let agentSummaries = breakdown.map { "\($0.agentName) $\(String(format: "%.2f", $0.cost))" }
        return "Token costs: $\(String(format: "%.2f", totalCost)) total, \(dateRange). \(agentSummaries.joined(separator: ", "))"
    }

    var body: some View {
        CardContainer(title: "Token Costs") {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                // Total cost display
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                    Text("Total Cost")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)

                    Text("$\(String(format: "%.2f", totalCost))")
                        .font(PerchTheme.Font.titleNumeric)
                        .foregroundColor(PerchTheme.textPrimary)

                    Text(dateRange)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }

                Divider()
                    .padding(.vertical, PerchTheme.Spacing.xSmall)

                // Per-agent breakdown
                VStack(spacing: PerchTheme.Spacing.small) {
                    ForEach(breakdown) { agent in
                        CostBreakdownRow(
                            agent: agent,
                            maxCost: maxCost,
                            totalCost: totalCost
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }
}

// MARK: - Cost Breakdown Row

struct CostBreakdownRow: View {
    let agent: CostBreakdownCard.AgentCost
    let maxCost: Double
    let totalCost: Double

    var percentOfTotal: Double {
        guard totalCost > 0 else { return 0 }
        return (agent.cost / totalCost) * 100
    }

    var barWidth: CGFloat {
        guard maxCost > 0 else { return 0 }
        return CGFloat(agent.cost / maxCost) * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
            HStack(spacing: PerchTheme.Spacing.small) {
                // Agent emoji/name
                Text(agent.agentEmoji)
                    .font(PerchTheme.Font.icon(PerchTheme.Icon.large))

                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xxSmall) {
                    Text(agent.agentName)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textPrimary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: PerchTheme.Spacing.xxSmall) {
                    Text("$\(String(format: "%.2f", agent.cost))")
                        .font(PerchTheme.Font.bodyNumeric)
                        .foregroundColor(PerchTheme.textPrimary)

                    Text(String(format: "%.1f%%", percentOfTotal))
                        .font(PerchTheme.Font.captionNumeric)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }

            // Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PerchTheme.cardInnerBackground)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(PerchTheme.accent)
                        .frame(width: geometry.size.width * (barWidth / 100))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Preview

#Preview {
    CostBreakdownCard(
        totalCost: 4.75,
        breakdown: [
            CostBreakdownCard.AgentCost(
                id: "claudinho",
                agentId: "claudinho",
                agentEmoji: "🤖",
                agentName: "Claudinho",
                cost: 2.10
            ),
            CostBreakdownCard.AgentCost(
                id: "biochecha",
                agentId: "biochecha",
                agentEmoji: "💊",
                agentName: "BioChecha",
                cost: 0.95
            ),
            CostBreakdownCard.AgentCost(
                id: "archie",
                agentId: "archie",
                agentEmoji: "📚",
                agentName: "Archie",
                cost: 1.70
            ),
        ],
        dateRange: "Today"
    )
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
