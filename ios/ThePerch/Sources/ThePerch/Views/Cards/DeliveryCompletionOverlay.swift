import SwiftUI

/// A brief celebration overlay shown when a delivery is marked as delivered.
/// Displays a green checkmark that scales up with a bounce, surrounded by
/// subtle particle dots that expand outward and fade.
struct DeliveryCompletionOverlay: View {
    @State private var showCheck = false
    @State private var showParticles = false
    @State private var fadeOut = false

    var body: some View {
        ZStack {
            // Particle burst
            ForEach(0..<8, id: \.self) { index in
                Circle()
                    .fill(PerchTheme.success.opacity(showParticles ? 0 : 0.7))
                    .frame(width: 6, height: 6)
                    .offset(particleOffset(index: index, expanded: showParticles))
            }

            // Checkmark circle
            ZStack {
                Circle()
                    .fill(PerchTheme.success)
                    .frame(width: 48, height: 48)
                    .scaleEffect(showCheck ? 1 : 0.01)
                    .opacity(fadeOut ? 0 : 1)

                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .scaleEffect(showCheck ? 1 : 0.01)
                    .opacity(fadeOut ? 0 : 1)
            }
        }
        .onAppear {
            guard !PerchMotion.prefersReduced else {
                // Instant display then hide for Reduce Motion
                showCheck = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    fadeOut = true
                }
                return
            }

            // Checkmark bounce in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                showCheck = true
            }

            // Particles expand
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                showParticles = true
            }

            // Fade out after 1.5s
            withAnimation(.easeIn(duration: 0.4).delay(1.2)) {
                fadeOut = true
            }
        }
        .allowsHitTesting(false)
    }

    private func particleOffset(index: Int, expanded: Bool) -> CGSize {
        let angle = Double(index) * (.pi / 4)
        let distance: CGFloat = expanded ? 36 : 0
        return CGSize(
            width: CGFloat(cos(angle)) * distance,
            height: CGFloat(sin(angle)) * distance
        )
    }
}

// MARK: - View Modifier

/// Modifier that shows the delivery completion celebration overlay.
struct DeliveryCompletionModifier: ViewModifier {
    let isDelivered: Bool
    @State private var wasDelivered = false
    @State private var showCelebration = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if showCelebration {
                    DeliveryCompletionOverlay()
                        .transition(.opacity)
                }
            }
            .onAppear {
                // Track initial state without triggering celebration
                wasDelivered = isDelivered
            }
            .onChange(of: isDelivered) { _, newValue in
                // Only celebrate when transitioning TO delivered
                if newValue && !wasDelivered {
                    PerchHaptics.success()
                    showCelebration = true
                    // Auto-dismiss after animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        showCelebration = false
                    }
                }
                wasDelivered = newValue
            }
    }
}

extension View {
    /// Shows a celebration overlay when the delivery status transitions to delivered.
    func deliveryCompletionCelebration(isDelivered: Bool) -> some View {
        modifier(DeliveryCompletionModifier(isDelivered: isDelivered))
    }
}

// MARK: - Preview

#Preview {
    VStack {
        DeliveryCompletionOverlay()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(PerchTheme.background)
}
