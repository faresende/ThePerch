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
        HStack(spacing: 0) {
            // Colored left border
            RoundedRectangle(cornerRadius: 2)
                .fill(borderColor)
                .frame(width: 4)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                // Time
                Text(timeFormatted)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PerchTheme.textSecondary)

                // Title
                Text(event.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PerchTheme.textPrimary)
                    .lineLimit(1)

                // Location
                if let location = event.location, !location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 12))
                        Text(location)
                            .font(.system(size: 12))
                    }
                    .foregroundColor(PerchTheme.textSecondary)
                    .padding(.top, 2)
                }

                // Agent note
                if let agentNote = event.agentNotes, !agentNote.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Text("🤖")
                            .font(.system(size: 12))

                        Text(agentNote)
                            .font(.system(size: 12))
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
            .padding(.horizontal, PerchTheme.Card.padding + 4)
            .padding(.vertical, 18)
        }
        .cardStyle()
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
