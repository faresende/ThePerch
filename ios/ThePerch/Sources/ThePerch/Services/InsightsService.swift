import Foundation
import Supabase

/// Service for reading agent-generated insights from `public.insights`.
/// Writes happen server-side (via the Python BioChecha agent + others);
/// iOS is read-only for now. Surfaces a couple of focused queries the
/// UI needs (today's daily insight, recent insights of a specific kind).
@MainActor
final class InsightsService {
    static let shared = InsightsService()

    private let supabaseService: SupabaseService
    private let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    init() {
        self.supabaseService = .shared
    }

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
    }

    /// Fetch the most recent `daily_health` insight whose
    /// `valid_for_date` is today (or null — backwards-compat for early
    /// rows). Returns nil when no insight exists for today yet —
    /// expected in the early morning before BioChecha's 7am cron has
    /// run. Caller renders an empty state.
    func fetchTodayDailyInsight() async throws -> Insight? {
        let today = ISO8601DateFormatter.dateOnly.string(from: .now)
        let result = try await supabaseService.databaseClient
            .from("insights")
            .select()
            .eq("insight_type", value: "daily_health")
            .or("valid_for_date.eq.\(today),valid_for_date.is.null")
            .order("generated_at", ascending: false)
            .limit(1)
            .execute()

        let rawArray = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] ?? []
        guard let item = rawArray.first else { return nil }
        let data = try JSONSerialization.data(withJSONObject: item)
        return try decoder.decode(Insight.self, from: data)
    }

    /// Fetch recent insights of any type for the user, newest first.
    /// Powers the future "all insights" list UI; not used yet on
    /// Today-tab v1 but ships the read-side now to avoid double work.
    func fetchRecentInsights(limit: Int = 50) async throws -> [Insight] {
        let result = try await supabaseService.databaseClient
            .from("insights")
            .select()
            .order("generated_at", ascending: false)
            .limit(limit)
            .execute()

        let rawArray = try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]] ?? []
        var items: [Insight] = []
        items.reserveCapacity(rawArray.count)
        for item in rawArray {
            do {
                let data = try JSONSerialization.data(withJSONObject: item)
                items.append(try decoder.decode(Insight.self, from: data))
            } catch {
#if DEBUG
                print("[InsightsService] Dropping malformed insight: \(error)")
#endif
            }
        }
        return items
    }

    /// Mark an insight as shown to the user (sets shown_at = now()
    /// if it's currently null). Best-effort; failures don't break
    /// anything — analytics field, not load-bearing for the UI.
    func markShown(_ insight: Insight) async {
        guard insight.shownAt == nil else { return }
        struct ShownPayload: Encodable { let shown_at: String }
        let now = ISO8601DateFormatter().string(from: .now)
        do {
            try await supabaseService.databaseClient
                .from("insights")
                .update(ShownPayload(shown_at: now))
                .eq("id", value: insight.id.uuidString)
                .execute()
        } catch {
#if DEBUG
            print("[InsightsService] markShown failed: \(error)")
#endif
        }
    }
}

private extension ISO8601DateFormatter {
    /// `YYYY-MM-DD` formatter for the `valid_for_date` column query.
    /// PostgREST accepts the ISO short-form date string when the
    /// column type is `date`.
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
