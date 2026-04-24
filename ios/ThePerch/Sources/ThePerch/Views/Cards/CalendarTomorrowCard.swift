import SwiftUI

/// Shows tomorrow's events as a compact preview.
/// Filters EventData where start date is tomorrow.
struct CalendarTomorrowCard: View {
    let records: [Record]
    /// Live EventKit events merged with records. Optional so this card
    /// still renders where it's called without eventKitEvents.
    var eventKitEvents: [EventData] = []
    @Environment(\.perchPalette) private var palette

    private struct IdentifiedEvent: Identifiable {
        let id: String
        let event: EventData
    }

    private var tomorrowEvents: [IdentifiedEvent] {
        let supabaseEvents: [IdentifiedEvent] = records.compactMap { record in
            guard record.category == .calendar,
                  record.type == .event,
                  let event = record.asEvent(),
                  Calendar.current.isDateInTomorrow(event.start) else { return nil }
            return IdentifiedEvent(id: record.id.uuidString, event: event)
        }
        let deviceEvents: [IdentifiedEvent] = eventKitEvents
            .filter { Calendar.current.isDateInTomorrow($0.start) }
            .map { IdentifiedEvent(id: "ek-\($0.title)|\(Int($0.start.timeIntervalSince1970))", event: $0) }
        var seen = Set<String>()
        var merged: [IdentifiedEvent] = []
        for ie in deviceEvents + supabaseEvents {
            let dedupeKey = "\(ie.event.title)|\(Int(ie.event.start.timeIntervalSince1970 / 60))"
            if seen.insert(dedupeKey).inserted {
                merged.append(ie)
            }
        }
        return merged.sorted { $0.event.start < $1.event.start }
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
                        ForEach(Array(tomorrowEvents.prefix(3).enumerated()), id: \.element.id) { _, item in
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
