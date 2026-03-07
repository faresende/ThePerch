import SwiftUI

/// Home section view that shows pinned and recent highlights across all categories.
struct HomeHighlightsView: View {
    @State private var records: [Record] = []
    @State private var isLoading = true

    private let supabaseService = SupabaseService.shared

    var pinnedRecords: [Record] {
        records.filter { $0.pinned }
    }

    var recentRecords: [Record] {
        records.filter { !$0.pinned }.prefix(5).map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                // Header
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                    Text("Home")
                        .font(PerchTheme.Font.largeTitle)
                        .foregroundColor(PerchTheme.textPrimary)

                    Text("Your pinned items and highlights")
                        .font(PerchTheme.Font.subheadline)
                        .foregroundColor(PerchTheme.textSecondary)
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.top, PerchTheme.Spacing.medium)

                if isLoading {
                    SkeletonHomeSection()
                        .padding(.horizontal, PerchTheme.Spacing.large)
                } else if pinnedRecords.isEmpty && recentRecords.isEmpty {
                    VStack(spacing: PerchTheme.Spacing.medium) {
                        Image(systemName: "bird.fill")
                            .font(.system(size: 48))
                            .foregroundColor(PerchTheme.accent.opacity(0.5))

                        Text("Welcome to The Perch")
                            .font(PerchTheme.Font.headline)
                            .foregroundColor(PerchTheme.textPrimary)

                        Text("Swipe to explore your sections")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(PerchTheme.Spacing.xxLarge)
                } else {
                    // Pinned items
                    if !pinnedRecords.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Pinned")
                                .font(PerchTheme.Font.headline)
                                .foregroundColor(PerchTheme.textPrimary)
                                .padding(.horizontal, PerchTheme.Spacing.large)

                            VStack(spacing: PerchTheme.Spacing.medium) {
                                ForEach(pinnedRecords) { record in
                                    WidgetRouter(record: record)
                                }
                            }
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }
                    }

                    // Recent items
                    if !recentRecords.isEmpty {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Recent")
                                .font(PerchTheme.Font.headline)
                                .foregroundColor(PerchTheme.textPrimary)
                                .padding(.horizontal, PerchTheme.Spacing.large)

                            VStack(spacing: PerchTheme.Spacing.medium) {
                                ForEach(recentRecords) { record in
                                    WidgetRouter(record: record)
                                }
                            }
                            .padding(.horizontal, PerchTheme.Spacing.large)
                        }
                    }
                }

                Spacer()
                    .frame(height: PerchTheme.Spacing.large)
            }
        }
        .refreshable {
            do {
                records = try await supabaseService.fetchRecords(forceRefresh: true)
            } catch {
                print("[HomeHighlightsView] Refresh failed: \(error)")
            }
        }
        .task {
            do {
                records = try await supabaseService.fetchRecords()
                isLoading = false
            } catch {
                isLoading = false
            }
        }
    }
}

#Preview {
    HomeHighlightsView()
}
