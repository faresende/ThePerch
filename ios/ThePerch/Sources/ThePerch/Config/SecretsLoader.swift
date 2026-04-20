import Foundation

/// Type-safe access to build-time secrets sourced from the xcconfig pipeline.
///
/// Values flow: `Secrets.xcconfig` → Xcode variable substitution → `Info.plist`
/// → `Bundle.main.object(forInfoDictionaryKey:)` → here.
///
/// Placeholder sentinels (`REPLACE_ME...`, `YOUR_...`) are treated as empty so
/// a half-configured build fails loudly in DEBUG but still boots to the
/// onboarding screen in RELEASE.
enum SecretsLoader {

    /// Keys must match the INFOPLIST entries in `ios/ThePerch/Info.plist`
    /// which are themselves sourced from `Config/Secrets.xcconfig`.
    enum Key: String {
        /// Self-hosted / personal Supabase project URL.
        case supabaseURL            = "SUPABASE_URL"
        /// Publishable / anon key for the self-hosted Supabase project.
        /// Named ANON_KEY for backward compatibility with the legacy
        /// `Secrets.plist` pipeline in `AppConfig`.
        case supabaseAnonKey        = "SUPABASE_ANON_KEY"
        /// Managed-tier Supabase project URL (ThePerch Cloud).
        case supabaseManagedURL     = "SUPABASE_MANAGED_URL"
        /// Managed-tier publishable key.
        case supabaseManagedAnonKey = "SUPABASE_MANAGED_ANON_KEY"
        /// Karakeep API token for direct bookmark fetching.
        case karakeepToken          = "KARAKEEP_TOKEN"
    }

    /// Returns the trimmed string value for `key`, or `nil` if missing,
    /// empty, or a known placeholder. Never returns placeholder strings,
    /// so callers don't have to defend against them individually.
    static func value(for key: Key) -> String? {
        guard
            let raw = Bundle.main.object(forInfoDictionaryKey: key.rawValue) as? String
        else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix("REPLACE_ME") { return nil }
        if trimmed.hasPrefix("YOUR_") { return nil }
        // When a build setting is undefined, xcconfig substitution leaves
        // the literal `$(NAME)` in place. Treat those as missing.
        if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") { return nil }
        return trimmed
    }

    /// Returns the value for `key`. Assertion-fails in DEBUG if missing so
    /// configuration issues surface immediately during development; in
    /// RELEASE returns empty string so the app can still launch and route
    /// the user to the onboarding flow.
    static func require(_ key: Key) -> String {
        if let value = value(for: key) {
            return value
        }

        #if DEBUG
        assertionFailure(
            """
            SecretsLoader: required key \(key.rawValue) is missing or a placeholder.
            Check that Secrets.xcconfig is populated and the project's base
            configuration points at it. See SECURITY.md for the setup steps.
            """
        )
        #endif
        return ""
    }
}
