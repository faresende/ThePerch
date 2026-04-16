import SwiftUI

private enum SearchResultItem: Identifiable {
    case record(Record)
    case delivery(DeliveryData)

    var id: String {
        switch self {
        case .record(let record):
            return "record-\(record.id.uuidString)"
        case .delivery(let delivery):
            return "delivery-\(delivery.orderId)"
        }
    }

    var category: RecordCategory {
        switch self {
        case .record(let record):
            return record.category
        case .delivery:
            return .deliveries
        }
    }
}

/// Global search view that searches across all record types.
/// Shows condensed result cards grouped by category.
struct SearchView: View {
    @Binding var searchText: String
    let records: [Record]
    let deliveries: [DeliveryData]

    @State private var selectedCategory: RecordCategory?

    init(searchText: Binding<String>, records: [Record], deliveries: [DeliveryData] = []) {
        self._searchText = searchText
        self.records = records
        self.deliveries = deliveries
    }

    private var filteredResults: [SearchResultItem] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()

        var results: [SearchResultItem] = records.compactMap { record in
            if record.title.lowercased().contains(query) { return .record(record) }
            if record.category.displayName.lowercased().contains(query) { return .record(record) }
            if record.type.displayName.lowercased().contains(query) { return .record(record) }

            if let event = record.asEvent() {
                if event.title.lowercased().contains(query) { return .record(record) }
                if event.location?.lowercased().contains(query) == true { return .record(record) }
            }
            if let bookmark = record.asBookmark() {
                if bookmark.displayTitle.lowercased().contains(query) { return .record(record) }
                if bookmark.domain?.lowercased().contains(query) == true { return .record(record) }
                if bookmark.summary?.lowercased().contains(query) == true { return .record(record) }
                if bookmark.tags.contains(where: { $0.lowercased().contains(query) }) { return .record(record) }
            }
            if let measurement = record.asMeasurement(), measurement.metric.lowercased().contains(query) {
                return .record(record)
            }
            return nil
        }

        let deliveryResults = deliveries.compactMap { delivery -> SearchResultItem? in
            if delivery.carrier.lowercased().contains(query) { return .delivery(delivery) }
            if delivery.items.contains(where: { $0.name.lowercased().contains(query) }) { return .delivery(delivery) }
            if delivery.trackingNumber.lowercased().contains(query) { return .delivery(delivery) }
            if delivery.status.lowercased().contains(query) { return .delivery(delivery) }
            return nil
        }
        results.append(contentsOf: deliveryResults)

        if let category = selectedCategory {
            results = results.filter { $0.category == category }
        }

        return results
    }

    var matchingCategories: [RecordCategory] {
        guard !searchText.isEmpty else { return [] }
        let categories = Set(filteredResults.map(\.category))
        return Array(categories).sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !matchingCategories.isEmpty && !searchText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Button {
                            selectedCategory = nil
                        } label: {
                            Text("All")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(selectedCategory == nil ? .black : PerchTheme.accent)
                                .padding(.horizontal, PerchTheme.Spacing.small)
                                .padding(.vertical, 6)
                                .background(selectedCategory == nil ? PerchTheme.accent : PerchTheme.accentMuted)
                                .cornerRadius(8)
                        }

                        ForEach(matchingCategories, id: \.self) { category in
                            Button {
                                selectedCategory = selectedCategory == category ? nil : category
                            } label: {
                                Text(category.displayName)
                                    .font(PerchTheme.Font.caption)
                                    .foregroundColor(selectedCategory == category ? .black : PerchTheme.accent)
                                    .padding(.horizontal, PerchTheme.Spacing.small)
                                    .padding(.vertical, 6)
                                    .background(selectedCategory == category ? PerchTheme.accent : PerchTheme.accentMuted)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)
                }
                .padding(.vertical, PerchTheme.Spacing.xSmall)
            }

            if searchText.isEmpty {
                Spacer()
            } else if filteredResults.isEmpty {
                VStack(spacing: PerchTheme.Spacing.small) {
                    Image(systemName: "magnifyingglass")
                        .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                        .foregroundColor(PerchTheme.textTertiary)
                    Text("No results for \"\(searchText)\"")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                ScrollView {
                    LazyVStack(spacing: PerchTheme.Spacing.small) {
                        ForEach(filteredResults) { item in
                            SearchResultRow(item: item)
                        }
                    }
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.vertical, PerchTheme.Spacing.small)
                }
            }
        }
    }
}

// MARK: - Search Result Row

/// A condensed card for search results showing type icon, title, category, and metadata.
private struct SearchResultRow: View {
    let item: SearchResultItem

    var body: some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            RoundedRectangle(cornerRadius: 8)
                .fill(PerchTheme.accentMuted)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: iconForItem)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.accent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textPrimary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(PerchTheme.Font.micro)
                    .foregroundColor(PerchTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(item.category.displayName)
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textSecondary)
                .padding(.horizontal, PerchTheme.Spacing.xSmall)
                .padding(.vertical, 3)
                .background(PerchTheme.cardInnerBackground)
                .cornerRadius(6)

            if !metadataText.isEmpty {
                Text(metadataText)
                    .font(PerchTheme.Font.micro)
                    .foregroundColor(PerchTheme.textTertiary)
            }
        }
        .padding(.horizontal, PerchTheme.Spacing.medium)
        .padding(.vertical, PerchTheme.Spacing.small)
        .background(PerchTheme.cardBackground)
        .cornerRadius(12)
        .onTapGesture(perform: handleTap)
    }

    private var displayTitle: String {
        switch item {
        case .record(let record):
            if let bookmark = record.asBookmark() { return bookmark.displayTitle }
            if let event = record.asEvent() { return event.title }
            return record.title
        case .delivery(let delivery):
            return delivery.items.first?.name ?? delivery.carrier
        }
    }

    private var subtitle: String {
        switch item {
        case .record(let record):
            if let event = record.asEvent() {
                return PerchFormatters.eventDateTime.string(from: event.start)
            }
            if let bookmark = record.asBookmark() {
                return bookmark.domain ?? bookmark.url
            }
            if let measurement = record.asMeasurement() {
                return "\(String(format: "%.1f", measurement.value)) \(measurement.unit)"
            }
            return record.type.displayName
        case .delivery(let delivery):
            return "\(delivery.carrier) - \(delivery.status)"
        }
    }

    private var metadataText: String {
        switch item {
        case .record(let record):
            return record.relativeTime
        case .delivery(let delivery):
            guard !delivery.trackingNumber.isEmpty else { return "" }
            return "#\(String(delivery.trackingNumber.suffix(6)))"
        }
    }

    private var iconForItem: String {
        switch item {
        case .delivery:
            return "shippingbox"
        case .record(let record):
            switch record.type {
            case .delivery: return "shippingbox"
            case .event: return "calendar"
            case .bookmark: return "bookmark"
            case .measurement: return "heart"
            case .meal: return "fork.knife"
            case .status: return "circle.fill"
            case .reminder: return "bell"
            case .textNote: return "note.text"
            case .checklist: return "checklist"
            case .costSummary: return "dollarsign.circle"
            case .command: return "terminal"
            case .trip: return "airplane"
            case .itinerary: return "map"
            case .travelAlert: return "exclamationmark.triangle"
            case .weatherForecast: return "cloud.sun"
            case .travelTask: return "checklist"
            case .workoutSession: return "dumbbell"
            case .calendarEvent: return "calendar"
            case .unknown: return "questionmark.circle"
            }
        }
    }

    private func handleTap() {
        switch item {
        case .record(let record):
            if let bookmark = record.asBookmark(), let url = URL(string: bookmark.url) {
                UIApplication.shared.open(url)
            } else if let event = record.asEvent() {
                let interval = event.start.timeIntervalSinceReferenceDate
                if let url = URL(string: "calshow:\(interval)") {
                    UIApplication.shared.open(url)
                }
            }
        case .delivery(let delivery):
            if let urlStr = delivery.trackingUrl, let url = URL(string: urlStr) {
                UIApplication.shared.open(url)
            }
        }
    }
}
