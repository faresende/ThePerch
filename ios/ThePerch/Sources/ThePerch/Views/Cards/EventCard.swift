import SwiftUI

/// Displays a calendar event with a colored left border accent.
/// Matches the React EventCard design with time, title, location, and agent note.
struct EventCard: View {
    let event: EventData
    let borderColor: Color

    init(event: EventData, borderColor: Color = PerchTheme.accent) {
        self.event = event
        self.borderColor = borderColor
    }

    private var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let start = formatter.string(from: event.start)
        let end = formatter.string(from: event.end)
        return "\(start) – \(end)"
    }

    var body: some View {
        Button(action: openInCalendar) {
            HStack(spacing: 0) {
                // Colored left border
                RoundedRectangle(cornerRadius: 2)
                    .fill(borderColor)
                    .frame(width: 4)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Time
                    Text(timeFormatted)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textSecondary)

                    // Title
                    Text(event.title)
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(1)

                    // Location
                    if let location = event.location, !location.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(PerchTheme.Font.caption)
                            Text(location)
                                .font(PerchTheme.Font.caption)
                        }
                        .foregroundColor(PerchTheme.textSecondary)
                        .padding(.top, 2)
                    }

                    // Agent note
                    if let agentNote = event.agentNotes, !agentNote.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Text("🤖")
                                .font(PerchTheme.Font.caption)

                            Text(agentNote)
                                .font(PerchTheme.Font.caption)
                                .italic()
                                .foregroundColor(PerchTheme.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(10)
                        .background(PerchTheme.cardInnerBackground)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(PerchTheme.accent.opacity(0.15), lineWidth: 1)
                        )
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.vertical, 18)
            }
            .cardStyle()
        }
        .buttonStyle(CardPressStyle())
    }

    /// Opens Apple Calendar at the event's date.
    private func openInCalendar() {
        // calshow: opens Calendar app at a specific date (seconds since reference date)
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
