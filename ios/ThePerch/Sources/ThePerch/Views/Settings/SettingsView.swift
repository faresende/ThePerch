import SwiftUI

/// Settings screen accessible from the home view.
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AuthViewModel.self) var authViewModel
    @Environment(DashboardViewModel.self) var dashboardViewModel

    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @State private var isSigningOut = false
    @State private var showChangeBackend = false
    @State private var editableSections: [Section] = []
    @State private var isSavingSections = false

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PerchTheme.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                        // User profile section
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Profile")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            CardContainer {
                                VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                                    ProfileField(
                                        label: "Display Name",
                                        value: authViewModel.displayName.isEmpty ? "there" : authViewModel.displayName
                                    )

                                    Divider()
                                        .padding(.vertical, PerchTheme.Spacing.xSmall)

                                    ProfileField(
                                        label: "Email",
                                        value: authViewModel.email
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)

                        // Preferences section
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Preferences")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            CardContainer {
                                VStack(spacing: 0) {
                                    HStack {
                                        Text("Dark Mode")
                                            .font(PerchTheme.Font.body)
                                            .foregroundColor(PerchTheme.textPrimary)

                                        Spacer()

                                        Toggle("", isOn: $darkModeEnabled)
                                    }
                                    .padding(PerchTheme.Spacing.small)
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)

                        // Section management — toggle visibility and reorder
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            HStack {
                                Text("Tabs")
                                    .font(PerchTheme.Font.heading)
                                    .foregroundColor(PerchTheme.textPrimary)
                                Spacer()
                                if isSavingSections {
                                    ProgressView().scaleEffect(0.8)
                                }
                            }

                            Text("Toggle tabs on/off or drag to reorder.")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textTertiary)

                            List {
                                ForEach($editableSections) { $section in
                                    HStack(spacing: PerchTheme.Spacing.medium) {
                                        Image(systemName: "line.3.horizontal")
                                            .foregroundColor(PerchTheme.textTertiary)
                                            .font(.caption)
                                        Text(section.displayName)
                                            .font(PerchTheme.Font.body)
                                            .foregroundColor(PerchTheme.textPrimary)
                                        Spacer()
                                        Toggle("", isOn: Binding(
                                            get: { section.isVisible },
                                            set: { newValue in
                                                section.isVisible = newValue
                                                Task { await saveSections() }
                                            }
                                        ))
                                            .labelsHidden()
                                            .tint(PerchTheme.accent)
                                    }
                                    .listRowBackground(PerchTheme.cardBackground)
                                }
                                .onMove { from, to in
                                    editableSections.move(fromOffsets: from, toOffset: to)
                                    Task { await saveSections() }
                                }
                            }
                            .listStyle(.plain)
                            .frame(height: CGFloat(editableSections.count) * 52)
                            .cornerRadius(PerchTheme.Card.cornerRadius)
                            .environment(\.editMode, .constant(.active))
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)

                        // Backend section
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Backend")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            CardContainer {
                                VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Mode")
                                                .font(PerchTheme.Font.caption)
                                                .foregroundColor(PerchTheme.textSecondary)
                                            Text(KeychainService.shared.load()?.backendMode == .managedCloud ? "ThePerch Cloud" : "Self-hosted (Supabase)")
                                                .font(PerchTheme.Font.body)
                                                .foregroundColor(PerchTheme.textPrimary)
                                        }
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(PerchTheme.success)
                                    }

                                    Divider().padding(.vertical, PerchTheme.Spacing.xSmall)

                                    Button {
                                        showChangeBackend = true
                                    } label: {
                                        HStack {
                                            Text("Change backend")
                                                .font(PerchTheme.Font.body)
                                                .foregroundColor(PerchTheme.error)
                                            Spacer()
                                            Image(systemName: "chevron.right")
                                                .font(.caption)
                                                .foregroundColor(PerchTheme.textTertiary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)
                        .sheet(isPresented: $showChangeBackend) {
                            OnboardingView {
                                showChangeBackend = false
                            }
                        }

                        // About section
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("About")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            CardContainer {
                                VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                                    HStack {
                                        Text("App Version")
                                            .font(PerchTheme.Font.body)
                                            .foregroundColor(PerchTheme.textSecondary)

                                        Spacer()

                                        Text(appVersion)
                                            .font(PerchTheme.Font.body)
                                            .foregroundColor(PerchTheme.textPrimary)
                                    }

                                    Divider()
                                        .padding(.vertical, PerchTheme.Spacing.xSmall)

                                    HStack {
                                        Text("Build")
                                            .font(PerchTheme.Font.body)
                                            .foregroundColor(PerchTheme.textSecondary)

                                        Spacer()

                                        Text("1")
                                            .font(PerchTheme.Font.body)
                                            .foregroundColor(PerchTheme.textPrimary)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)

                        // Sign out button
                        Button(action: { handleSignOut() }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                                    .fill(PerchTheme.error.opacity(0.1))

                                HStack(spacing: PerchTheme.Spacing.small) {
                                    if isSigningOut {
                                        ProgressView()
                                            .tint(PerchTheme.error)
                                    }

                                    Text("Sign Out")
                                        .font(PerchTheme.Font.heading)
                                        .foregroundColor(PerchTheme.error)
                                }
                            }
                        }
                        .frame(height: 50)
                        .disabled(isSigningOut)
                        .opacity(isSigningOut ? 0.6 : 1)
                        .padding(.horizontal, PerchTheme.Spacing.large)

                        Spacer()
                            .frame(height: PerchTheme.Spacing.large)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                editableSections = dashboardViewModel.sections
                    .filter { $0.slug != "legal" }
                    .sorted { $0.sortOrder < $1.sortOrder }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: PerchTheme.Spacing.xSmall) {
                            Image(systemName: "chevron.left")
                                .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                            Text("Back")
                        }
                        .foregroundColor(PerchTheme.accent)
                    }
                }
            }
        }
    }

    private func handleSignOut() {
        isSigningOut = true
        Task {
            await authViewModel.signOut()
            isSigningOut = false
        }
    }

    private func saveSections() async {
        isSavingSections = true
        // Update sort_order based on current array position
        var updated = editableSections
        for i in updated.indices {
            updated[i].sortOrder = i
        }
        await dashboardViewModel.reorderSections(updated)
        isSavingSections = false
    }
}

// MARK: - Profile Field

struct ProfileField: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textSecondary)

            Spacer()

            Text(value)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AuthViewModel())
        .environment(DashboardViewModel())
}
