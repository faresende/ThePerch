import SwiftUI

struct CardRendererFactory {
    @ViewBuilder
    static func view(for record: Record) -> some View {
        switch record.displayHint {
        case .singleValue:
            MetricCardRenderer(record: record)
        case .checklist:
            ChecklistCardRenderer(record: record)
        case .timeline:
            TimelineCardRenderer(record: record)
        case .statusList:
            StatusCardRenderer(record: record)
        default:
            // Fallback to existing specialized card views (legacy)
            // If no dedicated universal renderer exists yet, show a simple text card.
            TextCardRenderer(record: record)
        }
    }
}
