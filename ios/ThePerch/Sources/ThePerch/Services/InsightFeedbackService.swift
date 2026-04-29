// InsightFeedbackService.swift
//
// Posts user reactions from the rage-shake feedback sheet to
// public.insight_feedback. Phase 5 of time-aware BioChecha insights.

import Foundation
import Supabase

@MainActor
final class InsightFeedbackService {
    static let shared = InsightFeedbackService()

    private let supabaseService: SupabaseService

    init() {
        self.supabaseService = .shared
    }

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
    }

    /// Insert a feedback row tied to the given insight (or untied if nil).
    /// Throws on auth failure or network/PostgREST error — caller should
    /// surface a non-blocking toast and let the user retry.
    func submit(insightId: UUID?, insightBody: String, reaction: String) async throws {
        guard let userIdString = supabaseService.currentUserId,
              let userId = UUID(uuidString: userIdString) else {
            throw InsightFeedbackError.notAuthenticated
        }
        let payload = InsightFeedbackPayload(
            user_id: userId,
            insight_id: insightId,
            insight_body: insightBody,
            reaction: reaction
        )
        try await supabaseService.databaseClient
            .from("insight_feedback")
            .insert(payload)
            .execute()
    }
}

enum InsightFeedbackError: Error {
    case notAuthenticated
}

private struct InsightFeedbackPayload: Encodable, Sendable {
    let user_id: UUID
    let insight_id: UUID?
    let insight_body: String
    let reaction: String
}
