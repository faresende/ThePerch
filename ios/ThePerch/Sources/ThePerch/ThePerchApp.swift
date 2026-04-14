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
    /// False triggers OnboardingView instead of the auth/main flow.
    @State private var isConfigured: Bool = !AppConfig.shared.isMisconfigured

    init() {
        // Install crash handler before anything else
        CrashReporter.shared.installHandler()
        // Register background refresh tasks
        BackgroundRefreshService.shared.registerTasks()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                PerchTheme.background.ignoresSafeArea()

                if !isConfigured {
                    // Step 1: No backend configured — show setup wizard.
                    OnboardingView {
                        isConfigured = true
                    }

                } else if authViewModel.isRestoringSession {
                    // Step 2: Configured but waiting for session restoration to finish.
                    // Show a minimal splash so there's no AuthView flash for returning users.
                    VStack(spacing: PerchTheme.Spacing.medium) {
                        Image(systemName: "bird.fill")
                            .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                            .foregroundColor(PerchTheme.accent)
                        ProgressView()
                            .tint(PerchTheme.accent)
                    }

                } else if authViewModel.isAuthenticated {
                    // Step 3: Authenticated — show the main app.
                    MainTabView()
                        .environment(authViewModel)
                        .environment(dashboardViewModel)
                        .environment(networkMonitor)
                        .preferredColorScheme(darkModeEnabled ? .dark : nil)
                        .onChange(of: scenePhase) { oldPhase, newPhase in
                            if newPhase == .active && oldPhase != .active {
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

                } else {
                    // Step 4: Configured but not authenticated — show sign-in screen.
                    AuthView()
                        .environment(authViewModel)
                }
            }
            // Re-runs whenever isConfigured changes (handles post-onboarding case).
            // On first launch with valid config, fires immediately and restores session.
            .task(id: isConfigured) {
                guard isConfigured else { return }
                await authViewModel.restoreSession()
            }
            // Once authenticated (either via restore or sign-in), load data.
            .task(id: authViewModel.isAuthenticated) {
                guard authViewModel.isAuthenticated else { return }
                await dashboardViewModel.loadDashboard()
                BackgroundRefreshService.shared.scheduleAppRefresh()
                await dashboardViewModel.setupRealtimeSubscriptions()
                if CrashReporter.shared.hasPendingCrashReports {
                    showCrashAlert = true
                }
            }
        }
    }
}
