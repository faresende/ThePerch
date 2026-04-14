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

/// Manages authentication state and sign-in/sign-up flows.
@Observable
@MainActor
final class AuthViewModel {
    // MARK: - Published Properties

    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    /// True while we're waiting for the initial session-restoration check on launch.
    /// Starts true so the app shows a splash instead of a premature AuthView flash.
    var isRestoringSession: Bool = true
    var error: SupabaseServiceError?
    var email: String = ""
    var password: String = ""
    var displayName: String = ""

    // MARK: - Private Properties

    private let supabaseService: SupabaseService
    @ObservationIgnored private let authObserverTaskBox = AuthObserverTaskBox()

    // MARK: - Initialization

    init(supabaseService: SupabaseService? = nil) {
        let supabaseService = supabaseService ?? .shared
        self.supabaseService = supabaseService
        self.isAuthenticated = supabaseService.isAuthenticated

        startObserver()
    }

    private func startObserver() {
        cancelObserver()

        let observerTask = Task { [weak self] in
            for await _ in NotificationCenter.default.publisher(for: NSNotification.Name("SupabaseAuthStateChanged")).values {
                guard let self else { return }
                self.isAuthenticated = supabaseService.isAuthenticated
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
        self.isAuthenticated = supabaseService.isAuthenticated
    }

    /// Attempts to sign in with the provided email and password.
    func signIn() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabaseService.signIn(email: email, password: password)
            self.isAuthenticated = supabaseService.isAuthenticated
            self.error = nil
        } catch let error as SupabaseServiceError {
            self.error = error
        } catch {
            self.error = .unknownError(error.localizedDescription)
        }
    }

    /// Attempts to sign up with the provided email, password, and display name.
    func signUp() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await supabaseService.signUp(
                email: email,
                password: password,
                displayName: displayName
            )
            self.isAuthenticated = supabaseService.isAuthenticated
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
            self.isAuthenticated = false
            self.email = ""
            self.password = ""
            self.displayName = ""
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
}
