import Foundation
import Combine
import Observation

// MARK: - AuthViewModel

/// Manages authentication state and sign-in/sign-up flows.
@Observable
@MainActor
final class AuthViewModel {
    // MARK: - Published Properties

    var isAuthenticated: Bool = false
    var isLoading: Bool = false
    var error: SupabaseServiceError?
    var email: String = ""
    var password: String = ""
    var displayName: String = ""

    // MARK: - Private Properties

    private let supabaseService: SupabaseService
    private var authObserverTask: Task<Void, Never>?

    // MARK: - Initialization

    init(supabaseService: SupabaseService = .shared) {
        self.supabaseService = supabaseService
        self.isAuthenticated = supabaseService.isAuthenticated

        authObserverTask = Task { [weak self] in
            for await _ in NotificationCenter.default.publisher(for: NSNotification.Name("SupabaseAuthStateChanged")).values {
                guard let self else { return }
                self.isAuthenticated = supabaseService.isAuthenticated
            }
        }
    }

    nonisolated func cancelObserver() {
        // Called from deinit context
    }

    deinit {
        // Cannot access main-actor isolated property from deinit
        // Task will be cleaned up when the object is deallocated
    }

    // MARK: - Authentication Methods

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
