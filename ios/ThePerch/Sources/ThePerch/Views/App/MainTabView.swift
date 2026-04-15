import SwiftUI

struct MainTabView: View {
    @Environment(DashboardViewModel.self) var dashboardViewModel
    @State private var selectedTab: RootTab = Self.initialTab()
    @State private var isShowingSettings = false
    @State private var isShowingCapture = false
    @State private var previousContentTab: RootTab = Self.initialTab()
    @State private var didHandleDebugLaunchRouting = false

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
        .tint(PerchTheme.accent)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sheet(isPresented: $isShowingSettings) {
            SettingsTab()
        }
        .sheet(isPresented: $isShowingCapture) {
            CaptureSheet()
        }
        .task {
            await dashboardViewModel.loadDashboard()
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            if newTab == .capture {
                selectedTab = previousContentTab
                isShowingCapture = true
            } else {
                previousContentTab = newTab
            }
        }
        .task {
            guard !didHandleDebugLaunchRouting else { return }
            didHandleDebugLaunchRouting = true
            if Self.debugLaunchesSettings {
                isShowingSettings = true
            }
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
