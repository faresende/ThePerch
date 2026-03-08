import Foundation

/// Persists records and sections to local JSON files for offline access.
/// Cache is keyed by user ID to support multi-user scenarios.
@MainActor
final class CacheService {
    static let shared = CacheService()

    /// Maximum cache age in seconds (7 days).
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60

    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private init() {
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.cacheDirectory = documentsDir.appendingPathComponent("cache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Cache Keys

    private func cacheFileURL(for key: String, userId: String) -> URL {
        cacheDirectory.appendingPathComponent("\(userId)_\(key).json")
    }

    private func metadataURL(for key: String, userId: String) -> URL {
        cacheDirectory.appendingPathComponent("\(userId)_\(key)_meta.json")
    }

    // MARK: - Metadata

    struct CacheMetadata: Codable {
        let cachedAt: Date
        let key: String

        var age: TimeInterval {
            Date.now.timeIntervalSince(cachedAt)
        }

        var relativeAgeString: String {
            let minutes = Int(age / 60)
            if minutes < 1 { return "just now" }
            if minutes < 60 { return "\(minutes)m ago" }
            let hours = minutes / 60
            if hours < 24 { return "\(hours)h ago" }
            let days = hours / 24
            return "\(days)d ago"
        }
    }

    // MARK: - Save

    func saveRecords(_ records: [Record], category: RecordCategory?, userId: String) {
        let key = cacheKey(for: category)
        save(records, key: key, userId: userId)
    }

    func saveSections(_ sections: [Section], userId: String) {
        save(sections, key: "sections", userId: userId)
    }

    private func save<T: Encodable>(_ value: T, key: String, userId: String) {
        guard let data = try? encoder.encode(value) else { return }
        let fileURL = cacheFileURL(for: key, userId: userId)
        try? data.write(to: fileURL, options: .atomic)

        let metadata = CacheMetadata(cachedAt: Date.now, key: key)
        if let metaData = try? encoder.encode(metadata) {
            try? metaData.write(to: metadataURL(for: key, userId: userId), options: .atomic)
        }
    }

    // MARK: - Load

    func loadRecords(category: RecordCategory?, userId: String) -> [Record]? {
        let key = cacheKey(for: category)
        return load([Record].self, key: key, userId: userId)
    }

    func loadSections(userId: String) -> [Section]? {
        load([Section].self, key: "sections", userId: userId)
    }

    private func load<T: Decodable>(_ type: T.Type, key: String, userId: String) -> T? {
        let fileURL = cacheFileURL(for: key, userId: userId)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    // MARK: - Metadata Queries

    func metadata(for category: RecordCategory?, userId: String) -> CacheMetadata? {
        let key = cacheKey(for: category)
        return loadMetadata(key: key, userId: userId)
    }

    func sectionsMetadata(userId: String) -> CacheMetadata? {
        loadMetadata(key: "sections", userId: userId)
    }

    private func loadMetadata(key: String, userId: String) -> CacheMetadata? {
        let metaURL = metadataURL(for: key, userId: userId)
        guard let data = try? Data(contentsOf: metaURL),
              let meta = try? decoder.decode(CacheMetadata.self, from: data) else { return nil }
        return meta
    }

    /// Whether cached data is older than maxCacheAge (7 days).
    func isCacheStale(category: RecordCategory?, userId: String) -> Bool {
        guard let meta = metadata(for: category, userId: userId) else { return true }
        return meta.age > maxCacheAge
    }

    // MARK: - Helpers

    private func cacheKey(for category: RecordCategory?) -> String {
        "records_\(category?.rawValue ?? "all")"
    }

    /// Clears all cache files for a specific user.
    func clearCache(userId: String) {
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        for file in files where file.lastPathComponent.hasPrefix(userId) {
            try? fileManager.removeItem(at: file)
        }
    }
}
