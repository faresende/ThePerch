import Foundation

/// Configuration for the application, including Supabase credentials.
struct AppConfig {
    static let shared = AppConfig()
    static let defaultUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    static let legacySelfHostedURLString = "https://cgmaotzmeoiueyzlchaz.supabase.co"
    static let managedCloudURLString = "https://ulmerwkvcczgjcxdhfuo.supabase.co"
    static let managedCloudAnonKey = "SCRUBBED_PUBLISHABLE_KEY"
    static let managedCloudConfiguration = AppConfiguration(
        supabaseURL: managedCloudURLString,
        supabaseAnonKey: managedCloudAnonKey,
        backendMode: .managedCloud
    )

    let supabaseURL: URL
    let supabaseAnonKey: String

    /// Karakeep API token for direct bookmark fetching.
    let karakeepToken: String

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
            self.isMisconfigured = false
        } else {
            // No config found, app will show OnboardingView
#if DEBUG
            print("[AppConfig] WARNING: Supabase credentials are missing or invalid. The app will run with mock data.")
#endif
            self.supabaseURL = URL(string: "https://placeholder.supabase.co")!
            self.supabaseAnonKey = ""
            self.karakeepToken = ""
            self.isMisconfigured = true
        }
    }

    private static func migrateLegacyKeychainConfigIfNeeded(_ config: AppConfiguration) -> AppConfiguration {
        guard config.supabaseURL == legacySelfHostedURLString else {
            return config
        }

        let migrated = managedCloudConfiguration
        try? KeychainService.shared.save(migrated)
        return migrated
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
