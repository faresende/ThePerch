import Foundation

// MARK: - Karakeep API Response Models

/// A bookmark as returned directly by the Karakeep API.
struct KarakeepBookmark: Identifiable, Codable, Sendable, Hashable {
    let id: String
    let url: String
    let title: String?
    let description: String?
    let tags: [String]
    let domain: String?
    let imageURL: String?
    let readingTimeMinutes: Int?
    let status: KarakeepStatus
    let createdAt: Date
    let updatedAt: Date

    enum KarakeepStatus: String, Codable, Sendable {
        case pending
        case processing
        case processed
        case failed
    }

    var displayTitle: String {
        title ?? domain ?? url
    }

    var summary: String? { description }

    var fileName: String? { nil }
    var fileType: String? { nil }

    var source: BookmarkSource { .karakeep }

    enum CodingKeys: String, CodingKey {
        case id, url, title, description, tags, domain
        case imageURL = "image_url"
        case readingTimeMinutes = "reading_time_minutes"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - API List Response

struct KarakeepListResponse: Codable, Sendable {
    let items: [KarakeepBookmark]
    let total: Int?
    let page: Int?
    let pageSize: Int?

    enum CodingKeys: String, CodingKey {
        case items, total, page
        case pageSize = "page_size"
    }
}

// MARK: - API Error Response

struct KarakeepAPIError: Codable, Sendable, LocalizedError {
    let message: String
    let code: String?

    var errorDescription: String? { message }
}

// MARK: - KarakeepService Errors

enum KarakeepServiceError: LocalizedError, Sendable {
    case invalidURL
    case networkError(String)
    case decodingError(String)
    case serverError(Int, String)
    case timeout
    case unauthorized
    case offline

    var errorDescription: String? {
        switch self {
        case .invalidURL:          return "Invalid API URL"
        case .networkError(let s): return "Network error: \(s)"
        case .decodingError(let s): return "Failed to parse response: \(s)"
        case .serverError(let c, let s): return "Server error (\(c)): \(s)"
        case .timeout:             return "Request timed out"
        case .unauthorized:        return "Invalid or expired API token"
        case .offline:            return "No internet connection"
        }
    }
}

// MARK: - KarakeepService

/// Singleton service for direct Karakeep API access.
/// Provides reliable bookmark fetching with retry logic and proper error handling.
@MainActor
final class KarakeepService {
    static let shared = KarakeepService()

    // MARK: - Configuration

    /// The Karakeep API token from AppConfig / environment.
    private var apiToken: String {
        AppConfig.shared.karakeepToken
    }

    /// The base URL for the Karakeep API. Override via `KARAKEEP_BASE_URL`
    /// in Secrets.plist / Info.plist if you self-host Karakeep on your own
    /// domain. Users without Karakeep should leave `karakeepToken` empty —
    /// callers skip this service when the token is unset.
    private let baseURL: String = {
        if let override = Bundle.main.infoDictionary?["KARAKEEP_BASE_URL"] as? String, !override.isEmpty {
            return override
        }
        return "https://karakeep.example.com/api/v1"
    }()

    // MARK: - Private

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0
    private let requestTimeout: TimeInterval = 15

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestTimeout
        config.timeoutIntervalForResource = requestTimeout
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)

        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase

        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Public API

    /// Fetches all bookmarks from Karakeep with optional filtering.
    /// - Parameters:
    ///   - status: Filter by bookmark status (optional).
    ///   - limit: Maximum number of bookmarks to return (default 500).
    /// - Returns: Array of `KarakeepBookmark` objects.
    func fetchBookmarks(status: KarakeepBookmark.KarakeepStatus? = nil, limit: Int = 500) async throws -> [KarakeepBookmark] {
        var components = URLComponents(string: "\(baseURL)/bookmarks")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort", value: "-created_at")
        ]
        if let status {
            queryItems.append(URLQueryItem(name: "status", value: status.rawValue))
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw KarakeepServiceError.invalidURL
        }

        let data = try await performRequest(url: url, method: "GET")

        // Try to decode as list response first, fall back to array
        if let listResponse = try? decoder.decode(KarakeepListResponse.self, from: data) {
            return listResponse.items
        }

        do {
            return try decoder.decode([KarakeepBookmark].self, from: data)
        } catch {
            throw KarakeepServiceError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches a single bookmark by ID.
    /// - Parameter id: The bookmark's unique identifier.
    /// - Returns: The `KarakeepBookmark` object.
    func fetchBookmark(id: String) async throws -> KarakeepBookmark {
        guard let url = URL(string: "\(baseURL)/bookmarks/\(id)") else {
            throw KarakeepServiceError.invalidURL
        }

        let data = try await performRequest(url: url, method: "GET")

        do {
            return try decoder.decode(KarakeepBookmark.self, from: data)
        } catch {
            throw KarakeepServiceError.decodingError(error.localizedDescription)
        }
    }

    /// Searches bookmarks by query string.
    /// - Parameter query: The search query.
    /// - Returns: Array of matching `KarakeepBookmark` objects.
    func searchBookmarks(query: String) async throws -> [KarakeepBookmark] {
        var components = URLComponents(string: "\(baseURL)/bookmarks/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "100")
        ]

        guard let url = components.url else {
            throw KarakeepServiceError.invalidURL
        }

        let data = try await performRequest(url: url, method: "GET")

        if let listResponse = try? decoder.decode(KarakeepListResponse.self, from: data) {
            return listResponse.items
        }

        do {
            return try decoder.decode([KarakeepBookmark].self, from: data)
        } catch {
            throw KarakeepServiceError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Request Helper

    /// Performs an HTTP request with exponential backoff retry.
    private func performRequest(url: URL, method: String, body: Data? = nil) async throws -> Data {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = method
                request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                if let body {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = body
                }

                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw KarakeepServiceError.networkError("Invalid response")
                }

                switch httpResponse.statusCode {
                case 200...299:
                    return data
                case 401, 403:
                    throw KarakeepServiceError.unauthorized
                case 400...499:
                    let message = String(data: data, encoding: .utf8) ?? "Client error"
                    throw KarakeepServiceError.serverError(httpResponse.statusCode, message)
                case 500...599:
                    let message = String(data: data, encoding: .utf8) ?? "Server error"
                    throw KarakeepServiceError.serverError(httpResponse.statusCode, message)
                default:
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    throw KarakeepServiceError.serverError(httpResponse.statusCode, message)
                }
            } catch let error as KarakeepServiceError {
                // Don't retry auth errors
                if case .unauthorized = error { throw error }
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch let error as URLError {
                if error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                    throw KarakeepServiceError.offline
                }
                if error.code == .timedOut {
                    throw KarakeepServiceError.timeout
                }
                lastError = KarakeepServiceError.networkError(error.localizedDescription)
                if attempt < maxRetries - 1 {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            } catch {
                lastError = KarakeepServiceError.networkError(error.localizedDescription)
                if attempt < maxRetries - 1 {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? KarakeepServiceError.networkError("All retries exhausted")
    }
}
