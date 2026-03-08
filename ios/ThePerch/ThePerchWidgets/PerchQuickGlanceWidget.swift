import WidgetKit
import SwiftUI

struct PerchQuickGlanceEntry: TimelineEntry {
    let date: Date
    let caloriesPercent: String
    let nextEvent: String
    let activeDeliveries: Int
}

struct PerchQuickGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> PerchQuickGlanceEntry {
        PerchQuickGlanceEntry(
            date: .now,
            caloriesPercent: "62%",
            nextEvent: "11:30",
            activeDeliveries: 1
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (PerchQuickGlanceEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PerchQuickGlanceEntry>) -> Void) {
        // v1: static timeline. Next iteration can read from an App Group or network.
        let entry = PerchQuickGlanceEntry(
            date: .now,
            caloriesPercent: "--%",
            nextEvent: "None",
            activeDeliveries: 0
        )

        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
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

                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(14)
        }
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
    PerchQuickGlanceEntry(date: .now, caloriesPercent: "62%", nextEvent: "11:30", activeDeliveries: 1)
}
