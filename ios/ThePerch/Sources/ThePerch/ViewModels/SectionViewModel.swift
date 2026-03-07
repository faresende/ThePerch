import Foundation
import Observation

// MARK: - SectionViewModel

/// Manages the state of a single category section.
/// Handles fetching, filtering, sorting, and grouping of records.
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

    private let supabaseService: SupabaseService
    private var sortOrder: SortOrder = .newestFirst

    // MARK: - Sort Order

    enum SortOrder {
        case newestFirst
        case oldestFirst
        case titleAtoZ
    }

    // MARK: - Initialization

    init(
        category: RecordCategory,
        supabaseService: SupabaseService = .shared
    ) {
        self.category = category
        self.supabaseService = supabaseService
    }

    // MARK: - Loading Data

    /// Loads records for the section's category.
    func loadRecords(forceRefresh: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedRecords = try await supabaseService.fetchRecords(
                category: category,
                limit: 100,
                forceRefresh: forceRefresh
            )
            self.records = loadedRecords
            self.groupedRecords = groupRecordsByType(loadedRecords)
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Refreshes the records by force-reloading from the server.
    func refresh() async {
        await loadRecords(forceRefresh: true)
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

    // MARK: - Record Actions

    /// Toggles the pinned state of a record.
    /// - Parameter recordId: The ID of the record to toggle.
    func togglePin(recordId: UUID) async {
        guard let index = records.firstIndex(where: { $0.id == recordId }) else { return }

        let newPinnedState = !records[index].pinned
        do {
            try await supabaseService.updateRecordPin(id: recordId, pinned: newPinnedState)
            records[index].pinned = newPinnedState
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
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
