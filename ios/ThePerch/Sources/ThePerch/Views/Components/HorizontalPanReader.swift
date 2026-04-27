import SwiftUI
import UIKit

// MARK: - SwipeReceiver
//
// Hosts SwiftUI content inside a UIHostingController inside a UIView,
// with a horizontal-only pan recognizer attached to the OUTER UIView.
// This is the only way to make swipe-to-reveal work cleanly inside
// the Hub's page-style TabView while preserving:
//
//   - Vertical scroll (the recognizer fails on predominantly vertical
//     motion, releasing the touch back to the parent ScrollView's pan).
//   - Tap-to-expand on the OrderCardV2 button (taps reach the SwiftUI
//     content normally — UIKit recognizers attached to a parent UIView
//     don't block taps on descendants).
//   - Horizontal swipe-to-reveal (the recognizer wins over the page
//     TabView's pan because it's attached to a deeper-nested UIView).
//
// Why not `.background(...)`: SwiftUI `.background()` is behind the
// content for hit-testing too. The foreground Button absorbs touches
// before the background view's recognizer ever sees them.
//
// Why UIHostingController: a recognizer on a UIView fires for ANY
// touch that hits the view or its descendants. Hosting the SwiftUI
// content as a child of our UIView means our recognizer sees every
// touch that hits the content.
//
// `host.sizingOptions = .intrinsicContentSize` keeps layout
// transparent — the wrapper's intrinsic size matches the SwiftUI
// content's natural size, so SwipeActionsContainer behaves
// identically to non-wrapped views in its parent ForEach.

struct SwipeReceiver<Content: View>: UIViewRepresentable {
    let content: Content
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize) -> Void

    init(
        @ViewBuilder content: () -> Content,
        onChanged: @escaping (CGSize) -> Void,
        onEnded: @escaping (CGSize) -> Void
    ) {
        self.content = content()
        self.onChanged = onChanged
        self.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.sizingOptions = .intrinsicContentSize

        container.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let pan = HorizontalOnlyPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        pan.delegate = context.coordinator
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        // cancelsTouchesInView = false lets taps on the underlying
        // SwiftUI Button fire normally — important for tap-to-expand.
        pan.cancelsTouchesInView = false
        container.addGestureRecognizer(pan)

        context.coordinator.host = host
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.host?.rootView = content
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGSize) -> Void
        var onEnded: (CGSize) -> Void
        var host: UIHostingController<Content>?

        init(onChanged: @escaping (CGSize) -> Void, onEnded: @escaping (CGSize) -> Void) {
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handle(_ recognizer: UIPanGestureRecognizer) {
            guard let view = recognizer.view else { return }
            let t = recognizer.translation(in: view)
            let size = CGSize(width: t.x, height: t.y)
            switch recognizer.state {
            case .changed:
                onChanged(size)
            case .ended, .cancelled, .failed:
                onEnded(size)
            default:
                break
            }
        }

        // Allow simultaneous recognition with the parent ScrollView's
        // pan recognizer. This means BOTH can be in `.possible` at the
        // same time — when our recognizer fails (on vertical motion),
        // the ScrollView pan keeps going. When our recognizer succeeds
        // (on horizontal motion), it doesn't interfere with the
        // ScrollView's already-running recognizer because vertical
        // scrolling and horizontal panning don't conflict.
        func gestureRecognizer(
            _ rec: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            return true
        }
    }
}

// MARK: - HorizontalOnlyPanGestureRecognizer
//
// On the first meaningful touch movement, decide whether this drag is
// horizontal (succeed) or vertical (fail fast so the parent ScrollView
// can take it). Threshold: 4pt of motion before deciding — large enough
// to ignore tap-jitter, small enough that the user's intent is clear.

private final class HorizontalOnlyPanGestureRecognizer: UIPanGestureRecognizer {
    private var didEvaluateAxis = false

    override func reset() {
        super.reset()
        didEvaluateAxis = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard !didEvaluateAxis else { return }
        guard state == .possible || state == .began else { return }
        guard let view = view else { return }

        let t = translation(in: view)
        let absX = abs(t.x)
        let absY = abs(t.y)
        guard absX > 4 || absY > 4 else { return }

        didEvaluateAxis = true
        if absY > absX {
            // Predominantly vertical — fail and let ScrollView take it.
            state = .failed
        }
        // Otherwise the recognizer continues normally.
    }
}
