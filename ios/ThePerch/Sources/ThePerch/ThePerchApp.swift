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

    private var bypassAuthForDebug: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiDebugBypassAuth")
        #else
        false
        #endif
    }

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
                    // Step 1: No backend configured, show setup wizard.
                    OnboardingView {
                        isConfigured = true
                    }

                } else if authViewModel.isRestoringSession {
                    // Step 2: Configured but waiting for session restoration.
                    //
                    // Renders the same composition as the native launch
                    // storyboard (bone bg + Perch01 + notification badge +
                    // wordmark) so the handoff from the launch screen into
                    // the app is seamless — no flash of a separate loading
                    // view with spinner. Once the session resolves, this
                    // swaps to MainTabView directly.
                    LaunchContinuationView()

                } else if bypassAuthForDebug || (authViewModel.isAuthenticated && !authViewModel.isPasswordRecovery) {
                    // Step 3: Authenticated, show the main app.
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
                    // Step 4: Configured but not authenticated, or in password recovery.
                    AuthView()
                        .environment(authViewModel)
                }
            }
            .task(id: isConfigured) {
                guard isConfigured else { return }
                if bypassAuthForDebug {
                    authViewModel.isRestoringSession = false
                    return
                }
                await authViewModel.restoreSession()
            }
            .task(id: bypassAuthForDebug || (authViewModel.isAuthenticated && !authViewModel.isPasswordRecovery)) {
                guard bypassAuthForDebug || authViewModel.isAuthenticated, !authViewModel.isPasswordRecovery else { return }
                await dashboardViewModel.loadDashboard()
                BackgroundRefreshService.shared.scheduleAppRefresh()
                // Realtime subscription used to be awaited here, which on
                // cellular blocked the .task for 600 ms – 2 s while the
                // WebSocket handshake completed. Nothing on first paint
                // depends on the channel being live (cards render from
                // cache + freshly-fetched records), so kick it off
                // detached and let the app respond to user taps right away.
                Task.detached(priority: .utility) { @MainActor in
                    await dashboardViewModel.setupRealtimeSubscriptions()
                }
                if CrashReporter.shared.hasPendingCrashReports {
                    showCrashAlert = true
                }
            }
            .onOpenURL { url in
                Task {
                    await authViewModel.handleIncomingURL(url)
                }
            }
        }
    }
}

// MARK: - LaunchContinuationView
//
// SwiftUI recreation of LaunchScreen.storyboard. Shown during
// session restoration so the handoff from the native launch screen
// into the app is visually invisible — same bone bg, same Perch01
// at 220pt, same notification badge, same wordmark, same offset.
//
// Centering math mirrors the storyboard: bird + 22pt gap + 44pt
// wordmark = 286pt group, centered in the screen with a -33pt
// offset (half of `gap + wordmark.height`) to sit just above the
// geometric middle.

private struct LaunchContinuationView: View {
    var body: some View {
        ZStack {
            Color("LaunchBG").ignoresSafeArea()

            VStack(spacing: 22) {
                Image("perch-bird-hero")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 220)
                    .overlay(alignment: .topTrailing) {
                        // Notification badge: 34pt bone ring around a
                        // 20pt terracotta dot. Same placement as the
                        // storyboard (top: 28, trailing: 18).
                        ZStack {
                            Circle()
                                .fill(Color("LaunchBG"))
                                .frame(width: 34, height: 34)
                            Circle()
                                .fill(Color(red: 0.882, green: 0.290, blue: 0.208)) // #E14A35
                                .frame(width: 20, height: 20)
                        }
                        .padding(.top, 28)
                        .padding(.trailing, 18)
                    }

                Image("launch-wordmark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 224, height: 44)
            }
            .offset(y: -33)
        }
    }
}
