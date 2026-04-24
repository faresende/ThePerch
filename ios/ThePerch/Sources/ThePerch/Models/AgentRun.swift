import Foundation

/// A single pipeline-run record from the `public.agent_runs` observability
/// table. Every cron / listener / aggregator brackets its work with one of
/// these rows so the iOS Admin view can answer "what broke, when?"
///
/// Schema:
///   id, agent_id, run_type, started_at, ended_at, status, summary, error_detail
///
/// `status` is one of: running | ok | error | partial | timeout
struct AgentRun: Identifiable, Codable, Sendable {
    let id: UUID
    let agentId: String
    let runType: String
    let startedAt: Date
    let endedAt: Date?
    let status: Status
    let summary: [String: JSONValue]?
    let errorDetail: String?

    enum Status: String, Codable, Sendable, Hashable {
        case running, ok, error, partial, timeout
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case agentId = "agent_id"
        case runType = "run_type"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case status
        case summary
        case errorDetail = "error_detail"
    }

    /// Duration in seconds if both timestamps are present.
    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    /// SF Symbol name for the status cell. Warning color is owned by the view.
    var statusIcon: String {
        switch status {
        case .ok:      return "checkmark.circle.fill"
        case .error:   return "xmark.octagon.fill"
        case .partial: return "exclamationmark.triangle.fill"
        case .timeout: return "clock.badge.exclamationmark.fill"
        case .running: return "arrow.triangle.2.circlepath"
        case .unknown: return "questionmark.circle"
        }
    }
}
