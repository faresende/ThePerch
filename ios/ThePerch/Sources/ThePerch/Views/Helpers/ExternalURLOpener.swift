import UIKit

/// Round 12 audit (HIGH): a single funnel for `UIApplication.shared.open`
/// that allowlists URL schemes before opening. The prior code path passed
/// server-controlled URL strings (shipment tracking_url, bookmark url,
/// calendar event url, review-item source_url, email summary url) straight
/// into `UIApplication.shared.open`, which honors ANY registered scheme —
/// `shortcuts://`, `mailto:`, `tel:`, `sms:`, `facetime:`, custom URL
/// schemes from other apps. An attacker controlling a Karakeep instance,
/// or whose order-confirmation email gets parsed into a bookmark/order
/// row, could inject e.g. `shortcuts://run-shortcut?name=Exfiltrate%20Photos`
/// and have iOS dispatch it on tap.
///
/// All call sites that originally passed a server-derived URL must route
/// through `openExternal(_:)`. Only `http` and `https` URLs are dispatched;
/// anything else is silently dropped (with a `#if DEBUG` log).
///
/// Round 13 audit (HIGH H-1): the R12 sweep grepped for
/// `UIApplication.shared.open` only and missed SwiftUI's `Link(destination:)`
/// and `@Environment(\.openURL)`, both of which call the same underlying
/// API and inherit the same scheme problem. All server-derived-URL sites
/// using those APIs were also routed through here. The rule is now:
/// **any URL string that originated from Supabase, an LLM, an email
/// classifier, Karakeep, or any other server source MUST be opened via
/// ExternalURLOpener** — never via Link, openURL, or
/// UIApplication.shared.open directly. Locally-constructed system-scheme
/// URLs (`calshow:`, `maps:`) are exempt because they're not user-tappable
/// in a way that lets server data choose the scheme.
enum ExternalURLOpener {
    /// Opens `url` via `UIApplication.shared.open` only if its scheme is
    /// `http` or `https`. Returns `true` when the open was attempted,
    /// `false` when the URL was rejected.
    @discardableResult
    @MainActor
    static func openExternal(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        guard scheme == "http" || scheme == "https" else {
            #if DEBUG
            print("[ExternalURLOpener] Refused non-http(s) URL: \(url.absoluteString.prefix(120))")
            #endif
            return false
        }
        UIApplication.shared.open(url)
        return true
    }
}
