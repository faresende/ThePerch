import Foundation
import Testing
@testable import ThePerch

// MARK: - Helpers

private func makeOrder(
    merchant: String = "Peak Design",
    orderNumber: String = "PD-1",
    status: String = "shipped",
    hidden: Bool = false,
    classification: String? = nil,
    manualDeliveredAt: Date? = nil
) -> Order {
    Order(
        id: UUID(),
        merchant: merchant,
        orderNumber: orderNumber,
        total: Decimal(string: "99"),
        currency: "EUR",
        status: status,
        confidence: 0.9,
        createdAt: .now,
        manualDeliveredAt: manualDeliveredAt,
        hidden: hidden,
        classification: classification
    )
}

private func makeShipment(
    orderId: UUID,
    trackingNumber: String = "1Z999AA10123456784",
    status: String = "in_transit",
    etaAt: Date? = nil
) -> Shipment {
    Shipment(
        id: UUID(),
        orderId: orderId,
        trackingNumber: trackingNumber,
        carrier: "UPS",
        status: status,
        createdAt: .now,
        etaAt: etaAt
    )
}

// MARK: - OrderZones.partition

@Suite("OrderZones.partition")
struct OrderZonesPartitionTests {
    @Test("an order with a live shipment lands in inTransit")
    func liveShipmentIsInTransit() {
        let order = makeOrder()
        let shipment = makeShipment(orderId: order.id, status: "in_transit")
        let model = OrderWithShipments(order: order, shipments: [shipment])

        let zones = OrderZones.partition([model])

        #expect(zones.inTransit.map(\.id) == [model.id])
        #expect(zones.expected.isEmpty)
        #expect(zones.delivered.isEmpty)
        #expect(zones.hidden.isEmpty)
    }

    @Test("a visible order with no shipment lands in expected")
    func noShipmentIsExpected() {
        let order = makeOrder(status: "ordered")
        let model = OrderWithShipments(order: order, shipments: [])

        let zones = OrderZones.partition([model])

        #expect(zones.expected.map(\.id) == [model.id])
        #expect(zones.inTransit.isEmpty)
        #expect(zones.delivered.isEmpty)
        #expect(zones.hidden.isEmpty)
    }

    @Test("a visible order whose only shipment is delivered lands in expected (no live shipment)")
    func deliveredShipmentButNotDeliveredOrderIsExpected() {
        // Order status still 'shipped', shipment delivered → effectiveStatus
        // follows the primary shipment, so this is actually delivered.
        // To exercise the "no live shipment but not delivered" branch we use
        // a cancelled shipment with an order that isn't delivered.
        let order = makeOrder(status: "ordered")
        let shipment = makeShipment(orderId: order.id, status: "cancelled")
        // primaryShipment.status == "cancelled" so effectiveStatus == "cancelled"
        // (not "delivered"), and the shipment is not live → expected.
        let model = OrderWithShipments(order: order, shipments: [shipment])

        let zones = OrderZones.partition([model])

        #expect(zones.expected.map(\.id) == [model.id])
        #expect(zones.inTransit.isEmpty)
    }

    @Test("a hidden order lands in hidden regardless of shipment state")
    func hiddenOrderIsHidden() {
        let order = makeOrder(hidden: true)
        let shipment = makeShipment(orderId: order.id, status: "in_transit")
        let model = OrderWithShipments(order: order, shipments: [shipment])

        let zones = OrderZones.partition([model])

        #expect(zones.hidden.map(\.id) == [model.id])
        #expect(zones.inTransit.isEmpty)
        #expect(zones.expected.isEmpty)
        #expect(zones.delivered.isEmpty)
    }

    @Test("a delivered order lands in delivered")
    func deliveredOrderIsDelivered() {
        let order = makeOrder(status: "delivered")
        let shipment = makeShipment(orderId: order.id, status: "delivered")
        let model = OrderWithShipments(order: order, shipments: [shipment])

        let zones = OrderZones.partition([model])

        #expect(zones.delivered.map(\.id) == [model.id])
        #expect(zones.inTransit.isEmpty)
        #expect(zones.expected.isEmpty)
        #expect(zones.hidden.isEmpty)
    }

    @Test("a manually-delivered order lands in delivered even with a live shipment")
    func manuallyDeliveredIsDelivered() {
        let order = makeOrder(status: "shipped", manualDeliveredAt: .now)
        let shipment = makeShipment(orderId: order.id, status: "in_transit")
        let model = OrderWithShipments(order: order, shipments: [shipment])

        let zones = OrderZones.partition([model])

        #expect(zones.delivered.map(\.id) == [model.id])
        #expect(zones.inTransit.isEmpty)
    }

    @Test("inTransit is sorted by soonest effectiveETA first, nils last")
    func inTransitSortedBySoonestETA() {
        let soon = Date(timeIntervalSinceNow: 86_400)        // +1 day
        let later = Date(timeIntervalSinceNow: 3 * 86_400)   // +3 days

        let orderLater = makeOrder(merchant: "Later", orderNumber: "L-1")
        let modelLater = OrderWithShipments(
            order: orderLater,
            shipments: [makeShipment(orderId: orderLater.id, status: "in_transit", etaAt: later)]
        )

        let orderSoon = makeOrder(merchant: "Soon", orderNumber: "S-1")
        let modelSoon = OrderWithShipments(
            order: orderSoon,
            shipments: [makeShipment(orderId: orderSoon.id, status: "in_transit", etaAt: soon)]
        )

        let orderNoETA = makeOrder(merchant: "NoETA", orderNumber: "N-1")
        let modelNoETA = OrderWithShipments(
            order: orderNoETA,
            shipments: [makeShipment(orderId: orderNoETA.id, status: "in_transit", etaAt: nil)]
        )

        // Feed in deliberately unsorted order.
        let zones = OrderZones.partition([modelNoETA, modelLater, modelSoon])

        #expect(zones.inTransit.map(\.id) == [modelSoon.id, modelLater.id, modelNoETA.id])
    }

    @Test("partition routes a mixed batch into the right zones")
    func mixedBatch() {
        let inTransitOrder = makeOrder(merchant: "Transit", orderNumber: "T-1")
        let inTransit = OrderWithShipments(
            order: inTransitOrder,
            shipments: [makeShipment(orderId: inTransitOrder.id, status: "in_transit")]
        )

        let expectedOrder = makeOrder(merchant: "Expected", orderNumber: "E-1", status: "ordered")
        let expected = OrderWithShipments(order: expectedOrder, shipments: [])

        let deliveredOrder = makeOrder(merchant: "Delivered", orderNumber: "D-1", status: "delivered")
        let delivered = OrderWithShipments(
            order: deliveredOrder,
            shipments: [makeShipment(orderId: deliveredOrder.id, status: "delivered")]
        )

        let hiddenOrder = makeOrder(merchant: "Hidden", orderNumber: "H-1", hidden: true)
        let hidden = OrderWithShipments(order: hiddenOrder, shipments: [])

        let zones = OrderZones.partition([inTransit, expected, delivered, hidden])

        #expect(zones.inTransit.map(\.id) == [inTransit.id])
        #expect(zones.expected.map(\.id) == [expected.id])
        #expect(zones.delivered.map(\.id) == [delivered.id])
        #expect(zones.hidden.map(\.id) == [hidden.id])
    }
}
