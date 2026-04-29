#if DEBUG
import Foundation

/// Mock data for previews and testing before real data flows in.
struct MockData {
    // MARK: - Mock Agents

    static let agents: [Agent] = [
        Agent(
            id: "claudinho",
            displayName: "Claudinho",
            emoji: "🤖",
            model: "claude-opus-4-7",
            isActive: true,
            lastHeartbeat: Date.now.addingTimeInterval(-300),
            ownerId: UUID(),
            createdAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Agent(
            id: "biochecha",
            displayName: "BioChecha",
            emoji: "💊",
            model: "claude-opus-4-7",
            isActive: true,
            lastHeartbeat: Date.now.addingTimeInterval(-600),
            ownerId: UUID(),
            createdAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Agent(
            id: "entregas",
            displayName: "Entregas",
            emoji: "📦",
            model: "claude-opus-4-7",
            isActive: true,
            lastHeartbeat: Date.now.addingTimeInterval(-1200),
            ownerId: UUID(),
            createdAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Agent(
            id: "calendario",
            displayName: "Calendario",
            emoji: "📅",
            model: "claude-opus-4-7",
            isActive: true,
            lastHeartbeat: Date.now.addingTimeInterval(-2400),
            ownerId: UUID(),
            createdAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Agent(
            id: "legal",
            displayName: "Legal",
            emoji: "⚖️",
            model: "claude-opus-4-7",
            isActive: true,
            lastHeartbeat: Date.now.addingTimeInterval(-300),
            ownerId: UUID(),
            createdAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Agent(
            id: "archie",
            displayName: "Archie",
            emoji: "📚",
            model: "claude-opus-4-7",
            isActive: true,
            lastHeartbeat: Date.now.addingTimeInterval(-450),
            ownerId: UUID(),
            createdAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
    ]

    // MARK: - Mock Records (Measurements)

    static let measurementRecords: [Record] = [
        Record(
            id: UUID(),
            agentId: "biochecha",
            userId: UUID(),
            type: .measurement,
            category: .health,
            title: "Weight",
            data: JSONValue.object([
                "metric": .string("weight"),
                "value": .number(82.5),
                "unit": .string("kg"),
                "context": .string("morning"),
                "timestamp": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-86400 * 7)))
            ]),
            displayHint: .chart,
            annotations: nil,
            pinned: false,
            createdAt: Date.now.addingTimeInterval(-86400 * 7),
            updatedAt: Date.now.addingTimeInterval(-86400 * 7),
            expiresAt: nil
        ),
        Record(
            id: UUID(),
            agentId: "biochecha",
            userId: UUID(),
            type: .measurement,
            category: .health,
            title: "Weight",
            data: JSONValue.object([
                "metric": .string("weight"),
                "value": .number(82.1),
                "unit": .string("kg"),
                "context": .string("morning"),
                "timestamp": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-86400 * 5)))
            ]),
            displayHint: .chart,
            annotations: nil,
            pinned: false,
            createdAt: Date.now.addingTimeInterval(-86400 * 5),
            updatedAt: Date.now.addingTimeInterval(-86400 * 5),
            expiresAt: nil
        ),
        Record(
            id: UUID(),
            agentId: "biochecha",
            userId: UUID(),
            type: .measurement,
            category: .health,
            title: "Weight",
            data: JSONValue.object([
                "metric": .string("weight"),
                "value": .number(81.8),
                "unit": .string("kg"),
                "context": .string("morning"),
                "timestamp": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-86400 * 3)))
            ]),
            displayHint: .chart,
            annotations: nil,
            pinned: false,
            createdAt: Date.now.addingTimeInterval(-86400 * 3),
            updatedAt: Date.now.addingTimeInterval(-86400 * 3),
            expiresAt: nil
        ),
        Record(
            id: UUID(),
            agentId: "biochecha",
            userId: UUID(),
            type: .measurement,
            category: .health,
            title: "Weight",
            data: JSONValue.object([
                "metric": .string("weight"),
                "value": .number(82.3),
                "unit": .string("kg"),
                "context": .string("morning"),
                "timestamp": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-86400 * 1)))
            ]),
            displayHint: .chart,
            annotations: nil,
            pinned: false,
            createdAt: Date.now.addingTimeInterval(-86400 * 1),
            updatedAt: Date.now.addingTimeInterval(-86400 * 1),
            expiresAt: nil
        ),
        Record(
            id: UUID(),
            agentId: "biochecha",
            userId: UUID(),
            type: .measurement,
            category: .health,
            title: "Weight",
            data: JSONValue.object([
                "metric": .string("weight"),
                "value": .number(81.5),
                "unit": .string("kg"),
                "context": .string("morning"),
                "timestamp": .string(ISO8601DateFormatter().string(from: Date.now))
            ]),
            displayHint: .chart,
            annotations: nil,
            pinned: true,
            createdAt: Date.now,
            updatedAt: Date.now,
            expiresAt: nil
        ),
    ]

    // MARK: - Mock Records (Deliveries)

    static let deliveryRecords: [Record] = [
        Record(
            id: UUID(),
            agentId: "entregas",
            userId: UUID(),
            type: .delivery,
            category: .deliveries,
            title: "Wireless Headphones",
            data: JSONValue.object([
                "order_id": .string("ORD-2024-001"),
                "carrier": .string("FedEx"),
                "tracking_number": .string("794648583294"),
                "status": .string("in_transit"),
                "eta": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(86400))),
                "items": .array([
                    .object([
                        "name": .string("Wireless Headphones"),
                        "quantity": .number(1),
                        "description": .string("Premium noise-cancelling headphones")
                    ])
                ]),
                "tracking_url": .string("https://tracking.fedex.com/794648583294")
            ]),
            displayHint: .statusList,
            annotations: nil,
            pinned: true,
            createdAt: Date.now.addingTimeInterval(-86400 * 2),
            updatedAt: Date.now.addingTimeInterval(-3600),
            expiresAt: nil
        ),
        Record(
            id: UUID(),
            agentId: "entregas",
            userId: UUID(),
            type: .delivery,
            category: .deliveries,
            title: "Desk Lamp",
            data: JSONValue.object([
                "order_id": .string("ORD-2024-002"),
                "carrier": .string("UPS"),
                "tracking_number": .string("1Z999AA10123456784"),
                "status": .string("out_for_delivery"),
                "eta": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(3600 * 4))),
                "items": .array([
                    .object([
                        "name": .string("LED Desk Lamp"),
                        "quantity": .number(1),
                        "description": .string("Adjustable brightness desk lamp")
                    ])
                ]),
                "tracking_url": .string("https://tracking.ups.com/1Z999AA10123456784")
            ]),
            displayHint: .statusList,
            annotations: nil,
            pinned: true,
            createdAt: Date.now.addingTimeInterval(-86400 * 1),
            updatedAt: Date.now.addingTimeInterval(-600),
            expiresAt: nil
        ),
    ]

    // MARK: - Mock Records (Bookmarks)

    static let bookmarkRecords: [Record] = [
        Record(
            id: UUID(),
            agentId: "archie",
            userId: UUID(),
            type: .bookmark,
            category: .bookmarks,
            title: "Understanding SwiftUI State Management",
            data: JSONValue.object([
                "url": .string("https://www.swiftui.dev/article/state-management"),
                "original_title": .string("SwiftUI State Management"),
                "enriched_title": .string("Understanding SwiftUI State Management"),
                "summary": .string("A comprehensive guide to managing state in SwiftUI applications, covering @State, @StateObject, @ObservedObject, and @EnvironmentObject."),
                "tags": .array([.string("SwiftUI"), .string("iOS"), .string("State Management")]),
                "status": .string("processed"),
                "domain": .string("swiftui.dev"),
                "reading_time_minutes": .number(12),
                "submitted_from": .string("ios_share"),
                "processed_at": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-3600)))
            ]),
            displayHint: .bookmarkCard,
            annotations: nil,
            pinned: true,
            createdAt: Date.now.addingTimeInterval(-3600),
            updatedAt: Date.now.addingTimeInterval(-3600),
            expiresAt: nil
        ),
        Record(
            id: UUID(),
            agentId: "archie",
            userId: UUID(),
            type: .bookmark,
            category: .bookmarks,
            title: "Latest Research on AI Safety",
            data: JSONValue.object([
                "url": .string("https://www.arxiv.org/pdf/2402.06000"),
                "original_title": .null,
                "enriched_title": .null,
                "summary": .null,
                "tags": .array([]),
                "status": .string("processing"),
                "domain": .string("arxiv.org"),
                "reading_time_minutes": .null,
                "submitted_from": .string("ios_share"),
                "processed_at": .null
            ]),
            displayHint: .bookmarkCard,
            annotations: nil,
            pinned: false,
            createdAt: Date.now.addingTimeInterval(-300),
            updatedAt: Date.now.addingTimeInterval(-300),
            expiresAt: nil
        ),
        Record(
            id: UUID(),
            agentId: "archie",
            userId: UUID(),
            type: .bookmark,
            category: .bookmarks,
            title: "How to Build Scalable APIs",
            data: JSONValue.object([
                "url": .string("https://www.api-design.dev/scalable-rest-apis"),
                "original_title": .string("Scalable REST APIs"),
                "enriched_title": .string("How to Build Scalable APIs"),
                "summary": .string("Detailed patterns and best practices for designing APIs that scale horizontally with minimal latency."),
                "tags": .array([.string("API Design"), .string("Backend"), .string("Scaling")]),
                "status": .string("processed"),
                "domain": .string("api-design.dev"),
                "reading_time_minutes": .number(8),
                "submitted_from": .string("safari_extension"),
                "processed_at": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(-86400)))
            ]),
            displayHint: .bookmarkCard,
            annotations: nil,
            pinned: false,
            createdAt: Date.now.addingTimeInterval(-86400),
            updatedAt: Date.now.addingTimeInterval(-86400),
            expiresAt: nil
        ),
    ]

    // MARK: - Mock Records (Events)

    static let eventRecords: [Record] = [
        Record(
            id: UUID(),
            agentId: "calendario",
            userId: UUID(),
            type: .event,
            category: .calendar,
            title: "Team Standup",
            data: JSONValue.object([
                "title": .string("Team Standup"),
                "start": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(3600))),
                "end": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(3600 + 1800))),
                "location": .string("Conference Room A"),
                "agent_notes": .string("Discuss Q1 roadmap and blockers")
            ]),
            displayHint: .timeline,
            annotations: nil,
            pinned: false,
            createdAt: Date.now.addingTimeInterval(-86400 * 30),
            updatedAt: Date.now.addingTimeInterval(-86400 * 30),
            expiresAt: nil
        ),
        Record(
            id: UUID(),
            agentId: "calendario",
            userId: UUID(),
            type: .event,
            category: .calendar,
            title: "Lunch with Client",
            data: JSONValue.object([
                "title": .string("Lunch with Client"),
                "start": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(86400 + 43200))),
                "end": .string(ISO8601DateFormatter().string(from: Date.now.addingTimeInterval(86400 + 50400))),
                "location": .string("Downtown Bistro"),
                "agent_notes": .string("Discuss new project opportunities")
            ]),
            displayHint: .timeline,
            annotations: nil,
            pinned: false,
            createdAt: Date.now.addingTimeInterval(-86400 * 30),
            updatedAt: Date.now.addingTimeInterval(-86400 * 30),
            expiresAt: nil
        ),
    ]

    // MARK: - Mock Records (Cost Summary)

    static let costSummaryRecords: [Record] = [
        Record(
            id: UUID(),
            agentId: "claudinho",
            userId: UUID(),
            type: .costSummary,
            category: .admin,
            title: "Daily Cost Summary",
            data: JSONValue.object([
                "period": .string("daily"),
                "date": .string(ISO8601DateFormatter().string(from: Date.now)),
                "total_cost_usd": .number(4.75),
                "breakdown": .object([
                    "claudinho": .number(2.10),
                    "biochecha": .number(0.95),
                    "archie": .number(1.70)
                ])
            ]),
            displayHint: .costBreakdown,
            annotations: nil,
            pinned: true,
            createdAt: Date.now,
            updatedAt: Date.now,
            expiresAt: nil
        ),
    ]

    // MARK: - Mock Records (Checklist)

    static let checklistRecords: [Record] = [
        Record(
            id: UUID(),
            agentId: "legal",
            userId: UUID(),
            type: .checklist,
            category: .legal,
            title: "AIMA Document Preparation",
            data: JSONValue.object([
                "items": .array([
                    .object([
                        "text": .string("Gather all incorporation documents"),
                        "done": .bool(true)
                    ]),
                    .object([
                        "text": .string("Create operating agreement"),
                        "done": .bool(true)
                    ]),
                    .object([
                        "text": .string("Register with Secretary of State"),
                        "done": .bool(false)
                    ]),
                    .object([
                        "text": .string("Obtain EIN from IRS"),
                        "done": .bool(false)
                    ]),
                    .object([
                        "text": .string("Open business bank account"),
                        "done": .bool(false)
                    ]),
                ])
            ]),
            displayHint: .checklist,
            annotations: nil,
            pinned: true,
            createdAt: Date.now.addingTimeInterval(-86400 * 7),
            updatedAt: Date.now,
            expiresAt: nil
        ),
    ]

    // MARK: - Mock Sections

    static let sections: [Section] = [
        Section(
            id: UUID(),
            userId: UUID(),
            slug: "home",
            displayName: "Home",
            sortOrder: 0,
            isVisible: true,
            config: nil,
            createdAt: Date.now.addingTimeInterval(-86400 * 30),
            updatedAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Section(
            id: UUID(),
            userId: UUID(),
            slug: "health",
            displayName: "Health",
            sortOrder: 1,
            isVisible: true,
            config: nil,
            createdAt: Date.now.addingTimeInterval(-86400 * 30),
            updatedAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Section(
            id: UUID(),
            userId: UUID(),
            slug: "deliveries",
            displayName: "Deliveries",
            sortOrder: 2,
            isVisible: true,
            config: nil,
            createdAt: Date.now.addingTimeInterval(-86400 * 30),
            updatedAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Section(
            id: UUID(),
            userId: UUID(),
            slug: "calendar",
            displayName: "Calendar",
            sortOrder: 3,
            isVisible: true,
            config: nil,
            createdAt: Date.now.addingTimeInterval(-86400 * 30),
            updatedAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Section(
            id: UUID(),
            userId: UUID(),
            slug: "bookmarks",
            displayName: "Bookmarks",
            sortOrder: 4,
            isVisible: true,
            config: nil,
            createdAt: Date.now.addingTimeInterval(-86400 * 30),
            updatedAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Section(
            id: UUID(),
            userId: UUID(),
            slug: "admin",
            displayName: "Admin",
            sortOrder: 5,
            isVisible: true,
            config: nil,
            createdAt: Date.now.addingTimeInterval(-86400 * 30),
            updatedAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
        Section(
            id: UUID(),
            userId: UUID(),
            slug: "legal",
            displayName: "Legal",
            sortOrder: 6,
            isVisible: true,
            config: nil,
            createdAt: Date.now.addingTimeInterval(-86400 * 30),
            updatedAt: Date.now.addingTimeInterval(-86400 * 30)
        ),
    ]

    // MARK: - All Mock Records Combined

    static let allRecords: [Record] = measurementRecords + deliveryRecords + bookmarkRecords + eventRecords + costSummaryRecords + checklistRecords
}
#endif
