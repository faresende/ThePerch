import ActivityKit
import Foundation

/// Shared (app + widget) ActivityKit types.
public struct DeliveryActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var status: String
        public var eta: Date?
        public var lastUpdated: Date

        public init(status: String, eta: Date?, lastUpdated: Date) {
            self.status = status
            self.eta = eta
            self.lastUpdated = lastUpdated
        }
    }

    public var orderId: String
    public var carrier: String
    public var trackingNumber: String

    public init(orderId: String, carrier: String, trackingNumber: String) {
        self.orderId = orderId
        self.carrier = carrier
        self.trackingNumber = trackingNumber
    }
}
