import SwiftUI
import UIKit

// MARK: - HorizontalPanReader
//
// UIKit-bridged pan gesture for swipe-to-reveal that coexists with
// vertical ScrollView scroll AND wins over horizontal page-TabView
// pan. Required because SwiftUI's DragGesture has no axis filter
// that releases the gesture on vertical motion — once captured via
// `.highPriorityGesture`, the parent ScrollView never gets vertical
// drags, breaking the orders list's scroll.
//
// How it works:
//   - A custom UIPanGestureRecognizer subclass evaluates the FIRST
//     meaningful motion. If it's predominantly vertical (|Δy| > |Δx|),
//     the recognizer fails — which UIKit's gesture coordination
//     interprets as "let other recognizers activate." The ScrollView's
//     own pan recognizer then takes over.
//   - For horizontal motion, our recognizer succeeds. Because it's
//     attached to a small inner view (not a parent), it wins over
//     ancestors that haven't yet engaged (e.g. the page TabView).
//
// Usage: wrap the swipeable content in a `.background()` of this view.
// `onChanged` fires for every move; `onEnded` fires once at the end
// (.ended / .cancelled / .failed).

struct HorizontalPanReader: UIViewRepresentable {
    let onChanged: (CGSize) -> Void
    let onEnded: (CGSize) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let pan = HorizontalOnlyPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        pan.delegate = context.coordinator
        // Lower minimumNumberOfTouches keeps single-finger drag working.
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChanged: onChanged, onEnded: onEnded)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onChanged: (CGSize) -> Void
        var onEnded: (CGSize) -> Void

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

        // We don't want our recognizer to fire simultaneously with
        // ScrollView's pan — UIKit picks one. Returning false here
        // means: when both recognizers could activate, only one wins.
        // Because our recognizer is attached to a smaller-area inner
        // view, it gets evaluated first; on vertical motion it fails
        // (see HorizontalOnlyPanGestureRecognizer below) and ScrollView
        // wins. On horizontal motion we succeed and ScrollView yields.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            return false
        }

        // Allow our recognizer to be required to fail before ScrollView
        // activates its pan. This makes the failure->success handoff
        // work cleanly: ScrollView's pan waits to see if we fail.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            return false
        }
    }
}

// MARK: - HorizontalOnlyPanGestureRecognizer
//
// On the first meaningful touch movement, decide whether this drag is
// horizontal (succeed) or vertical (fail fast so the parent ScrollView
// can take it). Threshold is 4pt — large enough to ignore tap-jitter,
// small enough that the user's intent is clear.

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
        // Wait for at least 4pt of motion in either axis before deciding.
        guard absX > 4 || absY > 4 else { return }

        didEvaluateAxis = true
        if absY > absX {
            // Predominantly vertical — fail and let ScrollView take it.
            state = .failed
        }
        // Otherwise, the recognizer continues. UIKit transitions
        // possible → began → changed naturally.
    }
}
