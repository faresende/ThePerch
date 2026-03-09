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

    // MARK: - Calories Record

    /// Before 14:00 shows yesterday's final tally; after 14:00 shows today's live data.
    /// Returns nil (--%) when no matching record exists, instead of falling back to stale data.
    var todaysCaloriesRecord: Record? {
        let caloriesRecords = records.filter { $0.asMeasurement()?.metric == "daily_calories" }
        let isMorning = Calendar.current.component(.hour, from: .now) < 14
        let targetDate: Date = isMorning
            ? Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
            : .now
        let dateString = PerchFormatters.isoDate.string(from: targetDate)

        // Try exact date match
        if let match = caloriesRecords.first(where: { $0.asMeasurement()?.context == dateString }) {
            return match
        }

        // For afternoon (today), fall back to most recent today-only record
        if !isMorning {
            return caloriesRecords
                .compactMap { r -> (Record, Date)? in
                    guard let m = r.asMeasurement(), let ts = m.timestamp else { return nil }
                    return Calendar.current.isDateInToday(ts) ? (r, ts) : nil
                }
                .sorted { $0.1 > $1.1 }
                .first?.0
        }

        return nil
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

}
