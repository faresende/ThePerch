import SwiftUI

/// Displays a Paperless document bookmark with document-style appearance.
/// Shows a document icon, filename, file type badge, and tags.
struct PaperlessCard: View {
    let bookmark: BookmarkData
    let onTap: (() -> Void)?

    private var fileTypeLabel: String {
        if let ft = bookmark.fileType?.uppercased() {
            return ft
        }
        // Infer from URL extension
        let ext = URL(string: bookmark.url)?.pathExtension.uppercased() ?? ""
        return ext.isEmpty ? "DOC" : ext
    }

    private var displayName: String {
        bookmark.fileName ?? bookmark.displayTitle
    }

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .top, spacing: PerchTheme.Spacing.small) {
                // Document icon
                RoundedRectangle(cornerRadius: 10)
                    .fill(PerchTheme.accent.opacity(0.08))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: "doc.fill")
                            .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                            .foregroundColor(PerchTheme.accent)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    // File name
                    Text(displayName)
                        .font(PerchTheme.Font.heading)
                        .foregroundColor(PerchTheme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    // File type badge + domain
                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Text(fileTypeLabel)
                            .font(PerchTheme.Font.micro)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(PerchTheme.accent)
                            .cornerRadius(4)

                        if let domain = bookmark.domain {
                            Text(domain)
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                        }
                    }

                    // Tags
                    if !bookmark.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(bookmark.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(PerchTheme.Font.micro)
                                    .foregroundColor(PerchTheme.accent)
                                    .padding(.horizontal, PerchTheme.Spacing.xSmall)
                                    .padding(.vertical, PerchTheme.Spacing.xxxSmall)
                                    .background(PerchTheme.accentMuted)
                                    .cornerRadius(6)
                            }

                            if bookmark.tags.count > 3 {
                                Text("+\(bookmark.tags.count - 3)")
                                    .font(PerchTheme.Font.micro)
                                    .foregroundColor(PerchTheme.textTertiary)
                            }
                        }
                        .padding(.top, PerchTheme.Spacing.xxSmall)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(PerchTheme.Font.micro)
                    .foregroundColor(PerchTheme.textTertiary)
                    .padding(.top, PerchTheme.Spacing.xxxSmall)
            }
            .padding(PerchTheme.Spacing.large)
            .cardStyle()
        }
        .buttonStyle(CardPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Document: \(displayName)")
    }
}
