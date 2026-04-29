import SwiftUI

/// A view wrapper that defers building its child view until the parent
/// actually places it into the view hierarchy.
///
/// SwiftUI's `TabView` with `.tabViewStyle(.page(...))` eagerly evaluates
/// the body of every page child on first appear (so swipe-preview can
/// snapshot neighbours). For our Hub and Health tabs that meant building
/// `BookmarksSectionContent`, `CalendarSectionContent`, and
/// `TravelSectionContent` on every Hub open — even though only one is
/// visible at a time. Wrapping each page in `LazyView { ... }` defers
/// the body call until the page actually becomes the selected tag.
///
/// Usage:
/// ```swift
/// hubPage { LazyView { BookmarksSectionContent() } }
///   .tag(HubSegment.bookmarks)
/// ```
struct LazyView<Content: View>: View {
    private let build: () -> Content

    init(@ViewBuilder _ build: @escaping () -> Content) {
        self.build = build
    }

    var body: Content {
        build()
    }
}
