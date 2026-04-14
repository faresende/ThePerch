import Foundation
import Combine
import Observation

fileprivate final class AuthObserverTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    func replace(with newTask: Task<Void, Never>) {
        lock.lock()
        let existingTask = task
        task = newTask
        lock.unlock()
        existingTask?.cancel()
    }

    func cancel() {
        lock.lock()
        let existingTask = task
        task = nil
        lock.unlock()
        existingTask?.cancel()
    }

    deinit {
        cancel()
    }
}

// MARK: - AuthViewModel

/// Manages authentication state and sign-in, sign-up, and password recovery flows.
@Observable
@MainActor
final class AuthViewModel {
    // MARK: - Published Properties

    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    /// True while we're waiting for the initial session-restoration check on launch.
    /// Starts true so the app shows a splash instead of a premature AuthView flash.
    var isRestoringSession: Bool = true
    var isPasswordRecovery: Bool = false
    var error: SupabaseServiceError?
    var statusMessage: String?
    var email: String = ""
    var password: String = ""
    var confirmPassword: String = ""
    var displayName: String = ""

    // MARK: - Private Properties

    private let supabaseService: SupabaseService
    @ObservationIgnored private let authObserverTaskBox = AuthObserverTaskBox()

    // MARK: - Initialization

    init(supabaseService: SupabaseService? = nil) {
        let supabaseService = supabaseService ?? .shared
        self.supabaseService = supabaseService
        syncAuthState()
        startObserver()
    }

    private func syncAuthState() {
        self.isAuthenticated = supabaseService.isAuthenticated
        self.isPasswordRecovery = supabaseService.isPasswordRecovery
    }

    private func startObserver() {
        cancelObserver()

        let observerTask = Task { [weak self] in
            for await _ in NotificationCenter.default.publisher(for: .supabaseAuthStateChanged).values {
                guard let self else { return }
                self.syncAuthState()
            }
        }
        authObserverTaskBox.replace(with: observerTask)
    }

    func cancelObserver() {
        authObserverTaskBox.cancel()
    }

    // MARK: - Authentication Methods

    /// Restores an existing Supabase auth session from the keychain on launch.
    /// Sets isAuthenticated and clears isRestoringSession when done.
    func restoreSession() async {
        defer { isRestoringSession = false }
        await supabaseService.restoreSession()
        syncAuthState()
    }

    /// Attempts to sign in with the provided email and password.
    func signIn() async {
        statusMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabaseService.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            syncAuthState()
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Attempts to sign up with the provided email, password, and display name.
    func signUp() async {
        statusMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabaseService.signUp(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password,
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            syncAuthState()
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Sends a password reset email to the typed email address.
    func sendPasswordReset() async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty else {
            self.error = .authError("Enter your email first")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await supabaseService.sendPasswordReset(email: trimmedEmail)
            self.statusMessage = "Password reset email sent to \(trimmedEmail)."
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Handles incoming auth callback URLs, including password recovery links.
    func handleIncomingURL(_ url: URL) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let isRecovery = try await supabaseService.handleIncomingAuthURL(url)
            syncAuthState()
            self.error = nil
            if isRecovery {
                self.password = ""
                self.confirmPassword = ""
                self.statusMessage = "Recovery link accepted. Set your new password below."
            }
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Completes password recovery by setting a new password on the recovery session.
    func completePasswordRecovery() async {
        statusMessage = nil

        guard password.count >= 8 else {
            self.error = .authError("Use at least 8 characters")
            return
        }

        guard password == confirmPassword else {
            self.error = .authError("Passwords do not match")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await supabaseService.updatePassword(password)
            syncAuthState()
            self.confirmPassword = ""
            self.statusMessage = "Password updated. You can sign in normally now."
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Cancels password recovery and clears the recovery session.
    func cancelPasswordRecovery() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabaseService.cancelPasswordRecovery()
            syncAuthState()
            self.password = ""
            self.confirmPassword = ""
            self.statusMessage = nil
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Signs out the current user.
    func signOut() async {
        do {
            try await supabaseService.signOut()
            syncAuthState()
            self.email = ""
            self.password = ""
            self.confirmPassword = ""
            self.displayName = ""
            self.statusMessage = nil
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Clears all error messages.
    func clearError() {
        self.error = nil
    }

    func clearStatusMessage() {
        self.statusMessage = nil
    }
}
