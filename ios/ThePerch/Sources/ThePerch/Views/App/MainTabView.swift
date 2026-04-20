import SwiftUI
import Photos
import PhotosUI
import AVFoundation

struct MainTabView: View {
    @Environment(\.perchPalette) private var palette
    @Environment(DashboardViewModel.self) var dashboardViewModel

    @State private var selectedTab: RootTab = Self.initialTab()
    @State private var isShowingSettings = false
    @State private var didHandleDebugLaunchRouting = false

    /// Shown briefly after Accept to confirm the capture was routed.
    /// Lives at the TabView level so it can overlay every tab.
    @State private var composeToastMessage: String?

    enum RootTab: String, Hashable {
        case today
        case health
        case hub
        case capture

        var title: String {
            switch self {
            case .today: "Today"
            case .health: "Health"
            case .hub: "Hub"
            case .capture: "Create"
            }
        }

        var systemImage: String {
            switch self {
            case .today: "house.fill"
            case .health: "heart.fill"
            case .hub: "square.grid.2x2.fill"
            case .capture: "plus"
            }
        }
    }

    private static func initialTab() -> RootTab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uiDebugInitialTab"), arguments.indices.contains(index + 1) {
            let candidate = arguments[index + 1].lowercased()
            if candidate == "settings" {
                return .today
            }
            if let tab = RootTab(rawValue: candidate) {
                return tab
            }
        }
        #endif

        return .today
    }

    var body: some View {
        let timeOfDay = PerchTimeOfDay.current
        let palette = PerchPalette.forTimeOfDay(timeOfDay)

        TabView(selection: $selectedTab) {
            Tab(RootTab.today.title, systemImage: RootTab.today.systemImage, value: RootTab.today) {
                TodayTab(onOpenProfile: presentSettings)
            }

            Tab(RootTab.health.title, systemImage: RootTab.health.systemImage, value: RootTab.health) {
                HealthTab(onOpenProfile: presentSettings)
            }

            Tab(RootTab.hub.title, systemImage: RootTab.hub.systemImage, value: RootTab.hub) {
                HubTab(onOpenProfile: presentSettings)
            }

            // The Create tab uses the iOS 26 `.search` role. When the
            // user taps it, iOS natively contracts the other tabs to
            // icon-only on the left and expands the search field on
            // the right — same mechanism Apple Music, Mail, and Photos
            // use. No custom overlay, no tab-bar-hide hack. The view
            // inside is the capture history; `.searchable` inside that
            // view binds the draft text and drives the keyboard.
            Tab(RootTab.capture.title, systemImage: RootTab.capture.systemImage, value: RootTab.capture) {
                CaptureHistoryView(
                    onSubmit: handleCaptureSubmit
                )
            }
        }
        .tint(palette.kinetic)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.perchPalette, palette)
        .environment(\.perchTimeOfDay, timeOfDay)
        .sheet(isPresented: $isShowingSettings) {
            SettingsTab()
        }
        .overlay(alignment: .top) {
            if let msg = composeToastMessage {
                PerchComposeToast(message: msg)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .task(id: "main-tab-debug-routing") {
            guard !didHandleDebugLaunchRouting else { return }
            didHandleDebugLaunchRouting = true
            if Self.debugLaunchesSettings {
                isShowingSettings = true
            }
        }
        .task(id: "main-tab-load-safety-net") {
            guard dashboardViewModel.allRecords.isEmpty,
                  !dashboardViewModel.isLoading else { return }
            await dashboardViewModel.loadDashboard()
        }
    }

    /// Called by CaptureHistoryView when the user submits a capture
    /// (via search-field return or a tapped history row). For v1 the
    /// AI routing is stubbed: text → Travel, photo → Nutrition. Real
    /// LLM call lands here later without changing the view shape.
    private func handleCaptureSubmit(_ draft: CaptureDraft) {
        let destination = draft.mockDestination
        // Pop the user back to Today so the toast reads as "that thing
        // landed in X" rather than staying on the search page.
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            selectedTab = .today
        }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
                composeToastMessage = "Added to \(destination)"
            }
            try? await Task.sleep(for: .milliseconds(2200))
            withAnimation(.easeOut(duration: 0.3)) {
                composeToastMessage = nil
            }
        }
    }


    // MARK: - Debug routing

    private static var debugLaunchesSettings: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-uiDebugInitialTab"), arguments.indices.contains(index + 1) {
            return arguments[index + 1].lowercased() == "settings"
        }
        #endif
        return false
    }

    private func presentSettings() {
        isShowingSettings = true
    }
}

#Preview {
    MainTabView()
        .environment(AuthViewModel())
        .environment(DashboardViewModel())
        .environment(NetworkMonitor.shared)
}

struct ProfileEntryButton: View {
    @Environment(AuthViewModel.self) private var authViewModel

    let prominence: Prominence
    let action: () -> Void

    enum Prominence {
        case prominent
        case subtle
    }

    var body: some View {
        Button(action: action) {
            avatar
                .padding(prominence == .prominent ? 4 : 3)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(PerchTheme.border, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open profile and settings")
    }

    private var avatar: some View {
        Text(initials)
            .font(.system(size: prominence == .prominent ? 13 : 12, weight: .bold))
            .foregroundColor(PerchTheme.accentForeground)
            .frame(width: prominence == .prominent ? 34 : 30, height: prominence == .prominent ? 34 : 30)
            .background(PerchTheme.accent)
            .clipShape(Circle())
    }

    private var initials: String {
        let source = authViewModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? authViewModel.email
            : authViewModel.displayName

        let pieces = source
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .prefix(2)

        let letters = pieces.compactMap { $0.first }.map { String($0).uppercased() }
        return letters.isEmpty ? "P" : letters.joined()
    }
}

enum CaptureActionOption: String, CaseIterable, Hashable, Sendable {
    case logMeal
    case quickNote

    static var primaryActions: [Self] {
        [.logMeal, .quickNote]
    }

    var title: String {
        switch self {
        case .logMeal: "Log meal"
        case .quickNote: "Quick note"
        }
    }

    var subtitle: String {
        switch self {
        case .logMeal: "Text or photo → nutrition analysis"
        case .quickNote: "Drop a thought, task, or reminder fast"
        }
    }

    var systemImage: String {
        switch self {
        case .logMeal: "fork.knife.circle.fill"
        case .quickNote: "note.text.badge.plus"
        }
    }
    
    var accentColor: Color {
        switch self {
        case .logMeal: PerchTheme.accent
        case .quickNote: PerchTheme.steel
        }
    }
}

struct QuickNoteDraft: Equatable, Sendable {
    var body: String

    var trimmedBody: String? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var derivedTitle: String {
        guard let trimmedBody else { return "Quick Note" }
        let firstMeaningfulLine = trimmedBody
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })

        guard let firstMeaningfulLine, !firstMeaningfulLine.isEmpty else {
            return "Quick Note"
        }

        return String(firstMeaningfulLine.prefix(60))
    }
}

struct CaptureSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showingMealInput = false
    @State private var showingQuickNote = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                        Text("Create")
                            .font(PerchTheme.Font.title)
                            .foregroundColor(PerchTheme.textPrimary)

                        Text("Fast capture from anywhere. Start with the two actions that actually matter.")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)
                    }

                    VStack(spacing: PerchTheme.Spacing.medium) {
                        ForEach(CaptureActionOption.primaryActions, id: \.self) { action in
                            Button {
                                present(action)
                            } label: {
                                CaptureActionCard(action: action)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("More routes can hang off this later, but these two are now real instead of decorative.")
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }
                .padding(PerchTheme.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PerchTheme.background.ignoresSafeArea())
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(PerchTheme.accent)
                }
            }
        }
        .sheet(isPresented: $showingMealInput) {
            CaptureMealFlowSheet {
                dismiss()
            }
        }
        .sheet(isPresented: $showingQuickNote) {
            QuickNoteInputSheet {
                dismiss()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func present(_ action: CaptureActionOption) {
        switch action {
        case .logMeal:
            showingMealInput = true
        case .quickNote:
            showingQuickNote = true
        }
    }
}

private struct CaptureActionCard: View {
    let action: CaptureActionOption

    var body: some View {
        HStack(spacing: PerchTheme.Spacing.medium) {
            Image(systemName: action.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(action.accentColor)
                .frame(width: 44, height: 44)
                .background(action.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(action.title)
                    .font(PerchTheme.Font.body)
                    .fontWeight(.semibold)
                    .foregroundColor(PerchTheme.textPrimary)

                Text(action.subtitle)
                    .font(PerchTheme.Font.caption)
                    .foregroundColor(PerchTheme.textSecondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: PerchTheme.Spacing.small)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(PerchTheme.textTertiary)
        }
        .padding(PerchTheme.Spacing.medium)
        .background(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .fill(PerchTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius, style: .continuous)
                .stroke(PerchTheme.border, lineWidth: 1)
        )
    }
}

private struct CaptureMealFlowSheet: View {
    @Environment(DashboardViewModel.self) private var dashboardViewModel
    @State private var nutritionViewModel = NutritionViewModel()
    @State private var completedCapture = false

    let onComplete: () -> Void

    var body: some View {
        MealInputSheet(isSubmitting: nutritionViewModel.isAnalyzing) { text, image in
            guard let submissionUserId = SupabaseService.shared.currentUserId else {
                nutritionViewModel.error = "You must be signed in to log a meal."
                return false
            }

            let didSubmit = await nutritionViewModel.logMeal(text: text, image: image, userId: submissionUserId)
            if didSubmit {
                await dashboardViewModel.loadDashboard(forceRefresh: true)
                completedCapture = true
            }
            return didSubmit
        }
        .onDisappear {
            if completedCapture {
                onComplete()
            }
        }
    }
}

private struct QuickNoteInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(DashboardViewModel.self) private var dashboardViewModel

    @State private var draft = QuickNoteDraft(body: "")
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var completedCapture = false

    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                    Text("Capture a thought before it evaporates.")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(PerchTheme.error)
                            .padding(PerchTheme.Spacing.medium)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(PerchTheme.error.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(PerchTheme.error.opacity(0.18), lineWidth: 1)
                            )
                            .cornerRadius(12)
                    }

                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                        Text("Note")
                            .font(PerchTheme.Font.cardEyebrow)
                            .foregroundColor(PerchTheme.textSecondary)

                        TextEditor(text: $draft.body)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textPrimary)
                            .frame(minHeight: 220)
                            .padding(PerchTheme.Spacing.small)
                            .background(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                    .fill(PerchTheme.cardInnerBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.innerCornerRadius)
                                    .stroke(PerchTheme.focusRing, lineWidth: 1)
                            )
                    }
                }
                .padding(PerchTheme.Spacing.large)
            }
            .background(PerchTheme.background.ignoresSafeArea())
            .navigationTitle("Quick Note")
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
                            await saveNote()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(PerchTheme.accent)
                        } else {
                            Text("Save")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(PerchTheme.accent)
                    .disabled(isSaving || draft.trimmedBody == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear {
            if completedCapture {
                onComplete()
            }
        }
    }

    private func saveNote() async {
        guard let body = draft.trimmedBody else { return }
        guard let currentUserId = SupabaseService.shared.currentUserId,
              let userId = UUID(uuidString: currentUserId) else {
            errorMessage = "You must be signed in to save a quick note."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            try await SupabaseService.shared.insertRecord(
                agentId: "claudinho",
                userId: userId,
                type: .textNote,
                category: .admin,
                title: draft.derivedTitle,
                data: [
                    "body": .string(body),
                    "tags": .array([]),
                ],
                displayHint: .unknown
            )
            await dashboardViewModel.loadDashboard(forceRefresh: true)
            completedCapture = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


// MARK: - Compose shimmer bar

/// Moving highlight bar, signals "AI is reading".
private struct ComposeShimmerBar: View {
    @Environment(\.perchPalette) private var palette
    @State private var phase: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(palette.ink.opacity(0.08))
                .overlay(
                    LinearGradient(
                        colors: [
                            palette.ink.opacity(0.02),
                            palette.ink.opacity(0.18),
                            palette.ink.opacity(0.02)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.55)
                    .offset(x: phase * geo.size.width)
                    .blendMode(.multiply)
                )
                .clipShape(Capsule())
        }
        .frame(height: 8)
        .onAppear {
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
        .accessibilityHidden(true)
    }
}


// MARK: - Compose acceptance toast

/// Liquid-glass pill that slides down from the top on accept.
/// Auto-dismiss is owned by the parent (MainTabView) — this view just
/// renders the pill.
struct PerchComposeToast: View {
    @Environment(\.perchPalette) private var palette
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(palette.kinetic)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.ink)
        }
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(palette.ink.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: palette.ink.opacity(0.12), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
    }
}

// MARK: - CaptureDraft
//
// Shape the CaptureHistoryView hands back to MainTabView when the
// user submits. Real AI routing plugs into `mockDestination` later.

struct CaptureDraft: Equatable {
    var text: String
    var photo: UIImage?

    /// Stubbed routing for v1. Photo → Nutrition, text → Travel.
    /// Matches the handoff's canned examples.
    var mockDestination: String {
        photo != nil ? "Nutrition" : "Travel"
    }

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && photo == nil
    }
}

// MARK: - CaptureHistoryView
//
// Rendered inside the `Tab(role: .search)` slot. iOS 26 automatically
// contracts the other tabs and expands the search field when this tab
// is active — no custom chrome needed.
//
// Structure:
//   - NavigationStack + List with "Recent captures" section (mocked for
//     v1; real history coming when captures persist to Supabase).
//   - `.searchable` binds the draft text to the native field. iOS
//     handles keyboard, clear/X button, and field animation.
//   - Keyboard toolbar (placement: .keyboard) adds the photo button +
//     Send. Tapping photo presents the native PhotosPicker as a sheet
//     until the custom photo-keyboard input view lands in a follow-up.
//   - Tapping a history row treats it like a re-submit with that item's
//     original text.

struct CaptureHistoryView: View {
    @Environment(\.perchPalette) private var palette

    let onSubmit: (CaptureDraft) -> Void

    @State private var draftText: String = ""
    @State private var draftPhoto: UIImage?

    /// Mocked history until captures persist to the backend. Each row
    /// shows what the user previously sent — tap to re-add.
    private let history: [CaptureHistoryItem] = [
        .init(text: "One pastel de nata", destination: "Nutrition", systemImage: "leaf", agoLabel: "Yesterday"),
        .init(text: "Flight to Porto · BA 1234", destination: "Travel", systemImage: "airplane", agoLabel: "2d ago"),
        .init(text: "Gym · Chest and Triceps", destination: "Health", systemImage: "dumbbell", agoLabel: "2d ago"),
        .init(text: "Dentist Wednesday 9:30 Dr Schneider", destination: "Calendar", systemImage: "calendar", agoLabel: "3d ago"),
        .init(text: "MR Porter · linen jacket", destination: "Orders", systemImage: "shippingbox", agoLabel: "1w ago"),
    ]

    var body: some View {
        NavigationStack {
            List {
                // Compose field sits at the top of the list as a
                // full-width card. Renders the attachment thumbnail
                // INSIDE the field (above the text line) when a photo
                // is picked, so the card grows in height naturally.
                SwiftUI.Section {
                    CaptureComposeField(
                        text: $draftText,
                        attachedPhoto: $draftPhoto,
                        palette: palette,
                        onSubmit: submitDraft
                    )
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                SwiftUI.Section("Recent captures") {
                    ForEach(history) { item in
                        Button {
                            // Tap-to-re-add shortcut. Hand straight to
                            // onSubmit with the item's text; the parent
                            // runs the same routing path.
                            let draft = CaptureDraft(text: item.text, photo: nil)
                            onSubmit(draft)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.systemImage)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(palette.kinetic)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle().fill(palette.kinetic.opacity(0.12))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("\(item.destination) · \(item.agoLabel)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var canSubmit: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftPhoto != nil
    }

    private func submitDraft() {
        guard canSubmit else { return }
        let draft = CaptureDraft(text: draftText, photo: draftPhoto)
        draftText = ""
        draftPhoto = nil
        onSubmit(draft)
    }
}

/// One row in the CaptureHistoryView list. Real items will come from
/// Supabase when captures persist; for v1 they're hard-coded.
private struct CaptureHistoryItem: Identifiable {
    let id = UUID()
    let text: String
    let destination: String
    let systemImage: String
    let agoLabel: String
}

// MARK: - CaptureComposeField
//
// Custom text field that expands vertically when a photo is attached.
// Attachment row sits ABOVE the input line inside the same rounded
// rectangle, so the field reads as growing to two rows — exactly
// what the user asked for. Camera icon (trailing) swaps the keyboard
// for our PerchPhotoKeyboardView via the UITextField's `inputView`;
// Send icon fires onSubmit.
//
// Trade-off: ditching `.searchable` means we lose the iOS 26
// Apple-Music-style tab-bar-contract animation on tap. We gain the
// multi-line-with-attachments behaviour UISearchBar fundamentally
// can't provide (it's single-line by design).

private struct CaptureComposeField: View {
    @Binding var text: String
    @Binding var attachedPhoto: UIImage?
    let palette: PerchPalette
    let onSubmit: () -> Void

    private var canSubmit: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || attachedPhoto != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Attachment row — only present when a photo is attached.
            // Makes the field visually grow to double height, with
            // the thumbnail sitting above the text line.
            if let photo = attachedPhoto {
                HStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: photo)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(palette.line, lineWidth: 0.5)
                            )

                        Button {
                            attachedPhoto = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .accessibilityLabel("Remove photo")
                    }
                    Spacer(minLength: 0)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Input row: text field (with photo-keyboard-capable
            // UITextField underneath) + camera toggle + send.
            HStack(spacing: 8) {
                CaptureInputTextField(
                    text: $text,
                    attachedPhoto: $attachedPhoto,
                    placeholder: "Log a meal, a receipt, anything",
                    tint: UIColor(palette.kinetic),
                    onReturn: onSubmit
                )
                .frame(maxWidth: .infinity, minHeight: 28)

                Button {
                    onSubmit()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(canSubmit
                                         ? Color(red: 1.0, green: 0.973, blue: 0.925)
                                         : palette.faint)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle().fill(canSubmit ? palette.kinetic : palette.ink.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .animation(.easeInOut(duration: 0.18), value: canSubmit)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(palette.line.opacity(0.4), lineWidth: 0.5)
        )
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: attachedPhoto != nil)
    }
}

// MARK: - CaptureInputTextField
//
// UITextField wrapped so we can tap-to-swap the keyboard for the
// PerchPhotoKeyboardView. SwiftUI's TextField doesn't expose
// `inputView`; UITextField does, and flipping it + calling
// `reloadInputViews()` is how you swap the keyboard for any
// custom view. A leading camera button inside the field triggers
// the swap. Tapping the text area (when the photo keyboard is
// showing) flips back to the system keyboard.

private struct CaptureInputTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var attachedPhoto: UIImage?
    let placeholder: String
    let tint: UIColor
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            attachedPhoto: $attachedPhoto,
            tint: tint,
            onReturn: onReturn
        )
    }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.placeholder = placeholder
        tf.font = .systemFont(ofSize: 16)
        tf.tintColor = tint
        tf.returnKeyType = .send
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        tf.autocorrectionType = .yes
        tf.clearButtonMode = .whileEditing

        // Leading camera button — lives inside the text field and
        // toggles the keyboard ↔ photo grid.
        let camera = UIButton(type: .system)
        let cfg = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        camera.setImage(UIImage(systemName: "camera", withConfiguration: cfg), for: .normal)
        camera.tintColor = tint
        camera.frame = CGRect(x: 0, y: 0, width: 32, height: 28)
        camera.addAction(UIAction { [weak coordinator = context.coordinator] _ in
            coordinator?.toggleInputView(on: tf)
        }, for: .touchUpInside)
        tf.leftView = camera
        tf.leftViewMode = .always

        // Gesture that flips back to keyboard if the photo grid is up
        // and the user taps the text area. `cancelsTouchesInView = false`
        // + delegate's `shouldRecognizeSimultaneously = true` so the
        // text field's own tap handlers (which promote it to first
        // responder) still fire on the first tap.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTextFieldTap))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        tf.addGestureRecognizer(tap)

        context.coordinator.textField = tf
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.tintColor = tint
        context.coordinator.onReturn = onReturn
    }

    @MainActor
    final class Coordinator: NSObject, UITextFieldDelegate, UIGestureRecognizerDelegate {
        @Binding var text: String
        @Binding var attachedPhoto: UIImage?
        var tint: UIColor
        var onReturn: () -> Void

        weak var textField: UITextField?
        private var photoKeyboardView: PerchPhotoKeyboardView?
        private var showingPhotoKeyboard: Bool = false

        init(
            text: Binding<String>,
            attachedPhoto: Binding<UIImage?>,
            tint: UIColor,
            onReturn: @escaping () -> Void
        ) {
            self._text = text
            self._attachedPhoto = attachedPhoto
            self.tint = tint
            self.onReturn = onReturn
        }

        @objc func editingChanged(_ tf: UITextField) {
            text = tf.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onReturn()
            return true
        }

        @objc func handleTextFieldTap() {
            guard showingPhotoKeyboard else { return }
            // Tapping the text area while the photo grid is up flips
            // back to the system keyboard.
            guard let tf = textField else { return }
            tf.inputView = nil
            showingPhotoKeyboard = false
            if tf.isFirstResponder { tf.reloadInputViews() }
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func toggleInputView(on tf: UITextField) {
            if showingPhotoKeyboard {
                tf.inputView = nil
                showingPhotoKeyboard = false
            } else {
                let grid: PerchPhotoKeyboardView
                if let existing = photoKeyboardView {
                    grid = existing
                } else {
                    grid = PerchPhotoKeyboardView { [weak self] image in
                        self?.attachedPhoto = image
                    }
                    photoKeyboardView = grid
                }
                tf.inputView = grid
                showingPhotoKeyboard = true
            }
            if tf.isFirstResponder {
                tf.reloadInputViews()
            } else {
                tf.becomeFirstResponder()
            }
        }
    }
}

final class PerchPhotoKeyboardView: UIView {
    var onPhotoSelected: (UIImage) -> Void

    private let collectionView: UICollectionView
    private let imageManager = PHCachingImageManager()
    private var assets: PHFetchResult<PHAsset>?
    private static let cameraReuseID = "CameraCell"
    private static let photoReuseID = "PhotoCell"

    // MARK: Live camera preview
    //
    // One AVCaptureSession is owned by the keyboard view (not the cell)
    // so session configuration / start / stop aren't tied to cell
    // recycling. The preview layer is attached to whichever CameraCell
    // is currently visible (usually the same one across scrolls).
    //
    // The session runs only while the keyboard view is in a window and
    // stops the moment it's detached — both for battery and so opening
    // the compose flow doesn't keep the camera hot.

    private let capturePreviewLayer = AVCaptureVideoPreviewLayer()
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "perch.compose.photoKeyboard.session")
    private var sessionConfigured = false
    private var cameraAuthorized = false

    init(onPhotoSelected: @escaping (UIImage) -> Void) {
        self.onPhotoSelected = onPhotoSelected

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 2
        layout.minimumLineSpacing = 2
        self.collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)

        // Height of ≈280pt fits within the keyboard's own slot on
        // most iPhones. Autoresizing lets it stretch horizontally.
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 280))
        autoresizingMask = [.flexibleWidth]

        capturePreviewLayer.videoGravity = .resizeAspectFill

        setUpCollectionView()
        requestPhotoAccessAndLoad()
        requestCameraAccess()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            startCaptureSessionIfAllowed()
        } else {
            stopCaptureSession()
        }
    }

    private func setUpCollectionView() {
        backgroundColor = .secondarySystemBackground
        collectionView.backgroundColor = .clear
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(CameraCell.self, forCellWithReuseIdentifier: Self.cameraReuseID)
        collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: Self.photoReuseID)
        collectionView.alwaysBounceVertical = true

        addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private func requestPhotoAccessAndLoad() {
        let handler: (PHAuthorizationStatus) -> Void = { [weak self] status in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if status == .authorized || status == .limited {
                    self.fetchAssets()
                } else {
                    // No permission — collection stays empty apart
                    // from the camera cell, which still works via
                    // UIImagePickerController's own permission flow.
                    self.collectionView.reloadData()
                }
            }
        }
        PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: handler)
    }

    private func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 120
        assets = PHAsset.fetchAssets(with: .image, options: options)
        collectionView.reloadData()
    }

    // MARK: Capture session lifecycle

    private func requestCameraAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                DispatchQueue.main.async {
                    self.cameraAuthorized = granted
                    if granted && self.window != nil {
                        self.startCaptureSessionIfAllowed()
                    }
                }
            }
        case .denied, .restricted:
            cameraAuthorized = false
        @unknown default:
            cameraAuthorized = false
        }
    }

    private func startCaptureSessionIfAllowed() {
        guard cameraAuthorized else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSessionIfNeeded()
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    private func stopCaptureSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
        }
    }

    private func configureSessionIfNeeded() {
        guard !sessionConfigured else { return }
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .medium

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        captureSession.commitConfiguration()

        DispatchQueue.main.async {
            self.capturePreviewLayer.session = self.captureSession
        }
        sessionConfigured = true
    }

    // MARK: - Cells

    /// First cell in the grid. Hosts the live AVCaptureVideoPreviewLayer
    /// from the enclosing keyboard view. The layer is owned by the
    /// view (not the cell) so session start/stop isn't entangled with
    /// cell recycling — the cell just pins it into its own bounds when
    /// `attach(previewLayer:)` is called.
    private final class CameraCell: UICollectionViewCell {
        private let fallbackIcon: UIImageView = {
            let iv = UIImageView(image: UIImage(systemName: "camera.fill"))
            iv.tintColor = .white
            iv.contentMode = .center
            iv.translatesAutoresizingMaskIntoConstraints = false
            return iv
        }()

        private weak var previewLayer: AVCaptureVideoPreviewLayer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = UIColor(white: 0.12, alpha: 1)
            layer.cornerRadius = 4
            clipsToBounds = true
            contentView.addSubview(fallbackIcon)
            NSLayoutConstraint.activate([
                fallbackIcon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                fallbackIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        }
        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = contentView.bounds
        }

        func attach(previewLayer: AVCaptureVideoPreviewLayer) {
            // If it's already parented here, just resize.
            if previewLayer.superlayer === contentView.layer {
                previewLayer.frame = contentView.bounds
                return
            }
            previewLayer.removeFromSuperlayer()
            contentView.layer.insertSublayer(previewLayer, above: fallbackIcon.layer)
            previewLayer.frame = contentView.bounds
            self.previewLayer = previewLayer
        }
    }

    private final class PhotoCell: UICollectionViewCell {
        private let imageView: UIImageView = {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.translatesAutoresizingMaskIntoConstraints = false
            return iv
        }()
        private var assetID: String?

        override init(frame: CGRect) {
            super.init(frame: frame)
            layer.cornerRadius = 4
            clipsToBounds = true
            contentView.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])
        }
        required init?(coder: NSCoder) { fatalError() }

        func configure(asset: PHAsset, manager: PHCachingImageManager, targetSize: CGSize) {
            assetID = asset.localIdentifier
            imageView.image = nil
            manager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: nil
            ) { [weak self] image, _ in
                guard let self, self.assetID == asset.localIdentifier else { return }
                self.imageView.image = image
            }
        }
    }

    // MARK: - Camera presentation

    private func presentCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            // No camera (simulator) — nothing to do. Photo library
            // thumbnails are still tappable below.
            return
        }
        guard let presenter = topMostViewController() else { return }

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = cameraDelegate
        presenter.present(picker, animated: true)
    }

    /// Held on the view so the picker's delegate outlives the call.
    private lazy var cameraDelegate: CameraPickerDelegate = CameraPickerDelegate { [weak self] image in
        guard let self, let image else { return }
        self.onPhotoSelected(image)
    }

    private final class CameraPickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void

        init(onImage: @escaping (UIImage?) -> Void) {
            self.onImage = onImage
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let image = info[.originalImage] as? UIImage
            picker.dismiss(animated: true) {
                self.onImage(image)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }

    private func topMostViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }
}

extension PerchPhotoKeyboardView: UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        (assets?.count ?? 0) + 1  // +1 for the camera tile
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.item == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.cameraReuseID, for: indexPath) as! CameraCell
            cell.attach(previewLayer: capturePreviewLayer)
            return cell
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Self.photoReuseID, for: indexPath) as! PhotoCell
        if let asset = assets?.object(at: indexPath.item - 1) {
            let size = cellSize(at: indexPath)
            let scale = UIScreen.main.scale
            let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
            cell.configure(asset: asset, manager: imageManager, targetSize: targetSize)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if indexPath.item == 0 {
            presentCamera()
        } else if let asset = assets?.object(at: indexPath.item - 1) {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true
            imageManager.requestImage(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                contentMode: .aspectFit,
                options: options
            ) { [weak self] image, _ in
                guard let self, let image else { return }
                DispatchQueue.main.async {
                    self.onPhotoSelected(image)
                }
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        cellSize(at: indexPath)
    }

    private func cellSize(at indexPath: IndexPath) -> CGSize {
        let spacing: CGFloat = 2
        let columns: CGFloat = 4
        let available = bounds.width
        let width = floor((available - spacing * (columns - 1)) / columns)
        return CGSize(width: width, height: width)
    }
}
