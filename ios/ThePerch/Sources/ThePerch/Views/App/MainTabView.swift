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
        ZStack(alignment: .top) {
            PerchTheme.background.ignoresSafeArea()

            // Time-of-day atmosphere gradient
            TimeOfDayAtmosphere()

            // Tab content sits underneath the glass header
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

                // Cache staleness warning
                if !networkMonitor.isConnected, let meta = CacheService.shared.metadata(for: nil, userId: "default_user") {
                    cacheAgeBanner(age: meta.relativeAgeString)
                } else if dashboardViewModel.isShowingCachedData, let lastUpdated = dashboardViewModel.lastUpdatedString {
                    cacheAgeBanner(age: lastUpdated.replacingOccurrences(of: "Last updated ", with: ""))
                }

                // Tab content — safeAreaInset pushes content below the floating pill bar
                TabView(selection: $selectedIndex) {
                    ForEach(Array(visibleSections.enumerated()), id: \.offset) { index, section in
                        SectionView(section: section)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)

            // Glass header overlay — floats above content, extends to top edge
            if !visibleSections.isEmpty {
                VStack(spacing: 0) {
                    HStack {
                        SectionNavigator(
                            selectedIndex: $selectedIndex,
                            sectionNames: sectionNames
                        )

                        // Realtime status indicator
                        if !reconnectManager.isConnected && !reconnectManager.hasGivenUp {
                            Circle()
                                .fill(PerchTheme.warning)
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
                    .padding(.vertical, PerchTheme.Spacing.xSmall)
                }
                .frame(maxWidth: .infinity)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea(edges: .top)
                )
                .glassEffect(.regular, in: Rectangle())
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(PerchTheme.accent.opacity(0.12))
                        .frame(height: 0.5)
                }
            }
        }
        .task {
            await dashboardViewModel.loadDashboard()
        }
        .onChange(of: selectedIndex) {
            // Haptic on tab switch
            PerchHaptics.selection()

            // Stale-section refresh is handled by the single-fetch architecture:
            // DashboardViewModel.allRecords is the source of truth, refreshed
            // via pull-to-refresh or realtime updates. No need to reload
            // all sections + widgets on every swipe.
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
                case "nutrition":
                    NutritionView()
                case "workouts":
                    WorkoutView(dashboardViewModel: dashboardViewModel)
                case "deliveries":
                    OrdersView()
                case "calendar":
                    CalendarView()
                case "admin":
                    AdminView()
                case "bookmarks":
                    BookmarksView()
                case "travel":
                    TravelView()
                default:
                    // Generic fallback for unknown section types
                    genericSectionView
                }
            }
            .safeAreaPadding(.top, 64) // Reserve space for the floating pill bar + breathing room
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : (PerchMotion.prefersReduced ? 0 : 12))
            .animation(
                PerchMotion.prefersReduced
                    ? .none
                    : .spring(response: 0.25, dampingFraction: 0.85),
                value: appeared
            )
            .onAppear { appeared = true }
            // Note: intentionally NOT resetting appeared on disappear
            // so cards don't re-animate on every tab revisit
        }
    }

    // MARK: - Generic Section (fallback for unknown slugs)

    private var genericRecords: [Record] {
        // Use the dynamic recordsBySlug lookup — handles any slug, including new ones
        // that don't exist in the RecordCategory enum yet
        return dashboardViewModel.recordsBySlug[section.slug] ?? []
    }

    @ViewBuilder
    private var genericSectionView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                // Section header with freshness
                SectionHeader(title: section.displayName, freshnessKey: section.slug)
                    .padding(.horizontal, PerchTheme.Spacing.large)
                    .padding(.top, PerchTheme.Spacing.medium)

                if dashboardViewModel.isLoading && genericRecords.isEmpty {
                    SkeletonCardsSection(count: 3)
                    .padding(.horizontal, PerchTheme.Spacing.large)
                } else if genericRecords.isEmpty {
                    emptyStateView
                } else {
                    VStack(spacing: PerchTheme.Spacing.medium) {
                        ForEach(genericRecords) { record in
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
            await dashboardViewModel.refreshRecords()
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        EmptyStateView(
            icon: "square.stack.3d.up.slash",
            title: "No items yet",
            subtitle: "Data from \(section.displayName) will appear here."
        )
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
        .environment(DashboardViewModel())
        .environment(NetworkMonitor.shared)
}
