import SwiftUI

/// Compact list of recent pipeline runs from the `agent_runs` table.
/// Surfaced inside DebugAdminView so you can answer "what's been firing,
/// what's broken" without needing a SQL shell.
///
/// Each row = one cron / listener / aggregator invocation:
///   ✓ ok   · agent_id · run_type · started_at · duration
///   ✗ error: tap the row for the summary + error detail
struct AgentRunsCard: View {
    @State private var runs: [AgentRun] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var expandedRunId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            HStack {
                Text("Pipeline runs")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)
                Spacer()
                Button {
                    Task { await reload() }
                } label: {
                    Image(systemName: isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .foregroundStyle(.secondary)
                }
                .disabled(isLoading)
                .accessibilityLabel("Refresh pipeline runs")
            }

            if let error {
                Text(error)
                    .font(PerchTheme.Font.caption)
                    .foregroundStyle(.red)
            } else if runs.isEmpty && !isLoading {
                Text("No runs recorded yet.")
                    .font(PerchTheme.Font.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(runs.prefix(12)) { run in
                        AgentRunRow(
                            run: run,
                            isExpanded: expandedRunId == run.id,
                            onTap: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    expandedRunId = (expandedRunId == run.id) ? nil : run.id
                                }
                            }
                        )
                        if run.id != runs.prefix(12).last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(PerchTheme.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .task {
            if runs.isEmpty { await reload() }
        }
    }

    private func reload() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            runs = try await AdminCommandService.shared.fetchRecentAgentRuns(limit: 40)
        } catch let e {
            error = e.localizedDescription
        }
    }
}

private struct AgentRunRow: View {
    let run: AgentRun
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onTap) {
                HStack(spacing: 10) {
                    Image(systemName: run.statusIcon)
                        .foregroundStyle(statusColor)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(run.agentId) · \(run.runType)")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                            .lineLimit(1)
                        Text(run.startedAt, format: .relative(presentation: .named))
                            .font(PerchTheme.Font.micro)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let dur = run.duration {
                        Text(formatDuration(dur))
                            .font(PerchTheme.Font.microMono)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    if let err = run.errorDetail, !err.isEmpty {
                        Text(err)
                            .font(PerchTheme.Font.captionMono)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let summary = run.summary, !summary.isEmpty {
                        Text(formatSummary(summary))
                            .font(PerchTheme.Font.captionMono)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 30)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch run.status {
        case .ok:      return .green
        case .error, .partial, .timeout: return .red
        case .running: return .orange
        case .unknown: return .secondary
        }
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        if s < 1 { return String(format: "%dms", Int(s * 1000)) }
        if s < 60 { return String(format: "%.1fs", s) }
        return String(format: "%dm%ds", Int(s) / 60, Int(s) % 60)
    }

    private func formatSummary(_ summary: [String: JSONValue]) -> String {
        summary
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(summarize($0.value))" }
            .joined(separator: " · ")
    }

    private func summarize(_ v: JSONValue) -> String {
        switch v {
        case .string(let s): return s.count > 40 ? String(s.prefix(37)) + "…" : s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .array(let a): return "[\(a.count)]"
        case .object(let o): return "{\(o.count)}"
        }
    }
}

#if DEBUG
#Preview {
    AgentRunsCard()
        .padding()
        .background(PerchTheme.background)
}
#endif
