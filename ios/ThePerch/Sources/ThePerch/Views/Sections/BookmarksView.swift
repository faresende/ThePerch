import SwiftUI

/// Bookmarks section with Karakeep/Paperless tabs, search, and filtering.
/// Reads records from DashboardViewModel (single-fetch architecture).
struct BookmarksView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel

    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []
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
            let matchesSearch = searchText.isEmpty ||
                bookmark.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                (bookmark.summary?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                (bookmark.fileName?.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesTags = selectedTags.isEmpty ||
                selectedTags.allSatisfy { bookmark.tags.contains($0) }

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

    var allTags: [String] { bookmarkData.allTags }
    var filteredBookmarks: [Record] { bookmarkData.filtered }
    var pendingBookmarks: [Record] { bookmarkData.pending }
    var processedBookmarks: [Record] { bookmarkData.processed }

    private var tabCount: Int { bookmarkData.filtered.count }

    /// Whether the current tab has any records (before search/tag filter).
    private var tabHasRecords: Bool {
        records.contains { record in
            guard let bookmark = record.asBookmark() else { return false }
            return (bookmark.source ?? .karakeep) == selectedTab
        }
    }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            if dashboardViewModel.isLoading && records.isEmpty {
                VStack(spacing: PerchTheme.Spacing.medium) {
                    SkeletonBookmarkCard()
                    SkeletonBookmarkCard()
                    SkeletonBookmarkCard()
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.top, 80)
            }

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
                        retryAction: { Task { await dashboardViewModel.refreshRecords() } },
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
                        selectedTags.removeAll()
                    }

                    // Search bar
                    HStack(spacing: PerchTheme.Spacing.small) {
                        Image(systemName: "magnifyingglass")
                            .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                            .foregroundColor(PerchTheme.textSecondary)

                        TextField(
                            selectedTab == .karakeep ? "Search bookmarks" : "Search documents",
                            text: $searchText
                        )
                        .autocorrectionDisabled()

                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
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
                                    Button(action: { toggleTag(tag) }) {
                                        Text(tag)
                                            .font(PerchTheme.Font.caption)
                                            .foregroundColor(
                                                selectedTags.contains(tag)
                                                    ? .white
                                                    : PerchTheme.accent
                                            )
                                            .padding(.horizontal, PerchTheme.Spacing.small)
                                            .padding(.vertical, PerchTheme.Spacing.xxSmall)
                                            .background(
                                                selectedTags.contains(tag)
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
                        // Count indicator
                        if !filteredBookmarks.isEmpty {
                            Text("\(tabCount) \(selectedTab == .karakeep ? "bookmark" : "document")\(tabCount == 1 ? "" : "s")")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textTertiary)
                                .padding(.horizontal, PerchTheme.Spacing.large)
                        }

                        // Pending/processing bookmarks
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

                        // Processed bookmarks
                        if !processedBookmarks.isEmpty {
                            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                                Text(selectedTab == .karakeep ? "Bookmarks" : "Documents")
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

                        // Empty state
                        if filteredBookmarks.isEmpty && !searchText.isEmpty {
                            emptySearchView
                        } else if !tabHasRecords && !dashboardViewModel.isLoading {
                            emptyStateView
                        }

                        Spacer()
                            .frame(height: PerchTheme.Spacing.large)
                    }
                }
                .refreshable {
                    PerchHaptics.medium()
                    await dashboardViewModel.refreshRecords()
                    PerchHaptics.success()
                }
            }
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

    // MARK: - Empty States

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: selectedTab == .karakeep ? "bookmark" : "doc")
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text(selectedTab == .karakeep ? "No bookmarks yet" : "No documents yet")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                Text(selectedTab == .karakeep
                    ? "Share articles from Safari or the Share Sheet"
                    : "Documents from Paperless will appear here")
                    .font(PerchTheme.Font.body)
                    .foregroundColor(PerchTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(PerchTheme.Spacing.large)
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

    private func toggleTag(_ tag: String) {
        PerchHaptics.selection()
        if selectedTags.contains(tag) {
            selectedTags.remove(tag)
        } else {
            selectedTags.insert(tag)
        }
    }
}

// MARK: - Preview

#Preview {
    BookmarksView()
        .environment(DashboardViewModel())
}
