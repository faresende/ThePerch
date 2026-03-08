import Foundation
import Observation
import WidgetKit

// MARK: - HomeViewModel

/// Manages the state of the Home section (dashboard-of-dashboards).
/// Reads records from DashboardViewModel (single-fetch), handles smart ordering,
/// widget data sync, and Live Activity sync.
@Observable
@MainActor
final class HomeViewModel {
    // MARK: - Properties

    var records: [Record] = []
    var smartOrderedRecords: [Record] = []
    var dailyBriefData: DailyBriefData?
    var loadError: String?

    // MARK: - Updating Data (fed from DashboardViewModel)

    /// Called when DashboardViewModel.allRecords changes.
    /// Recomputes smart order, daily brief, widget data, and syncs live activities.
    func updateRecords(_ newRecords: [Record]) {
        guard newRecords != records else { return }
        records = newRecords
        recomputeSmartOrder()
        recomputeDailyBrief()
        updateWidgetData()
        Task { await syncLiveActivities() }
    }

    // MARK: - Quick Glance Data

    var caloriesPercentText: String {
        guard let record = todaysCaloriesRecord,
              let m = record.asMeasurement(),
              let target = m.target, target > 0 else { return "--%" }
        let pct = Int(min(m.value / target, 1.5) * 100)
        return "\(pct)%"
    }

    var caloriesColor: String {
        guard let record = todaysCaloriesRecord,
              let m = record.asMeasurement(),
              let target = m.target, target > 0 else { return "tertiary" }
        let ratio = m.value / target
        if ratio > 1.1 { return "error" }
        if ratio > 0.9 { return "success" }
        return "accent"
    }

    var nextEventTimeText: String {
        let futureEvents = records.compactMap { record -> (Record, EventData)? in
            guard let event = record.asEvent(), event.start > Date.now else { return nil }
            return (record, event)
        }.sorted { $0.1.start < $1.1.start }

        guard let next = futureEvents.first else { return "None" }
        let interval = next.1.start.timeIntervalSince(Date.now)
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        if hours > 0 {
            return "\(hours)h \(minutes % 60)m"
        }
        return "\(minutes)m"
    }

    var activeDeliveryCount: Int {
        records.filter {
            guard let d = $0.asDelivery() else { return false }
            let s = d.status.lowercased()
            return s != "delivered" && s != "cancelled"
        }.count
    }

    // MARK: - Smart Ordering

    /// Current time-of-day period for predictive content ordering.
    private enum TimePeriod {
        case morning, midday, evening, night

        static var current: TimePeriod {
            let hour = Calendar.current.component(.hour, from: Date.now)
            switch hour {
            case 6..<10: return .morning
            case 10..<16: return .midday
            case 16..<22: return .evening
            default: return .night
            }
        }
    }

    /// Recalculates smartOrderedRecords from the current records array.
    /// Called once after records change, not on every SwiftUI body evaluation.
    private func recomputeSmartOrder() {
        var ordered: [Record] = []
        var usedIds = Set<UUID>()

        func addUnique(_ record: Record) {
            guard !usedIds.contains(record.id) else { return }
            usedIds.insert(record.id)
            ordered.append(record)
        }

        func addUniqueAll(_ records: [Record]) {
            for r in records { addUnique(r) }
        }

        let period = TimePeriod.current

        // === Always-urgent: out-for-delivery ===
        let outForDelivery = records.filter {
            guard let d = $0.asDelivery() else { return false }
            return d.status.lowercased().replacingOccurrences(of: " ", with: "_") == "out_for_delivery"
        }
        addUniqueAll(outForDelivery)

        // === Always-urgent: calendar events within 2 hours ===
        let twoHoursFromNow = Date.now.addingTimeInterval(2 * 3600)
        let imminentEvents = records.filter {
            guard let e = $0.asEvent() else { return false }
            return e.start > Date.now && e.start <= twoHoursFromNow
        }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
        addUniqueAll(imminentEvents)

        // === Time-of-day boosted content ===
        switch period {
        case .morning:
            let sleepRecords = records.filter {
                guard let m = $0.asMeasurement() else { return false }
                return m.metric.contains("sleep") || m.metric.contains("resting")
            }
            addUniqueAll(sleepRecords)

            let todayEvents = records.filter {
                guard let e = $0.asEvent() else { return false }
                return Calendar.current.isDateInToday(e.start) && e.start > Date.now
            }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
            addUniqueAll(todayEvents)

        case .midday:
            let activeDeliveries = records.filter {
                guard let d = $0.asDelivery() else { return false }
                let s = d.status.lowercased()
                return s != "delivered" && s != "cancelled"
            }
            addUniqueAll(activeDeliveries)

            let todayEvents = records.filter {
                guard let e = $0.asEvent() else { return false }
                return e.start > Date.now && Calendar.current.isDateInToday(e.start)
            }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
            addUniqueAll(todayEvents)

        case .evening:
            if let caloriesRecord = todaysCaloriesRecord {
                addUnique(caloriesRecord)
            }
            let macrosRecords = records.filter { $0.displayHint == .macrosBar }
            addUniqueAll(macrosRecords)

            let tomorrowEvents = records.filter {
                guard let e = $0.asEvent() else { return false }
                return Calendar.current.isDateInTomorrow(e.start)
            }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
            addUniqueAll(tomorrowEvents)

        case .night:
            let healthRecords = records.filter {
                guard let m = $0.asMeasurement() else { return false }
                return m.metric.contains("sleep") || m.metric.contains("heart") || m.metric.contains("resting")
            }
            addUniqueAll(healthRecords)

            let tomorrowEvents = records.filter {
                guard let e = $0.asEvent() else { return false }
                return Calendar.current.isDateInTomorrow(e.start)
            }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
            addUniqueAll(Array(tomorrowEvents.prefix(2)))
        }

        // === Standard priority items ===
        if let caloriesRecord = todaysCaloriesRecord,
           let m = caloriesRecord.asMeasurement(),
           let target = m.target, target > 0, m.value > target * 1.1 {
            addUnique(caloriesRecord)
        }

        let otherActiveDeliveries = records.filter {
            guard let d = $0.asDelivery() else { return false }
            let s = d.status.lowercased()
            return s != "delivered" && s != "cancelled"
        }
        addUniqueAll(otherActiveDeliveries)

        if let caloriesRecord = todaysCaloriesRecord {
            addUnique(caloriesRecord)
        }

        let upcomingEvents = records.filter {
            guard let e = $0.asEvent() else { return false }
            return e.start > twoHoursFromNow
        }.sorted { ($0.asEvent()?.start ?? .distantFuture) < ($1.asEvent()?.start ?? .distantFuture) }
        addUniqueAll(Array(upcomingEvents.prefix(3)))

        if let bookmark = records.first(where: { $0.type == .bookmark }) {
            addUnique(bookmark)
        }
        if let checklist = records.first(where: { $0.type == .checklist }) {
            addUnique(checklist)
        }
        if let cost = records.first(where: { $0.type == .costSummary }) {
            addUnique(cost)
        }

        smartOrderedRecords = ordered
    }

    // MARK: - Calories Record

    var todaysCaloriesRecord: Record? {
        let caloriesRecords = records.filter { $0.asMeasurement()?.metric == "daily_calories" }
        let todayString = PerchFormatters.isoDate.string(from: Date.now)
        if let today = caloriesRecords.first(where: { $0.asMeasurement()?.context == todayString }) {
            return today
        }
        return caloriesRecords.sorted {
            let d0 = $0.asMeasurement()?.timestamp ?? $0.createdAt
            let d1 = $1.asMeasurement()?.timestamp ?? $1.createdAt
            return d0 > d1
        }.first
    }

    // MARK: - Card Prominence

    func prominence(for record: Record) -> CardProminence {
        if let d = record.asDelivery() {
            let s = d.status.lowercased().replacingOccurrences(of: " ", with: "_")
            if s == "out_for_delivery" { return .featured }
            if s == "delivered" || s == "cancelled" { return .muted }
        }
        if let e = record.asEvent() {
            let twoHours = Date.now.addingTimeInterval(2 * 3600)
            if e.start > Date.now && e.start <= twoHours { return .featured }
            if e.end < Date.now { return .muted }
        }
        if record.isExpired { return .muted }
        if let _ = record.asBookmark() {
            let age = Date.now.timeIntervalSince(record.createdAt)
            if age > 7 * 86400 { return .muted }
        }
        return .standard
    }

    // MARK: - Live Activity Sync

    private func syncLiveActivities() async {
        let activeDeliveries = records.compactMap { record -> DeliveryData? in
            guard let d = record.asDelivery() else { return nil }
            let s = d.status.lowercased().replacingOccurrences(of: " ", with: "_")
            guard s == "in_transit" || s == "shipped" || s == "out_for_delivery" || s == "processing" || s == "ordered" else { return nil }
            return d
        }
        await DeliveryLiveActivityManager.shared.sync(activeDeliveries: activeDeliveries)
    }

    // MARK: - Widget Data

    func updateWidgetData() {
        guard let defaults = UserDefaults(suiteName: "group.com.theperch.shared") else { return }

        defaults.set(caloriesPercentText, forKey: "widget_calories_percent")

        let futureEvents = records.compactMap { record -> EventData? in
            guard let event = record.asEvent(), event.start > .now else { return nil }
            return event
        }.sorted { $0.start < $1.start }

        if let next = futureEvents.first {
            defaults.set("\(next.title) \(PerchFormatters.time24h.string(from: next.start))", forKey: "widget_next_event")
        } else {
            defaults.set("No events", forKey: "widget_next_event")
        }

        defaults.set(activeDeliveryCount, forKey: "widget_active_deliveries")
        defaults.set(Date.now, forKey: "widget_last_updated")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Daily Brief Pre-computation

    private func recomputeDailyBrief() {
        dailyBriefData = DailyBriefData(
            sleepSummary: computeSleepSummary(),
            calendarSummary: computeCalendarSummary(),
            deliverySummary: computeDeliverySummary(),
            nutritionYesterday: computeNutritionSummary(forYesterday: true),
            nutritionToday: computeNutritionSummary(forYesterday: false),
            tomorrowPreview: computeTomorrowPreview()
        )
    }

    private func computeSleepSummary() -> DailyBriefData.SleepSummary? {
        let healthRecords = records.filter { $0.category == .health }

        let sleepDuration = healthRecords
            .compactMap { $0.asMeasurement() }
            .filter { $0.metric == "sleep_duration" }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            .first

        guard let sleepDuration else { return nil }

        let deepSleep = healthRecords
            .compactMap { $0.asMeasurement() }
            .filter { $0.metric == "deep_sleep" }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            .first

        let hrv = healthRecords
            .compactMap { $0.asMeasurement() }
            .filter { $0.metric == "avg_sleep_hrv" }
            .sorted { ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast) }
            .first

        let durationStr = DailyBriefData.formatHours(sleepDuration.value)
        let deepStr = deepSleep.map { DailyBriefData.formatHours($0.value) }
        let hrvStr = hrv.map { "\(Int($0.value))" }

        return DailyBriefData.SleepSummary(duration: durationStr, deepSleep: deepStr, hrv: hrvStr)
    }

    private func computeCalendarSummary() -> DailyBriefData.CalendarSummary? {
        let todayEvents = records.compactMap { record -> EventData? in
            guard let event = record.asEvent(),
                  Calendar.current.isDateInToday(event.start),
                  event.start > .now else { return nil }
            return event
        }.sorted { $0.start < $1.start }

        let firstEvent = todayEvents.first.map { event in
            (time: PerchFormatters.time24h.string(from: event.start), title: event.title)
        }

        return DailyBriefData.CalendarSummary(eventCount: todayEvents.count, firstEventTime: firstEvent?.time, firstEventTitle: firstEvent?.title)
    }

    private func computeDeliverySummary() -> DailyBriefData.DeliverySummary? {
        let activeDeliveries = records.compactMap { $0.asDelivery() }
            .filter {
                let s = $0.status.lowercased()
                return s != "delivered" && s != "cancelled"
            }

        let ofd = activeDeliveries.filter {
            $0.status.lowercased().replacingOccurrences(of: " ", with: "_") == "out_for_delivery"
        }.count

        return DailyBriefData.DeliverySummary(total: activeDeliveries.count, outForDelivery: ofd)
    }

    private func computeNutritionSummary(forYesterday: Bool) -> DailyBriefData.NutritionSummary? {
        let dateString: String = {
            if forYesterday {
                return PerchFormatters.isoDate.string(from: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
            }
            return PerchFormatters.isoDate.string(from: .now)
        }()

        let caloriesRecord = records
            .filter { $0.asMeasurement()?.metric == "daily_calories" }
            .first { $0.asMeasurement()?.context == dateString }
            ?? (forYesterday ? nil : records
                .filter { $0.asMeasurement()?.metric == "daily_calories" }
                .sorted { ($0.asMeasurement()?.timestamp ?? $0.createdAt) > ($1.asMeasurement()?.timestamp ?? $1.createdAt) }
                .first)

        let macrosRecord = records
            .filter { $0.asMacros() != nil }
            .first { $0.asMacros()?.date == dateString }

        guard caloriesRecord != nil || macrosRecord != nil else { return nil }

        var caloriePercent: Int?
        var consumed: Double?
        var target: Double?
        if let m = caloriesRecord?.asMeasurement() {
            consumed = m.value
            target = m.target
            if let t = m.target, t > 0 {
                caloriePercent = Int(m.value / t * 100)
            }
        }

        var proteinStatus: String?
        if let macros = macrosRecord?.asMacros() {
            if let pt = macros.proteinTarget, pt > 0 {
                let pct = Int(macros.protein / pt * 100)
                proteinStatus = "\(pct)%"
            } else {
                proteinStatus = "\(Int(macros.protein))g"
            }
        }

        return DailyBriefData.NutritionSummary(
            caloriePercent: caloriePercent,
            caloriesConsumed: consumed,
            caloriesTarget: target,
            proteinStatus: proteinStatus
        )
    }

    private func computeTomorrowPreview() -> DailyBriefData.CalendarSummary? {
        let tomorrowEvents = records.compactMap { record -> EventData? in
            guard let event = record.asEvent(),
                  Calendar.current.isDateInTomorrow(event.start) else { return nil }
            return event
        }.sorted { $0.start < $1.start }

        let firstEvent = tomorrowEvents.first.map { event in
            (time: PerchFormatters.time24h.string(from: event.start), title: event.title)
        }

        return DailyBriefData.CalendarSummary(eventCount: tomorrowEvents.count, firstEventTime: firstEvent?.time, firstEventTitle: firstEvent?.title)
    }
}

// MARK: - DailyBriefData

/// Pre-computed data for the daily brief card, computed once when records change.
struct DailyBriefData {
    let sleepSummary: SleepSummary?
    let calendarSummary: CalendarSummary?
    let deliverySummary: DeliverySummary?
    let nutritionYesterday: NutritionSummary?
    let nutritionToday: NutritionSummary?
    let tomorrowPreview: CalendarSummary?

    struct SleepSummary {
        let duration: String
        let deepSleep: String?
        let hrv: String?
    }

    struct CalendarSummary {
        let eventCount: Int
        let firstEventTime: String?
        let firstEventTitle: String?
    }

    struct DeliverySummary {
        let total: Int
        let outForDelivery: Int
    }

    struct NutritionSummary {
        let caloriePercent: Int?
        let caloriesConsumed: Double?
        let caloriesTarget: Double?
        let proteinStatus: String?
    }

    static func formatHours(_ value: Double) -> String {
        let hours = Int(value)
        let minutes = Int((value - Double(hours)) * 60)
        if minutes == 0 { return "\(hours)h" }
        return "\(hours)h\(minutes)m"
    }
}
