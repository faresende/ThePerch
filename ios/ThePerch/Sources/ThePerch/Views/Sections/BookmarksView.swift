import SwiftUI

/// Bookmarks section with Karakeep/Paperless tabs, search, and filtering.
/// Karakeep tab uses BookmarksViewModel + KarakeepService for reliable direct API access.
/// Paperless tab reads records from DashboardViewModel (single-fetch architecture).
struct BookmarksView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @Environment(DeepLinkState.self) private var deepLinkState

    @State private var viewModel = BookmarksViewModel()
    @State private var selectedTab: BookmarkSource = .karakeep

    private var records: [Record] { dashboardViewModel.bookmarkRecords }

    // MARK: - Filtered Data (single-pass decode)

    /// Pre-computed bookmark view data: decodes each record once, then filters/partitions.
    private var bookmarkData: (
        allTags: [String],
        filtered: [Record],
        pending: [Record],
        processed: [Record]
    ) {
        // Karakeep tab uses BookmarksViewModel (direct API) — handled separately below
        // Paperless tab uses Record-based decoding (existing architecture)
        guard selectedTab == .paperless else {
            // Return empty — Karakeep tab renders from viewModel directly
            return ([], [], [], [])
        }

        // Step 1: filter to active tab (single decode per record)
        var tabRecords: [(Record, BookmarkData)] = []
        for record in records {
            guard let bookmark = record.asBookmark() else { continue }
            let source = bookmark.source ?? .karakeep
            if source == selectedTab {
                tabRecords.append((record, bookmark))
            }
        }

        // Step 2: collect all tags from tab records
        var tagSet = Set<String>()
        for (_, bookmark) in tabRecords {
            for tag in bookmark.tags { tagSet.insert(tag) }
        }
        let sortedTags = tagSet.sorted()

        // Step 3: apply search + tag filters
        var filtered: [Record] = []
        var pending: [Record] = []
        var processed: [Record] = []
        for (record, bookmark) in tabRecords {
            let matchesSearch = viewModel.searchQuery.isEmpty ||
                bookmark.displayTitle.localizedCaseInsensitiveContains(viewModel.searchQuery) ||
                (bookmark.summary?.localizedCaseInsensitiveContains(viewModel.searchQuery) ?? false) ||
                (bookmark.fileName?.localizedCaseInsensitiveContains(viewModel.searchQuery) ?? false)

            let matchesTags = viewModel.selectedTags.isEmpty ||
                viewModel.selectedTags.allSatisfy { bookmark.tags.contains($0) }

            guard matchesSearch && matchesTags else { continue }
            filtered.append(record)

            if bookmark.status == .pending || bookmark.status == .processing {
                pending.append(record)
            } else if bookmark.status == .processed {
                processed.append(record)
            }
        }

        return (sortedTags, filtered, pending, processed)
    }

    private var karakeepData: (
        allTags: [String],
        pending: [KarakeepBookmark],
        processed: [KarakeepBookmark],
        count: Int
    ) {
        let pending = viewModel.pendingKarakeepBookmarks
        let processed = viewModel.processedKarakeepBookmarks
        let allTags = viewModel.allTags
        return (allTags, pending, processed, pending.count + processed.count)
    }

    var allTags: [String] {
        selectedTab == .karakeep ? karakeepData.allTags : bookmarkData.allTags
    }

    private var tabCount: Int {
        selectedTab == .karakeep ? karakeepData.count : bookmarkData.filtered.count
    }

    /// Whether the current tab has any records (before search/tag filter).
    private var tabHasRecords: Bool {
        if selectedTab == .karakeep {
            return viewModel.karakeepTabHasRecords
        }
        return records.contains { record in
            guard let bookmark = record.asBookmark() else { return false }
            return (bookmark.source ?? .karakeep) == selectedTab
        }
    }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Section header with count
                SectionHeader(title: "Bookmarks", freshnessKey: "bookmarks")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.top, PerchTheme.Spacing.medium)
                    .padding(.bottom, PerchTheme.Spacing.small)

                // Error banner
                if dashboardViewModel.error != nil {
                    ErrorBanner(
                        message: "Failed to load bookmarks",
                        retryAction: { Task { await dashboardViewModel.loadDashboard(forceRefresh: true) } },
                        onDismiss: { dashboardViewModel.clearError() }
                    )
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.bottom, PerchTheme.Spacing.small)
                }

                // Tab picker + search + tags
                VStack(spacing: PerchTheme.Spacing.medium) {
                    // Segmented picker for Karakeep / Paperless
                    Picker("Source", selection: $selectedTab) {
                        Text("Karakeep").tag(BookmarkSource.karakeep)
                        Text("Paperless").tag(BookmarkSource.paperless)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedTab) { _, _ in
                        PerchHaptics.selection()
                        viewModel.selectedTags.removeAll()
                        viewModel.searchQuery = ""
                    }

                    // Search bar
                    HStack(spacing: PerchTheme.Spacing.small) {
                        Image(systemName: "magnifyingglass")
                            .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                            .foregroundColor(PerchTheme.textSecondary)

                        TextField(
                            selectedTab == .karakeep ? "Search bookmarks" : "Search documents",
                            text: $viewModel.searchQuery
                        )
                        .autocorrectionDisabled()

                        if !viewModel.searchQuery.isEmpty {
                            Button(action: { viewModel.clearSearch() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                                    .foregroundColor(PerchTheme.textTertiary)
                            }
                        }
                    }
                    .padding(PerchTheme.Spacing.small)
                    .background(PerchTheme.cardBackground)
                    .cornerRadius(PerchTheme.Card.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                            .stroke(PerchTheme.border, lineWidth: 1)
                    )

                    // Tag filters
                    if !allTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: PerchTheme.Spacing.xSmall) {
                                ForEach(allTags, id: \.self) { tag in
                                    Button(action: { viewModel.toggleTag(tag) }) {
                                        Text(tag)
                                            .font(PerchTheme.Font.caption)
                                            .foregroundColor(
                                                viewModel.selectedTags.contains(tag)
                                                    ? .white
                                                    : PerchTheme.accent
                                            )
                                            .padding(.horizontal, PerchTheme.Spacing.small)
                                            .padding(.vertical, PerchTheme.Spacing.xxSmall)
                                            .background(
                                                viewModel.selectedTags.contains(tag)
                                                    ? PerchTheme.accent
                                                    : PerchTheme.accent.opacity(0.1)
                                            )
                                            .cornerRadius(4)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(PerchTheme.Spacing.large)
                .background(PerchTheme.background)

                // Content
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                        // Loading state
                        if shouldShowLoadingState {
                            SkeletonCardsSection(count: 3)
                                .padding(.horizontal, PerchTheme.Spacing.large)
                        }
                        // Error state (Karakeep tab)
                        else if selectedTab == .karakeep, let error = viewModel.error {
                            ErrorBanner(
                                message: error,
                                retryAction: { Task { await viewModel.loadBookmarks() } },
                                onDismiss: { viewModel.clearError() }
                            )
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }
                        // Error state (Paperless tab)
                        else if selectedTab == .paperless, dashboardViewModel.error != nil {
                            ErrorBanner(
                                message: "Failed to load documents",
                                retryAction: { Task { await dashboardViewModel.loadDashboard(forceRefresh: true) } },
                                onDismiss: { dashboardViewModel.clearError() }
                            )
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }
                        // Karakeep tab content
                        else if selectedTab == .karakeep {
                            karakeepContent
                        }
                        // Paperless tab content
                        else {
                            paperlessContent
                        }

                        Spacer()
                            .frame(height: PerchTheme.Spacing.large)
                    }
                }
                .refreshable {
                    PerchHaptics.medium()
                    if selectedTab == .karakeep {
                        await viewModel.loadBookmarks()
                    } else {
                        await dashboardViewModel.loadDashboard(forceRefresh: true)
                    }
                    PerchHaptics.success()
                }
            }
        }
        .onAppear {
            // Load Karakeep bookmarks when the view first appears
            if !viewModel.hasLoaded {
                Task { await viewModel.loadBookmarks() }
            }
        }
        .onChange(of: deepLinkState.pendingDestination) { _, dest in
            // Hand-off from HubTab: theperch://bookmarks?source=karakeep|paperless
            // maps the source onto the segment. We accept destination-less
            // bookmarks (no source) as "leave the default in place".
            if case .bookmarks(let source) = dest {
                if let raw = source?.rawValue, let s = BookmarkSource(rawValue: raw) {
                    selectedTab = s
                }
                deepLinkState.consume()
            }
        }
    }

    // MARK: - State Helpers

    private var shouldShowLoadingState: Bool {
        if selectedTab == .karakeep {
            return viewModel.isLoading && viewModel.karakeepBookmarks.isEmpty
        }
        return dashboardViewModel.isLoading && records.isEmpty
    }

    private var shouldShowEmptyState: Bool {
        if selectedTab == .karakeep {
            return !viewModel.isLoading && viewModel.karakeepBookmarks.isEmpty && viewModel.hasLoaded
        }
        return !dashboardViewModel.isLoading && records.isEmpty &&
            !records.contains { record in
                guard let bookmark = record.asBookmark() else { return false }
                return (bookmark.source ?? .karakeep) == selectedTab
            }
    }

    // MARK: - Karakeep Content

    @ViewBuilder
    private var karakeepContent: some View {
        // Count indicator
        if !viewModel.filteredKarakeepBookmarks.isEmpty {
            Text("\(karakeepData.count) bookmark\(karakeepData.count == 1 ? "" : "s")")
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)
                .padding(.horizontal, PerchTheme.Spacing.large)
        }

        // Pending/processing bookmarks
        if !karakeepData.pending.isEmpty {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                Text("Processing")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                VStack(spacing: PerchTheme.Spacing.medium) {
                    ForEach(karakeepData.pending) { bookmark in
                        bookmarkCardView(bookmark: bookmark)
                    }
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        }

        // Processed bookmarks
        if !karakeepData.processed.isEmpty {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                Text("Bookmarks")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                VStack(spacing: PerchTheme.Spacing.medium) {
                    ForEach(karakeepData.processed) { bookmark in
                        bookmarkCardView(bookmark: bookmark)
                    }
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        }

        // Empty search result
        if viewModel.filteredKarakeepBookmarks.isEmpty && !viewModel.searchQuery.isEmpty {
            emptySearchView
        }
        // Empty tab
        else if !tabHasRecords && viewModel.hasLoaded {
            emptyStateView
        }
    }

    // MARK: - Paperless Content

    @ViewBuilder
    private var paperlessContent: some View {
        let pendingBookmarks = bookmarkData.pending
        let processedBookmarks = bookmarkData.processed

        // Count indicator
        if !bookmarkData.filtered.isEmpty {
            Text("\(tabCount) document\(tabCount == 1 ? "" : "s")")
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textTertiary)
                .padding(.horizontal, PerchTheme.Spacing.large)
        }

        // Pending/processing
        if !pendingBookmarks.isEmpty {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                Text("Processing")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                VStack(spacing: PerchTheme.Spacing.medium) {
                    ForEach(pendingBookmarks) { record in
                        if let bookmark = record.asBookmark() {
                            bookmarkCardView(bookmark: bookmark)
                        }
                    }
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        }

        // Processed
        if !processedBookmarks.isEmpty {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                Text("Documents")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                VStack(spacing: PerchTheme.Spacing.medium) {
                    ForEach(processedBookmarks) { record in
                        if let bookmark = record.asBookmark() {
                            bookmarkCardView(bookmark: bookmark)
                        }
                    }
                }
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
        }

        // Empty search result
        if bookmarkData.filtered.isEmpty && !viewModel.searchQuery.isEmpty {
            emptySearchView
        }
        // Empty tab
        else if !tabHasRecords && !dashboardViewModel.isLoading {
            emptyStateView
        }
    }

    // MARK: - Card Selection

    @ViewBuilder
    private func bookmarkCardView(bookmark: BookmarkData) -> some View {
        let tapAction = {
            if let url = URL(string: bookmark.url) {
                UIApplication.shared.open(url)
            }
        }

        if selectedTab == .paperless {
            PaperlessCard(bookmark: bookmark, onTap: tapAction)
        } else {
            BookmarkCard(bookmark: bookmark, onTap: tapAction)
        }
    }

    @ViewBuilder
    private func bookmarkCardView(bookmark: KarakeepBookmark) -> some View {
        let tapAction = {
            if let url = URL(string: bookmark.url) {
                UIApplication.shared.open(url)
            }
        }

        // Convert to BookmarkData for consistent card rendering
        let bookmarkData = BookmarkData(
            url: bookmark.url,
            originalTitle: bookmark.title,
            enrichedTitle: nil,
            summary: bookmark.summary,
            tags: bookmark.tags,
            status: BookmarkStatus(rawValue: bookmark.status.rawValue) ?? .processed,
            domain: bookmark.domain,
            imageUrl: bookmark.imageURL,
            readingTimeMinutes: bookmark.readingTimeMinutes,
            submittedFrom: nil,
            processedAt: nil,
            source: .karakeep,
            fileType: nil,
            fileName: nil
        )
        BookmarkCard(bookmark: bookmarkData, onTap: tapAction)
    }

    // MARK: - Empty States

    @ViewBuilder
    private var emptyStateView: some View {
        EmptyStateView(
            icon: selectedTab == .karakeep ? "bookmark" : "doc",
            title: selectedTab == .karakeep ? "No bookmarks saved" : "No documents saved",
            subtitle: selectedTab == .karakeep
                ? "Share articles from Safari or the Share Sheet to save them here."
                : "Documents from Paperless will appear here once they sync."
        )
    }

    @ViewBuilder
    private var emptySearchView: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "magnifyingglass")
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text("No results")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                Text("Try different keywords or filters")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PerchTheme.Spacing.large)
    }
}

// MARK: - Preview

#Preview {
    BookmarksView()
        .environment(DashboardViewModel())
}
