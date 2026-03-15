import Foundation
import Observation
import WidgetKit

// MARK: - HomeViewModel

/// Manages the state of the Home section (dashboard-of-dashboards).
/// Reads records from DashboardViewModel (single-fetch), handles
/// widget data sync, Quick Glance data, and Live Activity sync.
@Observable
@MainActor
final class HomeViewModel {
    // MARK: - Properties

    var records: [Record] = []
    var loadError: String?

    // MARK: - Updating Data (fed from DashboardViewModel)

    /// Called when DashboardViewModel.allRecords changes.
    /// Updates widget data and syncs live activities.
    func updateRecords(_ newRecords: [Record]) {
        guard newRecords != records else { return }
        records = newRecords
        updateWidgetData()
        Task { [weak self] in await self?.syncLiveActivities() }
    }

    // MARK: - Quick Glance Data

    var caloriesPercentText: String {
        guard let record = todaysCaloriesRecord,
              let m = record.asMeasurement(),
              let target = m.target, target > 0 else {
            // After 2am with no data: show 0%, not --%
            let hour = Calendar.current.component(.hour, from: .now)
            return hour >= 2 ? "0%" : "--%"
        }
        let pct = Int(min(m.value / target, 1.5) * 100)
        return "\(pct)%"
    }

    var caloriesColor: String {
        guard let record = todaysCaloriesRecord,
              let m = record.asMeasurement(),
              let target = m.target, target > 0 else {
            let hour = Calendar.current.component(.hour, from: .now)
            return hour >= 2 ? "accent" : "tertiary"
        }
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

    // MARK: - Calories Record

    /// Calories display logic:
    /// - Before 2am: show today's data if any, otherwise yesterday's final tally
    /// - After 2am: show today's data if any, otherwise treat as 0 (new day, fresh start)
    ///
    /// Returns a sentinel record with value=0 after 2am when no today data exists,
    /// so the UI shows "0%" instead of "--%" .
    var todaysCaloriesRecord: Record? {
        let caloriesRecords = records.filter { $0.asMeasurement()?.metric == "daily_calories" }
        let hour = Calendar.current.component(.hour, from: .now)
        let isLateNight = hour < 2
        let todayString = PerchFormatters.isoDate.string(from: .now)
        let yesterdayString = PerchFormatters.isoDate.string(from: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)

        // Always check today first
        let todayRecords = caloriesRecords
            .filter { $0.asMeasurement()?.context == todayString }
            .sorted { $0.createdAt > $1.createdAt }
        if let todayRecord = todayRecords.first {
            return todayRecord
        }

        // Fall back to today by timestamp
        let todayByTimestamp = caloriesRecords
            .compactMap { r -> (Record, Date)? in
                guard let m = r.asMeasurement(), let ts = m.timestamp else { return nil }
                return Calendar.current.isDateInToday(ts) ? (r, ts) : nil
            }
            .sorted { $0.1 > $1.1 }
            .first?.0
        if let match = todayByTimestamp { return match }

        // No today data: before 2am show yesterday, after 2am show nothing (0%)
        if isLateNight {
            if let yesterdayRecord = caloriesRecords.first(where: { $0.asMeasurement()?.context == yesterdayString }) {
                return yesterdayRecord
            }
        }

        return nil
    }

    /// Whether the displayed calories are from yesterday (for UI labeling).
    var isShowingYesterdayCalories: Bool {
        guard let record = todaysCaloriesRecord,
              let m = record.asMeasurement(),
              let ctx = m.context else { return false }
        let todayString = PerchFormatters.isoDate.string(from: .now)
        return ctx != todayString
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

        // Existing quick glance data
        defaults.set(caloriesPercentText, forKey: "widget_calories_percent")

        // New: calories consumed + target for lock screen widgets
        if let record = todaysCaloriesRecord,
           let m = record.asMeasurement() {
            defaults.set(Int(m.value), forKey: "widget_calories_consumed")
            defaults.set(Int(m.target ?? 0), forKey: "widget_calories_target")
        } else {
            defaults.removeObject(forKey: "widget_calories_consumed")
            defaults.removeObject(forKey: "widget_calories_target")
        }

        // Next event data
        let futureEvents = records.compactMap { record -> EventData? in
            guard let event = record.asEvent(), event.start > .now else { return nil }
            return event
        }.sorted { $0.start < $1.start }

        if let next = futureEvents.first {
            defaults.set("\(next.title) \(PerchFormatters.time24h.string(from: next.start))", forKey: "widget_next_event")
            // New: separate title and time for lock screen widget
            defaults.set(next.title, forKey: "widget_next_event_title")
            defaults.set(PerchFormatters.time24h.string(from: next.start), forKey: "widget_next_event_time")
        } else {
            defaults.set("No events", forKey: "widget_next_event")
            defaults.removeObject(forKey: "widget_next_event_title")
            defaults.removeObject(forKey: "widget_next_event_time")
        }

        defaults.set(activeDeliveryCount, forKey: "widget_active_deliveries")
        defaults.set(Date.now, forKey: "widget_last_updated")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Travel Timezone

    private var relevantTravelTrip: TripData? {
        let tripRecords = records.compactMap { r -> TripData? in r.asTrip() }
            .sorted { ($0.startDateParsed ?? .distantFuture) < ($1.startDateParsed ?? .distantFuture) }

        if let activeTrip = tripRecords.first(where: { $0.status == "active" }) {
            return activeTrip
        }

        return tripRecords.first { $0.status == "upcoming" && ($0.daysUntilStart ?? 99) <= 7 }
    }

    /// Returns dual clock info when an active/upcoming trip has a different timezone.
    /// Nil when no trip or same timezone.
    var dualClockInfo: (homeTz: String, destTz: String, homeLabel: String, destLabel: String)? {
        guard let trip = relevantTravelTrip else { return nil }

        guard let originTz = trip.originTz,
              let destTz = trip.destinationTz,
              originTz != destTz else { return nil }

        let originCity = trip.origin ?? originTz.components(separatedBy: "/").last ?? "Home"
        let destCity = trip.destination

        return (homeTz: originTz, destTz: destTz, homeLabel: originCity, destLabel: destCity)
    }

    var travelQuickGlanceText: String? {
        if let trip = relevantTravelTrip, trip.status == "active" {
            if let day = trip.currentTripDay {
                return "📍 \(trip.destination) Day \(day)"
            }
            return "📍 \(trip.destination)"
        }

        if let trip = relevantTravelTrip, trip.status == "upcoming", let days = trip.daysUntilStart {
            return "✈️ \(trip.destination) in \(days)d"
        }

        return nil
    }

    // MARK: - Cross-Domain Travel Alerts

    /// Deliveries that will arrive during an active trip (when no one's home).
    var deliveriesWhileAway: [(Record, DeliveryData)] {
        guard let trip = records.compactMap({ $0.asTrip() }).first(where: { $0.status == "active" || $0.status == "upcoming" }),
              let start = trip.startDateParsed,
              let end = trip.endDateParsed else { return [] }

        return records.compactMap { record -> (Record, DeliveryData)? in
            guard let d = record.asDelivery() else { return nil }
            let status = d.status.lowercased().replacingOccurrences(of: " ", with: "_")
            guard status != "delivered" && status != "cancelled" else { return nil }
            // Check if ETA falls during trip
            if let eta = d.eta, eta >= start && eta <= end {
                return (record, d)
            }
            return nil
        }
    }
}
