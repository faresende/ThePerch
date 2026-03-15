import SwiftUI

struct StatusCardRenderer: View {
    struct Payload: Decodable {
        struct Item: Decodable, Identifiable {
            let id: String
            let label: String
            let value: String
            let status: String?
        }
        let items: [Item]
    }

    let record: Record

    private func color(for status: String?) -> Color {
        switch status {
        case "ok":
            return PerchTheme.success
        case "warning":
            return PerchTheme.warning
        case "error":
            return PerchTheme.error
        default:
            return PerchTheme.textSecondary
        }
    }

    var body: some View {
        let payload = record.decodeData(as: Payload.self)
        let items = payload?.items ?? []

        UniversalCardContainer(record: record, iconOverride: "heartbeat") {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                ForEach(items.prefix(6)) { item in
                    HStack {
                        Circle()
                            .fill(color(for: item.status))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)

                        Text(item.label)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)

                        Spacer(minLength: 0)

                        Text(item.value)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }
            }
            .accessibilityLabel("\(record.title), status")
        }
    }
}
