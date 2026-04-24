import Foundation

/// Defaults for an optional ThePerch Cloud tier.
///
/// The Perch is a single-user app by default: each developer clones the
/// repo, points at their own Supabase backend, and that's it. If at some
/// point you want to offer a shared cloud tier that friends can sign
/// into without configuring their own backend, populate the constants
/// below and publishable keys will ship in the binary.
///
/// ## Why it's safe to commit these values
///
/// Supabase publishable / anon keys are designed to be embedded in
/// client apps. Row-level security (RLS) — not key secrecy — is what
/// guards data access. If `defaultManagedCloudAnonKey` is ever
/// populated with a real value, add it to `.gitleaks.toml` so CI
/// doesn't false-positive on the JWT-shaped string.
///
/// ## Current state
///
/// `defaultManagedCloudAnonKey` is empty. When empty, the app treats
/// the cloud tier as unconfigured: OnboardingView still offers the
/// cloud option but picking it will fall through to self-hosted setup.
/// Most users are expected to bring their own Supabase project.
enum CloudDefaults {

    /// ThePerch Cloud Supabase project URL. Not a secret — visible in
    /// any network trace. Safe to commit.
    static let defaultManagedCloudURL = "https://ulmerwkvcczgjcxdhfuo.supabase.co"

    /// ThePerch Cloud publishable / anon key. Empty by default. Paste
    /// the real key here if you want to ship a public cloud tier — then
    /// add the literal to `.gitleaks.toml` allowlist.
    ///
    /// Supabase anon keys are JWTs that look like secrets but aren't —
    /// they're designed for client-side use. Access control is enforced
    /// by RLS policies on the database side.
    static let defaultManagedCloudAnonKey = ""

    /// True when a real key has been pasted above. Used by AppConfig to
    /// decide whether the managed cloud tier is actually available.
    static var isManagedCloudConfigured: Bool {
        !defaultManagedCloudAnonKey.isEmpty
    }
}
