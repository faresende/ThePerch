import SwiftUI

struct MetricCardRenderer: View {
    struct Payload: Decodable {
        let value: String?
        let unit: String?
        let trend: String?
        let caption: String?
    }

    let record: Record

    var body: some View {
        let payload = record.decodeData(as: Payload.self)

        UniversalCardContainer(
            record: record,
            subtitleOverride: payload?.caption,
            iconOverride: "gauge"
        ) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text([payload?.value, payload?.unit].compactMap { $0 }.joined(separator: " "))
                        .font(PerchTheme.Font.title)
                        .foregroundColor(PerchTheme.textPrimary)

                    if let trend = payload?.trend {
                        Text(trend)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityLabel("\(record.title), \(payload?.value ?? "")")
        }
    }
}
