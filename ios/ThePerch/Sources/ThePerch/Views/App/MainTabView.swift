import SwiftUI
import PhotosUI

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
            Tab(RootTab.capture.title, systemImage: RootTab.capture.systemImage, value: RootTab.capture, role: .search) {
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
    @State private var isPresentingPhotoPicker: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem?

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
                // Attached photo preview — shown only while a photo is
                // selected and the user hasn't submitted yet.
                if let photo = draftPhoto {
                    // `Section` resolves to the app's data model; qualify
                    // as SwiftUI.Section.
                    SwiftUI.Section {
                        HStack(spacing: 12) {
                            Image(uiImage: photo)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Attached photo")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Tap Send or add a note")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                draftPhoto = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove photo")
                        }
                    }
                }

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
            .searchable(
                text: $draftText,
                prompt: "Log a meal, a receipt, anything"
            )
            .onSubmit(of: .search) {
                submitDraft()
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    // Photo attach: native PhotosPicker sheet for now.
                    // Custom photo-keyboard replacement is a follow-up.
                    Button {
                        isPresentingPhotoPicker = true
                    } label: {
                        Image(systemName: "photo")
                    }

                    Spacer()

                    Button {
                        submitDraft()
                    } label: {
                        Text("Send")
                            .fontWeight(.semibold)
                    }
                    .disabled(canSubmit == false)
                }
            }
            .photosPicker(
                isPresented: $isPresentingPhotoPicker,
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared()
            )
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run {
                            draftPhoto = image
                        }
                    }
                    await MainActor.run { selectedPhotoItem = nil }
                }
            }
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
