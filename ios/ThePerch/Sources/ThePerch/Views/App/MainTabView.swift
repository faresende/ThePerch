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
        // The previous "safety-net" task here would race the
        // ThePerchApp .task that already loads the dashboard after
        // auth restore — sometimes both fired and we paid two
        // concurrent fetches at boot. Removed; the App-level task
        // is the single source of truth for the cold-load.
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
    /// Multiple photos accumulate as the user taps thumbnails in the
    /// photo keyboard — each selection appends. Remove individual
    /// photos via the X on each tile in the floating strip.
    @State private var draftPhotos: [UIImage] = []

    /// One-time "what's coming" splash — auto-shown on first visit
    /// per install (gated by AppStorage) so visitors / demo viewers
    /// understand the tab is a beta surface. Persistent in-place
    /// "BETA" banner stays visible afterwards as a quieter reminder.
    @AppStorage("captureBetaSplashSeen") private var splashSeen = false
    @State private var showingSplash = false

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
                // Persistent in-place beta banner — quiet but always
                // visible. Tap it to re-open the full explanatory
                // splash for context.
                SwiftUI.Section {
                    Button {
                        showingSplash = true
                    } label: {
                        captureBetaBanner
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                }

                // Capture list — palette-aware styling below overrides
                // the insetGrouped default. See `.scrollContentBackground`
                // + `.listRowBackground` + palette fonts.
                SwiftUI.Section {
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
                                    .frame(width: 32, height: 32)
                                    .background(
                                        Circle().fill(palette.kinetic.opacity(0.12))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.text)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(palette.ink)
                                        .lineLimit(1)
                                    Text("\(item.destination) · \(item.agoLabel)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(palette.muted)
                                }

                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.card)
                        .listRowSeparatorTint(palette.line.opacity(0.5))
                    }
                } header: {
                    Text("Recent captures")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(palette.muted)
                        .textCase(.uppercase)
                        .listRowInsets(EdgeInsets(top: 12, leading: 4, bottom: 8, trailing: 0))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.bg.ignoresSafeArea())
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.large)
            // Floating thumbnail strip above the bottom search field.
            // On iOS 26 `Tab(role: .search)` places the active search
            // bar at the bottom alongside the tab bar; `.safeAreaInset(
            // edge: .bottom)` plants this strip immediately above it,
            // so the thumbnails read as floating out of the compose
            // bar rather than sticking at the top of the screen.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !draftPhotos.isEmpty {
                    CaptureAttachmentStrip(
                        photos: draftPhotos,
                        palette: palette,
                        onRemove: { idx in
                            draftPhotos.remove(at: idx)
                        }
                    )
                    // 56pt bottom padding lifts the strip well clear
                    // of the bottom search bar. The safeAreaInset
                    // default anchors content flush against the bar,
                    // which is why they were overlapping.
                    .padding(.bottom, 56)
                    .transition(.opacity.combined(with: .offset(y: 12)))
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.82), value: draftPhotos.count)
            .searchable(
                text: $draftText,
                prompt: "Log a meal, a receipt, anything"
            )
            .onSubmit(of: .search) {
                submitDraft()
            }
            // Swap the search field's leading magnifying glass for a
            // tappable camera button + install the photo-grid keyboard.
            // attachedPhoto: pass the most-recent pick so the
            // controller can mirror state (mainly for the photo keyboard
            // to know what's current).
            .background(
                SearchBarInputController(
                    systemImage: "camera",
                    tint: UIColor(palette.kinetic),
                    attachedPhoto: draftPhotos.last,
                    onPhotoSelected: { image in
                        // Append rather than replace — user can stack
                        // multiple photos into one compose.
                        draftPhotos.append(image)
                    },
                    onPhotoRemoved: {
                        draftPhotos.removeAll()
                    }
                )
            )
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    // Camera lives inside the search field now (as the
                    // leading icon), so the keyboard toolbar only needs
                    // the Send button on the trailing side.
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
        }
        // Auto-present the splash on first visit.
        .task(id: "capture-beta-splash") {
            if !splashSeen {
                // Small delay so it doesn't feel like a popup
                // ambush the moment the user taps the tab.
                try? await Task.sleep(for: .milliseconds(400))
                showingSplash = true
            }
        }
        .sheet(isPresented: $showingSplash, onDismiss: {
            splashSeen = true
        }) {
            CaptureBetaSplash(onDismiss: { showingSplash = false })
        }
    }

    private var canSubmit: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draftPhotos.isEmpty
    }

    private func submitDraft() {
        guard canSubmit else { return }
        // CaptureDraft is still single-photo for v1. The first photo
        // in the stack is sent; additional photos drop on the floor
        // until the draft/routing pipeline supports arrays.
        let draft = CaptureDraft(text: draftText, photo: draftPhotos.first)
        draftText = ""
        draftPhotos = []
        onSubmit(draft)
    }

    /// In-place beta banner that lives at the top of the capture
    /// history list. Quiet visual weight — small kicker text in muted
    /// color with a kinetic-tinted "BETA" pill — but tappable so the
    /// user can re-read the splash any time.
    private var captureBetaBanner: some View {
        HStack(spacing: 10) {
            Text("BETA")
                .font(.system(size: 10, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(palette.kinetic)
                .clipShape(Capsule())

            Text("Auto-routing coming soon")
                .font(.system(size: 13, weight: .regular, design: .serif).italic())
                .foregroundStyle(palette.muted)

            Spacer()

            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(palette.faint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.line.opacity(0.45), lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }
}

// MARK: - Capture Beta Splash
//
// First-visit-only auto-presented sheet that explains what the
// `+` (Create) tab will eventually do. Until the AI routing layer
// ships, the tab is functionally a writing prompt + recent-captures
// stub. The splash sets expectations so demos / shared views don't
// read as "broken."

private struct CaptureBetaSplash: View {
    @Environment(\.perchPalette) private var palette
    @Environment(\.dismiss) private var dismissEnv

    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("BETA")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(palette.kinetic)
                        .clipShape(Capsule())

                    Text("Capture is in beta.")
                        .font(.system(size: 28, weight: .semibold, design: .serif).italic())
                        .foregroundStyle(palette.ink)

                    Text("The plan: one place to drop a thought, photo, or receipt — and the app routes it to the right surface for you. *Pastel de nata* goes to Nutrition. *MR Porter linen jacket* goes to Orders. *Dentist Wednesday at 9:30* goes to Calendar. No more deciding which tab to open first.")
                        .font(.system(size: 16, design: .serif).italic())
                        .foregroundStyle(palette.ink)
                        .lineSpacing(3)

                    Text("Today's status")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(palette.muted)
                        .padding(.top, 8)

                    bullet("The capture history is live — recent items show up below.")
                    bullet("The text + photo capture works — you can send something and it'll land in a default destination for now.")
                    bullet("The AI routing (the part that decides where each capture goes) is being built. Until it ships, captures land in placeholder surfaces.")

                    Text("Why surface this now?")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(palette.muted)
                        .padding(.top, 8)

                    Text("Better to see the shape of the feature than to think the tab is broken. The capture history is real value already; the routing is the unfinished bit.")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.muted)
                        .lineSpacing(2)

                    Spacer(minLength: 24)

                    Button {
                        onDismiss()
                    } label: {
                        Text("Got it")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(palette.kinetic)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(palette.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(palette.kinetic)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(palette.kinetic.opacity(0.55))
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(palette.ink)
                .lineSpacing(2)
        }
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

// MARK: - CaptureAttachmentStrip
//
// Floating angled "sticker" thumbnails that sit just above the
// bottom search field (via `.safeAreaInset(edge: .bottom)` in
// CaptureHistoryView). Each tile rotates ~8° for a casual,
// pinned-to-the-bar feel; additional photos stack to the right
// with slight offsets so you can see each one peeking out.
//
// Tile itself is 72pt with a white card, 4pt border in palette.card,
// soft shadow. Remove-X sits at the top-right corner, always
// upright so it remains tappable.

private struct CaptureAttachmentStrip: View {
    let photos: [UIImage]
    let palette: PerchPalette
    let onRemove: (Int) -> Void

    private static let tileSize: CGFloat = 72
    private static let rotation: Double = -35 // degrees; user spec
    private static let stepX: CGFloat = 52    // per-tile leading offset

    var body: some View {
        // ZStack with explicit per-tile offsets so the tilted tiles
        // don't collapse on top of each other (SwiftUI's HStack
        // measures pre-rotation bounds, which made the 35° tiles
        // bunch tight in earlier attempts). Each new tile shifts
        // `stepX` pts to the right and lifts in front of the last
        // via zIndex.
        ZStack(alignment: .topLeading) {
            ForEach(Array(photos.enumerated()), id: \.offset) { idx, photo in
                tile(photo: photo, index: idx)
                    .offset(x: CGFloat(idx) * Self.stepX, y: 0)
                    .zIndex(Double(idx))
            }
        }
        .frame(height: Self.tileSize + 16, alignment: .topLeading)
        .padding(.leading, 24)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func tile(photo: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: photo)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Self.tileSize, height: Self.tileSize)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(palette.card, lineWidth: 4)
                )
                .shadow(color: palette.ink.opacity(0.18), radius: 6, x: 0, y: 3)

            // X sits in the tile's top-right CORNER. Lives inside the
            // same rotated group as the image so it tilts together —
            // reads as one unit.
            Button {
                onRemove(index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
            .accessibilityLabel("Remove photo")
        }
        .rotationEffect(.degrees(Self.rotation), anchor: .center)
    }
}

// MARK: - SearchBarInputController
//
// SwiftUI's `.searchable` creates a UISearchBar internally but doesn't
// expose it. This representable reaches into UIKit for two jobs:
//   1. Swap the search bar's leading magnifying glass for a tappable
//      camera button.
//   2. Toggle the search text field's `inputView` between the default
//      keyboard and our custom PerchPhotoKeyboardView when the camera
//      button is tapped.
//
// Uses a Coordinator that persists across SwiftUI view updates — no
// work is done on every `updateUIView` tick (that was the source of
// the earlier perf regression). Install is one-shot, capped at 30
// retries on a 100ms tick (≈3s) in case the NavigationStack's search
// controller isn't attached yet.

private struct SearchBarInputController: UIViewRepresentable {
    let systemImage: String
    let tint: UIColor
    let attachedPhoto: UIImage?
    let onPhotoSelected: (UIImage) -> Void
    let onPhotoRemoved: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            systemImage: systemImage,
            tint: tint,
            attachedPhoto: attachedPhoto,
            onPhotoSelected: onPhotoSelected,
            onPhotoRemoved: onPhotoRemoved
        )
    }

    func makeUIView(context: Context) -> UIView {
        let probe = UIView()
        probe.isUserInteractionEnabled = false
        probe.backgroundColor = .clear
        context.coordinator.probe = probe
        context.coordinator.scheduleFirstInstall()
        return probe
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Only re-apply the lightweight config (image, tint, closures,
        // attached photo); the heavy install happens once from makeUIView.
        context.coordinator.updateConfig(
            systemImage: systemImage,
            tint: tint,
            attachedPhoto: attachedPhoto,
            onPhotoSelected: onPhotoSelected,
            onPhotoRemoved: onPhotoRemoved
        )
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private var systemImage: String
        private var tint: UIColor
        private var attachedPhoto: UIImage?
        private var onPhotoSelected: (UIImage) -> Void
        private var onPhotoRemoved: () -> Void

        weak var probe: UIView?
        private weak var searchBar: UISearchBar?
        private weak var installedButton: UIButton?
        private var photoKeyboardView: PerchPhotoKeyboardView?
        private var retryWorkItem: DispatchWorkItem?
        private static let maxRetries = 30

        /// Which input view the search text field is currently using.
        /// `false` = system keyboard, `true` = photo grid keyboard.
        private var showingPhotoKeyboard: Bool = false

        init(
            systemImage: String,
            tint: UIColor,
            attachedPhoto: UIImage?,
            onPhotoSelected: @escaping (UIImage) -> Void,
            onPhotoRemoved: @escaping () -> Void
        ) {
            self.systemImage = systemImage
            self.tint = tint
            self.attachedPhoto = attachedPhoto
            self.onPhotoSelected = onPhotoSelected
            self.onPhotoRemoved = onPhotoRemoved
            super.init()
        }

        func updateConfig(
            systemImage: String,
            tint: UIColor,
            attachedPhoto: UIImage?,
            onPhotoSelected: @escaping (UIImage) -> Void,
            onPhotoRemoved: @escaping () -> Void
        ) {
            self.systemImage = systemImage
            self.tint = tint
            self.onPhotoSelected = onPhotoSelected
            self.onPhotoRemoved = onPhotoRemoved

            if let button = installedButton {
                applyConfig(to: button)
            }
            photoKeyboardView?.onPhotoSelected = onPhotoSelected

            // Attached photo is now rendered by the SwiftUI banner
            // above the List, not by this controller. The controller
            // still holds the reference so the photo grid knows what
            // the "current selection" is, but doesn't touch leftView.
            self.attachedPhoto = attachedPhoto
        }

        func scheduleFirstInstall() {
            guard installedButton == nil else { return }
            retryWorkItem?.cancel()
            attemptInstall(retriesLeft: Self.maxRetries)
        }

        private func attemptInstall(retriesLeft: Int) {
            if let bar = findSearchBar() {
                install(on: bar)
                return
            }
            guard retriesLeft > 0 else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.attemptInstall(retriesLeft: retriesLeft - 1)
            }
            retryWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        }

        /// Walk up the UIResponder chain from the probe view to find
        /// the UISearchBar installed by SwiftUI's `.searchable`.
        private func findSearchBar() -> UISearchBar? {
            guard let probe else { return nil }
            var responder: UIResponder? = probe
            while let r = responder {
                if let vc = r as? UIViewController {
                    if let bar = vc.navigationItem.searchController?.searchBar {
                        return bar
                    }
                    if let nav = vc as? UINavigationController,
                       let top = nav.topViewController,
                       let bar = top.navigationItem.searchController?.searchBar {
                        return bar
                    }
                }
                responder = r.next
            }
            return nil
        }

        private func install(on bar: UISearchBar) {
            let button = UIButton(type: .system)
            button.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
            button.addAction(UIAction { [weak self] _ in
                self?.toggleInputView()
            }, for: .touchUpInside)
            applyConfig(to: button)

            bar.searchTextField.leftView = button
            bar.searchTextField.leftViewMode = .always

            // Tap gesture that ONLY flips back to keyboard when the
            // photo grid is showing. `delegate = self` +
            // shouldRecognizeSimultaneously = true lets the text
            // field's own tap handlers fire too — otherwise the first
            // tap wouldn't make the field first-responder and the
            // keyboard wouldn't appear.
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTextFieldTap))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            bar.searchTextField.addGestureRecognizer(tap)

            installedButton = button
            searchBar = bar
        }

        // MARK: UIGestureRecognizerDelegate

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Let every other recogniser on the text field — including
            // the tap that promotes it to first responder — fire
            // alongside ours. Otherwise iOS 26's search bar loses its
            // keyboard-on-first-tap behaviour.
            true
        }

        private func applyConfig(to button: UIButton) {
            let config = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            let image = UIImage(systemName: systemImage, withConfiguration: config)
            button.setImage(image, for: .normal)
            button.tintColor = tint
        }

        @objc private func handleTextFieldTap() {
            // If we're showing the photo grid and the user taps the
            // field, flip back to the keyboard.
            if showingPhotoKeyboard {
                showKeyboard()
            }
        }

        private func toggleInputView() {
            showingPhotoKeyboard ? showKeyboard() : showPhotoKeyboard()
        }

        private func showPhotoKeyboard() {
            guard let textField = searchBar?.searchTextField else { return }

            let gridView: PerchPhotoKeyboardView
            if let existing = photoKeyboardView {
                gridView = existing
            } else {
                gridView = PerchPhotoKeyboardView(onPhotoSelected: onPhotoSelected)
                photoKeyboardView = gridView
            }

            textField.inputView = gridView
            showingPhotoKeyboard = true
            if textField.isFirstResponder {
                textField.reloadInputViews()
            } else {
                textField.becomeFirstResponder()
            }
        }

        private func showKeyboard() {
            guard let textField = searchBar?.searchTextField else { return }
            textField.inputView = nil
            showingPhotoKeyboard = false
            if textField.isFirstResponder {
                textField.reloadInputViews()
            }
        }

    }
}

// MARK: - PerchPhotoKeyboardView
//
// UIView that replaces the on-screen keyboard when the compose
// camera icon is tapped. Shows a 4-column grid: first cell is a
// camera tile (tap to take a photo), the rest are thumbnails
// fetched from the user's photo library, most-recent first.
//
// Height is fixed at 280pt — comfortably below a standard keyboard.
// Selecting a photo fires `onPhotoSelected(UIImage)` on the caller,
// which attaches it to the current compose draft. The camera tile
// presents UIImagePickerController(.camera) on top of the key window.
//
// Future: live AVCaptureSession preview inside the camera tile,
// multi-select with a Send-N-items confirm row, permission empty
// states. Intentionally single-select for v1 — smallest surface
// that matches the user's spec.

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
        // most iPhones. Initial width is irrelevant because autoresizing
        // (.flexibleWidth) immediately stretches us to the host's bounds —
        // avoids the deprecated `UIScreen.main` accessor entirely.
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 280))
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
            // `UIScreen.main.scale` was deprecated in iOS 26.0. Pull the
            // display scale from the trait collection of the view we're
            // already mounted in — that's the correct per-window scale
            // and stays current across screen moves.
            let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2.0
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
