import PhotosUI
import SwiftUI
import UIKit

/// Sheet for logging a meal via text, photo, or both.
struct MealInputSheet: View {
    let isSubmitting: Bool
    let onSubmit: (_ text: String?, _ image: UIImage?) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var mealDescription = ""
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?

    private var trimmedDescription: String? {
        let value = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var canSubmit: Bool {
        trimmedDescription != nil || selectedImage != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    Text("Tell the agent what you ate or attach a meal photo for analysis.")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)

                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                        Text("Meal description")
                            .font(PerchTheme.Font.cardEyebrow)
                            .foregroundColor(PerchTheme.textSecondary)

                        TextField("Salmon bowl, avocado, rice...", text: $mealDescription, axis: .vertical)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                            .lineLimit(3...6)
                            .padding(PerchTheme.Spacing.medium)
                            .background(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                    .fill(PerchTheme.cardInnerBackground)
                            )
                    }

                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                        Text("Meal photo")
                            .font(PerchTheme.Font.cardEyebrow)
                            .foregroundColor(PerchTheme.textSecondary)

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            HStack(spacing: PerchTheme.Spacing.small) {
                                Image(systemName: "photo.badge.plus")
                                    .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                                Text(selectedImage == nil ? "Choose photo" : "Replace photo")
                                    .font(PerchTheme.Font.body)
                            }
                            .foregroundColor(PerchTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, PerchTheme.Spacing.medium)
                            .background(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                    .fill(PerchTheme.accentMuted)
                            )
                        }
                        .buttonStyle(.plain)

                        if let selectedImage {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: selectedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 220)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius))

                                Button {
                                    self.selectedImage = nil
                                    self.selectedPhoto = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                                        .foregroundColor(.white)
                                        .padding(PerchTheme.Spacing.small)
                                }
                            }
                        }
                    }
                }
                .padding(PerchTheme.Spacing.large)
            }
            .background(PerchTheme.background.ignoresSafeArea())
            .navigationTitle("Log Meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(PerchTheme.textSecondary)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            let didSubmit = await onSubmit(trimmedDescription, selectedImage)
                            if didSubmit {
                                dismiss()
                            }
                        }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .tint(PerchTheme.accent)
                        } else {
                            Text("Submit")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(PerchTheme.accent)
                    .disabled(!canSubmit || isSubmitting)
                }
            }
        }
        .onChange(of: selectedPhoto) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImage = image
                    }
                }
            }
        }
    }
}
