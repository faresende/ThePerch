import Foundation
import Security

// MARK: - AppConfiguration

/// Runtime backend configuration stored securely in Keychain.
/// Replaces compile-time Secrets.plist for the open-source / self-hosted use case.
struct AppConfiguration: Codable, Equatable {
    let supabaseURL: String
    let supabaseAnonKey: String
    let backendMode: BackendMode

    enum BackendMode: String, Codable {
        case selfHosted = "self_hosted"
        case managedCloud = "managed_cloud"
    }
}

// MARK: - KeychainService

/// Stores and retrieves `AppConfiguration` from the system Keychain.
final class KeychainService {
    static let shared = KeychainService()

    private let service = "com.NotButter.ThePerch"
    private let account = "AppConfiguration"

    private init() {}

    // MARK: - Save

    func save(_ config: AppConfiguration) throws {
        let data = try JSONEncoder().encode(config)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String:   data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }

    // MARK: - Load

    func load() -> AppConfiguration? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AppConfiguration.self, from: data)
    }

    // MARK: - Clear

    func clear() {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Errors

    enum KeychainError: LocalizedError {
        case unhandledError(status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .unhandledError(let status):
                return "Keychain error: \(status)"
            }
        }
    }
}
