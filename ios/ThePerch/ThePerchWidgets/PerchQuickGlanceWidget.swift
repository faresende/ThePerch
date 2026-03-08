import WidgetKit
import SwiftUI

struct PerchQuickGlanceEntry: TimelineEntry {
    let date: Date
    let caloriesPercent: String
    let nextEvent: String
    let activeDeliveries: Int
    let lastUpdated: Date?
}

struct PerchQuickGlanceProvider: TimelineProvider {
    private let sharedDefaults = UserDefaults(suiteName: "group.com.theperch.shared")

    func placeholder(in context: Context) -> PerchQuickGlanceEntry {
        PerchQuickGlanceEntry(
            date: .now,
            caloriesPercent: "62%",
            nextEvent: "Team Standup 10:00",
            activeDeliveries: 1,
            lastUpdated: .now
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PerchQuickGlanceEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PerchQuickGlanceEntry>) -> Void) {
        let entry = readEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func readEntry() -> PerchQuickGlanceEntry {
        let defaults = sharedDefaults
        return PerchQuickGlanceEntry(
            date: .now,
            caloriesPercent: defaults?.string(forKey: "widget_calories_percent") ?? "--%",
            nextEvent: defaults?.string(forKey: "widget_next_event") ?? "No events",
            activeDeliveries: defaults?.integer(forKey: "widget_active_deliveries") ?? 0,
            lastUpdated: defaults?.object(forKey: "widget_last_updated") as? Date
        )
    }
}

struct PerchQuickGlanceWidget: Widget {
    let kind: String = "PerchQuickGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PerchQuickGlanceProvider()) { entry in
            PerchQuickGlanceWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Glance")
        .description("A compact snapshot of your day")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct PerchQuickGlanceWidgetView: View {
    let entry: PerchQuickGlanceEntry

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07)

            VStack(alignment: .leading, spacing: 10) {
                Text("The Perch")
                    .font(.headline)
                    .foregroundStyle(.white)

                VStack(alignment: .leading, spacing: 6) {
                    Row(label: "Calories", value: entry.caloriesPercent)
                    Row(label: "Next", value: entry.nextEvent)
                    Row(label: "Deliveries", value: "\(entry.activeDeliveries)")
                }

                Spacer(minLength: 0)

                Text(updatedAgoText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(14)
        }
    }

    private var updatedAgoText: String {
        guard let lastUpdated = entry.lastUpdated else { return "Not yet updated" }
        let interval = Date.now.timeIntervalSince(lastUpdated)
        let minutes = Int(interval / 60)
        if minutes < 1 { return "Updated just now" }
        if minutes < 60 { return "Updated \(minutes)m ago" }
        let hours = minutes / 60
        return "Updated \(hours)h ago"
    }

    private struct Row: View {
        let label: String
        let value: String

        var body: some View {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 8)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
    }
}

#Preview(as: .systemSmall) {
    PerchQuickGlanceWidget()
} timeline: {
    PerchQuickGlanceEntry(date: .now, caloriesPercent: "62%", nextEvent: "Team Standup 10:00", activeDeliveries: 1, lastUpdated: .now)
}
