import SwiftUI

/// Bookmarks section with search and filtering.
struct BookmarksView: View {
    @State private var viewModel = SectionViewModel(category: .bookmarks)

    @State private var searchText = ""
    @State private var selectedTags: Set<String> = []

    var allTags: [String] {
        Array(Set(viewModel.records.compactMap { $0.asBookmark()?.tags }.flatMap { $0 })).sorted()
    }

    var filteredBookmarks: [Record] {
        viewModel.records.filter { record in
            guard let bookmark = record.asBookmark() else { return false }

            let matchesSearch = searchText.isEmpty ||
                bookmark.displayTitle.localizedCaseInsensitiveContains(searchText) ||
                (bookmark.summary?.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesTags = selectedTags.isEmpty ||
                selectedTags.allSatisfy { bookmark.tags.contains($0) }

            return matchesSearch && matchesTags
        }
    }

    var pendingBookmarks: [Record] {
        filteredBookmarks.filter { $0.asBookmark()?.status == .pending || $0.asBookmark()?.status == .processing }
    }

    var processedBookmarks: [Record] {
        filteredBookmarks.filter { $0.asBookmark()?.status == .processed }
    }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.records.isEmpty {
                VStack(spacing: PerchTheme.Spacing.medium) {
                    SkeletonBookmarkCard()
                    SkeletonBookmarkCard()
                    SkeletonBookmarkCard()
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.top, 80)
            }

            VStack(spacing: 0) {
                // Section header with freshness
                SectionHeader(title: "Bookmarks", freshnessKey: "bookmarks")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.top, PerchTheme.Spacing.medium)
                    .padding(.bottom, PerchTheme.Spacing.small)

                // Search bar (always visible)
                VStack(spacing: PerchTheme.Spacing.medium) {
                    HStack(spacing: PerchTheme.Spacing.small) {
                        Image(systemName: "magnifyingglass")
                            .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                            .foregroundColor(PerchTheme.textSecondary)

                        TextField("Search bookmarks", text: $searchText)
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
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                        // Pending/processing bookmarks
                        if !pendingBookmarks.isEmpty {
                            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                                Text("Processing")
                                    .font(PerchTheme.Font.heading)
                                    .foregroundColor(PerchTheme.textPrimary)

                                VStack(spacing: PerchTheme.Spacing.medium) {
                                    ForEach(pendingBookmarks) { record in
                                        if let bookmark = record.asBookmark() {
                                            BookmarkCard(
                                                bookmark: bookmark,
                                                onTap: {
                                                    if let url = URL(string: bookmark.url) {
                                                        UIApplication.shared.open(url)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }

                        // Processed bookmarks
                        if !processedBookmarks.isEmpty {
                            VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                                Text("Bookmarks")
                                    .font(PerchTheme.Font.heading)
                                    .foregroundColor(PerchTheme.textPrimary)

                                VStack(spacing: PerchTheme.Spacing.medium) {
                                    ForEach(processedBookmarks) { record in
                                        if let bookmark = record.asBookmark() {
                                            BookmarkCard(
                                                bookmark: bookmark,
                                                onTap: {
                                                    if let url = URL(string: bookmark.url) {
                                                        UIApplication.shared.open(url)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }

                        // Empty state
                        if filteredBookmarks.isEmpty && !searchText.isEmpty {
                            emptySearchView
                        } else if viewModel.records.isEmpty {
                            emptyStateView
                        }

                        Spacer()
                            .frame(height: PerchTheme.Spacing.large)
                    }
                }
                .refreshable {
                    PerchHaptics.medium()
                    await viewModel.refresh()
                    PerchHaptics.success()
                }
            }
        }
        .task {
            await viewModel.loadRecords()
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "bookmark")
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text("No bookmarks yet")
                    .font(PerchTheme.Font.heading)
                    .foregroundColor(PerchTheme.textPrimary)

                Text("Share articles from Safari or the Share Sheet")
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
}
