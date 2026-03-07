import SwiftUI

struct ShareExtensionView: View {
    let url: URL
    let title: String
    let extensionContext: NSExtensionContext?

    @State private var tags: String = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                // Header
                HStack {
                    Text("Save to The Perch")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                ScrollView {
                    VStack(spacing: 12) {
                        // URL/Domain indicator with favicon placeholder
                        // TODO: Fabio - Add actual favicon fetching here
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 40, height: 40)

                                Image(systemName: "link.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.blue)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                if let host = url.host {
                                    Text(host)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text(title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                        // URL (truncated)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("URL")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            Text(url.absoluteString)
                                .font(.caption)
                                .lineLimit(3)
                                .truncationMode(.tail)
                                .foregroundColor(.secondary)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)

                        // Tags input
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tags (optional, comma-separated)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)

                            TextField("e.g. design, inspiration, tutorial", text: $tags)
                                .font(.subheadline)
                                .padding(10)
                                .background(Color(.systemGray6))
                                .cornerRadius(6)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12)
                }

                Spacer(minLength: 12)

                // Error message (if any)
                if let error = errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(6)
                    .padding(.horizontal, 16)
                }

                // Action buttons
                HStack(spacing: 12) {
                    Button(action: cancel) {
                        Text("Cancel")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .foregroundColor(.gray)
                    }
                    .disabled(isLoading || showSuccess)

                    Button(action: save) {
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                            }
                            Text(isLoading ? "Saving..." : "Save")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(12)
                        .foregroundColor(.white)
                        .background(Color.blue)
                        .cornerRadius(8)
                    }
                    .disabled(isLoading || showSuccess)
                }
                .padding(16)
            }
            .opacity(showSuccess ? 0.3 : 1)

            // Success overlay
            if showSuccess {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.green)
                        .scaleEffect(showSuccess ? 1 : 0.5)

                    Text("Saved!")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground).opacity(0.95))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSuccess)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func save() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let supabaseClient = ShareSupabaseClient()

                // Parse tags
                let parsedTags = tags
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                // Save to Supabase
                _ = try await supabaseClient.saveBookmark(
                    url: url.absoluteString,
                    title: title.isEmpty ? url.host ?? url.absoluteString : title,
                    tags: parsedTags
                )

                // Show success and dismiss
                await MainActor.run {
                    showSuccess = true
                }

                // Auto-dismiss after 1.5 seconds
                try await Task.sleep(nanoseconds: 1_500_000_000)

                await MainActor.run {
                    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func cancel() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

#Preview {
    ShareExtensionView(
        url: URL(string: "https://example.com/article")!,
        title: "Example Article Title",
        extensionContext: nil
    )
}
