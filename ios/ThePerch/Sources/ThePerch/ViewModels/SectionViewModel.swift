import Foundation
import Observation

// MARK: - SectionViewModel

/// Manages the state of a single category section.
/// Records are fed from DashboardViewModel (single-fetch architecture).
/// Handles filtering, sorting, and grouping of records.
@Observable
@MainActor
final class SectionViewModel {
    // MARK: - Published Properties

    var records: [Record] = []
    var groupedRecords: [RecordType: [Record]] = [:]
    var isLoading: Bool = false
    var error: SupabaseServiceError?
    let category: RecordCategory

    // MARK: - Private Properties

    private var sortOrder: SortOrder = .newestFirst

    // MARK: - Sort Order

    enum SortOrder {
        case newestFirst
        case oldestFirst
        case titleAtoZ
    }

    // MARK: - Initialization

    init(category: RecordCategory) {
        self.category = category
    }

    // MARK: - Updating Data (fed from DashboardViewModel)

    /// Called when DashboardViewModel provides new records for this category.
    func updateRecords(_ newRecords: [Record]) {
        self.records = newRecords
        self.groupedRecords = groupRecordsByType(newRecords)
        self.error = nil
    }

    // MARK: - Sorting & Grouping

    /// Groups records by their type.
    private func groupRecordsByType(_ records: [Record]) -> [RecordType: [Record]] {
        var grouped: [RecordType: [Record]] = [:]
        for record in records {
            if grouped[record.type] == nil {
                grouped[record.type] = []
            }
            grouped[record.type]?.append(record)
        }
        return grouped
    }

    /// Sorts the current records based on the sort order.
    func setSortOrder(_ order: SortOrder) {
        self.sortOrder = order
        applySorting()
    }

    /// Applies the current sort order to the records.
    private func applySorting() {
        switch sortOrder {
        case .newestFirst:
            records.sort { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            records.sort { $0.createdAt < $1.createdAt }
        case .titleAtoZ:
            records.sort { $0.title.lowercased() < $1.title.lowercased() }
        }
        groupedRecords = groupRecordsByType(records)
    }

    // MARK: - Filtering

    /// Filters records by type.
    /// - Parameter type: The RecordType to filter by.
    /// - Returns: An array of records matching the type.
    func recordsForType(_ type: RecordType) -> [Record] {
        records.filter { $0.type == type }
    }

    /// Filters records by search query (searches title and data).
    /// - Parameter query: The search query string.
    /// - Returns: An array of records matching the query.
    func search(_ query: String) -> [Record] {
        guard !query.isEmpty else { return records }
        let lowercasedQuery = query.lowercased()
        return records.filter { record in
            record.title.lowercased().contains(lowercasedQuery)
        }
    }

    /// Returns pinned records (sorted to the top).
    var pinnedRecords: [Record] {
        records.filter { $0.pinned }
    }

    /// Returns unpinned records.
    var unpinnedRecords: [Record] {
        records.filter { !$0.pinned }
    }

    // MARK: - Error Handling

    /// Clears any error messages.
    func clearError() {
        self.error = nil
    }
}
