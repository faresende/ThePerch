import SwiftUI

/// The main app entry point for The Perch dashboard.
/// Manages authentication state, realtime subscriptions, notifications, and background refresh.
@main
struct ThePerchApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var dashboardViewModel = DashboardViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            // TODO: Re-enable auth gate once Supabase Auth user is created
            // if authViewModel.isAuthenticated {
            MainTabView()
                .environment(authViewModel)
                .environment(dashboardViewModel)
                .task {
                    // Request notification permission on first launch
                    await NotificationService.shared.requestPermission()
                    // Set up realtime subscriptions
                    await dashboardViewModel.setupRealtimeSubscriptions()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active && oldPhase != .active {
                        // Refresh data when app comes to foreground
                        Task {
                            await dashboardViewModel.loadDashboard()
                        }
                    }
                }
            // } else {
            //     AuthView()
            //         .environment(authViewModel)
            // }
        }
    }
}
