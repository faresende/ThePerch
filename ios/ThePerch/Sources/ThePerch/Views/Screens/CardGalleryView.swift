import SwiftUI

struct CardGalleryView: View {
    struct GalleryItem: Identifiable {
        let id: String
        let name: String
        let systemImage: String
        let description: String
    }

    private let items: [GalleryItem] = [
        .init(id: "metric", name: "Metric", systemImage: "gauge", description: "Single value with optional trend"),
        .init(id: "list", name: "List", systemImage: "list.bullet", description: "Ordered items like tasks or deliveries"),
        .init(id: "timeline", name: "Timeline", systemImage: "clock", description: "Chronological events"),
        .init(id: "status", name: "Status", systemImage: "heartbeat", description: "Health indicators for services"),
        .init(id: "text", name: "Text", systemImage: "text.alignleft", description: "Notes, summaries, briefings"),
        .init(id: "checklist", name: "Checklist", systemImage: "checklist", description: "Toggleable items"),
    ]

    private let columns: [GridItem] = [
        GridItem(.adaptive(minimum: 160), spacing: PerchTheme.Spacing.small)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: PerchTheme.Spacing.small) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                        HStack {
                            Image(systemName: item.systemImage)
                                .foregroundColor(PerchTheme.accent)
                            Text(item.name)
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)
                            Spacer(minLength: 0)
                        }

                        Text(item.description)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                    .padding(PerchTheme.Card.padding)
                    .cardStyle()
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(PerchTheme.Spacing.medium)
        }
        .navigationTitle("Card Gallery")
        .background(PerchTheme.background)
    }
}

#Preview {
    NavigationStack {
        CardGalleryView()
    }
}
