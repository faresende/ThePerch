import Foundation
import Observation

// MARK: - BookmarksViewModel

/// Manages the state for BookmarksView, independently fetching from Karakeep API.
/// Provides loading, error, search, and tag-filtering states for both
/// Karakeep and Paperless tabs.
@Observable
@MainActor
final class BookmarksViewModel {
    // MARK: - Published State

    /// Bookmarks from Karakeep API (decoded as KarakeepBookmark).
    var karakeepBookmarks: [KarakeepBookmark] = []

    /// The currently selected bookmark source tab.
    var selectedTab: BookmarkSource = .karakeep

    /// Whether a network request is in flight.
    var isLoading: Bool = false

    /// The most recent error, if any.
    var error: String?

    /// The user's search query.
    var searchQuery: String = ""

    /// Tags currently selected for filtering.
    var selectedTags: Set<String> = []

    /// Whether the data has been loaded at least once.
    private(set) var hasLoaded: Bool = false

    // MARK: - Private

    private let karakeepService: KarakeepService

    // MARK: - Initialization

    init(karakeepService: KarakeepService = .shared) {
        self.karakeepService = karakeepService
    }

    // MARK: - Computed: All Tags

    /// All unique tags across the currently loaded Karakeep bookmarks.
    var allTags: [String] {
        Array(Set(karakeepBookmarks.flatMap { $0.tags })).sorted()
    }

    // MARK: - Computed: Filtered Bookmarks (Karakeep tab)

    /// Karakeep bookmarks filtered by search query and selected tags.
    var filteredKarakeepBookmarks: [KarakeepBookmark] {
        karakeepBookmarks.filter { bookmark in
            let matchesSearch = searchQuery.isEmpty ||
                bookmark.displayTitle.localizedCaseInsensitiveContains(searchQuery) ||
                (bookmark.summary?.localizedCaseInsensitiveContains(searchQuery) ?? false) ||
                (bookmark.domain?.localizedCaseInsensitiveContains(searchQuery) ?? false)

            let matchesTags = selectedTags.isEmpty ||
                selectedTags.allSatisfy { bookmark.tags.contains($0) }

            return matchesSearch && matchesTags
        }
    }

    // MARK: - Computed: Partitioned by Status

    var pendingKarakeepBookmarks: [KarakeepBookmark] {
        filteredKarakeepBookmarks.filter {
            $0.status == .pending || $0.status == .processing
        }
    }

    var processedKarakeepBookmarks: [KarakeepBookmark] {
        filteredKarakeepBookmarks.filter { $0.status == .processed }
    }

    // MARK: - Computed: Tab Records

    /// Whether the Karakeep tab has any bookmarks at all (before filtering).
    var karakeepTabHasRecords: Bool {
        !karakeepBookmarks.isEmpty
    }

    /// Whether the Paperless tab has any records (delegated to DashboardViewModel).
    var paperlessTabHasRecords: Bool {
        false // Paperless uses DashboardViewModel.bookmarkRecords directly
    }

    // MARK: - Loading

    /// Loads bookmarks from the Karakeep API with retry logic.
    /// Sets `isLoading` and `error` appropriately.
    func loadBookmarks() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil

        var lastError: Error?
        let maxRetries = 3
        let baseDelay: TimeInterval = 1.0

        for attempt in 0..<maxRetries {
            do {
                karakeepBookmarks = try await karakeepService.fetchBookmarks(limit: 500)
                hasLoaded = true
                isLoading = false
                return
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = baseDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // All retries exhausted
        isLoading = false
        hasLoaded = true
        error = lastError?.localizedDescription ?? "Failed to load bookmarks"
    }

    /// Searches bookmarks using the Karakeep search API.
    /// Falls back to local filtering if the search request fails.
    func search() async {
        guard !searchQuery.isEmpty else {
            // If query is cleared, just reload all
            await loadBookmarks()
            return
        }

        isLoading = true
        error = nil

        do {
            karakeepBookmarks = try await karakeepService.searchBookmarks(query: searchQuery)
            hasLoaded = true
        } catch {
            // Fall back to local filtering — don't show error, just filter what we have
            // (user may have bookmarks loaded from a prior fetch)
            #if DEBUG
            print("[BookmarksViewModel] Search API failed, using local filter: \(error.localizedDescription)")
            #endif
        }

        isLoading = false
    }

    /// Filters bookmarks by the given tags.
    /// Tags are ANDed — a bookmark must have all selected tags.
    func filterByTags(_ tags: Set<String>) {
        selectedTags = tags
    }

    /// Toggles a single tag in/out of the selected set.
    func toggleTag(_ tag: String) {
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }

    /// Clears any error state.
    func clearError() {
        error = nil
    }

    /// Clears the search query and reloads.
    func clearSearch() {
        searchQuery = ""
    }

    /// Returns true if the Karakeep tab should show the empty state.
    func shouldShowEmptyState(for tab: BookmarkSource) -> Bool {
        switch tab {
        case .karakeep:
            return !isLoading && karakeepBookmarks.isEmpty && hasLoaded
        case .paperless:
            // Paperless empty state is handled by DashboardViewModel in BookmarksView
            return false
        }
    }

    /// Returns true if the Karakeep tab should show the loading skeleton.
    func shouldShowLoadingState(for tab: BookmarkSource) -> Bool {
        switch tab {
        case .karakeep:
            return isLoading && karakeepBookmarks.isEmpty
        case .paperless:
            return false // Handled by DashboardViewModel in BookmarksView
        }
    }
}
