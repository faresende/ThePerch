import Foundation

/// Configuration for the application, including Supabase credentials.
struct AppConfig {
    static let shared = AppConfig()
    static let defaultUserID = UUID(uuidString: "20436ef5-90f7-4224-9eff-f5ff3cb02530")!

    let supabaseURL: URL
    let supabaseAnonKey: String

    /// True when Supabase credentials are missing or invalid.
    let isMisconfigured: Bool

    private init() {
        let urlString = Self.getConfigValue(key: "SUPABASE_URL")
        let anonKey = Self.getConfigValue(key: "SUPABASE_ANON_KEY")

        if let url = URL(string: urlString), !urlString.isEmpty, !anonKey.isEmpty {
            self.supabaseURL = url
            self.supabaseAnonKey = anonKey
            self.isMisconfigured = false
        } else {
            // Fallback to a placeholder so the app can launch and show an error state
            // instead of crashing on missing config.
#if DEBUG
            print("[AppConfig] WARNING: Supabase credentials are missing or invalid. The app will run with mock data.")
#endif
            self.supabaseURL = URL(string: "https://placeholder.supabase.co")!
            self.supabaseAnonKey = ""
            self.isMisconfigured = true
        }
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
