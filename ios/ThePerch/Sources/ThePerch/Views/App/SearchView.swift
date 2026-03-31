import SwiftUI

/// Global search view that searches across all record types.
/// Shows condensed result cards grouped by category.
struct SearchView: View {
    @Binding var searchText: String
    let records: [Record]

    @State private var selectedCategory: RecordCategory?

    var filteredRecords: [Record] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        var results = records.filter { record in
            // Search title
            if record.title.lowercased().contains(query) { return true }
            // Search category/type names
            if record.category.displayName.lowercased().contains(query) { return true }
            if record.type.displayName.lowercased().contains(query) { return true }
            // Search data-specific fields
            if let delivery = record.asDelivery() {
                if delivery.carrier.lowercased().contains(query) { return true }
                if delivery.items.contains(where: { $0.name.lowercased().contains(query) }) { return true }
                if delivery.trackingNumber.lowercased().contains(query) { return true }
            }
            if let event = record.asEvent() {
                if event.title.lowercased().contains(query) { return true }
                if event.location?.lowercased().contains(query) == true { return true }
            }
            if let bookmark = record.asBookmark() {
                if bookmark.displayTitle.lowercased().contains(query) { return true }
                if bookmark.domain?.lowercased().contains(query) == true { return true }
                if bookmark.summary?.lowercased().contains(query) == true { return true }
                if bookmark.tags.contains(where: { $0.lowercased().contains(query) }) { return true }
            }
            if let measurement = record.asMeasurement() {
                if measurement.metric.lowercased().contains(query) { return true }
            }
            return false
        }

        // Filter by selected category
        if let category = selectedCategory {
            results = results.filter { $0.category == category }
        }

        return results
    }

    var matchingCategories: [RecordCategory] {
        guard !searchText.isEmpty else { return [] }
        let query = searchText.lowercased()
        let categories = Set(records.filter { record in
            record.title.lowercased().contains(query) ||
            record.category.displayName.lowercased().contains(query)
        }.map { $0.category })
        return Array(categories).sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category filter chips
            if !matchingCategories.isEmpty && !searchText.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        // "All" chip
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

            // Results
            if searchText.isEmpty {
                // Empty search state
                Spacer()
            } else if filteredRecords.isEmpty {
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
                        ForEach(filteredRecords) { record in
                            SearchResultRow(record: record)
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

/// A condensed card for search results showing type icon, title, category, and age.
struct SearchResultRow: View {
    let record: Record

    var body: some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            // Type icon
            RoundedRectangle(cornerRadius: 8)
                .fill(PerchTheme.accentMuted)
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: iconForType)
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.accent)
                )

            // Title + subtitle
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

            // Category badge
            Text(record.category.displayName)
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textSecondary)
                .padding(.horizontal, PerchTheme.Spacing.xSmall)
                .padding(.vertical, 3)
                .background(PerchTheme.cardInnerBackground)
                .cornerRadius(6)

            // Age
            Text(record.relativeTime)
                .font(PerchTheme.Font.micro)
                .foregroundColor(PerchTheme.textTertiary)
        }
        .padding(.horizontal, PerchTheme.Spacing.medium)
        .padding(.vertical, PerchTheme.Spacing.small)
        .background(PerchTheme.cardBackground)
        .cornerRadius(12)
        .onTapGesture(perform: handleTap)
    }

    private var displayTitle: String {
        if let bookmark = record.asBookmark() { return bookmark.displayTitle }
        if let delivery = record.asDelivery() { return delivery.items.first?.name ?? record.title }
        if let event = record.asEvent() { return event.title }
        return record.title
    }

    private var subtitle: String {
        if let delivery = record.asDelivery() { return "\(delivery.carrier) - \(delivery.status)" }
        if let event = record.asEvent() {
            return PerchFormatters.eventDateTime.string(from: event.start)
        }
        if let bookmark = record.asBookmark() { return bookmark.domain ?? bookmark.url }
        if let measurement = record.asMeasurement() {
            return "\(String(format: "%.1f", measurement.value)) \(measurement.unit)"
        }
        return record.type.displayName
    }

    private var iconForType: String {
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

    private func handleTap() {
        if let bookmark = record.asBookmark(), let url = URL(string: bookmark.url) {
            UIApplication.shared.open(url)
        } else if let delivery = record.asDelivery(),
                  let urlStr = delivery.trackingUrl,
                  let url = URL(string: urlStr) {
            UIApplication.shared.open(url)
        } else if let event = record.asEvent() {
            let interval = event.start.timeIntervalSinceReferenceDate
            if let url = URL(string: "calshow:\(interval)") {
                UIApplication.shared.open(url)
            }
        }
    }
}
