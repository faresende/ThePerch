import SwiftUI

/// A passthrough wrapper that takes a `@ViewBuilder` closure and returns
/// its built body. The name is misleading: SwiftUI eagerly evaluates the
/// `body` accessor of every page in a `TabView(...).tabViewStyle(.page(...))`
/// on first appear (it has to, in order to snapshot neighbour pages for
/// the swipe preview). Wrapping a page in `LazyView { ... }` does NOT
/// defer construction — body still gets called immediately. Round 10
/// audit corrected the prior comment that claimed otherwise.
///
/// The wrapper is kept (rather than deleted) only because removing it
/// would touch ~6 call sites and add no measurable win. If you genuinely
/// need lazy children inside a paged TabView, use Apple's iOS 18+ `Tab`
/// API or move heavy work into `.onAppear { ... }` blocks. Inside this
/// wrapper, treat all closures as eagerly evaluated.
///
/// Usage (passthrough — no laziness implied):
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
