import SwiftUI

struct TimelineCardRenderer: View {
    struct Payload: Decodable {
        struct Event: Decodable, Identifiable {
            let id: String
            let time: String?
            let title: String
            let subtitle: String?
        }
        let events: [Event]
    }

    let record: Record

    var body: some View {
        let payload = record.decodeData(as: Payload.self)
        let events = payload?.events ?? []

        UniversalCardContainer(record: record, iconOverride: "clock") {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                ForEach(events.prefix(6)) { event in
                    HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
                        VStack(alignment: .leading, spacing: 2) {
                            if let time = event.time {
                                Text(time)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textSecondary)
                            }
                            Text(event.title)
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textPrimary)
                                .lineLimit(2)
                            if let subtitle = event.subtitle {
                                Text(subtitle)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Divider().opacity(0.35)
                }
            }
            .accessibilityLabel("\(record.title), timeline")
        }
    }
}
