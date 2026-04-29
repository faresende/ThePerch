import Foundation
import Security

/**
 SharedCredentials - Manages shared credentials between The Perch app and Share Extension

 Uses App Groups (group.com.theperch.shared) to securely share:
 - Supabase URL and anonymous key (in UserDefaults)
 - Access token (in Keychain)
 - User ID (in UserDefaults)

 The main app calls saveCredentials() after login.
 The extension calls loadCredentials() to access them.
 */

class SharedCredentials {
    private let appGroupID = "group.com.theperch.shared"

    // MARK: - UserDefaults Keys

    private let supabaseURLKey = "ThePerch_SupabaseURL"
    private let supabaseAnonKeyKey = "ThePerch_SupabaseAnonKey"
    private let userIDKey = "ThePerch_UserID"

    // MARK: - Keychain Keys

    private let keychainAccessTokenKey = "ThePerch_AccessToken"
    private let keychainServiceName = "com.theperch.shared"
    private let keychainAccessGroup = "group.com.theperch.shared"

    // MARK: - Public API

    /// Save credentials to App Group storage (called by main app after login)
    /// - Parameters:
    ///   - supabaseURL: Supabase project URL
    ///   - anonKey: Supabase anonymous key
    ///   - accessToken: User's authentication token
    ///   - userId: User's unique identifier
    func saveCredentials(
        supabaseURL: String,
        anonKey: String,
        accessToken: String,
        userId: String
    ) {
        let defaults = UserDefaults(suiteName: appGroupID)

        // Store non-sensitive values in UserDefaults
        defaults?.set(supabaseURL, forKey: supabaseURLKey)
        defaults?.set(anonKey, forKey: supabaseAnonKeyKey)
        defaults?.set(userId, forKey: userIDKey)
        defaults?.synchronize()

        // Store sensitive token in Keychain
        storeAccessTokenInKeychain(accessToken)
    }

    /// Load credentials from App Group storage (called by extension)
    /// - Returns: Tuple of (supabaseURL, anonKey, accessToken, userId) or nil if not found
    func loadCredentials() -> (supabaseURL: String, anonKey: String, accessToken: String, userId: String)? {
        let defaults = UserDefaults(suiteName: appGroupID)

        guard let supabaseURL = defaults?.string(forKey: supabaseURLKey),
              let anonKey = defaults?.string(forKey: supabaseAnonKeyKey),
              let userId = defaults?.string(forKey: userIDKey) else {
            return nil
        }

        guard let accessToken = retrieveAccessTokenFromKeychain() else {
            return nil
        }

        return (supabaseURL: supabaseURL, anonKey: anonKey, accessToken: accessToken, userId: userId)
    }

    /// Clear all stored credentials (called on logout)
    func clearCredentials() {
        let defaults = UserDefaults(suiteName: appGroupID)
        defaults?.removeObject(forKey: supabaseURLKey)
        defaults?.removeObject(forKey: supabaseAnonKeyKey)
        defaults?.removeObject(forKey: userIDKey)
        defaults?.synchronize()

        deleteAccessTokenFromKeychain()
    }

    /// Check if credentials are available
    func hasCredentials() -> Bool {
        return loadCredentials() != nil
    }

    // MARK: - Keychain Management

    private func storeAccessTokenInKeychain(_ token: String) {
        // Delete existing token first
        deleteAccessTokenFromKeychain()

        let tokenData = token.data(using: .utf8)!

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: keychainAccessTokenKey,
            kSecValueData as String: tokenData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Add access group for app group sharing
        query[kSecAttrAccessGroup as String] = keychainAccessGroup

        SecItemAdd(query as CFDictionary, nil)
    }

    private func retrieveAccessTokenFromKeychain() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: keychainAccessTokenKey,
            kSecReturnData as String: true
        ]

        // Add access group for app group sharing
        query[kSecAttrAccessGroup as String] = keychainAccessGroup

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let tokenData = result as? Data,
              let token = String(data: tokenData, encoding: .utf8) else {
            return nil
        }

        return token
    }

    private func deleteAccessTokenFromKeychain() {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecAttrAccount as String: keychainAccessTokenKey
        ]

        query[kSecAttrAccessGroup as String] = keychainAccessGroup

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Helper Extension for ShareSupabaseClient

extension SharedCredentials {
    struct LoadedCredentials {
        let supabaseURL: String
        let anonKey: String
        let accessToken: String
        let userId: String
    }

    func loadCredentialsAsStruct() -> LoadedCredentials? {
        guard let (supabaseURL, anonKey, accessToken, userId) = loadCredentials() else {
            return nil
        }
        return LoadedCredentials(
            supabaseURL: supabaseURL,
            anonKey: anonKey,
            accessToken: accessToken,
            userId: userId
        )
    }
}
