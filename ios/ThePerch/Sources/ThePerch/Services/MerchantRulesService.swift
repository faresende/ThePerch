// MerchantRulesService.swift
//
// Reads/writes public.merchant_rules — the Phase 2 distill layer of the
// orders corrections-and-rules feedback loop. Auto-promoted rules show
// up here without iOS doing anything; this service exposes them for
// the Settings → Auto-learned rules screen so the user can disable or
// delete a rule that turned out to be wrong.

import Foundation
import Supabase

@MainActor
final class MerchantRulesService {
    static let shared = MerchantRulesService()

    private let supabaseService: SupabaseService
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(supabaseService: SupabaseService = .shared) {
        self.supabaseService = supabaseService
    }

    /// Load every rule for the current user, newest-first.
    func fetchRules() async throws -> [MerchantRule] {
        let response = try await supabaseService.databaseClient
            .from("merchant_rules")
            .select()
            .order("created_at", ascending: false)
            .execute()

        // Decode permissively: skip malformed rows so a single bad row
        // doesn't black-hole the whole list.
        let raws = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] ?? []
        var rules: [MerchantRule] = []
        rules.reserveCapacity(raws.count)
        for raw in raws {
            guard let data = try? JSONSerialization.data(withJSONObject: raw) else { continue }
            if let rule = try? decoder.decode(MerchantRule.self, from: data) {
                rules.append(rule)
            }
        }
        return rules
    }

    /// Toggle a rule on/off. Disabled rules stay in the table for
    /// audit; the autopilot's lookup ignores enabled=false rows.
    func setEnabled(_ id: UUID, enabled: Bool) async throws {
        struct Payload: Encodable { let enabled: Bool }
        try await supabaseService.databaseClient
            .from("merchant_rules")
            .update(Payload(enabled: enabled))
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Permanently delete a rule. Use when the user wants the system
    /// to start re-classifying that domain again from scratch.
    func deleteRule(_ id: UUID) async throws {
        try await supabaseService.databaseClient
            .from("merchant_rules")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }
}

struct MerchantRule: Identifiable, Codable, Sendable, Hashable {
    let id: UUID
    let userId: UUID
    let matchKind: String           // 'sender_email' | 'sender_domain' | 'normalized_merchant'
    let matchValue: String
    let action: String              // 'skip_purchase' | 'require_review'
    let source: String              // 'auto_promoted' | 'user_created'
    let promotedFromCorrectionCount: Int?
    let notes: String?
    let enabled: Bool
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case matchKind = "match_kind"
        case matchValue = "match_value"
        case action
        case source
        case promotedFromCorrectionCount = "promoted_from_correction_count"
        case notes
        case enabled
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Single-line label for the rule list.
    var displayMatch: String {
        switch matchKind {
        case "sender_email":        return matchValue
        case "sender_domain":       return "@\(matchValue)"
        case "normalized_merchant": return "Merchant: \(matchValue)"
        default:                    return matchValue
        }
    }

    /// Short verb describing what the rule does.
    var displayAction: String {
        switch action {
        case "skip_purchase":  return "Skip"
        case "require_review": return "Require review"
        default:               return action
        }
    }

    /// "Auto-learned" / "Manual" badge.
    var sourceLabel: String {
        source == "auto_promoted" ? "Auto-learned" : "Manual"
    }
}
