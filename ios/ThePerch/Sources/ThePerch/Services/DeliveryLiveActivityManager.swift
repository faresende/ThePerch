import ActivityKit
import Foundation
import PerchSharedKit

/// Keeps a single Live Activity in sync with the most relevant active delivery.
///
/// v1 behavior:
/// - If there is at least one active delivery: start (or update) a Live Activity for the first one.
/// - If there are no active deliveries: end all delivery activities.
@MainActor
final class DeliveryLiveActivityManager {
    static let shared = DeliveryLiveActivityManager()

    private init() {}

    func sync(activeDeliveries: [DeliveryData]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return
        }

        if let first = activeDeliveries.first {
            await startOrUpdate(for: first)
        } else {
            await endAll()
        }
    }

    private func startOrUpdate(for delivery: DeliveryData) async {
        let existing = Activity<DeliveryActivityAttributes>.activities.first { activity in
            activity.attributes.orderId == delivery.orderId
        }

        let state = DeliveryActivityAttributes.ContentState(
            status: delivery.status,
            eta: delivery.eta,
            lastUpdated: Date.now
        )

        if let existing {
            // ActivityKit's `update(using:)` was deprecated in iOS 16.2 in
            // favour of `update(_:)`, which takes an ActivityContent value
            // (the same shape we already pass to `Activity.request` below).
            await existing.update(ActivityContent(state: state, staleDate: nil))
        } else {
            let attributes = DeliveryActivityAttributes(
                orderId: delivery.orderId,
                carrier: delivery.carrier,
                trackingNumber: delivery.trackingNumber
            )

            do {
                _ = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil)
                )
            } catch {
                // Best-effort: Live Activities should never crash the app.
                print("Failed to start Live Activity: \(error)")
            }
        }
    }

    private func endAll() async {
        for activity in Activity<DeliveryActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
