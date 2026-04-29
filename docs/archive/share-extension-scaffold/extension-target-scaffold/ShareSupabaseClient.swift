import Foundation

/**
 ShareSupabaseClient - Lightweight Supabase client for the Share Extension

 This client handles writing bookmark data to Supabase.
 It reads credentials from App Group UserDefaults and writes to two tables:
 - bookmarks: Direct bookmark records
 - records: Generic record table for the OpenClaw agent pipeline
 */

enum ShareSupabaseError: LocalizedError {
    case credentialsNotFound
    case invalidURL
    case invalidRequest
    case networkError(String)
    case decodingError(String)
    case serverError(Int, String)
    case unknownError

    var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            return "Supabase credentials not found. Please open The Perch app first."
        case .invalidURL:
            return "Invalid URL format."
        case .invalidRequest:
            return "Failed to prepare request."
        case .networkError(let message):
            return "Network error: \(message)"
        case .decodingError(let message):
            return "Failed to parse response: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .unknownError:
            return "An unknown error occurred."
        }
    }
}

struct BookmarkResponse: Codable {
    let id: String
    let url: String
    let original_title: String?
    let tags: [String]?
    let status: String
    let submitted_from: String
    let user_id: String
    let created_at: String
}

class ShareSupabaseClient {
    private let sharedCredentials = SharedCredentials()

    // MARK: - Public API

    /// Save a bookmark to Supabase
    /// - Parameters:
    ///   - url: The URL to bookmark
    ///   - title: Optional page title
    ///   - tags: Array of tags for organization
    /// - Returns: The ID of the created bookmark
    func saveBookmark(
        url: String,
        title: String?,
        tags: [String]
    ) async throws -> String {
        guard let (supabaseURL, anonKey, accessToken, userId) = sharedCredentials.loadCredentials() else {
            throw ShareSupabaseError.credentialsNotFound
        }

        guard URL(string: url) != nil else {
            throw ShareSupabaseError.invalidURL
        }

        let bookmarkID = UUID().uuidString

        // Write to bookmarks table
        try await insertBookmark(
            id: bookmarkID,
            url: url,
            title: title,
            tags: tags,
            accessToken: accessToken,
            supabaseURL: supabaseURL,
            anonKey: anonKey
        )

        // Write to records table for agent processing
        try await insertRecord(
            id: UUID().uuidString,
            bookmarkID: bookmarkID,
            url: url,
            title: title,
            tags: tags,
            userId: userId,
            accessToken: accessToken,
            supabaseURL: supabaseURL,
            anonKey: anonKey
        )

        return bookmarkID
    }

    // MARK: - Private Methods

    private func insertBookmark(
        id: String,
        url: String,
        title: String?,
        tags: [String],
        accessToken: String,
        supabaseURL: String,
        anonKey: String
    ) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/bookmarks"

        var request = try createRequest(
            url: endpoint,
            method: "POST",
            anonKey: anonKey,
            accessToken: accessToken
        )

        let payload: [String: Any] = [
            "id": id,
            "url": url,
            "original_title": title ?? NSNull(),
            "tags": tags.isEmpty ? NSNull() : tags,
            "status": "pending",
            "submitted_from": "ios_share"
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
    }

    private func insertRecord(
        id: String,
        bookmarkID: String,
        url: String,
        title: String?,
        tags: [String],
        userId: String,
        accessToken: String,
        supabaseURL: String,
        anonKey: String
    ) async throws {
        let endpoint = "\(supabaseURL)/rest/v1/records"

        var request = try createRequest(
            url: endpoint,
            method: "POST",
            anonKey: anonKey,
            accessToken: accessToken
        )

        let recordData: [String: Any] = [
            "url": url,
            "original_title": title ?? NSNull(),
            "tags": tags.isEmpty ? NSNull() : tags,
            "status": "pending",
            "submitted_from": "ios_share",
            "bookmark_id": bookmarkID
        ]

        let payload: [String: Any] = [
            "id": id,
            "type": "bookmark",
            "category": "bookmarks",
            "title": title ?? url,
            "display_hint": "bookmark_card",
            "data": recordData,
            "user_id": userId,
            "agent_id": "main"
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)
    }

    private func createRequest(
        url: String,
        method: String,
        anonKey: String,
        accessToken: String
    ) throws -> URLRequest {
        guard let requestURL = URL(string: url) else {
            throw ShareSupabaseError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")

        return request
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShareSupabaseError.unknownError
        }

        switch httpResponse.statusCode {
        case 200...299:
            break // Success
        case 400...499:
            let message = "Client error: \(httpResponse.statusCode)"
            throw ShareSupabaseError.serverError(httpResponse.statusCode, message)
        case 500...599:
            let message = "Server error: \(httpResponse.statusCode)"
            throw ShareSupabaseError.serverError(httpResponse.statusCode, message)
        default:
            throw ShareSupabaseError.serverError(httpResponse.statusCode, "Unknown error")
        }
    }
}

