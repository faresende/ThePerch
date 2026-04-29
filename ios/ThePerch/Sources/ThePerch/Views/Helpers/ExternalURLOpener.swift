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
