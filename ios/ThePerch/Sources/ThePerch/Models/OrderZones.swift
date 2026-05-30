import Foundation

/// Pure partitioning of orders into the two-zone tracker's buckets.
///
/// The order tracker surfaces two live zones — **In Transit** (a package with
/// a live shipment) and **Expected** (a physical order we're still waiting to
/// ship) — plus **Delivered** and **Hidden** (digital/non-package noise, already
/// `hidden=true` server-side).
///
/// `Expected` is derived STRUCTURALLY: a visible order with no live shipment.
/// It is deliberately NOT keyed on `order.classification` — that column is only
/// stamped on new orders going forward and is NULL on every existing row, so
/// gating Expected on `classification == "physical"` would leave it empty on
/// day one. A visible (non-hidden) order is implicitly a real physical purchase,
/// because digital orders are already filtered out via `hidden`.
enum OrderZones {
    struct Zones: Equatable {
        let inTransit: [OrderWithShipments]
        let expected: [OrderWithShipments]
        let delivered: [OrderWithShipments]
        let hidden: [OrderWithShipments]
    }

    /// Splits `all` into the four zones. Pure — no I/O, deterministic for a
    /// given input. `inTransit` is sorted ascending by `effectiveETA` with nil
    /// ETAs LAST (an order with no known ETA sorts after ones that have one).
    static func partition(_ all: [OrderWithShipments]) -> Zones {
        var inTransit: [OrderWithShipments] = []
        var expected: [OrderWithShipments] = []
        var delivered: [OrderWithShipments] = []
        var hidden: [OrderWithShipments] = []

        for o in all {
            if o.order.hidden {
                hidden.append(o)
            } else if o.effectiveStatus == "delivered" {
                delivered.append(o)
            } else {
                let hasLiveShipment = o.shipments.contains {
                    !$0.trackingNumber.isEmpty
                        && $0.status.lowercased() != "delivered"
                        && $0.status.lowercased() != "cancelled"
                }
                if hasLiveShipment {
                    inTransit.append(o)
                } else {
                    expected.append(o)
                }
            }
        }

        // Soonest arriving first; orders with no ETA sort to the end.
        inTransit.sort { ($0.effectiveETA ?? .distantFuture) < ($1.effectiveETA ?? .distantFuture) }

        return Zones(
            inTransit: inTransit,
            expected: expected,
            delivered: delivered,
            hidden: hidden
        )
    }
}
