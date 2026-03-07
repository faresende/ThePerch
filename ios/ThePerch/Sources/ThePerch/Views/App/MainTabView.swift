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

                // Page indicator dots at bottom
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    ForEach(Array(visibleSections.enumerated()), id: \.offset) { index, _ in
                        Circle()
                            .fill(selectedIndex == index ? PerchTheme.accent : PerchTheme.border)
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: selectedIndex)
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
                    // Section header
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                        Text(section.displayName)
                            .font(PerchTheme.Font.largeTitle)
                            .foregroundColor(PerchTheme.textPrimary)

                        Text("Managed by \(section.slug.capitalized)")
                            .font(PerchTheme.Font.subheadline)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
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
            ProgressView()
                .foregroundColor(PerchTheme.accent)
                .onAppear {
                    if let category = section.category {
                        viewModel = SectionViewModel(category: category)
                        Task {
                            await viewModel?.loadRecords()
                        }
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
