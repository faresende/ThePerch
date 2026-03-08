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
