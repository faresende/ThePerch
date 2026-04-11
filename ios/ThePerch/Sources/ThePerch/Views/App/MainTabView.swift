import SwiftUI

/// Root navigation view — bottom tab bar with 4 tabs: Today, Health, Hub, Settings.
/// Uses Apple's native iOS 26 TabView with Liquid Glass floating pill.
/// No custom tab bar needed — SwiftUI handles everything natively.
struct MainTabView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @Environment(NetworkMonitor.self) var networkMonitor
    @ObservedObject private var supabaseService = SupabaseService.shared
    @State private var selectedTab: String = "today"

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()
            TimeOfDayAtmosphere()

            TabView(selection: $selectedTab) {
                Tab("Today", systemImage: "house.fill", value: "today") {
                    TodayTab()
                }

                Tab("Health", systemImage: "heart.fill", value: "health") {
                    HealthTab()
                }

                Tab("Hub", systemImage: "square.grid.2x2.fill", value: "hub") {
                    HubTab()
                }

                Tab("Settings", systemImage: "gearshape.fill", value: "settings") {
                    SettingsTab()
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)  // Collapses on scroll like Apple Music
        }
        .task {
            await dashboardViewModel.loadDashboard()
        }
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
        .environment(DashboardViewModel())
        .environment(NetworkMonitor.shared)
}
