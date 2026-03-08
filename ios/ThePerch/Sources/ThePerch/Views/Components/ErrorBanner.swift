import SwiftUI

/// Reusable error banner with warning icon, message, retry button, and dismiss.
/// Uses PerchTheme.error color with 0.1 opacity background.
struct ErrorBanner: View {
    let message: String
    let retryAction: () -> Void
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(PerchTheme.error)

            Text(message)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textSecondary)
                .lineLimit(2)

            Spacer()

            Button("Retry") {
                retryAction()
            }
            .font(PerchTheme.Font.caption)
            .foregroundColor(PerchTheme.accent)

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(PerchTheme.Font.micro)
                        .foregroundColor(PerchTheme.textTertiary)
                }
            }
        }
        .padding(PerchTheme.Spacing.medium)
        .background(PerchTheme.error.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    VStack(spacing: 16) {
        ErrorBanner(
            message: "Failed to load data",
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
