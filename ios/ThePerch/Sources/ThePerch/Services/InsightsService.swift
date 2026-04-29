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
        // Insight rows mix two date shapes:
        //   - timestamptz columns (generated_at, shown_at, etc.) →
        //     PostgREST returns ISO 8601 with time + offset.
        //   - `date` column (valid_for_date) → PostgREST returns
        //     bare "YYYY-MM-DD".
        // The .iso8601 strategy throws on the bare-date form, which
        // killed the whole insight decode silently and left the
        // Today tab stuck on the "BioChecha takes the morning…"
        // empty state. Custom strategy: try ISO 8601 first, fall
        // back to "yyyy-MM-dd" for the date-only column.
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFmtNoFrac = ISO8601DateFormatter()
        isoFmtNoFrac.formatOptions = [.withInternetDateTime]
        let dateOnly = DateFormatter()
        dateOnly.calendar = Calendar(identifier: .iso8601)
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
        dateOnly.dateFormat = "yyyy-MM-dd"
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let d = isoFmt.date(from: raw) { return d }
            if let d = isoFmtNoFrac.date(from: raw) { return d }
            if let d = dateOnly.date(from: raw) { return d }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(raw)"
            )
        }
        return dec
    }()

    init() {
        self.supabaseService = .shared
    }

    init(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
    }

    /// Fetch the most recent BioChecha insight valid for today, regardless
    /// of slot. With time-aware insights live, the latest of
    /// daily_health_morning/midday/afternoon/evening (or event_logistics)
    /// always wins — the iOS card simply shows the freshest take.
    /// Falls back to the legacy `daily_health` rows that pre-date the
    /// migration (the SQL rename should have caught these, but the OR
    /// keeps things working if a stray remains).
    /// Returns nil when no insight exists for today yet — expected in
    /// the early morning before BioChecha's 7am cron has run. Caller
    /// renders an empty state.
    func fetchTodayDailyInsight() async throws -> Insight? {
        let today = ISO8601DateFormatter.dateOnly.string(from: .now)
        let result = try await supabaseService.databaseClient
            .from("insights")
            .select()
            .eq("agent_id", value: "biochecha")
            .eq("valid_for_date", value: today)
            .order("generated_at", ascending: false)
            .limit(1)
            .execute()

        // Decode the array directly — was previously running every row
        // through JSONSerialization → JSONEncoder → JSONDecoder, which
        // is ~3× the JSON work per element. Direct decode skips all of
        // that and the response is small (limit 1) so we don't need
        // the per-row failable wrapper here.
        let items = try decoder.decode([Insight].self, from: result.data)
        return items.first
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

        // Permissive decode: a single malformed insight should not
        // black-hole the whole list. FailableDecodable absorbs per-row
        // failures without the JSONSerialization round-trip the older
        // version did per row.
        let wrapped = try decoder.decode([FailableDecodable<Insight>].self, from: result.data)
        return wrapped.compactMap { entry in
#if DEBUG
            if case .failure(let err) = entry.result {
                print("[InsightsService] Dropping malformed insight: \(err)")
            }
#endif
            return entry.value
        }
    }

    /// Mark an insight as shown to the user (sets shown_at = now()
    /// if it's currently null). Best-effort; failures don't break
    /// anything — analytics field, not load-bearing for the UI.
    func markShown(_ insight: Insight) async {
        guard insight.shownAt == nil else { return }
        struct ShownPayload: Encodable { let shown_at: String }
        let now = PerchFormatters.iso8601.string(from: .now)
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
