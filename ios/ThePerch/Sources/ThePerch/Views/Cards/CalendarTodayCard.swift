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

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.HomeCard.verticalPadding) {
            // Tappable header
            Button {
                PerchHaptics.selection()
                PerchMotion.withOptionalAnimation(.easeInOut(duration: 0.3)) {
                    isCompact.toggle()
                }
            } label: {
                HomeCardHeader(
                    systemImage: "calendar",
                    title: "TODAY",
                    trailingText: todayEvents.isEmpty ? nil : "\(todayEvents.count) event\(todayEvents.count == 1 ? "" : "s")",
                    showsChevron: true,
                    isExpanded: !isCompact
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CardPressStyle())

            if todayEvents.isEmpty {
                // Empty state
                HStack(spacing: PerchTheme.Spacing.small) {
                    Text("No events today — enjoy your free time 🎉")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, PerchTheme.Spacing.small)
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

    private func eventRow(event: EventData, isNext: Bool) -> some View {
        let isHappening = event.start <= now && event.end > now

        return HStack(spacing: PerchTheme.HomeCard.rowSpacing) {
            // Status indicator — green dot when event is happening now
            if isHappening {
                Circle()
                    .fill(PerchTheme.success)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(isNext ? PerchTheme.accent : PerchTheme.textTertiary)
                    .frame(width: 8, height: 8)
            }

            // Time
            Text(PerchFormatters.time24h.string(from: event.start))
                .font(isNext ? PerchTheme.Font.headingNumeric : PerchTheme.Font.bodyNumeric)
                .foregroundColor(PerchTheme.textPrimary)
                .frame(minWidth: 50, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            // Title
            Text(event.title)
                .font(isNext ? PerchTheme.Font.heading : PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)
                .lineLimit(1)
                .multilineTextAlignment(.leading)

            Spacer()

            // Relative time — "Now" with green, countdown with accent
            if isHappening {
                HStack(spacing: PerchTheme.Spacing.xxSmall) {
                    Circle()
                        .fill(PerchTheme.success)
                        .frame(width: 6, height: 6)
                    Text("Now")
                        .font(PerchTheme.Font.caption)
                        .fontWeight(.medium)
                        .foregroundColor(PerchTheme.success)
                }
            } else {
                Text(relativeTimeLabel(for: event))
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(isNext ? PerchTheme.accent : PerchTheme.textTertiary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, isHappening ? PerchTheme.Spacing.small : 0)
        .background(isHappening ? PerchTheme.success.opacity(0.08) : (isNext ? PerchTheme.accentMuted : Color.clear))
        .cornerRadius(PerchTheme.Card.innerCornerRadius)
        .homeCardRowStyle()
    }

    private func pastEventRow(event: EventData) -> some View {
        let endedMinutesAgo = Int(now.timeIntervalSince(event.end) / 60)

        return HStack(spacing: PerchTheme.HomeCard.rowSpacing) {
            Image(systemName: "checkmark")
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)
                .frame(width: 8)

            Text(PerchFormatters.time24h.string(from: event.start))
                .font(PerchTheme.Font.captionNumeric)
                .foregroundColor(PerchTheme.textTertiary)
                .frame(minWidth: 50, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

            Text(event.title)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .layoutPriority(1)

            Spacer()

            Text(Self.pastRelativeLabel(minutesAgo: endedMinutesAgo))
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: PerchTheme.HomeCard.trailingColumnMinWidth, alignment: .trailing)
        }
        .homeCardRowStyle()
        .opacity(endedMinutesAgo > 120 ? 0.6 : 0.8)
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
