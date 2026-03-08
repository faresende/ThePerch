import ActivityKit
import SwiftUI
import WidgetKit
import PerchSharedKit

struct DeliveryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryActivityAttributes.self) { context in
            // Lock screen / banner UI
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(context.attributes.carrier)")
                        .font(.headline)
                    Spacer()
                    Text(context.state.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Tracking \(context.attributes.trackingNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let eta = context.state.eta {
                    Text("ETA \(eta.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption.weight(.semibold))
                }

                Text("Updated \(context.state.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .activityBackgroundTint(Color(red: 0.06, green: 0.06, blue: 0.07))
            .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.carrier)
                        .font(.caption.weight(.semibold))
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tracking \(context.attributes.trackingNumber)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let eta = context.state.eta {
                            Text("ETA \(eta.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption.weight(.semibold))
                        }
                    }
                }
            } compactLeading: {
                Text("📦")
            } compactTrailing: {
                Text(context.state.status.prefix(3).uppercased())
                    .font(.caption2.weight(.semibold))
            } minimal: {
                Text("📦")
            }
            .widgetURL(URL(string: "theperch://deliveries"))
        }
    }
}
