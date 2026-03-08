import SwiftUI

struct TextCardRenderer: View {
    struct Payload: Decodable {
        let text: String
    }

    let record: Record

    var body: some View {
        let payload = record.decodeData(as: Payload.self)

        UniversalCardContainer(record: record, iconOverride: "text.alignleft") {
            Text(payload?.text ?? "")
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)
                .lineLimit(8)
                .accessibilityLabel(payload?.text ?? record.title)
        }
    }
}
