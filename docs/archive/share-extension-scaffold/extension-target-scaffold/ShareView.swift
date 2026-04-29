import SwiftUI

struct ShareView: View {
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @State private var isLoading: Bool = false
    @State private var isSaved: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false

    let sharedURL: URL?
    let sharedTitle: String?
    let extensionContext: NSExtensionContext?

    private let commonTags = ["article", "research", "design", "development", "inspiration", "reference"]
    private let supabaseClient = ShareSupabaseClient()

    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Save to The Perch")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        // URL Display
                        VStack(alignment: .leading, spacing: 4) {
                            Text("URL")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)

                                Text(sharedURL?.absoluteString ?? "No URL")
                                    .font(.caption)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                    .foregroundColor(.primary)

                                Spacer()
                            }
                            .padding(10)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }

                        // Title Display
                        if let title = sharedTitle, !title.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Page Title")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(title)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .foregroundColor(.primary)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            }
                        }

                        // Tags Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tags (optional)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // Tag Input Field
                            TextField(
                                "Add tags (comma-separated)",
                                text: $tagInput
                            )
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                            .font(.caption)

                            // Current Tags
                            if !tags.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(tags, id: \.self) { tag in
                                        TagChip(
                                            tag: tag,
                                            onRemove: {
                                                tags.removeAll { $0 == tag }
                                            }
                                        )
                                    }
                                }
                            }

                            // Common Tags
                            Text("Common:")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            FlowLayout(spacing: 6) {
                                ForEach(commonTags, id: \.self) { tag in
                                    Button(action: {
                                        if !tags.contains(tag) {
                                            tags.append(tag)
                                        }
                                    }) {
                                        Text(tag)
                                            .font(.caption2)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(
                                                tags.contains(tag)
                                                    ? Color.accentColor
                                                    : Color(.systemGray5)
                                            )
                                            .foregroundColor(
                                                tags.contains(tag) ? .white : .primary
                                            )
                                            .cornerRadius(6)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Action Buttons
                HStack(spacing: 10) {
                    Button(action: {
                        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                    }) {
                        Text("Cancel")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(8)
                    }

                    Button(action: saveBookmark) {
                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.8, anchor: .center)
                                Text("Saving...")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                            }
                        } else {
                            Text("Save")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                    .disabled(isLoading || sharedURL == nil)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
            .blur(radius: isSaved ? 3 : 0)
            .disabled(isSaved)

            // Success Overlay
            if isSaved {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                        .scaleEffect(0.8)
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isSaved)

                    Text("Saved!")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }

            // Error Alert
            if showError, let error = errorMessage {
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.red)

                        Text("Error Saving")
                            .font(.headline)

                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)

                    HStack(spacing: 10) {
                        Button(action: {
                            showError = false
                            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                        }) {
                            Text("Cancel")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(Color(.systemGray5))
                                .foregroundColor(.primary)
                                .cornerRadius(8)
                        }

                        Button(action: saveBookmark) {
                            Text("Retry")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.3))
            }
        }
        .onChange(of: tagInput) { newValue in
            // Auto-parse comma-separated tags
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            if trimmed.hasSuffix(",") {
                let newTag = trimmed.dropLast().trimmingCharacters(in: .whitespaces)
                if !newTag.isEmpty && !tags.contains(newTag) {
                    tags.append(newTag)
                    tagInput = ""
                }
            }
        }
    }

    private func saveBookmark() {
        guard let url = sharedURL else { return }

        isLoading = true
        showError = false
        errorMessage = nil

        Task {
            do {
                let _ = try await supabaseClient.saveBookmark(
                    url: url.absoluteString,
                    title: sharedTitle,
                    tags: tags
                )

                DispatchQueue.main.async {
                    withAnimation {
                        isSaved = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct TagChip: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(tag)
                .font(.caption2)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor)
        .foregroundColor(.white)
        .cornerRadius(6)
    }
}

struct FlowLayout: View {
    let spacing: CGFloat
    @State private var totalHeight = CGFloat.zero

    var content: [AnyView]

    init<Data: RandomAccessCollection>(spacing: CGFloat = 8, @ViewBuilder _ content: () -> ForEach<Data, Data.Element.ID, AnyView>) where Data.Element: Identifiable & Hashable {
        self.spacing = spacing
        let forEach = content()
        self.content = forEach.data.map { item in
            AnyView(forEach.content(item))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(0..<content.count, id: \.self) { index in
                content[index]
            }
        }
    }
}

// Extension for compatibility with FlowLayout
extension ForEach: RandomAccessCollection where ID: Hashable, Content: View {
    public var startIndex: Int { 0 }
    public var endIndex: Int { data.count }
    public subscript(position: Int) -> Content {
        content(data[data.index(data.startIndex, offsetBy: position)])
    }
}

#Preview {
    ShareView(
        sharedURL: URL(string: "https://www.example.com/article/the-future-of-ai")!,
        sharedTitle: "The Future of AI and Machine Learning",
        extensionContext: nil
    )
}
