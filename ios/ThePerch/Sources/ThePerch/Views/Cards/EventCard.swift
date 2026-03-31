import SwiftUI

/// Displays a calendar event with a colored left border accent.
/// Matches the React EventCard design with time, title, location, and agent note.
struct EventCard: View {
    let event: EventData
    let borderColor: Color
    let timezoneText: String?

    init(event: EventData, borderColor: Color = PerchTheme.accent, timezoneText: String? = nil) {
        self.event = event
        self.borderColor = borderColor
        self.timezoneText = timezoneText
    }

    /// Whether this event has already ended.
    private var isPast: Bool {
        event.end < Date.now
    }

    private var timeFormatted: String {
        let start = PerchFormatters.time12h.string(from: event.start)
        let end = PerchFormatters.time12h.string(from: event.end)
        return "\(start) – \(end)"
    }

    var body: some View {
        Button(action: openInCalendar) {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(isPast ? borderColor.opacity(0.3) : borderColor)
                    .frame(width: 4)

                VStack(alignment: .leading, spacing: 4) {
                    Text(timeFormatted)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(isPast ? PerchTheme.textTertiary : PerchTheme.textSecondary)

                    Text(event.title)
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(isPast ? PerchTheme.textTertiary : PerchTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(PerchTheme.Font.caption)
                            Text(location)
                                .font(PerchTheme.Font.caption)
                        }
                        .foregroundColor(PerchTheme.textTertiary)
                        .padding(.top, 2)
                    }

                    if let timezoneText, !timezoneText.isEmpty {
                        Label(timezoneText, systemImage: "globe")
                            .font(PerchTheme.Font.micro)
                            .foregroundColor(PerchTheme.textSecondary)
                            .padding(.top, 2)
                    }

                    if !isPast, let agentNote = event.agentNotes, !agentNote.isEmpty {
                        Text(agentNote)
                            .font(PerchTheme.Font.caption)
                            .italic()
                            .foregroundColor(PerchTheme.textSecondary)
                            .lineLimit(2)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.vertical, 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(PerchTheme.cardBackground)
            .cornerRadius(PerchTheme.Card.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                    .stroke(PerchTheme.border, lineWidth: PerchTheme.Card.borderWidth)
            )
            .opacity(isPast ? 0.6 : 1.0)
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let startTime = PerchFormatters.time12h.string(from: event.start)

        let dayRef: String = {
            if Calendar.current.isDateInToday(event.start) { return "today" }
            if Calendar.current.isDateInTomorrow(event.start) { return "tomorrow" }
            return PerchFormatters.weekday.string(from: event.start)
        }()

        var summary = "Event: \(event.title) at \(startTime) \(dayRef)"
        if let location = event.location, !location.isEmpty {
            summary += ", at \(location)"
        }
        if let timezoneText, !timezoneText.isEmpty {
            summary += ", \(timezoneText)"
        }
        return summary
    }

    private func openInCalendar() {
        let interval = event.start.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(interval)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: PerchTheme.Spacing.small) {
        EventCard(
            event: EventData(
                title: "Team Standup",
                start: Date.now.addingTimeInterval(3600),
                end: Date.now.addingTimeInterval(5400),
                location: "Google Meet",
                agentNotes: "Remind Fabio to share the API docs with the team"
            )
        )

        EventCard(
            event: EventData(
                title: "Dentist Appointment",
                start: Date.now.addingTimeInterval(86400),
                end: Date.now.addingTimeInterval(86400 + 3600),
                location: "123 Smile Ave",
                agentNotes: nil
            ),
            borderColor: PerchTheme.success
        )

        EventCard(
            event: EventData(
                title: "Product Review",
                start: Date.now.addingTimeInterval(7200),
                end: Date.now.addingTimeInterval(9000),
                location: nil,
                agentNotes: nil
            )
        )
    }
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
