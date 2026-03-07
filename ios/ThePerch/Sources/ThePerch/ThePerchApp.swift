import SwiftUI

/// The main app entry point for The Perch dashboard.
/// Manages authentication state and routes to the appropriate view.
@main
struct ThePerchApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var dashboardViewModel = DashboardViewModel()

    var body: some Scene {
        WindowGroup {
            // TODO: Re-enable auth gate once Supabase Auth user is created
            // if authViewModel.isAuthenticated {
            MainTabView()
                .environment(authViewModel)
                .environment(dashboardViewModel)
            // } else {
            //     AuthView()
            //         .environment(authViewModel)
            // }
        }
    }
}
