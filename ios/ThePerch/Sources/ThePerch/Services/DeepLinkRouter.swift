import Foundation

/// Parsed deep-link destinations the app knows how to route to. Extend the
/// enum to add new surfaces — the parser, the consumers in MainTabView /
/// HubTab, and the emitters in widgets & Live Activities all switch over it.
///
/// URL scheme `theperch://` is registered in Info.plist. Examples:
///
///   theperch://today                       → Today tab
///   theperch://health                      → Health tab
///   theperch://hub                         → Hub tab (default subsection)
///   theperch://hub/orders                  → Hub tab, Orders subsection
///   theperch://hub/bookmarks               → Hub tab, Bookmarks subsection
///   theperch://hub/bookmarks?source=karakeep
///                                          → Bookmarks, Karakeep sub-tab
///   theperch://orders                      → shorthand for hub/orders
///   theperch://orders?review=1             → Orders + review-items sheet open
///   theperch://capture                     → open Capture sheet
///
/// Unknown URLs fall through to `.today`.
enum DeepLinkDestination: Equatable, Sendable {
    case today
    case health
    case hub(HubSubsection? = nil)
    case orders(openReviewItems: Bool = false)
    case bookmarks(source: BookmarksSource? = nil)
    case calendar
    case capture

    /// Hub segmented-picker choice, when relevant.
    enum HubSubsection: String, Sendable {
        case orders
        case bookmarks
        case calendar
        case travel
    }

    /// Bookmarks sub-tab (Karakeep vs Paperless).
    enum BookmarksSource: String, Sendable {
        case karakeep
        case paperless
    }
}

enum DeepLinkRouter {
    /// Parse a `theperch://…` URL into a destination. Returns nil for
    /// other schemes or wildly malformed inputs.
    static func parse(_ url: URL) -> DeepLinkDestination? {
        guard url.scheme?.lowercased() == "theperch" else { return nil }
        // iOS sometimes gives us the first path segment as `url.host` and
        // sometimes as the first pathComponent. Normalize.
        var segments = [String]()
        if let host = url.host, !host.isEmpty { segments.append(host.lowercased()) }
        for part in url.pathComponents where part != "/" && !part.isEmpty {
            segments.append(part.lowercased())
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? {
            query.first { $0.name.lowercased() == name.lowercased() }?.value
        }

        guard let top = segments.first else { return .today }

        switch top {
        case "today":
            return .today
        case "health":
            return .health
        case "hub":
            if segments.count >= 2, let sub = DeepLinkDestination.HubSubsection(rawValue: segments[1]) {
                // Nested aliases for bookmarks source.
                if sub == .bookmarks, let srcRaw = q("source"),
                   let src = DeepLinkDestination.BookmarksSource(rawValue: srcRaw) {
                    return .bookmarks(source: src)
                }
                if sub == .orders && q("review") == "1" {
                    return .orders(openReviewItems: true)
                }
                return .hub(sub)
            }
            return .hub(nil)
        case "orders":
            return .orders(openReviewItems: q("review") == "1")
        case "bookmarks":
            if let raw = q("source"), let src = DeepLinkDestination.BookmarksSource(rawValue: raw) {
                return .bookmarks(source: src)
            }
            return .bookmarks(source: nil)
        case "calendar":
            return .calendar
        case "capture":
            return .capture
        default:
            return nil
        }
    }
}
