import SwiftUI

/// The root navigation view after authentication.
/// Uses a horizontally paged TabView with section-specific content.
struct MainTabView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var selectedIndex: Int = 0

    var visibleSections: [Section] {
        dashboardViewModel.sections.filter { $0.isVisible }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Tab content
                TabView(selection: $selectedIndex) {
                    ForEach(Array(visibleSections.enumerated()), id: \.offset) { index, section in
                        SectionView(section: section)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Page indicator dots at bottom — active dot is a wider capsule
                HStack(spacing: 6) {
                    ForEach(Array(visibleSections.enumerated()), id: \.offset) { index, _ in
                        Capsule()
                            .fill(selectedIndex == index ? PerchTheme.accent : PerchTheme.border)
                            .frame(width: selectedIndex == index ? 20 : 8, height: 8)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selectedIndex)
                    }
                    Spacer()
                }
                .padding(.horizontal, PerchTheme.Spacing.large)
                .padding(.vertical, PerchTheme.Spacing.medium)
            }
        }
        .task {
            await dashboardViewModel.loadDashboard()
        }
        .onChange(of: selectedIndex) {
            // Haptic on tab switch
            PerchHaptics.selection()

            // Auto-refresh stale sections when swiped to
            guard selectedIndex < visibleSections.count else { return }
            let section = visibleSections[selectedIndex]
            let key = section.slug
            if DataFreshnessTracker.shared.isStale(key) {
                Task {
                    await dashboardViewModel.loadDashboard(forceRefresh: true)
                }
            }
        }
    }
}

// MARK: - Section View

struct SectionView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    let section: Section

    @State private var viewModel: SectionViewModel?

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            // Dispatch to custom section views based on section slug.
            // "home" has no RecordCategory so we also check category == nil.
            switch section.slug {
            case _ where section.category == nil:
                HomeView()
            case "health":
                HealthView()
            case "deliveries":
                DeliveriesView()
            case "calendar":
                CalendarView()
            case "admin":
                AdminView()
            case "legal":
                LegalView()
            case "bookmarks":
                BookmarksView()
            default:
                // Generic fallback for unknown section types
                genericSectionView
            }
        }
    }

    // MARK: - Generic Section (fallback for unknown slugs)

    @ViewBuilder
    private var genericSectionView: some View {
        if let viewModel = viewModel {
            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    // Section header with freshness
                    SectionHeader(title: section.displayName, freshnessKey: section.slug)
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .padding(.top, PerchTheme.Spacing.medium)

                    // Records
                    if viewModel.records.isEmpty {
                        emptyStateView
                    } else {
                        VStack(spacing: PerchTheme.Spacing.medium) {
                            ForEach(viewModel.records) { record in
                                WidgetRouter(record: record)
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                    }

                    Spacer()
                        .frame(height: PerchTheme.Spacing.large)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
        } else {
            VStack(spacing: PerchTheme.Spacing.medium) {
                SkeletonSingleValueCard()
                SkeletonSingleValueCard()
                SkeletonChartCard()
            }
            .padding(.horizontal, PerchTheme.Spacing.large)
            .padding(.top, 60)
            .task {
                    if let category = section.category {
                        let vm = SectionViewModel(category: category)
                        viewModel = vm
                        await vm.loadRecords()
                    }
                }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 48))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text("No items yet")
                    .font(PerchTheme.Font.headline)
                    .foregroundColor(PerchTheme.textPrimary)

                Text("Data from \(section.displayName) will appear here")
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
    MainTabView()
        .environment(DashboardViewModel())
}
