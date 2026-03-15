import SwiftUI

/// Reusable error banner with warning icon, message, retry button, and dismiss.
/// Uses PerchTheme.error color with 0.1 opacity background.
struct ErrorBanner: View {
    let message: String
    let retryAction: () -> Void
    var onDismiss: (() -> Void)?

    private var displayMessage: String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()

        if trimmed.isEmpty || lowered.contains("cancelled") || lowered.contains("canceled") {
            return "Unable to sync right now"
        }
        if lowered.contains("network") || lowered.contains("offline") || lowered.contains("internet") || lowered.contains("connection") || lowered.contains("timed out") {
            return "Connection error"
        }
        if lowered.hasPrefix("unknown error") || lowered.hasPrefix("query error") || lowered.hasPrefix("decoding error") {
            return "Unable to sync"
        }

        return trimmed
    }

    var body: some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
            Image(systemName: "wifi.exclamationmark")
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.error)
                .padding(8)
                .background(PerchTheme.error.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(displayMessage)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textPrimary)
                    .lineLimit(2)

                Button("Retry") {
                    retryAction()
                }
                .font(PerchTheme.Font.caption)
                .fontWeight(.semibold)
                .foregroundColor(PerchTheme.accent)
            }

            Spacer(minLength: 0)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                        .padding(6)
                }
                .accessibilityLabel("Dismiss error")
            }
        }
        .padding(PerchTheme.Spacing.medium)
        .background(PerchTheme.error.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PerchTheme.error.opacity(0.18), lineWidth: 1)
        )
        .cornerRadius(12)
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorBanner(
            message: "Cancelled",
            retryAction: {},
            onDismiss: {}
        )
        ErrorBanner(
            message: "Network error",
            retryAction: {}
        )
    }
    .padding()
    .background(PerchTheme.background)
}
