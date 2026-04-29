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
                        // R12: action.deepLink is server-controlled (agents
                        // populate the action records). Route through the
                        // scheme allowlist — http/https only.
                        if let url = URL(string: action.deepLink) {
                            ExternalURLOpener.openExternal(url)
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
