import SwiftUI

/// First-launch onboarding screen shown when no backend is configured.
/// Lets the user choose between self-hosted (Supabase) and managed cloud (coming soon).
struct OnboardingView: View {
    let onConfigured: () -> Void

    @State private var selectedMode: SetupMode = .selfHosted
    @State private var supabaseURL = ""
    @State private var supabaseAnonKey = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    enum SetupMode { case selfHosted, managedCloud }

    var body: some View {
        ZStack {
            PerchTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: PerchTheme.Spacing.xLarge) {
                    // Header
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.small) {
                        Text("Welcome to ThePerch")
                            .font(PerchTheme.Font.display)
                            .foregroundColor(PerchTheme.textPrimary)

                        Text("Your personal dashboard. Connect a backend to get started.")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(PerchTheme.textSecondary)
                    }

                    // Mode picker
                    VStack(spacing: PerchTheme.Spacing.small) {
                        modeButton(
                            mode: .selfHosted,
                            title: "Self-hosted",
                            subtitle: "Bring your own Supabase project",
                            icon: "server.rack"
                        )
                        modeButton(
                            mode: .managedCloud,
                            title: "ThePerch Cloud",
                            subtitle: "Sign in with your ThePerch account",
                            icon: "cloud.fill",
                            disabled: false
                        )
                    }

                    // Self-hosted form
                    // Self-hosted form
                    if selectedMode == .selfHosted {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("Supabase Project")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.8)

                            VStack(spacing: PerchTheme.Spacing.small) {
                                inputField(
                                    value: $supabaseURL,
                                    placeholder: "https://yourproject.supabase.co",
                                    label: "Project URL"
                                )
                                inputField(
                                    value: $supabaseAnonKey,
                                    placeholder: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
                                    label: "Anon Key",
                                    isSecure: true
                                )
                            }

                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(PerchTheme.error)
                                        .font(.caption)
                                    Text(error)
                                        .font(PerchTheme.Font.caption)
                                        .foregroundColor(PerchTheme.error)
                                }
                                .padding(.horizontal, PerchTheme.Spacing.small)
                            }

                            Button {
                                Task { await connect() }
                            } label: {
                                HStack {
                                    if isConnecting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: PerchTheme.accentForeground))
                                            .scaleEffect(0.8)
                                    }
                                    Text(isConnecting ? "Connecting..." : "Connect")
                                        .font(PerchTheme.Font.body.bold())
                                        .foregroundColor(PerchTheme.accentForeground)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, PerchTheme.Spacing.medium)
                                .background(PerchTheme.accent)
                                .cornerRadius(12)
                            }
                            .disabled(isConnecting || supabaseURL.isEmpty || supabaseAnonKey.isEmpty)

                            Text("Your credentials are stored securely in the system Keychain and never leave your device.")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textTertiary)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    // Managed cloud section
                    if selectedMode == .managedCloud {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.medium) {
                            Text("ThePerch Cloud")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.8)

                            Button {
                                Task { await connectManagedCloud() }
                            } label: {
                                HStack {
                                    if isConnecting {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: PerchTheme.accentForeground))
                                            .scaleEffect(0.8)
                                    }
                                    Text(isConnecting ? "Connecting..." : "Continue with ThePerch Cloud")
                                        .font(PerchTheme.Font.body.bold())
                                        .foregroundColor(PerchTheme.accentForeground)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, PerchTheme.Spacing.medium)
                                .background(PerchTheme.accent)
                                .cornerRadius(12)
                            }
                            .disabled(isConnecting)

                            if let error = errorMessage {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .foregroundColor(PerchTheme.error)
                                        .font(.caption)
                                    Text(error)
                                        .font(PerchTheme.Font.caption)
                                        .foregroundColor(PerchTheme.error)
                                }
                                .padding(.horizontal, PerchTheme.Spacing.small)
                            }

                            Text("Your data is hosted securely by ThePerch. You can switch to self-hosted at any time.")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(PerchTheme.textTertiary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .padding(PerchTheme.Spacing.large)
                .padding(.top, 60)
            }
        }
    }

    // MARK: - Subviews

    private func modeButton(mode: SetupMode, title: String, subtitle: String, icon: String, disabled: Bool = false) -> some View {
        Button {
            if !disabled { selectedMode = mode }
        } label: {
            HStack(spacing: PerchTheme.Spacing.medium) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(selectedMode == mode ? PerchTheme.accent : PerchTheme.textTertiary)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(PerchTheme.Font.body.bold())
                        .foregroundColor(disabled ? PerchTheme.textTertiary : PerchTheme.textPrimary)
                    Text(subtitle)
                        .font(PerchTheme.Font.caption)
                        .foregroundColor(PerchTheme.textTertiary)
                }

                Spacer()

                if selectedMode == mode && !disabled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(PerchTheme.accent)
                }
            }
            .padding(PerchTheme.Spacing.medium)
            .background(selectedMode == mode && !disabled ? PerchTheme.cardBackground : PerchTheme.cardInnerBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selectedMode == mode && !disabled ? PerchTheme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private func inputField(value: Binding<String>, placeholder: String, label: String, isSecure: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(PerchTheme.Font.caption)
                .foregroundColor(PerchTheme.textSecondary)

            Group {
                if isSecure {
                    SecureField(placeholder, text: value)
                } else {
                    TextField(placeholder, text: value)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                }
            }
            .font(PerchTheme.Font.body)
            .foregroundColor(PerchTheme.textPrimary)
            .padding(PerchTheme.Spacing.medium)
            .background(PerchTheme.cardBackground)
            .cornerRadius(10)
        }
    }

    // MARK: - Connection

    @MainActor
    private func connectManagedCloud() async {
        // ThePerch Cloud credentials — embedded in the app (anon key, safe)
        // When you provision the managed Supabase project, update these values
        let cloudURL = "https://ulmerwkvcczgjcxdhfuo.supabase.co"
        let cloudAnonKey = "sb_publishable_EAyfYGe3LQXCvmVDkgmiDw_H4u3lZbA"

        isConnecting = true
        errorMessage = nil

        do {
            try await SupabaseService.testConnection(url: cloudURL, anonKey: cloudAnonKey)
            let config = AppConfiguration(
                supabaseURL: cloudURL,
                supabaseAnonKey: cloudAnonKey,
                backendMode: .managedCloud
            )
            try KeychainService.shared.save(config)
            onConfigured()
        } catch {
            errorMessage = "Could not connect to ThePerch Cloud. Please try again."
        }

        isConnecting = false
    }

    @MainActor
    private func connect() async {
        let url = supabaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = supabaseAnonKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !url.isEmpty, !key.isEmpty else {
            errorMessage = "Please enter both the project URL and anon key."
            return
        }
        guard url.hasPrefix("https://") else {
            errorMessage = "Project URL must start with https://"
            return
        }

        isConnecting = true
        errorMessage = nil

        do {
            // Test connection by attempting to create a client and fetch sections
            try await SupabaseService.testConnection(url: url, anonKey: key)

            // Save to Keychain
            let config = AppConfiguration(
                supabaseURL: url,
                supabaseAnonKey: key,
                backendMode: .selfHosted
            )
            try KeychainService.shared.save(config)
            onConfigured()
        } catch {
            errorMessage = "Could not connect. Check your URL and key and try again."
        }

        isConnecting = false
    }
}
