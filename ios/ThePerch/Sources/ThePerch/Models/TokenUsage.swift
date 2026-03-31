import Foundation

/// Represents token usage statistics for an agent or user.
struct TokenUsage: Identifiable, Codable {
    let id: UUID
    let userId: UUID
    let agentId: String
    let date: Date
    let inputTokens: Int
    let outputTokens: Int
    let totalTokens: Int
    let costUsd: Double
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case costUsd = "cost_usd"
        case createdAt = "created_at"
        case userId = "user_id"
        case agentId = "agent_id"
    }

    /// Returns the cost per 1K tokens (useful for comparison).
    var costPer1kTokens: Double {
        guard totalTokens > 0 else { return 0 }
        return (costUsd / Double(totalTokens)) * 1000
    }
}
