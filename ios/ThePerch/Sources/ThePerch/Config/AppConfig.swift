import Foundation

/// Configuration for the application, including Supabase credentials.
struct AppConfig {
    static let shared = AppConfig()

    let supabaseURL: URL
    let supabaseAnonKey: String

    private init() {
        // TODO: Fabio — Load these from a Secrets.plist file or environment variables.
        // For now, they should be filled in during app setup.
        // Example: Create a Secrets.plist in the project with keys "SUPABASE_URL" and "SUPABASE_ANON_KEY"

        guard let url = URL(string: Self.getConfigValue(key: "SUPABASE_URL")) else {
            fatalError("Invalid Supabase URL in configuration")
        }

        self.supabaseURL = url
        self.supabaseAnonKey = Self.getConfigValue(key: "SUPABASE_ANON_KEY")

        if supabaseAnonKey.isEmpty {
            fatalError("Supabase anon key is not configured")
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
