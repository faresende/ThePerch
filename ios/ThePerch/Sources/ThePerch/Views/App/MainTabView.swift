import SwiftUI

struct MainTabView: View {
    @Environment(\.perchPalette) private var palette
    @Environment(DashboardViewModel.self) var dashboardViewModel

    @State private var selectedTab: RootTab = Self.initialTab()
    @State private var isShowingSettings = false
    @State private var previousContentTab: RootTab = Self.initialTab()
    @State private var didHandleDebugLaunchRouting = false

    // Compose flow state — all in one place so the custom bottom bar
    // morph + AI card + toast can react to a single state machine.
    @State private var composePhase: ComposePhase = .idle
    @State private var composeDraftText: String = ""
    @State private var composeHasPhoto: Bool = false
    @State private var composePhoto: UIImage?
    @State private var isPresentingCamera: Bool = false
    @State private var composeToastMessage: String?
    @FocusState private var isComposeInputFocused: Bool

    enum ComposePhase: Equatable {
        case idle       // native tab bar visible, no compose UI
        case composing  // morphed bar: section FAB + input pill (keyboard up)
        case sending    // shimmer bar + "Reading…"
        case ai         // AI response card floats above the input pill
    }

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

        /// Outline SF Symbol used by the section-icon FAB during compose.
        /// Filled weights are too heavy against liquid glass.
        var dockSymbol: String {
            switch self {
            case .today:   "house"
            case .health:  "heart"
            case .hub:     "square.grid.2x2"
            case .capture: "square.grid.2x2"
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
        let isComposing = composePhase != .idle

        ZStack(alignment: .bottom) {
            // ── Main content stack ──────────────────────────────────
            // Native TabView — untouched in idle. When compose is
            // active we hide its tab bar and blur the content so the
            // custom morphed bar below can own the bottom slot.
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
            .toolbar(isComposing ? .hidden : .visible, for: .tabBar)
            // 2pt blur per spec — gentle enough to let the glass do the
            // actual lifting. A heavier blur flattens the content,
            // leaving the glass with nothing to pull from and making the
            // custom bar read as plastic instead of material.
            .blur(radius: isComposing ? 2 : 0)
            .disabled(isComposing)
            .animation(.easeInOut(duration: 0.28), value: isComposing)

            // ── Morphed compose bar overlay ─────────────────────────
            // Lives only while composePhase != .idle. Section-icon
            // glass FAB on the left replaces the nav; input pill on
            // the right expands to take the remaining bottom width.
            // AI response card floats above both when present.
            if isComposing {
                composeOverlay(palette: palette)
                    .transition(.opacity)
            }
        }
        .background(palette.bg.ignoresSafeArea())
        .environment(\.perchPalette, palette)
        .environment(\.perchTimeOfDay, timeOfDay)
        .sheet(isPresented: $isShowingSettings) {
            SettingsTab()
        }
        .fullScreenCover(isPresented: $isPresentingCamera) {
            PerchComposeCameraPicker(
                onCapture: { image in
                    if let image {
                        composePhoto = image
                        composeHasPhoto = true
                    }
                    isPresentingCamera = false
                },
                onCancel: {
                    isPresentingCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if let msg = composeToastMessage {
                PerchComposeToast(message: msg)
                    .padding(.top, 64)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .capture {
                // Bounce the tab selection back to the previous content
                // tab and open the compose overlay in its place. The
                // section-FAB symbol follows `previousContentTab`.
                selectedTab = previousContentTab
                startComposing()
            } else {
                previousContentTab = newTab
            }
        }
        .onChange(of: composePhase) { _, new in
            if new == .sending {
                Task { await runMockSending() }
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

    // MARK: - Compose overlay

    @ViewBuilder
    private func composeOverlay(palette: PerchPalette) -> some View {
        VStack(spacing: 10) {
            if composePhase == .ai {
                composeAICard(palette: palette)
                    .padding(.horizontal, 12)
                    .transition(.asymmetric(
                        insertion: .offset(y: 18).combined(with: .opacity),
                        removal: .opacity
                    ))
            }

            // GlassEffectContainer groups the section FAB and the input
            // pill into a single coherent glass surface — same iOS 26
            // material the native tab bar uses. Without the container,
            // the two elements render as independent glass shapes and
            // the effect feels detached / placeholder-ish.
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    composeSectionFAB(palette: palette)
                    composeInputPill(palette: palette)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.bottom, 12)
    }

    /// The collapsed tab bar on the left — a glass square showing the
    /// currently-active section's icon. Tap to cancel and return to idle.
    @ViewBuilder
    private func composeSectionFAB(palette: PerchPalette) -> some View {
        Button {
            collapseCompose()
        } label: {
            Image(systemName: previousContentTab.dockSymbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(palette.ink)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .accessibilityLabel(Text("Close compose"))
    }

    /// Liquid-glass capsule holding camera · (optional photo thumb) ·
    /// text field · send. Expands to fill the remaining bottom width.
    @ViewBuilder
    private func composeInputPill(palette: PerchPalette) -> some View {
        HStack(spacing: 6) {
            composeCameraButton(palette: palette)

            if composeHasPhoto && composePhase != .sending {
                composePhotoThumbnail
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            composeInputField(palette: palette)
                .frame(maxWidth: .infinity)

            composeSendButton(palette: palette)
        }
        .padding(6)
        .frame(height: 52)
        .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder
    private func composeCameraButton(palette: PerchPalette) -> some View {
        Button {
            isPresentingCamera = true
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(composePhase == .composing ? palette.ink : palette.faint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(palette.ink.opacity(0.05)))
        }
        .buttonStyle(.plain)
        .disabled(composePhase != .composing)
        .accessibilityLabel(Text("Take photo"))
    }

    @ViewBuilder
    private var composePhotoThumbnail: some View {
        Group {
            if let photo = composePhoto {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fallback used when composeHasPhoto is forced true
                // without an actual UIImage (shouldn't happen in
                // production — defensive).
                Color.gray
            }
        }
        .frame(width: 32, height: 32)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func composeInputField(palette: PerchPalette) -> some View {
        switch composePhase {
        case .sending:
            HStack(spacing: 10) {
                ComposeShimmerBar()
                    .frame(maxWidth: .infinity)
                Text("Reading…")
                    .font(.system(size: 12.5, weight: .regular, design: .serif).italic())
                    .foregroundStyle(palette.muted)
            }
        case .ai:
            Text(composeHasPhoto ? "Photo · understood" : composeDraftText)
                .font(.system(size: 14.5))
                .foregroundStyle(palette.muted)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .composing, .idle:
            TextField(
                composeHasPhoto ? "Add a note…" : "Log a meal, a receipt, anything",
                text: $composeDraftText,
                axis: .horizontal
            )
            .font(.system(size: 14.5))
            .foregroundStyle(palette.ink)
            .tint(palette.kinetic)
            .submitLabel(.send)
            .focused($isComposeInputFocused)
            .onSubmit(attemptSend)
        }
    }

    private var canSend: Bool {
        composePhase == .composing &&
        (composeHasPhoto || !composeDraftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private func composeSendButton(palette: PerchPalette) -> some View {
        Button(action: attemptSend) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(canSend
                                 ? Color(red: 1.0, green: 0.973, blue: 0.925)
                                 : palette.faint)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(canSend ? palette.kinetic : palette.ink.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeInOut(duration: 0.2), value: canSend)
        .accessibilityLabel(Text("Send"))
    }

    // MARK: - AI response card

    @ViewBuilder
    private func composeAICard(palette: PerchPalette) -> some View {
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
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
                        composePhase = .composing
                    }
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        isComposeInputFocused = true
                    }
                } label: {
                    Text("Edit")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(palette.ink.opacity(0.08))
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
                        .shadow(color: palette.kinetic.opacity(0.35), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(.plain)
                .layoutPriority(1.4)
            }
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - Mock AI + state transitions

    /// Canned AI response for v1. Photo → Nutrition, text → Travel.
    /// Swap for a real LLM call without changing the view shape.
    private var mockAI: AIResult {
        if composeHasPhoto {
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

    struct AIResult: Equatable {
        let title: String
        let body: String
        let destination: String
    }

    private func startComposing() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            composePhase = .composing
        }
        // Slight delay gives the keyboard animation room to align with
        // the bar expansion — avoids the "bar jumps" look.
        Task {
            try? await Task.sleep(for: .milliseconds(320))
            isComposeInputFocused = true
        }
    }

    private func collapseCompose() {
        isComposeInputFocused = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            composePhase = .idle
            composeDraftText = ""
            composeHasPhoto = false
            composePhoto = nil
        }
    }

    private func attemptSend() {
        guard canSend else { return }
        isComposeInputFocused = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            composePhase = .sending
        }
    }

    private func runMockSending() async {
        try? await Task.sleep(for: .milliseconds(1600))
        guard composePhase == .sending else { return }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            composePhase = .ai
        }
    }

    private func acceptAI(_ ai: AIResult) {
        let destination = ai.destination
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            composePhase = .idle
            composeDraftText = ""
            composeHasPhoto = false
            composePhoto = nil
        }
        Task {
            try? await Task.sleep(for: .milliseconds(200))
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

// MARK: - Compose camera picker (native UIImagePickerController)

/// Wraps the system UIImagePickerController so the compose flow pulls
/// real photos from the camera on device, and falls back to the photo
/// library on the simulator (no camera hardware). The captured image
/// is returned to the caller via `onCapture(UIImage?)`.
struct PerchComposeCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        #if targetEnvironment(simulator)
        // The simulator has no camera; fall back to the photo library
        // so the compose flow is still testable.
        picker.sourceType = .photoLibrary
        #else
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera
            : .photoLibrary
        #endif
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PerchComposeCameraPicker

        init(_ parent: PerchComposeCameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
        ) {
            let image = info[.originalImage] as? UIImage
            parent.onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
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
