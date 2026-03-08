import Foundation
import Observation
import WidgetKit

// MARK: - HomeViewModel

/// Manages the state of the Home section (dashboard-of-dashboards).
/// Handles data loading, smart ordering, widget data sync, and Live Activity sync.
@Observable
@MainActor
final class HomeViewModel: SectionViewModelProtocol {
    // MARK: - Properties

    var records: [Record] = []
    var smartOrderedRecords: [Record] = []
    var isLoading: Bool = false
    var error: SupabaseServiceError?
    var loadError: String?

    // MARK: - Private Properties

    private let supabaseService: SupabaseService
    private let freshnessTracker = DataFreshnessTracker.shared

    // MARK: - Initialization

    init(supabaseService: SupabaseService = .shared) {
        self.supabaseService = supabaseService
    }

    // MARK: - Loading Data

    func loadRecords(forceRefresh: Bool = false) async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            records = try await supabaseService.fetchRecords(limit: 50, forceRefresh: forceRefresh)
            recomputeSmartOrder()
            updateWidgetData()
            await syncLiveActivities()
            self.error = nil
        } catch let err as SupabaseServiceError {
            error = err
            loadError = "Failed to load data"
        } catch {
            self.error = .unknownError(error.localizedDescription)
            loadError = "Failed to load data"
        }
    }

    func refresh() async {
        await loadRecords(forceRefresh: true)
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
}
