import Foundation

/// Constants shared between the main app and the Share Extension
/// Place this file in a location accessible to both targets (e.g., in a Shared framework or shared source folder)
struct SharedConstants {
    // MARK: - App Group Configuration
    /// App Group identifier for keychain and UserDefaults sharing
    static let appGroupIdentifier = "group.com.theperch.shared"

    // MARK: - Keychain Configuration
    /// Service name for keychain items
    static let keychainService = "com.theperch.auth"

    /// Keychain key for storing the user's Supabase auth token
    static let authTokenKeychainKey = "supabase_auth_token"

    // MARK: - UserDefaults Keys (Shared App Group)
    /// Key for storing the Supabase URL in shared UserDefaults
    static let supabaseURLKey = "supabase_url"

    /// Key for storing the Supabase anon key in shared UserDefaults
    static let supabaseAnonKeyKey = "supabase_anon_key"

    // MARK: - Supabase Configuration
    /// The user's ID stored in the auth token claims
    /// (This is typically extracted from the JWT token on the main app side)
    static let userIDKeychainKey = "user_id"

    // MARK: - Supabase Table & Column Names
    /// Bookmarks table name
    static let bookmarksTable = "bookmarks"

    /// Records table name
    static let recordsTable = "records"
}
