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

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.HomeCard.verticalPadding) {
            // Tappable header
            Button {
                PerchHaptics.selection()
                PerchMotion.withOptionalAnimation(.easeInOut(duration: 0.3)) {
                    isCompact.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HomeCardHeader(
                        systemImage: "calendar",
                        title: "TODAY",
                        trailingText: todayEvents.isEmpty ? nil : "\(todayEvents.count) event\(todayEvents.count == 1 ? "" : "s")",
                        showsChevron: true,
                        isExpanded: !isCompact
                    )

                    // Gentle one-line read on the day's calendar shape.
                    // Rotates daily through a library of variants so the
                    // dashboard doesn't feel robotic across re-visits.
                    Text(calendarPhrase)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textPrimary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle())

            if todayEvents.isEmpty {
                // Empty-day state — illustration carries the warmth, phrase
                // above (e.g. "A breezy one") carries the message. No text
                // duplication.
                HStack {
                    Spacer()
                    Image("empty-calendar")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 120)
                        .accessibilityLabel("No events today")
                    Spacer()
                }
                .padding(.vertical, PerchTheme.Spacing.xSmall)
            } else if isCompact {
                // Compact: single-line summary
                Text(compactSummary)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
            } else {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                    // Upcoming events (up to 5)
                    ForEach(Array(upcomingEvents.prefix(5).enumerated()), id: \.element.record.id) { index, item in
                        eventRow(event: item.event, isNext: index == 0)
                    }

                    // Past events divider
                    if !pastEvents.isEmpty && !upcomingEvents.isEmpty {
                        Rectangle()
                            .fill(PerchTheme.border)
                            .frame(height: 1)
                            .padding(.vertical, PerchTheme.Spacing.xxSmall)
                    }

                    // Past events (up to 2)
                    ForEach(Array(pastEvents.suffix(2).enumerated()), id: \.element.record.id) { _, item in
                        pastEventRow(event: item.event)
                    }

                    // "View all" if more than 5 upcoming
                    if upcomingEvents.count > 5 {
                        Text("View all \(todayEvents.count) events")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.accent)
                            .padding(.top, PerchTheme.Spacing.xxSmall)
                    }
                }
            }
        }
        .padding(.horizontal, PerchTheme.HomeCard.horizontalPadding)
        .padding(.vertical, PerchTheme.HomeCard.verticalPadding)
        .cardStyle()
        .animation(.easeInOut(duration: 0.3), value: isCompact)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            now = Date.now
        }
    }

    // MARK: - Event Rows

    /// Upcoming / currently-happening event row. Editorial layout:
    /// strong monospaced time column, clean title, quiet right-aligned
    /// status (a small pill for "Now", a muted countdown otherwise).
    /// No decorative bullets — hierarchy comes from weight and colour.
    private func eventRow(event: EventData, isNext: Bool) -> some View {
        let isHappening = event.start <= now && event.end > now

        return HStack(alignment: .firstTextBaseline, spacing: PerchTheme.Spacing.medium) {
            // Time column — monospaced, fixed width, stronger when "next"
            Text(PerchFormatters.time24h.string(from: event.start))
                .font(PerchTheme.Font.headingNumeric)
                .foregroundColor(isNext || isHappening ? PerchTheme.textPrimary : PerchTheme.textSecondary)
                .frame(width: 56, alignment: .leading)

            // Title
            Text(event.title)
                .font(PerchTheme.Font.heading)
                .fontWeight(isNext || isHappening ? .semibold : .regular)
                .foregroundColor(PerchTheme.textPrimary)
                .lineLimit(1)

            Spacer(minLength: PerchTheme.Spacing.small)

            // Status pill: "Now" for happening, countdown for next, muted
            // relative label for further-out events. One accent per row max.
            if isHappening {
                Text("Now")
                    .font(PerchTheme.Font.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(PerchTheme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(PerchTheme.success.opacity(0.12))
                    )
            } else {
                Text(relativeTimeLabel(for: event))
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(isNext ? PerchTheme.accent : PerchTheme.textTertiary)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 4)
    }

    /// Past event row — restrained, dim, smaller. Filters to the visual
    /// background so attention stays on what's next.
    private func pastEventRow(event: EventData) -> some View {
        let endedMinutesAgo = Int(now.timeIntervalSince(event.end) / 60)

        return HStack(alignment: .firstTextBaseline, spacing: PerchTheme.Spacing.medium) {
            Text(PerchFormatters.time24h.string(from: event.start))
                .font(PerchTheme.Font.captionNumeric)
                .foregroundColor(PerchTheme.textTertiary)
                .frame(width: 56, alignment: .leading)

            Text(event.title)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)
                .lineLimit(1)

            Spacer(minLength: PerchTheme.Spacing.small)

            Text(Self.pastRelativeLabel(minutesAgo: endedMinutesAgo))
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 4)
        .opacity(endedMinutesAgo > 120 ? 0.55 : 0.75)
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
