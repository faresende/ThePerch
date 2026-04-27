import SwiftUI

// MARK: - SwipeActionsContainer (deprecated — pass-through)
//
// Originally a custom drag-to-reveal swipe affordance for order
// corrections. Retired after three failed attempts to make swipe
// coexist with the Hub's page-style TabView (horizontal pan eaten
// by tab-paging) AND the parent ScrollView's vertical scroll.
// SwiftUI's gesture system + UIKit's recognizer coordination don't
// have a clean primitive for "win horizontal but yield vertical
// AND yield to specific other horizontal recognizers."
//
// Corrections moved to the long-press contextMenu on each
// OrderCardV2 / OrderCard. Less discoverable than swipe but
// fully reliable. The corrections data engine (parse_trace
// snapshot + order_corrections row + RPC undo) doesn't care
// which surface captured the input.
//
// Kept as a pass-through (rather than removed) so all the call
// sites that wrap their content in `SwipeActionsContainer { ... }`
// continue to compile. The `actions` parameter is silently
// ignored — long-press menus are wired separately in the
// parent views.
//
// If iOS swipe-to-reveal becomes worth revisiting, the proper
// fix is to migrate the orders list out of HubTab's page TabView
// (so there's no horizontal-pan competitor) and use SwiftUI's
// native `.swipeActions(edge:)` on a List.

struct SwipeAction: Identifiable {
    enum Role { case normal, destructive }

    let id = UUID()
    let label: String
    let systemImage: String
    let tint: Color
    let role: Role
    let handler: () -> Void
}

struct SwipeActionsContainer<Content: View>: View {
    let actions: [SwipeAction]
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Pass-through: render the content as-is. The `actions`
        // parameter is intentionally unused — corrections are now
        // surfaced via long-press menu in the calling view.
        content()
    }
}
