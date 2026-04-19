import SwiftUI

/// Shows tomorrow's events as a compact preview.
/// Filters EventData where start date is tomorrow.
struct CalendarTomorrowCard: View {
    let records: [Record]
    @Environment(\.perchPalette) private var palette

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
        TodayCard {
            VStack(alignment: .leading, spacing: 0) {
                TodayEyebrow(
                    label: "TOMORROW",
                    accent: palette.wellness,
                    freshness: tomorrowEvents.isEmpty ? nil : "\(tomorrowEvents.count) event\(tomorrowEvents.count == 1 ? "" : "s")"
                )

                if tomorrowEvents.isEmpty {
                    Text("Tomorrow is clear")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(palette.faint)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                } else {
                    VStack(spacing: 12) {
                        ForEach(Array(tomorrowEvents.prefix(3).enumerated()), id: \.element.record.id) { _, item in
                            compactEventRow(event: item.event)
                        }

                        if tomorrowEvents.count > 3 {
                            Text("+ \(tomorrowEvents.count - 3) more")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(palette.kinetic)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 2)
                        }
                    }
                }
            }
        }
    }

    private func compactEventRow(event: EventData) -> some View {
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
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
