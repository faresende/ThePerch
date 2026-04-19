import Combine
import SwiftUI

/// Shows today's events with time-relative labels ("in 45 min", "now", "2h ago").
/// Filters EventData where start date is today.
struct CalendarTodayCard: View {
    let records: [Record]

    static func pastRelativeLabel(minutesAgo: Int) -> String {
        if minutesAgo < 60 {
            return "\(minutesAgo)m ago"
        }
        return "done"
    }

    @State private var now = Date.now
    @AppStorage("card_compact_calendar") private var isCompact = false

    private var todayEvents: [(record: Record, event: EventData)] {
        records.compactMap { record -> (Record, EventData)? in
            guard record.category == .calendar,
                  record.type == .event,
                  let event = record.asEvent(),
                  Calendar.current.isDateInToday(event.start) else { return nil }
            return (record, event)
        }.sorted { $0.1.start < $1.1.start }
    }

    private var upcomingEvents: [(record: Record, event: EventData)] {
        todayEvents.filter { $0.event.end >= now }
    }

    private var pastEvents: [(record: Record, event: EventData)] {
        todayEvents.filter { $0.event.end < now }
    }

    /// Compact summary for calendar card
    private var compactSummary: String {
        let upcoming = upcomingEvents
        if upcoming.isEmpty { return "\(todayEvents.count) events — all done" }
        let next = upcoming.first!.event
        return "\(upcoming.count) upcoming · Next: \(next.title) \(relativeTimeLabel(for: next))"
    }

    /// Rotating interpretive phrase for the day — "A breezy one", "Full plate",
    /// etc. Keyed to today's date + event count so it stays stable for the
    /// whole day but rotates across the library day-over-day.
    private var calendarPhrase: String {
        PerchPhrase.calendarPhrase(eventCount: todayEvents.count)
    }

    @Environment(\.perchPalette) private var palette

    var body: some View {
        TodayCard {
            VStack(alignment: .leading, spacing: 0) {
                TodayEyebrow(label: "TODAY · \(todayDateString)", accent: palette.wellness, freshness: "LIVE")
                TodayPhrase(text: calendarPhrase)

                if todayEvents.isEmpty {
                    emptyStateIllustration
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(upcomingEvents.prefix(5).enumerated()), id: \.element.record.id) { index, item in
                            eventRow(event: item.event, isNext: index == 0)
                        }

                        if !pastEvents.isEmpty && !upcomingEvents.isEmpty {
                            Rectangle()
                                .fill(palette.line)
                                .frame(height: 1)
                                .padding(.vertical, 2)
                        }

                        ForEach(Array(pastEvents.suffix(2).enumerated()), id: \.element.record.id) { _, item in
                            pastEventRow(event: item.event)
                        }

                        if upcomingEvents.count > 5 {
                            Text("View all \(todayEvents.count) events")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(palette.kinetic)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            now = Date.now
        }
    }

    /// "TUE, 7 APR" — card eyebrow suffix.
    private var todayDateString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEE, d MMM"
        return f.string(from: Date.now).uppercased()
    }

    @ViewBuilder
    private var emptyStateIllustration: some View {
        HStack {
            Spacer()
            Image("empty-calendar")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 130)
                .accessibilityLabel("No events today")
            Spacer()
        }
    }

    // MARK: - Event Rows (Linen spec)
    //
    // Row grid: [time 56pt fixed] [title + where] [chip]
    // Chips:
    //   - Now  → white on wellness
    //   - Soon → kinetic on chipBg (relative time, e.g. "in 2h")
    //   - Done → faint, transparent
    // Done rows render at 0.5 opacity with strikethrough.

    private func eventRow(event: EventData, isNext: Bool) -> some View {
        let isHappening = event.start <= now && event.end > now
        let isFuture = event.start > now

        return HStack(alignment: .top, spacing: 10) {
            Text(PerchFormatters.time24h.string(from: event.start))
                .font(PerchTheme.Font.rowNumeric)
                .tracking(0.2)
                .foregroundColor(palette.muted)
                .frame(width: 56, alignment: .leading)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(palette.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHappening {
                TodayChip(text: "Now", color: .white, background: palette.wellness)
            } else if isFuture {
                TodayChip(
                    text: relativeTimeLabel(for: event),
                    color: palette.kinetic,
                    background: palette.chipBg
                )
            }
            // done → no chip at all per spec; row is already opacity'd
        }
    }

    private func pastEventRow(event: EventData) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(PerchFormatters.time24h.string(from: event.start))
                .font(PerchTheme.Font.rowNumeric)
                .tracking(0.2)
                .foregroundColor(palette.muted)
                .frame(width: 56, alignment: .leading)
                .padding(.top, 1)

            Text(event.title)
                .font(PerchTheme.Font.body)
                .foregroundColor(palette.ink)
                .strikethrough(color: palette.faint)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .opacity(0.48)
    }

    // MARK: - Helpers

    private func relativeTimeLabel(for event: EventData) -> String {
        let interval = event.start.timeIntervalSince(now)

        // Currently happening
        if event.start <= now && event.end > now {
            return "now"
        }

        // In the future
        if interval > 0 {
            let minutes = Int(interval / 60)
            let hours = minutes / 60
            if hours > 0 {
                let remainingMinutes = minutes % 60
                if remainingMinutes > 0 {
                    return "in \(hours)h \(remainingMinutes)m"
                }
                return "in \(hours)h"
            }
            return "in \(minutes)m"
        }

        // In the past
        let pastMinutes = Int(-interval / 60)
        let pastHours = pastMinutes / 60
        if pastHours > 0 {
            return "\(pastHours)h ago"
        }
        return "\(pastMinutes)m ago"
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        CalendarTodayCard(records: [])
            .padding(PerchTheme.Spacing.large)
    }
    .background(PerchTheme.background)
}
