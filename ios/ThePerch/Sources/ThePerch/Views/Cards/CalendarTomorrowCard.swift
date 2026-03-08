import SwiftUI

/// Shows tomorrow's events as a compact preview.
/// Filters EventData where start date is tomorrow.
struct CalendarTomorrowCard: View {
    let records: [Record]

    private var tomorrowEvents: [(record: Record, event: EventData)] {
        records.compactMap { record -> (Record, EventData)? in
            guard record.category == .calendar,
                  record.type == .event,
                  let event = record.asEvent(),
                  Calendar.current.isDateInTomorrow(event.start) else { return nil }
            return (record, event)
        }.sorted { $0.1.start < $1.1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
            // Header
            HStack(spacing: PerchTheme.Spacing.xSmall) {
                Image(systemName: "calendar.badge.clock")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.accent)
                Text("TOMORROW")
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
                    .textCase(.uppercase)
                Spacer()
                if !tomorrowEvents.isEmpty {
                    Text("\(tomorrowEvents.count) event\(tomorrowEvents.count == 1 ? "" : "s")")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }

            if tomorrowEvents.isEmpty {
                Text("Tomorrow is clear")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, PerchTheme.Spacing.small)
            } else {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                    ForEach(Array(tomorrowEvents.prefix(3).enumerated()), id: \.element.record.id) { _, item in
                        compactEventRow(event: item.event)
                    }

                    if tomorrowEvents.count > 3 {
                        Text("+ \(tomorrowEvents.count - 3) more")
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.accent)
                            .padding(.top, PerchTheme.Spacing.xxSmall)
                    }
                }
            }
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
    }

    // MARK: - Components

    private func compactEventRow(event: EventData) -> some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            Circle()
                .fill(PerchTheme.textTertiary)
                .frame(width: 6, height: 6)

            Text(PerchFormatters.time24h.string(from: event.start))
                .font(PerchTheme.Font.captionNumeric)
                .foregroundColor(PerchTheme.textSecondary)
                .frame(width: 50, alignment: .leading)

            Text(event.title)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, PerchTheme.Spacing.xxxSmall)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        CalendarTomorrowCard(records: [])
            .padding(PerchTheme.Spacing.large)
    }
    .background(PerchTheme.background)
}
