import SwiftUI

struct UniversalCardFooter: View {
    struct Action: Identifiable, Equatable {
        let id: String
        let title: String
        let systemImage: String?
        let deepLink: String
    }

    let actions: [Action]

    var body: some View {
        if actions.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: PerchTheme.Spacing.small) {
                ForEach(actions) { action in
                    Button {
                        // Deep links are executed by higher-level router.
                        // For now, we just open URL.
                        if let url = URL(string: action.deepLink) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if let systemImage = action.systemImage {
                                Image(systemName: systemImage)
                            }
                            Text(action.title)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(action.title)
                }

                Spacer(minLength: 0)
            }
        }
    }
}
