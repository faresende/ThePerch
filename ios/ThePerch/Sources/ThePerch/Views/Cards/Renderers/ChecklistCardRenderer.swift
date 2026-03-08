import SwiftUI

struct ChecklistCardRenderer: View {
    struct Payload: Decodable {
        struct Item: Decodable, Identifiable {
            let id: String
            let title: String
            let isDone: Bool?
        }
        let items: [Item]
    }

    let record: Record

    var body: some View {
        let payload = record.decodeData(as: Payload.self)
        let items = payload?.items ?? []

        UniversalCardContainer(record: record, iconOverride: "checklist") {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                ForEach(items.prefix(8)) { item in
                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Image(systemName: (item.isDone ?? false) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor((item.isDone ?? false) ? .green : PerchTheme.textSecondary)
                            .accessibilityHidden(true)

                        Text(item.title)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)

                        Spacer(minLength: 0)
                    }
                }
            }
            .accessibilityLabel("\(record.title), checklist")
        }
    }
}
