import Foundation
import Observation

/// Shared state that carries an incoming deep-link destination from the
/// app's `.onOpenURL` handler to whichever view is responsible for routing.
/// The consumer (MainTabView) reads `pendingDestination`, acts on it, and
/// writes `nil` back so the same link isn't processed twice if the view
/// re-renders.
@Observable
@MainActor
final class DeepLinkState {
    var pendingDestination: DeepLinkDestination?

    /// Convenience — called by the app's `.onOpenURL` handler.
    func handle(url: URL) {
        if let dest = DeepLinkRouter.parse(url) {
            pendingDestination = dest
        }
    }

    /// Called by the consumer after routing so the state doesn't re-fire.
    func consume() {
        pendingDestination = nil
    }
}
