import Foundation
import SwiftUI

/**
 INTEGRATION_EXAMPLE.swift - Code samples for integrating the Share Extension

 This file contains example code snippets that should be integrated into your
 main app's authentication and settings flows.

 DO NOT include this file in the actual project - it's reference material only.
 */

// MARK: - Example 1: Saving Credentials After Login

class AuthenticationViewModel: ObservableObject {
    @Published var isLoggedIn = false
    @Published var user: User?

    let sharedCredentials = SharedCredentials()

    /// Call this after successful authentication with Supabase
    func handleLoginSuccess(
        user: User,
        accessToken: String,
        supabaseURL: String,
        anonKey: String
    ) {
        // Save user
        self.user = user
        self.isLoggedIn = true

        // IMPORTANT: Save credentials to App Group so Share Extension can access them
        sharedCredentials.saveCredentials(
            supabaseURL: supabaseURL,
            anonKey: anonKey,
            accessToken: accessToken,
            userId: user.id
        )

        print("Credentials saved to App Group - Share Extension now has access")
    }

    /// Call this on logout
    func handleLogout() {
        self.user = nil
        self.isLoggedIn = false

        // Clear credentials from App Group
        sharedCredentials.clearCredentials()

        print("Credentials cleared from App Group")
    }
}

// MARK: - Example 2: Login View Integration

struct LoginView: View {
    @StateObject var authViewModel = AuthenticationViewModel()
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            SecureField("Password", text: $password)
                .textContentType(.password)

            Button(action: login) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Sign In")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.accentColor)
            .foregroundColor(.white)
            .cornerRadius(8)
            .disabled(isLoading || email.isEmpty || password.isEmpty)

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }

    private func login() {
        isLoading = true
        errorMessage = nil

        // Example: authenticate with Supabase
        Task {
            do {
                // This is pseudocode - adapt to your actual auth method
                let (user, accessToken) = try await authenticateWithSupabase(
                    email: email,
                    password: password
                )

                // After successful login, save credentials for the extension
                authViewModel.handleLoginSuccess(
                    user: user,
                    accessToken: accessToken,
                    supabaseURL: "https://your-project.supabase.co",
                    anonKey: "your-anon-key"
                )

                // Navigate to main app
            } catch {
                errorMessage = error.localizedDescription
            }

            isLoading = false
        }
    }

    // Placeholder
    private func authenticateWithSupabase(
        email: String,
        password: String
    ) async throws -> (user: User, accessToken: String) {
        throw NSError(domain: "Example", code: 0)
    }
}

// MARK: - Example 3: Settings View with Extension Status

struct SettingsView: View {
    @StateObject var authViewModel = AuthenticationViewModel()

    var hasExtensionAccess: Bool {
        let credentials = SharedCredentials()
        return credentials.hasCredentials()
    }

    var body: some View {
        List {
            Section(header: Text("Share Extension")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The Perch Share Extension")
                            .font(.headline)

                        if hasExtensionAccess {
                            Label("Ready to use", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Label("Log in to enable", systemImage: "exclamationmark.circle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }

                    Spacer()

                    Image(systemName: "arrow.right")
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)

            Section(header: Text("About")) {
                Text("The Share Extension allows you to save URLs from Safari, Mail, Twitter, and other apps directly to The Perch.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                Button(role: .destructive, action: logout) {
                    Text("Sign Out")
                }
            }
        }
    }

    private func logout() {
        authViewModel.handleLogout()
    }
}

// MARK: - Example 4: SceneDelegate Integration

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Refresh credentials when returning from Share Extension
        // This ensures the token is still valid
        refreshCredentialsIfNeeded()
    }

    private func refreshCredentialsIfNeeded() {
        let credentials = SharedCredentials()

        // If main app has valid credentials, refresh them
        // This is optional but recommended if tokens expire
        if credentials.hasCredentials() {
            // You could optionally validate the token here
            // and refresh it if needed
        }
    }
}

// MARK: - Example 5: App Startup Check

struct AppDelegate: UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // On app launch, verify shared credentials are available
        checkExtensionReadiness()
        return true
    }

    private func checkExtensionReadiness() {
        let credentials = SharedCredentials()

        if credentials.hasCredentials() {
            print("✅ Share Extension credentials are available")
        } else {
            print("⚠️ Share Extension will not work until user logs in")
        }
    }
}

// MARK: - Example 6: Monitoring Share Extension Activity

class ShareExtensionMonitor {
    let supabaseClient: SupabaseClient

    /// Poll for recent bookmarks submitted from the share extension
    func checkRecentShareExtensionBookmarks() async throws {
        let recentBookmarks = try await supabaseClient
            .from("bookmarks")
            .select()
            .eq("submitted_from", value: "ios_share")
            .eq("status", value: "pending")
            .gte("created_at", value: Date().addingTimeInterval(-3600).ISO8601Format())
            .order("created_at", ascending: false)
            .limit(10)
            .execute()

        print("Found \(recentBookmarks.count) recent bookmarks from Share Extension")

        // You could use this to show a badge or notification
        // in the main app UI
    }
}

// MARK: - Example 7: Testing Helper

/// Use this in your test suite to simulate share extension activity
class ShareExtensionTestHelper {
    static func simulateShareExtensionBookmark(
        url: String,
        title: String?,
        tags: [String] = []
    ) async throws {
        let client = ShareSupabaseClient()

        let bookmarkID = try await client.saveBookmark(
            url: url,
            title: title,
            tags: tags
        )

        print("Simulated bookmark creation: \(bookmarkID)")
    }
}

// MARK: - Example 8: Error Handling and User Feedback

struct BookmarkSaveAlert: View {
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var alertTitle = ""

    var body: some View {
        VStack {
            Button("Test Share Extension") {
                Task {
                    await testShareExtension()
                }
            }
        }
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK") {
                showAlert = false
            }
        } message: {
            Text(alertMessage)
        }
    }

    private func testShareExtension() async {
        do {
            try await ShareExtensionTestHelper.simulateShareExtensionBookmark(
                url: "https://www.example.com/article",
                title: "Example Article",
                tags: ["test", "example"]
            )

            alertTitle = "Success"
            alertMessage = "Bookmark saved! Check Supabase for details."
        } catch {
            alertTitle = "Error"
            alertMessage = error.localizedDescription
        }

        showAlert = true
    }
}

// MARK: - Supporting Types

struct User: Codable {
    let id: String
    let email: String
}

// These are placeholder implementations for compilation
class SupabaseClient {
    func from(_ table: String) -> QueryBuilder {
        return QueryBuilder()
    }
}

class QueryBuilder {
    func select() -> Self { return self }
    func eq(_ column: String, value: String) -> Self { return self }
    func gte(_ column: String, value: String) -> Self { return self }
    func order(_ column: String, ascending: Bool) -> Self { return self }
    func limit(_ limit: Int) -> Self { return self }
    func execute() async throws -> [String] { return [] }
}
