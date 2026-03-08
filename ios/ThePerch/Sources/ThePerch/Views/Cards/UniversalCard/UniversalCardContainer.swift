import SwiftUI

struct UniversalCardContainer<Content: View>: View {
    enum CardState: String {
        case ok
        case loading
        case error
    }

    let record: Record
    let titleOverride: String?
    let subtitleOverride: String?
    let iconOverride: String?
    let accentColorOverride: Color?
    let state: CardState
    let errorMessage: String?
    let actions: [UniversalCardFooter.Action]
    let content: Content

    init(
        record: Record,
        titleOverride: String? = nil,
        subtitleOverride: String? = nil,
        iconOverride: String? = nil,
        accentColorOverride: Color? = nil,
        state: CardState = .ok,
        errorMessage: String? = nil,
        actions: [UniversalCardFooter.Action] = [],
        @ViewBuilder content: () -> Content
    ) {
        self.record = record
        self.titleOverride = titleOverride
        self.subtitleOverride = subtitleOverride
        self.iconOverride = iconOverride
        self.accentColorOverride = accentColorOverride
        self.state = state
        self.errorMessage = errorMessage
        self.actions = actions
        self.content = content()
    }

    private var headerIcon: String? { iconOverride }
    private var headerTitle: String { titleOverride ?? record.title }
    private var headerSubtitle: String? { subtitleOverride }

    var body: some View {
        VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
            UniversalCardHeader(
                icon: headerIcon,
                title: headerTitle,
                subtitle: headerSubtitle,
                freshnessText: record.relativeTime,
                isPinned: record.pinned
            )

            Group {
                switch state {
                case .ok:
                    content
                case .loading:
                    LoadingOverlay()
                case .error:
                    ErrorOverlay(message: errorMessage ?? "Something went wrong")
                }
            }

            UniversalCardFooter(actions: actions)
        }
        .padding(PerchTheme.Card.padding)
        .cardStyle()
        .accessibilityElement(children: .contain)
    }
}

private struct LoadingOverlay: View {
    var body: some View {
        HStack(spacing: PerchTheme.Spacing.small) {
            ProgressView()
            Text("Loading")
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, PerchTheme.Spacing.xSmall)
        .accessibilityLabel("Loading")
    }
}

private struct ErrorOverlay: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, PerchTheme.Spacing.xSmall)
        .accessibilityLabel("Error: \(message)")
    }
}
