import SwiftUI

struct ListCardRenderer: View {
    struct Payload: Decodable {
        struct Item: Decodable, Identifiable {
            let id: String
            let title: String
            let subtitle: String?
            let systemImage: String?
        }
        let items: [Item]
    }

    let record: Record

    var body: some View {
        let payload = record.decodeData(as: Payload.self)
        let items = payload?.items ?? []

        UniversalCardContainer(record: record, iconOverride: "list.bullet") {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                ForEach(items.prefix(6)) { item in
                    HStack(alignment: .top, spacing: PerchTheme.Spacing.xSmall) {
                        if let systemImage = item.systemImage {
                            Image(systemName: systemImage)
                                .foregroundColor(PerchTheme.textSecondary)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .font(PerchTheme.Font.body)
                                .foregroundColor(PerchTheme.textPrimary)
                                .lineLimit(2)
                            if let subtitle = item.subtitle {
                                Text(subtitle)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(PerchTheme.textSecondary)
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .accessibilityLabel("\(record.title), list")
        }
    }
}
