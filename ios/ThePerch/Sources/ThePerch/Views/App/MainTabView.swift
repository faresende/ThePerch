import SwiftUI

/// Root navigation view — bottom tab bar with 4 tabs: Today, Health, Hub, Settings.
/// Uses custom GlassTabBar for navigation chrome.
struct MainTabView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @Environment(NetworkMonitor.self) var networkMonitor
    @ObservedObject private var supabaseService = SupabaseService.shared
    @State private var selectedTabId: String = "today"

    private var reconnectManager: RealtimeReconnectManager { RealtimeReconnectManager.shared }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            // Time-of-day atmosphere gradient (behind everything)
            TimeOfDayAtmosphere()

            VStack(spacing: 0) {
                // Banners
                bannerStack

                // Tab content
                Group {
                    switch selectedTabId {
                    case "today":
                        TodayTab()
                    case "health":
                        HealthTab()
                    case "hub":
                        HubTab()
                    case "settings":
                        SettingsTab()
                    default:
                        TodayTab()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.15), value: selectedTabId)
            }
            // Render tab bar as a bottom safe-area inset so SwiftUI
            // reserves layout space for it across all tabs/ScrollViews.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                GlassTabBar(selectedId: $selectedTabId)
                    .zIndex(1000)
            }
        }
        .task {
            await dashboardViewModel.loadDashboard()
        }
    }

    // MARK: - Banner Stack

    @ViewBuilder
    private var bannerStack: some View {
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
            if !networkMonitor.isConnected,
               let meta = CacheService.shared.metadata(for: nil, userId: "default_user") {
                cacheAgeBanner(age: meta.relativeAgeString)
            } else if dashboardViewModel.isShowingCachedData,
                      let lastUpdated = dashboardViewModel.lastUpdatedString {
                cacheAgeBanner(age: lastUpdated.replacingOccurrences(of: "Last updated ", with: ""))
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

// MARK: - Preview

#Preview {
    MainTabView()
        .environment(DashboardViewModel())
        .environment(NetworkMonitor.shared)
}
