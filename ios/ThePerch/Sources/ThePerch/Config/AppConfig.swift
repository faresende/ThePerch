import Foundation

/// Configuration for the application, including Supabase credentials.
struct AppConfig {
    static let shared = AppConfig()

    /// Project URLs are not secrets (they're visible in any network trace),
    /// so they may remain as string literals. Keys are never hardcoded.
    /// The managed-cloud URL below is the ThePerch Cloud tier; users of the
    /// self-hosted tier provide their own URL via the onboarding flow.
    static let managedCloudURLString = CloudDefaults.defaultManagedCloudURL

    /// Managed-tier publishable key. Sourced from `CloudDefaults.swift`,
    /// which is committed to the repo. Empty by default — populated only
    /// if a forker wants to ship a functional public cloud tier. See
    /// `CloudDefaults.swift` for the rationale on why this is safe to
    /// commit when filled in.
    static var managedCloudAnonKey: String {
        CloudDefaults.defaultManagedCloudAnonKey
    }

    static var managedCloudConfiguration: AppConfiguration {
        AppConfiguration(
            supabaseURL: managedCloudURLString,
            supabaseAnonKey: managedCloudAnonKey,
            backendMode: .managedCloud
        )
    }

    let supabaseURL: URL
    let supabaseAnonKey: String

    /// Karakeep API token for direct bookmark fetching. Empty when no
    /// token configured — bookmarks integration silently disables and
    /// the Hub's Bookmarks segment renders a friendly empty state with
    /// a docs link rather than failing network calls.
    let karakeepToken: String

    /// Karakeep API base URL. Defaults to empty string when no
    /// `KARAKEEP_BASE_URL` is set; combined with empty `karakeepToken`
    /// this disables the Karakeep integration entirely. Self-hosters
    /// set their own instance via env / Keychain config.
    let karakeepBaseURL: String

    /// True when Karakeep is configured (both URL + token present).
    /// Drives whether Bookmarks UI shows the data view or the
    /// "bring your own" empty state.
    var hasKarakeep: Bool {
        !karakeepBaseURL.isEmpty && !karakeepToken.isEmpty
    }

    /// True when Supabase credentials are missing or invalid.
    let isMisconfigured: Bool

    private init() {
        // Priority 1: Keychain (runtime config, self-hosted or cloud)
        if let storedConfig = KeychainService.shared.load() {
            let effectiveConfig = Self.migrateLegacyKeychainConfigIfNeeded(storedConfig)
            if let url = URL(string: effectiveConfig.supabaseURL),
               !effectiveConfig.supabaseAnonKey.isEmpty {
                self.supabaseURL = url
                self.supabaseAnonKey = effectiveConfig.supabaseAnonKey
                self.karakeepToken = Self.getConfigValue(key: "KARAKEEP_TOKEN")
                self.karakeepBaseURL = Self.getConfigValue(key: "KARAKEEP_BASE_URL")
                self.isMisconfigured = false
                return
            }
        }

        // Priority 2: Secrets.plist / Info.plist / env (legacy / dev convenience)
        let urlString = Self.getConfigValue(key: "SUPABASE_URL")
        let anonKey = Self.getConfigValue(key: "SUPABASE_ANON_KEY")

        if let url = URL(string: urlString), !urlString.isEmpty, !anonKey.isEmpty {
            self.supabaseURL = url
            self.supabaseAnonKey = anonKey
            self.karakeepToken = Self.getConfigValue(key: "KARAKEEP_TOKEN")
            self.karakeepBaseURL = Self.getConfigValue(key: "KARAKEEP_BASE_URL")
            self.isMisconfigured = false
        } else {
            // No config found, app will show OnboardingView
#if DEBUG
            print("[AppConfig] WARNING: Supabase credentials are missing or invalid. The app will run with mock data.")
#endif
            self.supabaseURL = URL(string: "https://placeholder.supabase.co")!
            self.supabaseAnonKey = ""
            self.karakeepToken = ""
            self.karakeepBaseURL = ""
            self.isMisconfigured = true
        }
    }

    private static func migrateLegacyKeychainConfigIfNeeded(_ config: AppConfiguration) -> AppConfiguration {
        // The managed cloud project is temporarily inactive.
        // Keep existing self-hosted installs on their current backend until
        // the cloud endpoint is verified healthy again.
        return config
    }

    /// Retrieves a configuration value from Info.plist or environment.
    /// - Parameter key: The configuration key to look up.
    /// - Returns: The configuration value, or an empty string if not found.
    private static func getConfigValue(key: String) -> String {
        // First, try to load from a Secrets.plist file
        if let secretsPath = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
           let secrets = NSDictionary(contentsOfFile: secretsPath) as? [String: String] {
            if let value = secrets[key] {
                return value
            }
        }

        // Fall back to Info.plist
        if let value = Bundle.main.infoDictionary?[key] as? String {
            return value
        }

        // Fall back to environment variables
        if let value = ProcessInfo.processInfo.environment[key] {
            return value
        }

        return ""
    }
}
