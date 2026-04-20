import SwiftUI

struct MainTabView: View {
    @Environment(\.perchPalette) private var palette

    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var selectedTab: RootTab = Self.initialTab()
    @State private var isShowingSettings = false
    @State private var isShowingCapture = false
    @State private var previousContentTab: RootTab = Self.initialTab()
    @State private var didHandleDebugLaunchRouting = false
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
        // Resolve the active palette once at the tab root so every tab
        // (Today, Health, Hub) inherits it via @Environment and the whole
        // app re-tints atomically with the hour.
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

            Tab(RootTab.capture.title, systemImage: RootTab.capture.systemImage, value: RootTab.capture, role: .search) {
                Color.clear
                    .ignoresSafeArea()
            }
        }
        .tint(palette.kinetic)
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(\.perchPalette, palette)
        .environment(\.perchTimeOfDay, timeOfDay)
        .sheet(isPresented: $isShowingSettings) {
            SettingsTab()
        }
        .sheet(isPresented: $isShowingCapture) {
            PerchComposeSheet { destination in
                // Sheet dismisses first (via the binding reset), then the
                // toast slides in from the top — the slight delay stops
                // the two animations from stepping on each other.
                isShowingCapture = false
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
        }
        .overlay(alignment: .top) {
            if let msg = composeToastMessage {
                PerchComposeToast(message: msg)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab == .capture {
                selectedTab = previousContentTab
                isShowingCapture = true
            } else {
                previousContentTab = newTab
            }
        }
        .task(id: "main-tab-debug-routing") {
            // Initial dashboard load is owned by ThePerchApp (auth-gated).
            // Only handle debug-launch routing here so we don't double-fetch on launch.
            guard !didHandleDebugLaunchRouting else { return }
            didHandleDebugLaunchRouting = true
            if Self.debugLaunchesSettings {
                isShowingSettings = true
            }
        }
        .task(id: "main-tab-load-safety-net") {
            // Defensive fallback: if MainTabView appears and the dashboard is
            // still empty AND not currently loading, the auth-gated task in
            // ThePerchApp didn't fire for some reason (timing race, debug
            // bypass edge case, etc.). Trigger the load here.
            //
            // This is a no-op in the happy path because loadDashboard's
            // completion leaves allRecords populated, so the guard returns
            // immediately on re-entry. No duplicate fetch.
            guard dashboardViewModel.allRecords.isEmpty,
                  !dashboardViewModel.isLoading else { return }
            await dashboardViewModel.loadDashboard()
        }
    }

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

// MARK: - PerchComposeSheet
//
// The + tab opens this as a sheet. Bottom tab bar is untouched —
// iOS handles the dim + overlay the same way it did for CaptureSheet.
//
// The compose flow runs a small state machine inside the sheet:
//
//   composing  →  user types / attaches photo / taps send
//   camera     →  full-screen mock viewfinder (present in production)
//   sending    →  shimmer bar + "Reading…" while the LLM "thinks"
//   ai         →  AI response card appears above the input, with
//                 Edit (back to composing) + Accept (confirm + toast)
//
// Sheet detent grows when the AI card needs room; collapses back on
// Edit. Accept fires `onAccept(destination)` so the parent can flash
// a "Added to {destination}" toast after dismissal.
//
// AI routing is stubbed for v1. Photo → Nutrition ("One pastel de
// nata"), text → Travel ("Flight to Porto · BA 1234") — matches the
// handoff's canned examples. Wire the real LLM call when ready;
// the view shape stays the same.

struct PerchComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.perchPalette) private var palette

    /// Fires when the user taps Accept on the AI response. Parent is
    /// expected to dismiss the sheet (binding reset) + surface a toast.
    let onAccept: (String) -> Void

    @State private var phase: Phase = .composing
    @State private var draftText: String = ""
    @State private var hasPhoto: Bool = false
    @State private var detent: PresentationDetent = .height(Self.composeDetent)
    @State private var isPresentingCamera: Bool = false
    @FocusState private var isInputFocused: Bool

    private static let composeDetent: CGFloat = 180
    private static let aiDetent: CGFloat = 380

    enum Phase: Equatable { case composing, sending, ai }

    /// Stubbed AI response. Photo → Nutrition, text → Travel — matches
    /// the handoff's demo copy.
    struct AIResult: Equatable {
        let title: String
        let body: String
        let destination: String
    }

    private var mockAI: AIResult {
        if hasPhoto {
            return AIResult(
                title: "One pastel de nata",
                body: "~250 cal · 5g P · 25g C · 14g F",
                destination: "Nutrition"
            )
        } else {
            return AIResult(
                title: "Flight to Porto · BA 1234",
                body: "Fri, 10 Apr · 07:45 LGW → 10:30 OPO",
                destination: "Travel"
            )
        }
    }

    private var canSend: Bool {
        phase == .composing &&
        (hasPhoto || !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(spacing: 14) {
            if phase == .ai {
                aiResponseCard
                    .padding(.horizontal, 16)
                    .transition(.asymmetric(
                        insertion: .offset(y: 18).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            Spacer(minLength: 0)

            inputCapsule
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.bg)
        .presentationDetents([.height(Self.composeDetent), .height(Self.aiDetent)], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(palette.bg)
        .fullScreenCover(isPresented: $isPresentingCamera) {
            PerchComposeCameraOverlay(
                onCapture: {
                    hasPhoto = true
                    isPresentingCamera = false
                },
                onClose: {
                    isPresentingCamera = false
                }
            )
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.88), value: phase)
        .onChange(of: phase) { _, new in
            // Drive sheet height from phase.
            withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                detent = new == .ai ? .height(Self.aiDetent) : .height(Self.composeDetent)
            }
            if new == .sending {
                Task { await runMockSending() }
            }
        }
        .task {
            // Auto-focus the text field once the sheet is onscreen.
            try? await Task.sleep(for: .milliseconds(320))
            isInputFocused = true
        }
    }

    // MARK: Input capsule

    @ViewBuilder
    private var inputCapsule: some View {
        HStack(spacing: 6) {
            cameraButton

            if hasPhoto && phase != .sending {
                photoThumbnail
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            inputField
                .frame(maxWidth: .infinity)

            sendButton
        }
        .padding(6)
        .frame(height: 52)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
        )
        .overlay(
            Capsule()
                .strokeBorder(palette.ink.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var cameraButton: some View {
        Button {
            isPresentingCamera = true
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(phase == .composing ? palette.ink : palette.faint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(palette.ink.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .disabled(phase != .composing)
        .accessibilityLabel(Text("Take photo"))
    }

    @ViewBuilder
    private var photoThumbnail: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.91, green: 0.69, blue: 0.44),
                    Color(red: 0.54, green: 0.31, blue: 0.13),
                    Color(red: 0.23, green: 0.12, blue: 0.04)
                ],
                center: .init(x: 0.35, y: 0.35),
                startRadius: 0,
                endRadius: 28
            )
            RadialGradient(
                colors: [Color.black.opacity(0.7), .clear],
                center: .init(x: 0.65, y: 0.70),
                startRadius: 0,
                endRadius: 18
            )
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(palette.ink.opacity(0.1), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var inputField: some View {
        switch phase {
        case .sending:
            HStack(spacing: 10) {
                ComposeShimmerBar()
                    .frame(maxWidth: .infinity)
                Text("Reading…")
                    .font(.system(size: 12.5, weight: .regular, design: .serif).italic())
                    .foregroundStyle(palette.muted)
            }
        case .ai:
            Text(hasPhoto ? "Photo · understood" : draftText)
                .font(.system(size: 14.5))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .composing:
            TextField(
                hasPhoto ? "Add a note…" : "Log a meal, a receipt, anything…",
                text: $draftText,
                axis: .horizontal
            )
            .font(.system(size: 14.5))
            .foregroundStyle(palette.ink)
            .tint(palette.kinetic)
            .submitLabel(.send)
            .focused($isInputFocused)
            .onSubmit(attemptSend)
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        Button(action: attemptSend) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(canSend
                                 ? Color(red: 1.0, green: 0.973, blue: 0.925)
                                 : palette.faint)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(canSend ? palette.kinetic : palette.ink.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeInOut(duration: 0.2), value: canSend)
        .accessibilityLabel(Text("Send"))
    }

    // MARK: AI response card

    @ViewBuilder
    private var aiResponseCard: some View {
        let ai = mockAI
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(palette.wellness)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(palette.wellness.opacity(0.22))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("UNDERSTOOD · GOES TO \(ai.destination.uppercased())")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(palette.muted)

                    Text(ai.title)
                        .font(.system(size: 20, weight: .medium, design: .serif).italic())
                        .foregroundStyle(palette.ink)
                        .tracking(-0.3)
                        .lineLimit(2)

                    Text(ai.body)
                        .font(.system(size: 13.5, weight: .regular, design: .serif))
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.88)) {
                        phase = .composing
                    }
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        isInputFocused = true
                    }
                } label: {
                    Text("Edit")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(palette.ink.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    acceptAI(ai)
                } label: {
                    Text("Accept")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Color(red: 1.0, green: 0.973, blue: 0.925))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(palette.kinetic)
                        )
                        .shadow(color: palette.kinetic.opacity(0.32), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .layoutPriority(1.4)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(palette.ink.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: palette.ink.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    // MARK: State transitions

    private func attemptSend() {
        guard canSend else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            phase = .sending
        }
    }

    private func runMockSending() async {
        try? await Task.sleep(for: .milliseconds(1600))
        guard phase == .sending else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            phase = .ai
        }
    }

    private func acceptAI(_ ai: AIResult) {
        onAccept(ai.destination)
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

// MARK: - Compose camera overlay (full-screen mock)

/// Placeholder camera UI. In production this is the OS camera picker;
/// for v1 it's a static viewfinder simulation. `onCapture` fires when
/// the shutter is tapped (no actual photo bytes returned yet).
struct PerchComposeCameraOverlay: View {
    let onCapture: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Circle())

                    Spacer()

                    Button {} label: {
                        Image(systemName: "bolt")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 54)

                // Viewfinder
                ZStack {
                    RadialGradient(
                        colors: [
                            Color(red: 0.17, green: 0.11, blue: 0.07),
                            Color(red: 0.08, green: 0.04, blue: 0.02),
                            .black
                        ],
                        center: .init(x: 0.30, y: 0.30),
                        startRadius: 0,
                        endRadius: 420
                    )

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.88, green: 0.63, blue: 0.35).opacity(0.45),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 110
                            )
                        )
                        .frame(width: 220, height: 220)
                        .offset(y: 10)

                    thirdsGrid

                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(red: 0.97, green: 0.92, blue: 0.82), lineWidth: 1.5)
                        .frame(width: 72, height: 72)
                        .opacity(0.7)
                        .offset(y: 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 28)

                Spacer(minLength: 0)

                // Bottom controls
                HStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
                        )
                        .frame(width: 44, height: 44)

                    Spacer()

                    Button(action: onCapture) {
                        Circle()
                            .fill(Color(red: 0.97, green: 0.92, blue: 0.82))
                            .frame(width: 76, height: 76)
                            .overlay(
                                Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 4)
                            )
                            .shadow(color: Color.white.opacity(0.15), radius: 6)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Capture"))

                    Spacer()

                    Button {} label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 64)
            }
        }
    }

    private var thirdsGrid: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w / 3, y: 0));       p.addLine(to: CGPoint(x: w / 3, y: h))
                p.move(to: CGPoint(x: 2 * w / 3, y: 0));   p.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                p.move(to: CGPoint(x: 0, y: h / 3));       p.addLine(to: CGPoint(x: w, y: h / 3))
                p.move(to: CGPoint(x: 0, y: 2 * h / 3));   p.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
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
