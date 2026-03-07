import SwiftUI

/// Dispatches to the correct card view based on a Record's displayHint.
///
/// When `isInteractive` is true, we also show a small "details" affordance that opens
/// an in-app detail view without breaking internal gestures (charts, toggles, etc.).
struct WidgetRouter: View {
    let record: Record

    /// Optional: additional records of the same type for chart aggregation
    var relatedRecords: [Record] = []

    /// When false, disables the detail affordance (used inside RecordDetailView to avoid recursion)
    var isInteractive: Bool = true

    @State private var showDetail = false

    var body: some View {
        cardWithDetailOverlay {
            routedContent
        }
        .sheet(isPresented: $showDetail) {
            NavigationStack {
                RecordDetailView(record: record)
            }
        }
    }

    // MARK: - Routing

    @ViewBuilder
    private var routedContent: some View {
        switch record.displayHint {
        case .chart:
            chartView

        case .singleValue:
            singleValueView

        case .statusList:
            statusListView

        case .timeline:
            timelineView

        case .checklist:
            checklistView

        case .costBreakdown:
            costBreakdownView

        case .bookmarkCard:
            bookmarkCardView

        case .bookmarkGrid:
            // Not implemented yet; treat as single bookmark
            bookmarkCardView

        case .progressGauge:
            progressGaugeView

        case .macrosBar:
            macrosBarView
        }
    }

    @ViewBuilder
    private func cardWithDetailOverlay(@ViewBuilder content: () -> some View) -> some View {
        ZStack(alignment: .topTrailing) {
            content()

            if isInteractive {
                Button {
                    PerchHaptics.selection()
                    showDetail = true
                } label: {
                    Image(systemName: "info.circle.fill")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.accent)
                        .padding(8)
                        .background(PerchTheme.cardBackground.opacity(0.95))
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(PerchTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(10)
                .accessibilityLabel("Show details")
            }
        }
    }

    // MARK: - Card Views

    @ViewBuilder
    private var chartView: some View {
        if let measurementData = record.asMeasurement() {
            // Use related records if provided (for multi-point charts), otherwise single record
            let chartRecords = relatedRecords.isEmpty ? [record] : relatedRecords
            ChartCard(
                title: record.title,
                records: chartRecords,
                unit: measurementData.unit
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var singleValueView: some View {
        if let measurementData = record.asMeasurement() {
            SingleValueCard(
                value: String(format: "%.1f", measurementData.value),
                label: record.title,
                unit: measurementData.unit,
                trend: nil,
                lastUpdated: record.updatedAt
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var statusListView: some View {
        if let deliveryData = record.asDelivery() {
            DeliveryCard(delivery: deliveryData)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var timelineView: some View {
        if let eventData = record.asEvent() {
            EventCard(event: eventData)
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var checklistView: some View {
        if let checklistData = record.asChecklist() {
            ChecklistCard(
                title: record.title,
                items: checklistData.items
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var costBreakdownView: some View {
        if let costData = record.asCostSummary() {
            let items = costData.breakdown.map { agentId, cost in
                let emoji = agentEmojiForId(agentId)
                return CostBreakdownCard.AgentCost(
                    id: agentId,
                    agentId: agentId,
                    agentEmoji: emoji,
                    agentName: agentNameForId(agentId),
                    cost: cost
                )
            }

            CostBreakdownCard(
                totalCost: costData.totalCostUsd,
                breakdown: items.sorted { $0.cost > $1.cost },
                dateRange: costData.period.capitalized
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var bookmarkCardView: some View {
        if let bookmarkData = record.asBookmark() {
            BookmarkCard(
                bookmark: bookmarkData,
                onTap: {
                    if let url = URL(string: bookmarkData.url) {
                        UIApplication.shared.open(url)
                    }
                }
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var progressGaugeView: some View {
        if let measurement = record.asMeasurement() {
            if let target = measurement.target {
                CaloriesCard(
                    consumed: measurement.value,
                    target: target,
                    unit: measurement.unit,
                    lastUpdated: record.updatedAt
                )
            } else {
                // No target set yet — show as a single value card instead of nothing
                SingleValueCard(
                    value: String(format: "%.0f", measurement.value),
                    label: record.title,
                    unit: measurement.unit,
                    trend: nil,
                    lastUpdated: record.updatedAt
                )
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var macrosBarView: some View {
        if let macros = record.asMacros() {
            MacrosCard(
                protein: macros.protein,
                proteinTarget: macros.proteinTarget,
                carbs: macros.carbs,
                carbsTarget: macros.carbsTarget,
                fat: macros.fat,
                fatTarget: macros.fatTarget,
                lastUpdated: record.updatedAt
            )
        } else {
            EmptyView()
        }
    }

    // MARK: - Helper Functions

    private func agentEmojiForId(_ agentId: String) -> String {
        switch agentId {
        case "claudinho": return "🤖"
        case "biochecha": return "💊"
        case "entregas": return "📦"
        case "calendario": return "📅"
        case "legal": return "⚖️"
        case "archie": return "📚"
        default: return "⚙️"
        }
    }

    private func agentNameForId(_ agentId: String) -> String {
        switch agentId {
        case "claudinho": return "Claudinho"
        case "biochecha": return "BioChecha"
        case "entregas": return "Entregas"
        case "calendario": return "Calendario"
        case "legal": return "Legal"
        case "archie": return "Archie"
        default: return agentId.capitalized
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: PerchTheme.Spacing.medium) {
        WidgetRouter(record: MockData.measurementRecords[0])
        WidgetRouter(record: MockData.deliveryRecords[0])
        WidgetRouter(record: MockData.bookmarkRecords[0])
    }
    .padding(PerchTheme.Spacing.medium)
    .background(PerchTheme.background)
    .ignoresSafeArea()
}
