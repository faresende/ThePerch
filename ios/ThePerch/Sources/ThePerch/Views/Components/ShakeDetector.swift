// ShakeDetector.swift
//
// View modifier that detects iOS device shake gestures (UIEvent.motionEnded
// with motion=.motionShake). Used by the Today tab to fire the rage-shake
// feedback sheet for the active BioChecha insight.

import SwiftUI
import UIKit

struct ShakeDetector: ViewModifier {
    let onShake: () -> Void

    func body(content: Content) -> some View {
        content
            .background(ShakeUIView(onShake: onShake))
    }
}

private struct ShakeUIView: UIViewRepresentable {
    let onShake: () -> Void

    func makeUIView(context: Context) -> _ShakeUIView {
        _ShakeUIView(onShake: onShake)
    }
    func updateUIView(_ uiView: _ShakeUIView, context: Context) {}
}

private final class _ShakeUIView: UIView {
    let onShake: () -> Void
    init(onShake: @escaping () -> Void) {
        self.onShake = onShake
        super.init(frame: .zero)
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }
    override var canBecomeFirstResponder: Bool { true }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { onShake() }
    }
}

extension View {
    /// Fire `onShake` when the device is physically shaken while this view
    /// is on screen. Backed by UIEvent.motionEnded.
    func onDeviceShake(perform onShake: @escaping () -> Void) -> some View {
        modifier(ShakeDetector(onShake: onShake))
    }
}
