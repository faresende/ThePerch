import Foundation
import Testing
@testable import ThePerch

// MARK: - Helpers

private func makeOrder(
    status: String = "ordered",
    manualDeliveredAt: Date? = nil
) -> Order {
    Order(
        id: UUID(),
        merchant: "Test Merchant",
        orderNumber: "ORD-001",
        total: Decimal(string: "42.00"),
        currency: "EUR",
        status: status,
        sourceEmailId: "email_1",
        confidence: 0.9,
        createdAt: .now,
        manualDeliveredAt: manualDeliveredAt
    )
}

private func makeShipment(status: String = "in_transit", orderId: UUID = UUID()) -> Shipment {
    Shipment(
        id: UUID(),
        orderId: orderId,
        trackingNumber: "TRACK123",
        carrier: "DHL",
        status: status,
        createdAt: .now
    )
}

// MARK: - Order.isManuallyDelivered

@Suite("Order.isManuallyDelivered")
struct OrderIsManuallyDeliveredTests {
    @Test("returns false when manualDeliveredAt is nil")
    func falseWhenNil() {
        let order = makeOrder(manualDeliveredAt: nil)
        #expect(!order.isManuallyDelivered)
    }

    @Test("returns true when manualDeliveredAt is set")
    func trueWhenSet() {
        let order = makeOrder(manualDeliveredAt: .now)
        #expect(order.isManuallyDelivered)
    }

    @Test("returns true even when underlying status is not delivered")
    func trueRegardlessOfStatus() {
        let order = makeOrder(status: "shipped", manualDeliveredAt: .now)
        #expect(order.isManuallyDelivered)
    }
}

// MARK: - OrderWithShipments.effectiveStatus

@Suite("OrderWithShipments.effectiveStatus")
struct OrderWithShipmentsEffectiveStatusTests {
    @Test("returns 'delivered' when manually overridden regardless of order status")
    func manualOverrideWinsOverOrderStatus() {
        let order = makeOrder(status: "in_transit", manualDeliveredAt: .now)
        let model = OrderWithShipments(order: order, shipments: [])
        #expect(model.effectiveStatus == "delivered")
    }

    @Test("returns 'delivered' when manually overridden even with active shipment")
    func manualOverrideWinsOverShipmentStatus() {
        let order = makeOrder(status: "shipped", manualDeliveredAt: .now)
        let shipment = makeShipment(status: "in_transit", orderId: order.id)
        let model = OrderWithShipments(order: order, shipments: [shipment])
        #expect(model.effectiveStatus == "delivered")
    }

    @Test("returns shipment status when no manual override")
    func shipmentStatusWhenNoOverride() {
        let order = makeOrder(status: "shipped", manualDeliveredAt: nil)
        let shipment = makeShipment(status: "in_transit", orderId: order.id)
        let model = OrderWithShipments(order: order, shipments: [shipment])
        #expect(model.effectiveStatus == "in_transit")
    }

    @Test("falls back to order status when no shipments and no override")
    func fallsBackToOrderStatus() {
        let order = makeOrder(status: "ordered", manualDeliveredAt: nil)
        let model = OrderWithShipments(order: order, shipments: [])
        #expect(model.effectiveStatus == "ordered")
    }

    @Test("displayStatus is unaffected by manual override")
    func displayStatusUnchanged() {
        // effectiveStatus should change but displayStatus should stay as raw DB value
        let order = makeOrder(status: "shipped", manualDeliveredAt: .now)
        let model = OrderWithShipments(order: order, shipments: [])
        #expect(model.displayStatus == "shipped")
        #expect(model.effectiveStatus == "delivered")
    }

    @Test("reverts to automated status when manualDeliveredAt is nil again")
    func reversionToAutomated() {
        // Simulate undo: same order but manualDeliveredAt = nil
        let originalOrder = makeOrder(status: "in_transit", manualDeliveredAt: .now)
        let afterUndo = Order(
            id: originalOrder.id,
            merchant: originalOrder.merchant,
            orderNumber: originalOrder.orderNumber,
            total: originalOrder.total,
            currency: originalOrder.currency,
            status: originalOrder.status,
            sourceEmailId: originalOrder.sourceEmailId,
            confidence: originalOrder.confidence,
            createdAt: originalOrder.createdAt,
            manualDeliveredAt: nil  // cleared
        )
        let modelAfterUndo = OrderWithShipments(order: afterUndo, shipments: [])
        #expect(modelAfterUndo.effectiveStatus == "in_transit")
        #expect(!afterUndo.isManuallyDelivered)
    }
}

// MARK: - Order Codable round-trip

@Suite("Order.Codable")
struct OrderCodableTests {
    @Test("decodes manualDeliveredAt when present")
    func decodesManualDeliveredAt() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "merchant": "Farfetch",
          "order_number": "FF-001",
          "total": 99.99,
          "currency": "EUR",
          "status": "shipped",
          "source_email_id": "e1",
          "confidence": 0.95,
          "created_at": "2026-04-13T10:00:00Z",
          "manual_delivered_at": "2026-04-13T12:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let order = try decoder.decode(Order.self, from: json)
        #expect(order.isManuallyDelivered)
    }

    @Test("decodes with manualDeliveredAt absent (backward compat)")
    func decodesWithoutManualDeliveredAt() throws {
        // Simulates an existing DB row that doesn't have the column yet.
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000002",
          "merchant": "Amazon",
          "order_number": "AMZ-001",
          "total": 29.99,
          "currency": "USD",
          "status": "in_transit",
          "source_email_id": "e2",
          "confidence": 0.88,
          "created_at": "2026-04-13T10:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let order = try decoder.decode(Order.self, from: json)
        #expect(!order.isManuallyDelivered)
        #expect(order.manualDeliveredAt == nil)
    }

    @Test("decodes with manualDeliveredAt explicitly null")
    func decodesWithManualDeliveredAtNull() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000003",
          "merchant": "Zalando",
          "order_number": "ZL-001",
          "total": 49.90,
          "currency": "EUR",
          "status": "delivered",
          "source_email_id": "e3",
          "confidence": 0.99,
          "created_at": "2026-04-13T10:00:00Z",
          "manual_delivered_at": null
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let order = try decoder.decode(Order.self, from: json)
        #expect(!order.isManuallyDelivered)
    }
}


// MARK: - Shipment tracking URLs

@Suite("Shipment.resolvedTrackingURL")
struct ShipmentResolvedTrackingURLTests {
    @Test("uses explicit tracking_url when present")
    func usesExplicitTrackingURL() {
        let shipment = Shipment(
            id: UUID(),
            orderId: UUID(),
            trackingNumber: "TRACK123",
            carrier: "DHL",
            status: "in_transit",
            createdAt: .now,
            trackingUrl: "https://example.com/track/TRACK123"
        )

        #expect(shipment.resolvedTrackingURL?.absoluteString == "https://example.com/track/TRACK123")
    }

    @Test("falls back to 17track when explicit tracking_url is absent")
    func fallsBackTo17Track() {
        let shipment = Shipment(
            id: UUID(),
            orderId: UUID(),
            trackingNumber: "1Z999AA10123456784",
            carrier: "UPS",
            status: "in_transit",
            createdAt: .now,
            trackingUrl: nil
        )

        #expect(shipment.resolvedTrackingURL?.absoluteString == "https://t.17track.net/en#nums=1Z999AA10123456784")
    }
}
