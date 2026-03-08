import SwiftUI

/// The main app entry point for The Perch dashboard.
/// Manages authentication state, realtime subscriptions, notifications, and background refresh.
@main
struct ThePerchApp: App {
    @State private var authViewModel = AuthViewModel()
    @State private var dashboardViewModel = DashboardViewModel()
    @State private var networkMonitor = NetworkMonitor.shared
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @Environment(\.scenePhase) private var scenePhase

    /// Whether to show the crash report alert.
    @State private var showCrashAlert = false

    init() {
        // Install crash handler before anything else
        CrashReporter.shared.installHandler()
        // Register background refresh tasks
        BackgroundRefreshService.shared.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            // TODO: Re-enable auth gate once Supabase Auth user is created
            // if authViewModel.isAuthenticated {
            MainTabView()
                .environment(authViewModel)
                .environment(dashboardViewModel)
                .environment(networkMonitor)
                .task {
                    // Eager initial load on app launch (cache first, then network)
                    await dashboardViewModel.loadDashboard()
                    // Schedule background refresh once we've loaded at least once
                    BackgroundRefreshService.shared.scheduleAppRefresh()

                    // Request notification permission on first launch
                    await NotificationService.shared.requestPermission()
                    // Set up realtime subscriptions
                    await dashboardViewModel.setupRealtimeSubscriptions()
                    // Check for crash reports from previous session
                    if CrashReporter.shared.hasPendingCrashReports {
                        showCrashAlert = true
                    }
                }
                .preferredColorScheme(darkModeEnabled ? .dark : nil)
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active && oldPhase != .active {
                        // Refresh data when app comes to foreground
                        Task {
                            await dashboardViewModel.loadDashboard()
                            BackgroundRefreshService.shared.scheduleAppRefresh()
                        }
                    }
                }
                .alert("Previous Crash Detected", isPresented: $showCrashAlert) {
                    Button("Dismiss") {
                        CrashReporter.shared.clearCrashReports()
                    }
                } message: {
                    Text(CrashReporter.shared.crashSummary() ?? "A crash occurred in a previous session.")
                }
            // } else {
            //     AuthView()
            //         .environment(authViewModel)
            // }
        }
    }
}
