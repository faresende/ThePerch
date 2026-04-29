import Foundation

/// Persists records and sections to local JSON files for offline access.
/// Cache is keyed by user ID to support multi-user scenarios.
///
/// `nonisolated` because the project's default actor-isolation is
/// MainActor — but every CacheService method is explicitly off-main
/// (we hop onto `ioQueue` for I/O, or call from `Task.detached`).
/// Marking the class nonisolated avoids the per-method annotation and
/// keeps Sendable-conformance for nested types like `CacheMetadata`.
nonisolated final class CacheService: @unchecked Sendable {
    static let shared = CacheService()

    /// Maximum cache age in seconds (7 days).
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60

    private let cacheDirectory: URL
    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.notbutter.theperch.cache-service")
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
        // Fire-and-forget: cache writes are not load-bearing for any UI
        // path — the only consumer is the next cold launch. Previous
        // version used `ioQueue.sync` from MainActor (every successful
        // network response paid 5–25 ms of synchronous JSON encode +
        // atomic file write on the UI thread). Switching to async means
        // loadDashboard returns immediately after the network landed.
        ioQueue.async { [encoder, fileURL = cacheFileURL(for: key, userId: userId), metaURL = metadataURL(for: key, userId: userId)] in
            guard let data = try? encoder.encode(value) else { return }
            try? data.write(to: fileURL, options: .atomic)

            let metadata = CacheMetadata(cachedAt: Date.now, key: key)
            if let metaData = try? encoder.encode(metadata) {
                try? metaData.write(to: metaURL, options: .atomic)
            }
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

    /// One-shot bundle load used by `DashboardViewModel.loadCachedData`.
    /// Three sequential `ioQueue.sync` hops collapsed to one — the
    /// serial queue used to serialize them anyway, but Swift's `sync`
    /// indirection still cost a few extra ms per hop on cold launch.
    struct CachedBundle: Sendable {
        let sections: [Section]?
        let records: [Record]?
        let metaAge: String?
    }

    func loadDashboardBundle(userId: String) -> CachedBundle {
        let recordsKey = cacheKey(for: nil)
        let sectionsKey = "sections"
        return ioQueue.sync {
            let sections: [Section]? = {
                let url = cacheFileURL(for: sectionsKey, userId: userId)
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode([Section].self, from: data)
            }()
            let records: [Record]? = {
                let url = cacheFileURL(for: recordsKey, userId: userId)
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode([Record].self, from: data)
            }()
            let metaAge: String? = {
                let url = metadataURL(for: recordsKey, userId: userId)
                guard let data = try? Data(contentsOf: url),
                      let meta = try? decoder.decode(CacheMetadata.self, from: data) else { return nil }
                return meta.relativeAgeString
            }()
            return CachedBundle(sections: sections, records: records, metaAge: metaAge)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String, userId: String) -> T? {
        ioQueue.sync {
            let fileURL = cacheFileURL(for: key, userId: userId)
            guard let data = try? Data(contentsOf: fileURL) else { return nil }
            return try? decoder.decode(type, from: data)
        }
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
        ioQueue.sync {
            let metaURL = metadataURL(for: key, userId: userId)
            guard let data = try? Data(contentsOf: metaURL),
                  let meta = try? decoder.decode(CacheMetadata.self, from: data) else { return nil }
            return meta
        }
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
        ioQueue.sync {
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
}
