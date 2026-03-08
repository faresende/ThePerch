import SwiftUI
import WidgetKit

// MARK: - Shared Data Provider

private struct LockScreenEntry: TimelineEntry {
    let date: Date
    let nextEventTitle: String?
    let nextEventTime: String?
    let caloriesConsumed: Int?
    let caloriesTarget: Int?
}

private struct LockScreenProvider: TimelineProvider {
    private let sharedDefaults = UserDefaults(suiteName: "group.com.theperch.shared")

    func placeholder(in context: Context) -> LockScreenEntry {
        LockScreenEntry(
            date: .now,
            nextEventTitle: "Team Standup",
            nextEventTime: "10:00",
            caloriesConsumed: 1847,
            caloriesTarget: 3400
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (LockScreenEntry) -> Void) {
        completion(readEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LockScreenEntry>) -> Void) {
        let entry = readEntry()
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func readEntry() -> LockScreenEntry {
        let defaults = sharedDefaults
        return LockScreenEntry(
            date: .now,
            nextEventTitle: defaults?.string(forKey: "widget_next_event_title"),
            nextEventTime: defaults?.string(forKey: "widget_next_event_time"),
            caloriesConsumed: defaults?.object(forKey: "widget_calories_consumed") as? Int,
            caloriesTarget: defaults?.object(forKey: "widget_calories_target") as? Int
        )
    }
}

// MARK: - Rectangular Lock Screen Widget (Next Event + Calories)

struct PerchLockScreenRectangularWidget: Widget {
    let kind: String = "PerchLockScreenRectangular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenProvider()) { entry in
            PerchRectangularView(entry: entry)
        }
        .configurationDisplayName("Perch Glance")
        .description("Next event and calorie progress")
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct PerchRectangularView: View {
    let entry: LockScreenEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Line 1: Next event
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                if let title = entry.nextEventTitle, let time = entry.nextEventTime {
                    Text("\(title) \(time)")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text("No events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Line 2: Calories
            HStack(spacing: 4) {
                Image(systemName: "flame")
                    .font(.caption2)
                if let consumed = entry.caloriesConsumed, let target = entry.caloriesTarget, target > 0 {
                    Text("\(consumed)/\(target) cal")
                        .font(.caption.weight(.medium))
                } else {
                    Text("-- cal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .widgetURL(URL(string: "theperch://home"))
    }
}

// MARK: - Circular Lock Screen Widget (Calorie Ring)

struct PerchLockScreenCircularWidget: Widget {
    let kind: String = "PerchLockScreenCircular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LockScreenProvider()) { entry in
            PerchCircularView(entry: entry)
        }
        .configurationDisplayName("Calorie Ring")
        .description("Today's calorie progress")
        .supportedFamilies([.accessoryCircular])
    }
}

private struct PerchCircularView: View {
    let entry: LockScreenEntry

    private var progress: Double {
        guard let consumed = entry.caloriesConsumed,
              let target = entry.caloriesTarget,
              target > 0 else { return 0 }
        return min(Double(consumed) / Double(target), 1.0)
    }

    private var percentText: String {
        guard entry.caloriesConsumed != nil, entry.caloriesTarget != nil else { return "--" }
        return "\(Int(progress * 100))%"
    }

    var body: some View {
        Gauge(value: progress, in: 0...1) {
            Image(systemName: "flame")
        } currentValueLabel: {
            Text(percentText)
                .font(.system(.caption2, design: .rounded, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetURL(URL(string: "theperch://home"))
    }
}

// MARK: - Previews

#Preview("Rectangular", as: .accessoryRectangular) {
    PerchLockScreenRectangularWidget()
} timeline: {
    LockScreenEntry(date: .now, nextEventTitle: "Team Standup", nextEventTime: "10:00", caloriesConsumed: 1847, caloriesTarget: 3400)
}

#Preview("Circular", as: .accessoryCircular) {
    PerchLockScreenCircularWidget()
} timeline: {
    LockScreenEntry(date: .now, nextEventTitle: nil, nextEventTime: nil, caloriesConsumed: 1847, caloriesTarget: 3400)
}
