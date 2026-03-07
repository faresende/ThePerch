import SwiftUI

/// Settings screen accessible from the home view.
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AuthViewModel.self) var authViewModel
    @Environment(DashboardViewModel.self) var dashboardViewModel

    @State private var isSigningOut = false

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PerchTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.large) {
                        // User profile section
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Profile")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            CardContainer {
                                VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                                    ProfileField(
                                        label: "Display Name",
                                        value: "Fabio"
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
                                    SettingsToggleRow(
                                        label: "Notifications",
                                        isOn: true,
                                        onChange: { _ in }
                                    )

                                    Divider()
                                        .padding(.vertical, PerchTheme.Spacing.xSmall)

                                    SettingsToggleRow(
                                        label: "Dark Mode",
                                        isOn: false,
                                        onChange: { _ in }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)

                        // Section management
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Sections")
                                .font(PerchTheme.Font.heading)
                                .foregroundColor(PerchTheme.textPrimary)

                            VStack(spacing: PerchTheme.Spacing.xSmall) {
                                ForEach(dashboardViewModel.sections) { section in
                                    HStack {
                                        Text(section.displayName)
                                            .font(PerchTheme.Font.body)
                                            .foregroundColor(PerchTheme.textPrimary)

                                        Spacer()

                                        Image(systemName: "eye\(section.isVisible ? "" : ".slash")")
                                            .font(PerchTheme.Font.icon(PerchTheme.Icon.medium))
                                            .foregroundColor(
                                                section.isVisible
                                                    ? PerchTheme.accent
                                                    : PerchTheme.textTertiary
                                            )
                                    }
                                    .padding(PerchTheme.Spacing.small)
                                    .background(PerchTheme.cardBackground)
                                    .cornerRadius(PerchTheme.Card.cornerRadius)
                                }
                            }
                        }
                        .padding(.horizontal, PerchTheme.Spacing.large)

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

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let label: String
    @State var isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack {
            Text(label)
                .font(PerchTheme.Font.body)
                .foregroundColor(PerchTheme.textPrimary)

            Spacer()

            Toggle("", isOn: $isOn)
                .onChange(of: isOn) { _, newValue in
                    onChange(newValue)
                }
        }
        .padding(PerchTheme.Spacing.small)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AuthViewModel())
        .environment(DashboardViewModel())
}
