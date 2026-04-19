import SwiftUI

struct MainTabView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel

    @State private var selectedTab: RootTab = Self.initialTab()
    @State private var isShowingSettings = false
    @State private var isComposeExpanded = false
    @State private var didHandleDebugLaunchRouting = false

    /// The three content tabs the compose dock switches between.
    /// `.capture` is retained only as a debug-routing target — it no longer
    /// appears in the nav; compose lives inline in the dock.
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

        /// SF Symbol used by the compose dock for each tab.
        /// Uses outline weights — the dock is liquid glass, filled icons
        /// look heavy against the frosted surface.
        var dockSymbol: String {
            switch self {
            case .today:   "house"
            case .health:  "heart"
            case .hub:     "square.grid.2x2"
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
            if let tab = RootTab(rawValue: candidate), tab != .capture {
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

        ZStack(alignment: .bottom) {
            // The three tabs live in a ZStack so NavigationStack state is
            // preserved across switches — the inactive tabs render but are
            // transparent + hit-test-disabled. This is cheaper than a real
            // TabView and lets us replace the system tab bar entirely with
            // the custom liquid-glass dock below.
            ZStack {
                TodayTab(onOpenProfile: presentSettings)
                    .opacity(selectedTab == .today ? 1 : 0)
                    .allowsHitTesting(selectedTab == .today)
                HealthTab(onOpenProfile: presentSettings)
                    .opacity(selectedTab == .health ? 1 : 0)
                    .allowsHitTesting(selectedTab == .health)
                HubTab(onOpenProfile: presentSettings)
                    .opacity(selectedTab == .hub ? 1 : 0)
                    .allowsHitTesting(selectedTab == .hub)
            }
            // 2px blur behind the compose dock when it's expanded — per spec,
            // enough to let the glass feel lifted without scrimming the page.
            .blur(radius: isComposeExpanded ? 2 : 0)
            .animation(.easeInOut(duration: 0.3), value: isComposeExpanded)
            // Reserve space at the bottom so scrollable content doesn't
            // hide behind the dock. 60pt dock + 24pt bottom margin = 84pt.
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 84)
            }

            PerchComposeDock(
                activeTab: $selectedTab,
                isExpanded: $isComposeExpanded
            )
            .padding(.bottom, 12)
        }
        .background(palette.bg.ignoresSafeArea())
        .tint(palette.kinetic)
        .environment(\.perchPalette, palette)
        .environment(\.perchTimeOfDay, timeOfDay)
        .sheet(isPresented: $isShowingSettings) {
            SettingsTab()
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

// MARK: - PerchComposeDock
//
// The floating bottom dock that replaces SwiftUI's TabView tab bar.
//
// Morphs between two shapes:
//   - IDLE: full-width liquid-glass nav pill (Today · Health · Hub) + "+" FAB
//   - EXPANDED: section-icon FAB on the left (collapsed nav) + compose input
//
// This mirrors the Apple Music / Maps / Books search-dock morph in iOS 26:
// tap "+" → nav crunches left into an icon button; the compose dock expands
// across the rest of the bottom band. Tapping the icon button returns to idle.
//
// State machine (the `Phase` enum):
//   idle      → FAB shows +
//   composing → text field focused; camera + send available
//   camera    → full-screen camera placeholder (production = OS camera)
//   sending   → shimmer + "Reading…" while the mock AI "thinks"
//   ai        → AI-interpreted response card floats above the dock
//
// AI routing is stubbed for v1. `acceptAI(_:)` currently just shows a toast
// and resets; wiring to real ingestion (Nutrition / Travel / Orders / etc.)
// is a follow-up. The canned responses intentionally match the prototype.
//
// All surfaces use `.glassEffect(.regular, in:)` — the iOS 26 Liquid Glass
// system material. The CSS `.lg` class in the handoff was just a stand-in.

struct PerchComposeDock: View {
    @Environment(\.perchPalette) private var palette

    @Binding var activeTab: MainTabView.RootTab
    @Binding var isExpanded: Bool

    @State private var phase: Phase = .idle
    @State private var draftText: String = ""
    @State private var hasPhoto: Bool = false
    @State private var toastMessage: String?
    @FocusState private var isInputFocused: Bool

    enum Phase: Equatable {
        case idle
        case composing
        case camera
        case sending
        case ai
    }

    /// Shape of a single AI-routed capture. Stubbed for v1.
    struct AIDraft: Equatable {
        let title: String
        let body: String
        let destination: String
    }

    /// The canned AI response. In v1 the routing is a stub — photo goes to
    /// Nutrition, text goes to Travel. Real multi-modal routing will replace
    /// this with an actual LLM call.
    private var mockAI: AIDraft {
        if hasPhoto {
            return AIDraft(
                title: "One pastel de nata",
                body: "~250 cal · 5g P · 25g C · 14g F",
                destination: "Nutrition"
            )
        } else {
            return AIDraft(
                title: "Flight to Porto · BA 1234",
                body: "Fri, 10 Apr · 07:45 LGW → 10:30 OPO",
                destination: "Travel"
            )
        }
    }

    /// Spring tuning matches the handoff's `cubic-bezier(.2,.8,.2,1) 450ms`.
    /// response ≈ 0.45, damping 0.85 reads as "snappy-but-soft, not bouncy".
    private var dockSpring: Animation {
        .spring(response: 0.45, dampingFraction: 0.85)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Camera placeholder takes over everything when active.
            if phase == .camera {
                PerchCameraOverlay(
                    onCapture: {
                        hasPhoto = true
                        withAnimation(dockSpring) { phase = .composing }
                    },
                    onClose: {
                        withAnimation(dockSpring) { phase = .composing }
                    }
                )
                .transition(.opacity)
                .zIndex(50)
            }

            // Bottom stack: AI card (if present) above the dock row.
            VStack(spacing: 12) {
                if phase == .ai {
                    aiResponseCard
                        .padding(.horizontal, 12)
                        .transition(.asymmetric(
                            insertion: .offset(y: 18).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                dockRow
                    .padding(.horizontal, 10)
            }

            // Toast floats from the top.
            if let toastMessage {
                VStack {
                    PerchAcceptToast(message: toastMessage, palette: palette)
                        .padding(.top, 72)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(60)
            }
        }
        .animation(dockSpring, value: phase)
        .animation(.easeInOut(duration: 0.35), value: toastMessage)
        .onChange(of: phase) { _, new in
            isExpanded = (new != .idle && new != .camera)
            if new == .sending {
                Task { await runMockSending() }
            }
            if new == .composing {
                // Slight delay lets the expand animation finish before the
                // keyboard overlaps the dock — otherwise the dock jumps.
                Task {
                    try? await Task.sleep(for: .milliseconds(280))
                    isInputFocused = true
                }
            } else if new == .idle {
                isInputFocused = false
            }
        }
    }

    // MARK: - Dock row (idle OR expanded)

    @ViewBuilder
    private var dockRow: some View {
        HStack(spacing: 8) {
            if isExpanded {
                sectionFAB
            } else {
                navPill
            }

            if isExpanded {
                inputCapsule
            } else {
                composeFAB
            }
        }
    }

    // MARK: - Idle: full nav pill (Today · Health · Hub)

    @ViewBuilder
    private var navPill: some View {
        HStack(spacing: 0) {
            navTab(.today,  label: "Today",  symbol: "house")
            navTab(.health, label: "Health", symbol: "heart")
            navTab(.hub,    label: "Hub",    symbol: "square.grid.2x2")
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder
    private func navTab(_ tab: MainTabView.RootTab, label: String, symbol: String) -> some View {
        let isActive = activeTab == tab
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                activeTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: isActive ? .medium : .regular))
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .foregroundStyle(isActive ? palette.ink : palette.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if isActive {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // MARK: - Idle: the "+" FAB that opens compose

    @ViewBuilder
    private var composeFAB: some View {
        Button {
            withAnimation(dockSpring) { phase = .composing }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(palette.ink)
                .frame(width: 60, height: 60)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .accessibilityLabel(Text("Compose"))
    }

    // MARK: - Expanded: section-icon FAB (dismisses compose)

    @ViewBuilder
    private var sectionFAB: some View {
        Button {
            closeCompose()
        } label: {
            Image(systemName: activeTab.dockSymbol)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(palette.ink)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: Circle())
        .transition(.scale(scale: 0.7).combined(with: .opacity))
        .accessibilityLabel(Text("Close compose"))
    }

    // MARK: - Expanded: input capsule (camera · thumbnail · field · send)

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
        .glassEffect(.regular, in: Capsule())
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    @ViewBuilder
    private var cameraButton: some View {
        Button {
            withAnimation(dockSpring) { phase = .camera }
        } label: {
            Image(systemName: "camera")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(phase == .composing ? palette.ink : palette.faint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .disabled(phase != .composing)
        .accessibilityLabel(Text("Take photo"))
    }

    @ViewBuilder
    private var photoThumbnail: some View {
        // Placeholder gradient — a warm radial that suggests a pastry,
        // matching the design. Replace with the actual captured image
        // when camera integration is wired.
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

            // Darker lower-right to give depth.
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
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var inputField: some View {
        switch phase {
        case .sending:
            HStack(spacing: 10) {
                PerchShimmerBar()
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
        default:
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

    private var canSend: Bool {
        phase == .composing &&
        (hasPhoto || !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @ViewBuilder
    private var sendButton: some View {
        Button(action: attemptSend) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(canSend ? Color(red: 1.0, green: 0.973, blue: 0.925) : palette.faint)
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(canSend ? palette.kinetic : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .animation(.easeInOut(duration: 0.2), value: canSend)
        .accessibilityLabel(Text("Send"))
    }

    // MARK: - AI response card

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
                            .fill(palette.wellness.opacity(0.25))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("UNDERSTOOD · GOES TO \(ai.destination.uppercased())")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(palette.muted)

                    Text(ai.title)
                        .font(.system(size: 20, weight: .regular, design: .serif).italic())
                        .foregroundStyle(palette.ink)
                        .tracking(-0.3)
                        .lineLimit(2)

                    Text(ai.body)
                        .font(.system(size: 13.5, weight: .regular, design: .serif))
                        .foregroundStyle(palette.muted)
                        .tracking(0.1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    withAnimation(dockSpring) { phase = .composing }
                } label: {
                    Text("Edit")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.12))
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
                        .shadow(color: palette.kinetic.opacity(0.4), radius: 9, x: 0, y: 6)
                }
                .buttonStyle(.plain)
                .layoutPriority(1.4) // Per spec: Accept is ~1.4x wider than Edit
            }
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - Transitions

    private func attemptSend() {
        guard canSend else { return }
        withAnimation(dockSpring) { phase = .sending }
    }

    private func runMockSending() async {
        try? await Task.sleep(for: .milliseconds(1800))
        guard phase == .sending else { return }
        withAnimation(dockSpring) { phase = .ai }
    }

    private func acceptAI(_ ai: AIDraft) {
        let message = "Added to \(ai.destination)"
        withAnimation(dockSpring) {
            phase = .idle
            draftText = ""
            hasPhoto = false
        }
        withAnimation(.easeOut(duration: 0.3)) {
            toastMessage = message
        }
        // Auto-dismiss the toast after the spec'd 2.2s dwell.
        Task {
            try? await Task.sleep(for: .milliseconds(2200))
            withAnimation(.easeOut(duration: 0.3)) {
                toastMessage = nil
            }
        }
    }

    private func closeCompose() {
        withAnimation(dockSpring) {
            phase = .idle
            draftText = ""
            hasPhoto = false
        }
    }
}

// MARK: - Toast

/// Liquid-glass pill that slides from the top to confirm "Added to {section}".
/// Auto-dismiss is owned by the dock — this view just renders the pill.
struct PerchAcceptToast: View {
    let message: String
    let palette: PerchPalette

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
        .glassEffect(.regular, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
    }
}

// MARK: - Shimmer bar (used while AI "thinks")

/// Moving white-gradient bar that signals active ingestion during the
/// `sending` phase. Matches the CSS `.shimmer` keyframes in the handoff.
struct PerchShimmerBar: View {
    @State private var phase: CGFloat = -1.0

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.white.opacity(0.06))
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.04),
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width)
                    .blendMode(.plusLighter)
                )
                .clipShape(Capsule())
        }
        .frame(height: 10)
        .onAppear {
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Camera placeholder

/// A full-screen mock camera overlay. In production this is the OS camera
/// picker; for v1 it's a static viewfinder simulation to prove the flow.
/// Hits `onCapture` for the shutter button, `onClose` for the X button.
struct PerchCameraOverlay: View {
    let onCapture: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar — close left, flash right
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

                    Button(action: { /* flash toggle placeholder */ }) {
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

                // Viewfinder: warm radial + rule-of-thirds grid + focus reticle
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

                    // Warm highlight blob — suggests a subject
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

                    // Rule-of-thirds overlay
                    thirdsGrid

                    // Focus reticle
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

                // Bottom controls: thumbnail · shutter · flip
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

                    Button(action: { /* camera flip placeholder */ }) {
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

    /// 3×3 grid overlay — thin white lines at 1/3 and 2/3 positions.
    private var thirdsGrid: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                // Vertical
                p.move(to: CGPoint(x: w / 3, y: 0));       p.addLine(to: CGPoint(x: w / 3, y: h))
                p.move(to: CGPoint(x: 2 * w / 3, y: 0));   p.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                // Horizontal
                p.move(to: CGPoint(x: 0, y: h / 3));       p.addLine(to: CGPoint(x: w, y: h / 3))
                p.move(to: CGPoint(x: 0, y: 2 * h / 3));   p.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
    }
}
