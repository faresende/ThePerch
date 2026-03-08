import SwiftUI

/// The root navigation view after authentication.
/// Uses a horizontally paged TabView with a scrollable pill bar for section navigation.
struct MainTabView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @Environment(NetworkMonitor.self) var networkMonitor
    @ObservedObject private var supabaseService = SupabaseService.shared
    @State private var selectedIndex: Int = 0

    private var reconnectManager: RealtimeReconnectManager { RealtimeReconnectManager.shared }

    var visibleSections: [Section] {
        dashboardViewModel.sections.filter { $0.isVisible && $0.slug != "legal" }.sorted { $0.sortOrder < $1.sortOrder }
    }

    var sectionNames: [String] {
        visibleSections.map { $0.displayName }
    }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            // Time-of-day atmosphere gradient
            TimeOfDayAtmosphere()

            VStack(spacing: 0) {
                // Offline banner
                if !networkMonitor.isConnected {
                    offlineBanner
                }

                // Connection error banner
                if let connectionError = supabaseService.connectionError, networkMonitor.isConnected {
                    errorBanner(message: connectionError)
                }

                // Dashboard-level error banner
                if let error = dashboardViewModel.error, supabaseService.connectionError == nil {
                    errorBanner(message: error.localizedDescription)
                }

                // Offline cache staleness warning
                if !networkMonitor.isConnected, let meta = CacheService.shared.metadata(for: nil, userId: "default_user") {
                    cacheAgeBanner(age: meta.relativeAgeString)
                }

                // Section navigator pill bar with realtime status
                if !visibleSections.isEmpty {
                    HStack {
                        SectionNavigator(
                            selectedIndex: $selectedIndex,
                            sectionNames: sectionNames
                        )

                        // Realtime status indicator
                        if !reconnectManager.isConnected && !reconnectManager.hasGivenUp {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                                .padding(.trailing, PerchTheme.Spacing.medium)
                        }

                        // Manual reconnect button when retries exhausted
                        if reconnectManager.hasGivenUp {
                            Button {
                                reconnectManager.manualReconnect {
                                    await dashboardViewModel.attemptRealtimeReconnect()
                                }
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption2)
                                    .foregroundColor(PerchTheme.error)
                            }
                            .padding(.trailing, PerchTheme.Spacing.medium)
                        }
                    }
                }

                // Tab content
                TabView(selection: $selectedIndex) {
                    ForEach(Array(visibleSections.enumerated()), id: \.offset) { index, section in
                        SectionView(section: section)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
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

    // MARK: - Offline Banner

    private var offlineBanner: some View {
        HStack(spacing: PerchTheme.Spacing.xSmall) {
            Image(systemName: "wifi.slash")
                .font(PerchTheme.Font.caption)
            Text("You're offline")
                .font(PerchTheme.Font.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, PerchTheme.Spacing.xSmall)
        .background(PerchTheme.textTertiary)
    }

    // MARK: - Cache Age Banner

    private func cacheAgeBanner(age: String) -> some View {
        HStack(spacing: PerchTheme.Spacing.xSmall) {
            Image(systemName: "clock.arrow.circlepath")
                .font(PerchTheme.Font.caption)
            Text("Last updated \(age)")
                .font(PerchTheme.Font.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(PerchTheme.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(PerchTheme.warning.opacity(0.15))
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(PerchTheme.error)
            Text(message)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textSecondary)
                .lineLimit(2)
            Spacer()
            Button("Retry") {
                Task { await dashboardViewModel.loadDashboard(forceRefresh: true) }
            }
            .font(PerchTheme.Font.caption)
            .foregroundColor(PerchTheme.accent)
        }
        .padding(PerchTheme.Spacing.small)
        .background(PerchTheme.error.opacity(0.1))
        .padding(.horizontal, PerchTheme.Spacing.large)
    }
}

// MARK: - Section View

struct SectionView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    let section: Section

    @State private var viewModel: SectionViewModel?
    @State private var appeared = false

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            // Dispatch to custom section views based on section slug.
            // "home" has no RecordCategory so we also check category == nil.
            Group {
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
                case "bookmarks":
                    BookmarksView()
                default:
                    // Generic fallback for unknown section types
                    genericSectionView
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (PerchMotion.prefersReduced ? 0 : 12))
            .animation(
                PerchMotion.prefersReduced
                    ? .none
                    : .spring(response: 0.25, dampingFraction: 0.85),
                value: appeared
            )
            .onAppear { appeared = true }
            .onDisappear { appeared = false }
        }
    }

    // MARK: - Generic Section (fallback for unknown slugs)

    @ViewBuilder
    private var genericSectionView: some View {
        if let viewModel = viewModel {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
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
                .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                .foregroundColor(PerchTheme.textTertiary)

            VStack(spacing: PerchTheme.Spacing.xSmall) {
                Text("No items yet")
                    .font(PerchTheme.Font.heading)
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
        .environment(NetworkMonitor.shared)
}
