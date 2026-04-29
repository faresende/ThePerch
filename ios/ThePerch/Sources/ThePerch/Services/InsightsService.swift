import Foundation
import Supabase

// MARK: - File-scope formatters
//
// Insight rows mix two date shapes — full ISO 8601 with offset (for
// `timestamptz` columns) and bare `YYYY-MM-DD` (for the `valid_for_date`
// column). The default `.iso8601` strategy throws on the bare-date
// form, which killed the whole insight decode silently and left the
// Today tab stuck on the "BioChecha takes the morning…" empty state.
//
// `nonisolated(unsafe)` because Foundation's date formatters are
// thread-safe per Apple but not Sendable — and `dateDecodingStrategy =
// .custom { ... }` is a `@Sendable` closure that needs to capture them.
nonisolated(unsafe) private let insightISOFormatterFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
nonisolated(unsafe) private let insightISOFormatterPlain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()
nonisolated private let insightDateOnlyFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .iso8601)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0)
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

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
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let d = insightISOFormatterFractional.date(from: raw) { return d }
            if let d = insightISOFormatterPlain.date(from: raw) { return d }
            if let d = insightDateOnlyFormatter.date(from: raw) { return d }
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

    /// Fetch the BioChecha insight that best matches the current local
    /// time of day, falling back through earlier slots when the
    /// time-matched one hasn't been generated yet.
    ///
    /// Old behavior (`ORDER BY generated_at DESC LIMIT 1`) had a sharp
    /// edge: a slot that fired LATE (e.g. afternoon catchup writing at
    /// 14:00 before midday) would display all afternoon even though
    /// midday is the semantically-current slot at 13:00. And once
    /// evening's cron fired late or missed, the user got "stuck" on
    /// afternoon for the rest of the day.
    ///
    /// New selection rule, by current local hour:
    ///   00:00–06:59 → evening (+ fallbacks below)
    ///   07:00–11:59 → morning_post_wake → morning
    ///   12:00–14:59 → midday → morning_post_wake → morning
    ///   15:00–19:59 → afternoon → midday → morning_post_wake → morning
    ///   20:00–23:59 → evening → afternoon → midday → morning_post_wake → morning
    ///
    /// At any hour the legacy `daily_health` row is the last fallback
    /// before yesterday's evening (early-morning carry-over) and finally
    /// nil. `event_logistics` is event-fired and only surfaces when its
    /// `generated_at` is more recent than the time-matched slot's row
    /// — otherwise it sits behind the rotation.
    func fetchTodayDailyInsight() async throws -> Insight? {
        let today = ISO8601DateFormatter.dateOnly.string(from: .now)
        let yesterday = ISO8601DateFormatter.dateOnly.string(
            from: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
        )

        // Pull all of today's BioChecha rows + yesterday's evening as a
        // safety net for the 00:00–06:59 window. Keeps it to one round
        // trip via an `in` filter on valid_for_date.
        let result = try await supabaseService.databaseClient
            .from("insights")
            .select()
            .eq("agent_id", value: "biochecha")
            .in("valid_for_date", values: [today, yesterday])
            .order("generated_at", ascending: false)
            .execute()

        let allRows = try decoder.decode([Insight].self, from: result.data)
        let todayRows = allRows.filter { row in
            guard let v = row.validForDate else { return false }
            return ISO8601DateFormatter.dateOnly.string(from: v) == today
        }

        // Build the per-hour preference order. First match wins.
        let hour = Calendar.current.component(.hour, from: .now)
        let preference: [String]
        switch hour {
        case 20...23:
            preference = ["daily_health_evening", "daily_health_afternoon",
                          "daily_health_midday", "daily_health_morning_post_wake",
                          "daily_health_morning", "daily_health"]
        case 15..<20:
            preference = ["daily_health_afternoon", "daily_health_midday",
                          "daily_health_morning_post_wake", "daily_health_morning",
                          "daily_health"]
        case 12..<15:
            preference = ["daily_health_midday", "daily_health_morning_post_wake",
                          "daily_health_morning", "daily_health"]
        case 7..<12:
            preference = ["daily_health_morning_post_wake", "daily_health_morning",
                          "daily_health"]
        default: // 00:00–06:59
            preference = ["daily_health_evening", "daily_health_afternoon",
                          "daily_health_midday", "daily_health_morning_post_wake",
                          "daily_health_morning", "daily_health"]
        }

        for slot in preference {
            if let match = todayRows.first(where: { $0.insightType == slot }) {
                return match
            }
        }

        // Nothing for today matched. Last-mile fallback for the
        // 00:00–06:59 window: yesterday's evening (so the card isn't
        // empty during the overnight gap before today's morning fires).
        if hour < 7 {
            let ydayEvening = allRows
                .filter { row in
                    guard let v = row.validForDate else { return false }
                    return ISO8601DateFormatter.dateOnly.string(from: v) == yesterday
                        && row.insightType == "daily_health_evening"
                }
                .first
            if let ydayEvening { return ydayEvening }
        }
        return nil
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
