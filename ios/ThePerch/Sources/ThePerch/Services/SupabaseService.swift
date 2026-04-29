import Foundation
import Combine
import Network
import Supabase
import Realtime

extension Notification.Name {
    static let supabaseAuthStateChanged = Notification.Name("SupabaseAuthStateChanged")
}

// MARK: - Session Expiry

extension Session {
    /// Whether this session's access token has already expired.
    /// Used to gate `isAuthenticated` so we don't treat an expired
    /// locally-cached session as a valid login (Supabase SDK emits
    /// expired sessions as `.initialSession` during app launch; see
    /// https://github.com/supabase/supabase-swift/pull/822).
    var isExpired: Bool {
        Date().timeIntervalSince1970 >= expiresAt
    }
}

// MARK: - Error Types

/// Errors that can occur during Supabase operations.
enum SupabaseServiceError: LocalizedError, Sendable {
    case clientNotInitialized
    case authError(String)
    case queryError(String)
    case decodingError(String)
    case networkError(String)
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .clientNotInitialized:
            return "Supabase client is not initialized"
        case .authError(let message):
            return "Authentication error: \(message)"
        case .queryError(let message):
            return "Query error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .unknownError(let message):
            return "Unknown error: \(message)"
        }
    }
}

// MARK: - Cache Entry

/// A time-stamped cache entry for avoiding redundant network requests within 30 seconds.
private struct CacheEntry<T> {
    let value: T
    let fetchedAt: Date

    var isStale: Bool {
        Date.now.timeIntervalSince(fetchedAt) > 30
    }
}

// MARK: - Data Freshness Tracking

/// Tracks when each data category was last fetched, for UI display and auto-refresh.
enum UrgencyTier {
    case fresh      // <5 min
    case stale      // >5 min — warning dot
    case warning    // >30 min — pulsing amber border
    case critical   // >2 hours — solid warning border
}

@Observable
@MainActor
final class DataFreshnessTracker {
    static let shared = DataFreshnessTracker()

    private(set) var lastFetchTimes: [String: Date] = [:]

    /// Auto-refresh threshold in seconds (5 minutes).
    let staleThreshold: TimeInterval = 300

    func recordFetch(for key: String) {
        lastFetchTimes[key] = Date.now
    }

    func isStale(_ key: String) -> Bool {
        guard let lastFetch = lastFetchTimes[key] else { return true }
        return Date.now.timeIntervalSince(lastFetch) > staleThreshold
    }

    func urgencyTier(for key: String) -> UrgencyTier {
        guard let lastFetch = lastFetchTimes[key] else { return .critical }
        let elapsed = Date.now.timeIntervalSince(lastFetch)
        if elapsed > 7200 { return .critical }
        if elapsed > 1800 { return .warning }
        if elapsed > 300 { return .stale }
        return .fresh
    }

    func relativeTimeString(for key: String) -> String? {
        guard let lastFetch = lastFetchTimes[key] else { return nil }
        let interval = Date.now.timeIntervalSince(lastFetch)
        let minutes = Int(interval / 60)
        if minutes < 1 {
            return "Updated just now"
        } else if minutes == 1 {
            return "Updated 1 min ago"
        } else {
            return "Updated \(minutes) min ago"
        }
    }
}

// MARK: - SupabaseService

/// A singleton service for managing Supabase interactions.
/// Connects to the real Supabase backend, with mock data fallback.
@MainActor
final class SupabaseService: ObservableObject, SupabaseServiceProtocol {
    static let shared = SupabaseService()

    // MARK: - Published Properties

    @Published var isAuthenticated: Bool = false
    @Published var isPasswordRecovery: Bool = false
    @Published var isLoading: Bool = false
    @Published var error: SupabaseServiceError?
    @Published var connectionError: String?
    @Published var isOffline: Bool = false

    // MARK: - Private Properties

    #if DEBUG
    /// Toggle to fall back to mock data during development only.
    private var useMockData = ProcessInfo.processInfo.arguments.contains("-uiDebugUseMockData")
    #endif

    /// The Supabase client instance.
    private let client: SupabaseClient
    private var authStateTask: Task<Void, Never>?

    /// Active realtime channels for subscription management.
    private var recordsChannel: RealtimeChannelV2?
    private var agentsChannel: RealtimeChannelV2?

    /// Managed tasks for realtime stream listeners (cancelled on unsubscribe).
    private var realtimeTasks: [Task<Void, Never>] = []

    /// Tracks when each category was last fetched for data freshness.
    @Published var lastFetchTimes: [RecordCategory: Date] = [:]
    @Published var lastGlobalFetchTime: Date?

    /// Shared JSON decoder for Supabase responses (ISO8601 dates).
    private let recordDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Retry configuration
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0

    // MARK: - Cache

    private var sectionsCache: CacheEntry<[Section]>?
    private var recordsCache: [String: CacheEntry<[Record]>] = [:]
    private var agentsCache: CacheEntry<[Agent]>?
    private var homeWidgetsCache: CacheEntry<[HomeWidget]>?

    let freshnessTracker = DataFreshnessTracker.shared
    private let cacheService = CacheService.shared

    /// The currently authenticated user's ID, updated whenever auth state changes.
    /// Used for user-scoped disk cache and widget shared defaults.
    private(set) var currentUserId: String?

    /// Cache key scoped to the signed-in user. Falls back to "unauthenticated" so
    /// signed-out cache reads never collide with any real user's data.
    private var cacheUserId: String {
        currentUserId ?? "unauthenticated"
    }

    // MARK: - Initialization

    private init() {
        // Cold-start critical path: only construct the SupabaseClient
        // here (50–150 ms first call — still expensive but unavoidable
        // since AuthViewModel.init() reads `isAuthenticated` synchronously
        // for the @State default).
        //
        // `startNetworkMonitoring` + `startAuthStateObserver` were
        // previously called here too — moved to `bootstrap()` which
        // ThePerchApp invokes from a `.task` AFTER first frame. Saved
        // ~30–100 ms off the critical path because both methods spawn
        // Tasks that hop the actor and re-arm observers; cheaper to
        // defer to post-paint than block init.
        let config = AppConfig.shared
        self.client = SupabaseClient(
            supabaseURL: config.supabaseURL,
            supabaseKey: config.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(redirectToURL: URL(string: "theperch://auth/callback"))
            )
        )
    }

    /// Idempotent post-first-frame bootstrap. Wires up network +
    /// auth-state observers that don't need to be live before the
    /// first paint.
    private var didBootstrap = false
    func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        startNetworkMonitoring()
        startAuthStateObserver()
    }

    var databaseClient: SupabaseClient {
        client
    }

    private func startAuthStateObserver() {
        authStateTask?.cancel()
        authStateTask = Task { [weak self] in
            guard let self else { return }
            for await (event, session) in client.auth.authStateChanges {
                // Task body inherits MainActor from the enclosing
                // service, so the call to `handleAuthStateChange` is a
                // straight invocation — no actor hop needed.
                self.handleAuthStateChange(event, session: session)
            }
        }
    }

    private func handleAuthStateChange(_ event: AuthChangeEvent, session: Session?) {
        switch event {
        case .passwordRecovery:
            isAuthenticated = session != nil
            isPasswordRecovery = true
            if let session { currentUserId = session.user.id.uuidString }
        case .signedIn:
            // Fresh sign-in always carries a just-minted session from the server.
            // Don't second-guess expiry here — any perceived "expiry" is clock
            // skew, not stale credentials.
            isAuthenticated = session != nil
            isPasswordRecovery = false
            currentUserId = session?.user.id.uuidString
        case .signedOut, .userDeleted:
            isAuthenticated = false
            isPasswordRecovery = false
            currentUserId = nil
        case .initialSession:
            // This is the ONLY event where the expiry check matters.
            // Supabase emits locally-stored sessions via .initialSession
            // regardless of expiry — using an expired token here causes
            // silent-empty dashboard fetches instead of a clean 401.
            let isValid = session != nil && !(session?.isExpired ?? true)
            isAuthenticated = isValid
            currentUserId = isValid ? session?.user.id.uuidString : nil
            if session == nil {
                isPasswordRecovery = false
            }
#if DEBUG
            if let session, session.isExpired {
                print("[SupabaseService] initialSession emitted an EXPIRED session; treating as unauthenticated (expires at \(Date(timeIntervalSince1970: session.expiresAt))).")
            }
#endif
        case .tokenRefreshed, .userUpdated, .mfaChallengeVerified:
            // SDK-driven events — if the SDK is handing us a session, trust it.
            isAuthenticated = session != nil
            currentUserId = session?.user.id.uuidString
        }

        NotificationCenter.default.post(
            name: .supabaseAuthStateChanged,
            object: self,
            userInfo: ["event": event.rawValue]
        )
    }

    private func authParameters(from url: URL) -> [String: String] {
        var params: [String: String] = [:]

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryItems = components.queryItems {
            for item in queryItems {
                if let value = item.value {
                    params[item.name] = value
                }
            }
        }

        if let fragment = url.fragment,
           let components = URLComponents(string: "https://theperch.invalid?\(fragment)"),
           let queryItems = components.queryItems {
            for item in queryItems {
                if let value = item.value {
                    params[item.name] = value
                }
            }
        }

        return params
    }

    // MARK: - Connection Test

    /// Tests a Supabase connection without affecting the shared service.
    /// Used by OnboardingView to validate credentials before saving.
    static func testConnection(url: String, anonKey: String) async throws {
        guard let supabaseURL = URL(string: url) else {
            throw URLError(.badURL)
        }
        let testClient = SupabaseClient(supabaseURL: supabaseURL, supabaseKey: anonKey)
        // Try fetching 1 section — if this succeeds the credentials are valid
        let _: [Section] = try await testClient
            .from("sections")
            .select()
            .limit(1)
            .execute()
            .value
    }

    // MARK: - Network Monitoring

    private func startNetworkMonitoring() {
        _ = withObservationTracking {
            NetworkMonitor.shared.isConnected
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOffline = !NetworkMonitor.shared.isConnected
                if NetworkMonitor.shared.isConnected {
                    self.connectionError = nil
                }
                self.startNetworkMonitoring()
            }
        }

        isOffline = !NetworkMonitor.shared.isConnected
        if NetworkMonitor.shared.isConnected {
            connectionError = nil
        }
    }

    // MARK: - Retry Logic

    /// Executes an async operation with exponential backoff retry (3 attempts).
    /// The body inherits `@MainActor` isolation from the enclosing service so
    /// callers can freely use MainActor-isolated state (e.g. cached decoders,
    /// the SupabaseClient) without `@Sendable` capture gymnastics.
    private func withRetry<T>(
        operation: String,
        body: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let result = try await body()
                self.connectionError = nil
                return result
            } catch {
                lastError = error
                // Fast-fail when offline. Without this, opening the app
                // on cellular with no signal stacks up to 1+2 = 3 s of
                // backoff sleeps × 7 parallel cold fetches before the
                // cached fallback gets a chance — the user just sees
                // a spinner.
                if !NetworkMonitor.shared.isConnected {
#if DEBUG
                    print("[\(operation)] Network is offline — failing fast without retry")
#endif
                    break
                }
                if attempt < maxRetries - 1 {
                    let delay = baseRetryDelay * pow(2.0, Double(attempt))
#if DEBUG
                    print("[\(operation)] Attempt \(attempt + 1) failed, retrying in \(delay)s: \(error.localizedDescription)")
#endif
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        let finalError = lastError ?? SupabaseServiceError.unknownError("All retries exhausted")
        connectionError = finalError.localizedDescription
        throw finalError
    }

    // MARK: - Cache Helpers

    private func recordsCacheKey(category: RecordCategory?, type: RecordType?, limit: Int) -> String {
        "\(category?.rawValue ?? "all")_\(type?.rawValue ?? "all")_\(limit)"
    }

    /// Invalidates all caches.
    func invalidateCache() {
        sectionsCache = nil
        recordsCache.removeAll()
        agentsCache = nil
        homeWidgetsCache = nil
    }

    /// Clears widget shared defaults on sign-out so a new user's widgets start blank.
    private func clearWidgetSharedDefaults() {
        guard let defaults = UserDefaults(suiteName: "group.com.theperch.shared") else { return }
        let widgetKeys = [
            "widget_calories_percent", "widget_calories_consumed", "widget_calories_target",
            "widget_next_event", "widget_next_event_title", "widget_next_event_time",
            "widget_active_deliveries", "widget_last_updated"
        ]
        for key in widgetKeys { defaults.removeObject(forKey: key) }
    }

    // MARK: - Authentication Methods

    /// Signs in a user with email and password.
    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        #if DEBUG
        if useMockData {
            try await Task.sleep(nanoseconds: 500_000_000)
            self.isAuthenticated = true
            self.isPasswordRecovery = false
            self.error = nil
            return
        }
        #endif

        do {
            try await client.auth.signIn(email: email, password: password)
            self.isAuthenticated = true
            self.isPasswordRecovery = false
            self.error = nil
        } catch {
            throw SupabaseServiceError.authError(error.localizedDescription)
        }
    }

    /// Signs up a new user with email, password, and display name.
    func signUp(email: String, password: String, displayName: String) async throws {
        isLoading = true
        defer { isLoading = false }

        #if DEBUG
        if useMockData {
            try await Task.sleep(nanoseconds: 500_000_000)
            self.isAuthenticated = true
            self.isPasswordRecovery = false
            self.error = nil
            return
        }
        #endif

        do {
            try await client.auth.signUp(
                email: email,
                password: password,
                data: ["display_name": .string(displayName)]
            )
            self.isAuthenticated = true
            self.isPasswordRecovery = false
            self.error = nil
        } catch {
            throw SupabaseServiceError.authError(error.localizedDescription)
        }
    }

    /// Sends a password reset email using the configured deep-link callback.
    func sendPasswordReset(email: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            try await client.auth.resetPasswordForEmail(email)
            self.error = nil
        } catch {
            throw SupabaseServiceError.authError(error.localizedDescription)
        }
    }

    /// Handles incoming auth callback URLs, including password recovery links.
    ///
    /// SECURITY: A naive `client.auth.session(from: url)` accepts ANY
    /// `theperch://x#access_token=…&refresh_token=…` URL — including
    /// one an attacker hands to the victim via Messages, a webview,
    /// AirDrop, etc. — and writes those attacker tokens into the SDK
    /// session. Result: session fixation (victim's app is now signed
    /// in as the attacker; subsequent writes go to the attacker's
    /// account). Round 7 audit caught this.
    ///
    /// Defenses applied here:
    ///   1. Reject any URL whose scheme isn't `theperch` (defensive —
    ///      iOS only routes us our scheme, but custom schemes can be
    ///      hijacked by other apps).
    ///   2. Require host = "auth" + path = "/callback" so only the
    ///      registered redirect path qualifies.
    ///   3. Require `type` = "recovery" or "signup" or "magiclink" or
    ///      "invite" — the four types Supabase Auth emits. Reject any
    ///      other value (including missing).
    ///   4. Refuse to clobber an EXISTING signed-in session unless the
    ///      URL is a recovery flow. A user already signed in shouldn't
    ///      be silently re-authed by a deeplink they didn't initiate.
    @discardableResult
    func handleIncomingAuthURL(_ url: URL) async throws -> Bool {
        // 1. Scheme + host + path validation.
        guard url.scheme?.lowercased() == "theperch" else {
            throw SupabaseServiceError.authError("Invalid auth URL scheme")
        }
        guard url.host?.lowercased() == "auth", url.path == "/callback" else {
            throw SupabaseServiceError.authError("Invalid auth URL path")
        }

        // 2. Type allowlist.
        let params = authParameters(from: url)
        let type = params["type"] ?? ""
        let allowedTypes: Set<String> = ["recovery", "signup", "magiclink", "invite"]
        guard allowedTypes.contains(type) else {
            throw SupabaseServiceError.authError("Unsupported auth flow")
        }
        let isRecovery = type == "recovery"

        // 3. Don't silently re-auth if already signed in (unless this
        // is a deliberate password-recovery handoff).
        if self.isAuthenticated && !isRecovery {
            throw SupabaseServiceError.authError("Already signed in — sign out first to switch accounts")
        }

        if isRecovery {
            self.isPasswordRecovery = true
            NotificationCenter.default.post(
                name: .supabaseAuthStateChanged,
                object: self,
                userInfo: ["event": AuthChangeEvent.passwordRecovery.rawValue]
            )
        }

        do {
            _ = try await client.auth.session(from: url)
            self.isAuthenticated = true
            self.error = nil
            return isRecovery
        } catch {
            if isRecovery {
                self.isPasswordRecovery = false
            }
            throw SupabaseServiceError.authError(error.localizedDescription)
        }
    }

    /// Updates the current user's password. Used after a password-recovery deep link.
    func updatePassword(_ newPassword: String) async throws {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
            self.isAuthenticated = true
            self.isPasswordRecovery = false
            self.error = nil
        } catch {
            throw SupabaseServiceError.authError(error.localizedDescription)
        }
    }

    /// Cancels password recovery by clearing the temporary recovery session.
    func cancelPasswordRecovery() async throws {
        try await signOut()
        self.isPasswordRecovery = false
    }

    /// Signs out the current user.
    func signOut() async throws {
        #if DEBUG
        if useMockData {
            self.isAuthenticated = false
            self.isPasswordRecovery = false
            self.error = nil
            return
        }
        #endif

        do {
            try await client.auth.signOut()
            self.isAuthenticated = false
            self.isPasswordRecovery = false
            self.currentUserId = nil
            self.error = nil
            invalidateCache()
            clearWidgetSharedDefaults()
        } catch {
            throw SupabaseServiceError.authError(error.localizedDescription)
        }
    }

    /// Checks for an existing session and restores it.
    func restoreSession() async {
        #if DEBUG
        if useMockData {
            self.isAuthenticated = true
            self.isPasswordRecovery = false
            return
        }
        #endif

        do {
            let session = try await client.auth.session
            // Reject expired sessions explicitly. The SDK may hand back a
            // cached session whose access token already lapsed — using it
            // would make dashboard fetches silently return empty instead of
            // throwing a 401, which is exactly the Today-tab-blank bug.
            guard !session.isExpired else {
#if DEBUG
                print("[SupabaseService] Restored session is EXPIRED (expires at \(Date(timeIntervalSince1970: session.expiresAt))); forcing unauthenticated state so AuthView can re-prompt.")
#endif
                self.isAuthenticated = false
                self.isPasswordRecovery = false
                self.currentUserId = nil
                return
            }
            self.isAuthenticated = true
            self.isPasswordRecovery = false
            self.currentUserId = session.user.id.uuidString
#if DEBUG
            print("[SupabaseService] Session restored for user: \(session.user.id)")
#endif
        } catch {
            self.isAuthenticated = false
            self.isPasswordRecovery = false
            self.currentUserId = nil
            print("[SupabaseService] No active session: \(error.localizedDescription)")
        }
    }

    // MARK: - Query Methods

    /// Fetches records with 30s cache and exponential backoff retry.
    func fetchRecords(
        category: RecordCategory? = nil,
        type: RecordType? = nil,
        limit: Int = 100,
        forceRefresh: Bool = false
    ) async throws -> [Record] {
        let cacheKey = recordsCacheKey(category: category, type: type, limit: limit)

        if !forceRefresh, let cached = recordsCache[cacheKey], !cached.isStale {
            return cached.value
        }

        #if DEBUG
        if useMockData {
            try await Task.sleep(nanoseconds: 300_000_000)
            var records = MockData.allRecords
            if let category { records = records.filter { $0.category == category } }
            if let type { records = records.filter { $0.type == type } }
            let result = Array(records.prefix(limit))
            recordsCache[cacheKey] = CacheEntry(value: result, fetchedAt: Date.now)
            return result
        }
        #endif

        do {
            let records: [Record] = try await withRetry(operation: "fetchRecords") { [client, recordDecoder, userId = self.currentUserId] in
                var query = client.from("dashboard_records").select()
                // Always pass an explicit `user_id = $` filter even though
                // RLS would gate this anyway. Without it, PostgREST emits
                // a no-WHERE catalog query that costs the planner a fresh
                // index lookup + RLS predicate injection per call —
                // adding the filter halves catalog-fetch latency under
                // both authenticated (planner picks the user-prefix
                // index immediately) and service-role (no RLS rewrite).
                if let userId {
                    query = query.eq("user_id", value: userId)
                }
                if let category {
                    query = query.eq("category", value: category.rawValue)
                }
                if let type {
                    query = query.eq("type", value: type.rawValue)
                }
                let result = try await query
                    .order("created_at", ascending: false)
                    .limit(limit)
                    .execute()
                
                // Direct decode of the array via FailableDecodable —
                // a malformed row gets logged and skipped, the rest
                // pass through. Killed the JSONSerialization → re-encode
                // → JSONDecoder round-trip the older shape did per row
                // (~1/3rd the JSON work for a 500-record payload).
                let wrapped = try recordDecoder.decode([FailableDecodable<Record>].self,
                                                       from: result.data)
                let records: [Record] = wrapped.compactMap { entry in
                    #if DEBUG
                    if case .failure(let err) = entry.result {
                        print("[SupabaseService] Dropping malformed record: \(err)")
                    }
                    #endif
                    return entry.value
                }
                return records
            }

            recordsCache[cacheKey] = CacheEntry(value: records, fetchedAt: Date.now)

            // Persist to disk for offline access
            cacheService.saveRecords(records, category: category, userId: cacheUserId)

            if let category {
                lastFetchTimes[category] = Date.now
                freshnessTracker.recordFetch(for: category.rawValue)
            } else {
                lastGlobalFetchTime = Date.now
                freshnessTracker.recordFetch(for: "all_records")
            }
            return records
        } catch {
            // Fallback to offline cache if network fetch fails
            if let cached = cacheService.loadRecords(category: category, userId: cacheUserId) {
#if DEBUG
                print("[SupabaseService] Network failed, using offline cache for \(category?.rawValue ?? "all")")
#endif
                var filtered = cached
                if let type { filtered = filtered.filter { $0.type == type } }
                let result = Array(filtered.prefix(limit))
                recordsCache[cacheKey] = CacheEntry(value: result, fetchedAt: Date.now)
                return result
            }
            throw error
        }
    }

    /// Fetches all active agents with 30s cache and retry.
    func fetchAgents(forceRefresh: Bool = false) async throws -> [Agent] {
        if !forceRefresh, let cached = agentsCache, !cached.isStale {
            return cached.value
        }

        #if DEBUG
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            let result = MockData.agents
            agentsCache = CacheEntry(value: result, fetchedAt: Date.now)
            return result
        }
        #endif

        let agents: [Agent] = try await withRetry(operation: "fetchAgents") { [client] in
            try await client.from("agents")
                .select()
                .eq("is_active", value: true)
                .execute()
                .value
        }
        agentsCache = CacheEntry(value: agents, fetchedAt: Date.now)
        freshnessTracker.recordFetch(for: "agents")
        return agents
    }

    /// Fetches token usage statistics with retry.
    func fetchTokenUsage(agentId: String? = nil, days: Int = 30) async throws -> [TokenUsage] {
        #if DEBUG
        if useMockData { return [] }
        #endif

        do {
            return try await withRetry(operation: "fetchTokenUsage") { [client] in
                var query = client.from("token_usage").select()
                if let agentId {
                    query = query.eq("agent_id", value: agentId)
                }
                return try await query
                    .order("date", ascending: false)
                    .limit(days)
                    .execute()
                    .value
            }
        } catch {
            connectionError = error.localizedDescription
            throw error
        }
    }

    /// Fetches all sections with 30s cache and retry.
    func fetchSections(forceRefresh: Bool = false) async throws -> [Section] {
        if !forceRefresh, let cached = sectionsCache, !cached.isStale {
            return cached.value
        }

        #if DEBUG
        if useMockData {
            try await Task.sleep(nanoseconds: 200_000_000)
            let result = MockData.sections
            sectionsCache = CacheEntry(value: result, fetchedAt: Date.now)
            return result
        }
        #endif

        do {
            let sections: [Section] = try await withRetry(operation: "fetchSections") { [client, recordDecoder, userId = self.currentUserId] in
                var query = client.from("sections").select()
                if let userId {
                    query = query.eq("user_id", value: userId)
                }
                let result = try await query
                    .order("sort_order", ascending: true)
                    .execute()
                return try recordDecoder.decode([Section].self, from: result.data)
            }

            sectionsCache = CacheEntry(value: sections, fetchedAt: Date.now)
            cacheService.saveSections(sections, userId: cacheUserId)
            freshnessTracker.recordFetch(for: "sections")
            return sections
        } catch {
            // Fallback to offline cache
            if let cached = cacheService.loadSections(userId: cacheUserId) {
#if DEBUG
                print("[SupabaseService] Network failed, using offline cache for sections")
#endif
                sectionsCache = CacheEntry(value: cached, fetchedAt: Date.now)
                return cached
            }
            throw error
        }
    }

    /// Fetches all home widget configurations with 30s cache and retry.
    func fetchHomeWidgets(forceRefresh: Bool = false) async throws -> [HomeWidget] {
        if !forceRefresh, let cached = homeWidgetsCache, !cached.isStale {
            return cached.value
        }

        #if DEBUG
        if useMockData { return [] }
        #endif

        let widgets: [HomeWidget] = try await withRetry(operation: "fetchHomeWidgets") { [client, userId = self.currentUserId] in
            var query = client.from("home_widgets").select()
            if let userId {
                query = query.eq("user_id", value: userId)
            }
            return try await query
                .order("sort_order", ascending: true)
                .execute()
                .value
        }
        homeWidgetsCache = CacheEntry(value: widgets, fetchedAt: Date.now)
        return widgets
    }

    // MARK: - Mutation Methods

    /// Updates the pinned state of a record.
    func updateRecordPin(id: UUID, pinned: Bool) async throws {
        #if DEBUG
        if useMockData { return }
        #endif

        struct PinUpdate: Encodable { let pinned: Bool }

        do {
            try await client.from("dashboard_records")
                .update(PinUpdate(pinned: pinned))
                .eq("id", value: id.uuidString)
                .execute()
            recordsCache.removeAll()
        } catch {
            throw SupabaseServiceError.queryError(error.localizedDescription)
        }
    }

    /// Updates the sort order of sections.
    func updateSectionOrder(sections: [Section]) async throws {
        #if DEBUG
        if useMockData { return }
        #endif

        struct SectionUpdate: Encodable {
            let sortOrder: Int
            let isVisible: Bool
            enum CodingKeys: String, CodingKey {
                case sortOrder = "sort_order"
                case isVisible = "is_visible"
            }
        }

        for section in sections {
            do {
                try await client.from("sections")
                    .update(SectionUpdate(sortOrder: section.sortOrder, isVisible: section.isVisible))
                    .eq("id", value: section.id.uuidString)
                    .execute()
            } catch {
                throw SupabaseServiceError.queryError(error.localizedDescription)
            }
        }
        sectionsCache = nil
    }

    /// Updates the JSON data field of a record (e.g. toggling medication checkboxes).
    func updateRecordData(recordId: UUID, data: [String: JSONValue]) async throws {
        #if DEBUG
        if useMockData { return }
        #endif

        struct DataUpdate: Encodable {
            let data: [String: JSONValue]
        }

        do {
            try await client.from("dashboard_records")
                .update(DataUpdate(data: data))
                .eq("id", value: recordId.uuidString)
                .execute()
            recordsCache.removeAll()
            DecodingCache.shared.clear()
        } catch {
            throw SupabaseServiceError.queryError(error.localizedDescription)
        }
    }

    // MARK: - Insert Methods

    /// Inserts a new record into the dashboard_records table.
    /// Used by HealthKitSyncService to write health data from Apple Health.
    func insertRecord(
        agentId: String,
        userId: UUID,
        type: RecordType,
        category: RecordCategory,
        title: String,
        data: [String: JSONValue],
        displayHint: DisplayHint
    ) async throws {
        #if DEBUG
        if useMockData {
            print("[SupabaseService] Mock mode: would insert \(title) record")
            return
        }
        #endif

        struct NewRecord: Encodable {
            let agent_id: String
            let user_id: String
            let type: String
            let category: String
            let title: String
            let data: [String: JSONValue]
            let display_hint: String
            let pinned: Bool
        }

        let record = NewRecord(
            agent_id: agentId,
            user_id: userId.uuidString,
            type: type.rawValue,
            category: category.rawValue,
            title: title,
            data: data,
            display_hint: displayHint.rawValue,
            pinned: false
        )

        do {
            try await client.from("dashboard_records")
                .insert(record)
                .execute()
#if DEBUG
            print("[SupabaseService] Inserted record: \(title)")
#endif
            recordsCache.removeAll()
        } catch {
            print("[SupabaseService] insertRecord error: \(error)")
            throw SupabaseServiceError.queryError(error.localizedDescription)
        }
    }

    // MARK: - Realtime Subscriptions

    /// Action types from Supabase Realtime postgres_changes.
    enum RealtimeAction: String {
        case insert = "INSERT"
        case update = "UPDATE"
        case delete = "DELETE"
    }

    /// Payload for realtime record changes.
    struct RealtimeRecordChange: Sendable {
        let action: RealtimeAction
        let record: Record?
        let oldId: UUID?
    }

    /// Subscribes to realtime record changes on `dashboard_records`.
    /// Calls `onChange` on the main actor whenever an INSERT, UPDATE, or DELETE occurs.
    func subscribeToRecords(onChange: @escaping @MainActor @Sendable (RealtimeRecordChange) -> Void) async throws {
        #if DEBUG
        if useMockData { return }
        #endif

        // Remove existing channel if reconnecting
        if let existing = recordsChannel {
            await client.realtimeV2.removeChannel(existing)
        }

        let channel = client.realtimeV2.channel("dashboard_records_changes")

        let insertions = channel.postgresChange(InsertAction.self, table: "dashboard_records")
        let updates = channel.postgresChange(UpdateAction.self, table: "dashboard_records")
        let deletions = channel.postgresChange(DeleteAction.self, table: "dashboard_records")

        self.recordsChannel = channel

        try await channel.subscribeWithError()
#if DEBUG
        print("[SupabaseService] Subscribed to dashboard_records realtime")
#endif

        // Listen for insertions. Reuse the shared `recordDecoder` so we
        // don't rebuild a JSONDecoder per realtime burst (a single
        // batch ingest can fire 30+ messages in a second).
        let sharedDecoder = self.recordDecoder
        // `insertion.record` is `[String: AnyJSON]` — passing it to
        // `JSONSerialization.data(withJSONObject:)` raises an
        // NSInvalidArgumentException ("Invalid type in JSON write
        // (__SwiftValue)") because AnyJSON is a Swift enum and doesn't
        // bridge to ObjC. `try?` doesn't catch it (NSException, not
        // Swift Error) and the app terminates. The SDK's `decodeRecord`
        // helper routes through JSONEncoder/JSONDecoder and avoids the
        // bridge entirely.
        let insertTask = Task {
            for await insertion in insertions {
                guard !Task.isCancelled else { break }
                if let record = try? insertion.decodeRecord(as: Record.self, decoder: sharedDecoder) {
                    onChange(RealtimeRecordChange(action: .insert, record: record, oldId: nil))
                } else {
                    // Even if decode fails, notify so UI can refresh
                    onChange(RealtimeRecordChange(action: .insert, record: nil, oldId: nil))
                }
            }
        }
        realtimeTasks.append(insertTask)

        // Listen for updates
        let updateTask = Task {
            for await update in updates {
                guard !Task.isCancelled else { break }
                if let record = try? update.decodeRecord(as: Record.self, decoder: sharedDecoder) {
                    onChange(RealtimeRecordChange(action: .update, record: record, oldId: nil))
                } else {
                    onChange(RealtimeRecordChange(action: .update, record: nil, oldId: nil))
                }
            }
        }
        realtimeTasks.append(updateTask)

        // Listen for deletions
        let deleteTask = Task {
            for await deletion in deletions {
                guard !Task.isCancelled else { break }
                let oldId: UUID? = {
                    // `deletion.oldRecord` is `[String: AnyJSON]` — casting
                    // straight to `String` always fails. Extract via
                    // AnyJSON's stringValue accessor.
                    if let idStr = deletion.oldRecord["id"]?.stringValue {
                        return UUID(uuidString: idStr)
                    }
                    return nil
                }()
                onChange(RealtimeRecordChange(action: .delete, record: nil, oldId: oldId))
            }
        }
        realtimeTasks.append(deleteTask)
    }

    /// Subscribes to realtime agent status changes on `agents`.
    func subscribeToAgents(onChange: @escaping @MainActor @Sendable (RealtimeAction) -> Void) async throws {
        #if DEBUG
        if useMockData { return }
        #endif

        if let existing = agentsChannel {
            await client.realtimeV2.removeChannel(existing)
        }

        let channel = client.realtimeV2.channel("agents_changes")

        let changes = channel.postgresChange(AnyAction.self, table: "agents")

        self.agentsChannel = channel

        try await channel.subscribeWithError()
#if DEBUG
        print("[SupabaseService] Subscribed to agents realtime")
#endif

        let agentTask = Task {
            for await change in changes {
                guard !Task.isCancelled else { break }
                let actionStr = String(describing: type(of: change)).lowercased()
                let action: RealtimeAction = actionStr.contains("insert") ? .insert :
                    actionStr.contains("delete") ? .delete : .update
                onChange(action)
            }
        }
        realtimeTasks.append(agentTask)
    }

    /// Unsubscribes from all realtime channels and cancels stream listener tasks.
    func unsubscribeAll() async {
        // Cancel all managed realtime tasks
        for task in realtimeTasks {
            task.cancel()
        }
        realtimeTasks.removeAll()

        if let channel = recordsChannel {
            await client.realtimeV2.removeChannel(channel)
            recordsChannel = nil
        }
        if let channel = agentsChannel {
            await client.realtimeV2.removeChannel(channel)
            agentsChannel = nil
        }
#if DEBUG
        print("[SupabaseService] Unsubscribed from all realtime channels")
#endif
    }

    /// Minutes since last fetch for a given category (nil = global).
    func minutesSinceLastFetch(category: RecordCategory? = nil) -> Int? {
        let date: Date?
        if let category {
            date = lastFetchTimes[category]
        } else {
            date = lastGlobalFetchTime
        }
        guard let date else { return nil }
        return Int(Date.now.timeIntervalSince(date) / 60)
    }
}
