import Foundation
import Security

/// Example integration code for the main app
/// This demonstrates how to store Supabase credentials in the shared App Group
/// so the Share Extension can access them
///
/// USAGE:
/// After successful authentication, call:
/// AuthenticationManager.storeSharedSupabaseCredentials(...)

class MainAppAuthenticationIntegration {
    /// Call this after user successfully authenticates with Supabase
    /// This makes credentials available to the Share Extension
    static func storeSharedSupabaseCredentials(
        supabaseURL: String,
        supabaseAnonKey: String,
        authToken: String,
        userID: String
    ) {
        // Step 1: Store Supabase configuration in shared UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier) {
            sharedDefaults.set(supabaseURL, forKey: SharedConstants.supabaseURLKey)
            sharedDefaults.set(supabaseAnonKey, forKey: SharedConstants.supabaseAnonKeyKey)
            sharedDefaults.synchronize()
        }

        // Step 2: Store auth token in shared Keychain
        storeInSharedKeychain(
            key: SharedConstants.authTokenKeychainKey,
            value: authToken,
            service: SharedConstants.keychainService
        )

        // Step 3: Optionally store user ID for reference
        storeInSharedKeychain(
            key: SharedConstants.userIDKeychainKey,
            value: userID,
            service: SharedConstants.keychainService
        )
    }

    /// Call this when user logs out
    /// Clears credentials from shared storage
    static func clearSharedSupabaseCredentials() {
        // Clear from UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier) {
            sharedDefaults.removeObject(forKey: SharedConstants.supabaseURLKey)
            sharedDefaults.removeObject(forKey: SharedConstants.supabaseAnonKeyKey)
            sharedDefaults.synchronize()
        }

        // Clear from Keychain
        deleteFromSharedKeychain(
            key: SharedConstants.authTokenKeychainKey,
            service: SharedConstants.keychainService
        )
        deleteFromSharedKeychain(
            key: SharedConstants.userIDKeychainKey,
            service: SharedConstants.keychainService
        )
    }

    /// Retrieve stored auth token (useful for debugging or token refresh)
    static func getStoredAuthToken() -> String? {
        retrieveFromSharedKeychain(
            key: SharedConstants.authTokenKeychainKey,
            service: SharedConstants.keychainService
        )
    }

    // MARK: - Private Keychain Helpers

    private static func storeInSharedKeychain(
        key: String,
        value: String,
        service: String
    ) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: SharedConstants.appGroupIdentifier,
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        var attributes = query
        if let data = value.data(using: .utf8) {
            attributes[kSecValueData as String] = data
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }

    private static func retrieveFromSharedKeychain(
        key: String,
        service: String
    ) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: SharedConstants.appGroupIdentifier,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static func deleteFromSharedKeychain(
        key: String,
        service: String
    ) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: SharedConstants.appGroupIdentifier,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Example Usage

/*
 EXAMPLE 1: After Supabase Authentication
 ==========================================

 In your main app's authentication flow:

 ```swift
 func didAuthenticateWithSupabase(
     supabaseURL: String,
     anonKey: String,
     session: Session  // From Supabase
 ) {
     // Extract auth token from session
     let authToken = session.accessToken

     // Extract user ID from session
     let userID = session.user.id.uuidString

     // Store credentials for the share extension
     MainAppAuthenticationIntegration.storeSharedSupabaseCredentials(
         supabaseURL: supabaseURL,
         supabaseAnonKey: anonKey,
         authToken: authToken,
         userID: userID
     )

     // Continue with main app initialization...
 }
 ```

 EXAMPLE 2: On User Logout
 ==========================

 ```swift
 func didLogout() {
     MainAppAuthenticationIntegration.clearSharedSupabaseCredentials()
     // Continue with logout flow...
 }
 ```

 EXAMPLE 3: Token Refresh (if using Supabase refresh tokens)
 ============================================================

 ```swift
 func refreshAuthTokenIfNeeded() async throws {
     let newSession = try await supabase.auth.refreshSession()

     // Update shared credentials with new token
     MainAppAuthenticationIntegration.storeSharedSupabaseCredentials(
         supabaseURL: supabaseURL,
         supabaseAnonKey: anonKey,
         authToken: newSession.accessToken,
         userID: newSession.user.id.uuidString
     )
 }
 ```
*/
