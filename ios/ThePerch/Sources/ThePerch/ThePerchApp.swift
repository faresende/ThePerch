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

    /// Whether the app is configured with valid Supabase credentials.
    /// False triggers OnboardingView instead of MainTabView.
    @State private var isConfigured: Bool = !AppConfig.shared.isMisconfigured

    init() {
        // Install crash handler before anything else
        CrashReporter.shared.installHandler()
        // Register background refresh tasks
        BackgroundRefreshService.shared.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            if !isConfigured {
                OnboardingView {
                    // Reconfigure the app with new credentials and proceed
                    isConfigured = true
                }
            } else {
            MainTabView()
                .environment(authViewModel)
                .environment(dashboardViewModel)
                .environment(networkMonitor)
                .task {
                    // Eager initial load on app launch (cache first, then network)
                    await dashboardViewModel.loadDashboard()
                    // Schedule background refresh once we've loaded at least once
                    BackgroundRefreshService.shared.scheduleAppRefresh()

                    // Notification permission removed — no push notifications in the system yet
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
}
