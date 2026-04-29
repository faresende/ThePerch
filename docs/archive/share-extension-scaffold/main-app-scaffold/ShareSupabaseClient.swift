import Foundation

/// Lightweight Supabase client for the Share Extension
/// Reads auth credentials from shared App Group keychain/UserDefaults
/// Minimal dependencies to keep extension memory footprint low
class ShareSupabaseClient {
    private let supabaseURL: URL
    private let anonKey: String
    private let authToken: String

    private let decoder = JSONDecoder()

    enum ShareSupabaseError: LocalizedError {
        case missingCredentials(String)
        case invalidURL
        case networkError(String)
        case decodingError(String)
        case serverError(Int, String)
        case unknown

        var errorDescription: String? {
            switch self {
            case .missingCredentials(let detail):
                return "Missing credentials: \(detail)"
            case .invalidURL:
                return "Invalid Supabase URL"
            case .networkError(let detail):
                return "Network error: \(detail)"
            case .decodingError(let detail):
                return "Failed to parse response: \(detail)"
            case .serverError(let code, let detail):
                return "Server error (\(code)): \(detail)"
            case .unknown:
                return "An unknown error occurred"
            }
        }
    }

    init() throws {
        // Read Supabase credentials from shared App Group UserDefaults
        guard let defaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier) else {
            throw ShareSupabaseError.missingCredentials("Could not access shared App Group defaults")
        }

        guard let urlString = defaults.string(forKey: SharedConstants.supabaseURLKey),
              let url = URL(string: urlString) else {
            throw ShareSupabaseError.missingCredentials("Supabase URL not configured")
        }

        guard let key = defaults.string(forKey: SharedConstants.supabaseAnonKeyKey) else {
            throw ShareSupabaseError.missingCredentials("Supabase anon key not configured")
        }

        self.supabaseURL = url
        self.anonKey = key

        // Read auth token from shared Keychain
        guard let token = KeychainHelper.retrieve(
            key: SharedConstants.authTokenKeychainKey,
            service: SharedConstants.keychainService
        ) else {
            throw ShareSupabaseError.missingCredentials("Auth token not found in keychain")
        }

        self.authToken = token
    }

    /// Save a bookmark to Supabase
    /// Inserts rows in both `bookmarks` and `records` tables
    /// - Returns: UUID of the created bookmark
    func saveBookmark(url: String, title: String, tags: [String]) async throws -> UUID {
        let bookmarkID = UUID()

        // Extract domain from URL
        let domain = extractDomain(from: url)

        // Step 1: Insert into bookmarks table
        let bookmarkPayload: [String: Any] = [
            "id": bookmarkID.uuidString,
            "url": url,
            "title": title,
            "domain": domain,
            "tags": tags,
            "status": "pending",
            "created_at": ISO8601DateFormatter().string(from: Date()),
        ]

        try await insertRow(
            table: "bookmarks",
            payload: bookmarkPayload
        )

        // Step 2: Insert into records table
        let recordPayload: [String: Any] = [
            "id": UUID().uuidString,
            "bookmark_id": bookmarkID.uuidString,
            "type": "bookmark",
            "category": "bookmarks",
            "display_hint": "bookmark_card",
            "metadata": [
                "url": url,
                "title": title,
                "tags": tags,
            ],
            "created_at": ISO8601DateFormatter().string(from: Date()),
        ]

        try await insertRow(
            table: "records",
            payload: recordPayload
        )

        return bookmarkID
    }

    // MARK: - Private Helpers

    private func insertRow(table: String, payload: [String: Any]) async throws {
        var request = URLRequest(url: supabaseURL.appendingPathComponent("/rest/v1/\(table)"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("true", forHTTPHeaderField: "Prefer")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw ShareSupabaseError.decodingError("Failed to encode payload: \(error.localizedDescription)")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareSupabaseError.networkError("Invalid response type")
        }

        switch httpResponse.statusCode {
        case 200, 201:
            // Success
            return
        case 400...599:
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ShareSupabaseError.serverError(httpResponse.statusCode, errorBody)
        default:
            throw ShareSupabaseError.unknown
        }
    }

    private func extractDomain(from urlString: String) -> String {
        if let url = URL(string: urlString), let host = url.host {
            // Remove "www." prefix if present
            if host.hasPrefix("www.") {
                return String(host.dropFirst(4))
            }
            return host
        }
        return urlString
    }
}

// MARK: - Keychain Helper

/// Simple keychain wrapper for the share extension
private struct KeychainHelper {
    static func retrieve(key: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecAttrAccessGroup as String: SharedConstants.appGroupIdentifier,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func store(key: String, value: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: SharedConstants.appGroupIdentifier,
        ]

        SecItemDelete(query as CFDictionary)

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: value.data(using: .utf8) ?? Data(),
            kSecAttrAccessGroup as String: SharedConstants.appGroupIdentifier,
        ]

        SecItemAdd(attributes as CFDictionary, nil)
    }
}
