import SwiftUI

/// Sign-in, sign-up, and password recovery screen.
struct AuthView: View {
    @Environment(AuthViewModel.self) var authViewModel

    @State private var isSignUp = false

    var body: some View {
        @Bindable var vm = authViewModel

        // Pre-login root: no MainTabView wrapper injects the palette here, so
        // AuthView sources its own time-of-day palette the same way MainTabView
        // does, and publishes it to the environment for any descendants.
        let resolvedTOD = PerchTimeOfDay.current
        let palette = PerchPalette.forTimeOfDay(resolvedTOD)

        ZStack {
            palette.bg.ignoresSafeArea()

            VStack(spacing: PerchTheme.Spacing.large) {
                Spacer()

                VStack(spacing: PerchTheme.Spacing.medium) {
                    Image(systemName: "bird.fill")
                        .font(PerchTheme.Font.icon(PerchTheme.Icon.xxLarge))
                        .foregroundColor(palette.kinetic)

                    VStack(spacing: PerchTheme.Spacing.xSmall) {
                        Text(screenTitle)
                            .font(PerchTheme.Font.display)
                            .foregroundColor(palette.ink)
                            .multilineTextAlignment(.center)

                        Text(screenSubtitle)
                            .font(PerchTheme.Font.body)
                            .foregroundColor(palette.muted)
                            .multilineTextAlignment(.center)
                    }
                }

                Spacer()

                VStack(spacing: PerchTheme.Spacing.medium) {
                    if !authViewModel.isPasswordRecovery {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                            Text("Email")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(palette.muted)

                            TextField("you@example.com", text: $vm.email)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                .padding(PerchTheme.Spacing.small)
                                .background(palette.card)
                                .cornerRadius(PerchTheme.Card.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                                        .stroke(palette.line, lineWidth: 1)
                                )
                        }
                    }

                    if isSignUp && !authViewModel.isPasswordRecovery {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                            Text("Display Name")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(palette.muted)

                            TextField("Your name", text: $vm.displayName)
                                .padding(PerchTheme.Spacing.small)
                                .background(palette.card)
                                .cornerRadius(PerchTheme.Card.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                                        .stroke(palette.line, lineWidth: 1)
                                )
                        }
                    }

                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                        Text(passwordLabel)
                            .font(PerchTheme.Font.caption)
                            .foregroundColor(palette.muted)

                        SecureField(passwordPlaceholder, text: $vm.password)
                            .textContentType(authViewModel.isPasswordRecovery ? .newPassword : .password)
                            .padding(PerchTheme.Spacing.small)
                            .background(palette.card)
                            .cornerRadius(PerchTheme.Card.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                                    .stroke(palette.line, lineWidth: 1)
                            )
                    }

                    if authViewModel.isPasswordRecovery {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                            Text("Confirm New Password")
                                .font(PerchTheme.Font.caption)
                                .foregroundColor(palette.muted)

                            SecureField("Repeat your new password", text: $vm.confirmPassword)
                                .textContentType(.newPassword)
                                .padding(PerchTheme.Spacing.small)
                                .background(palette.card)
                                .cornerRadius(PerchTheme.Card.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                                        .stroke(palette.line, lineWidth: 1)
                                )
                        }
                    }

                    if let statusMessage = authViewModel.statusMessage {
                        HStack(spacing: PerchTheme.Spacing.small) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                            Text(statusMessage)
                                .font(PerchTheme.Font.caption)
                            Spacer()
                        }
                        .foregroundColor(.green)
                        .padding(PerchTheme.Spacing.small)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(PerchTheme.Card.cornerRadius)
                    }

                    if let error = authViewModel.error {
                        HStack(spacing: PerchTheme.Spacing.small) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(PerchTheme.Font.icon(PerchTheme.Icon.small))
                            Text(error.errorDescription ?? "Unknown error")
                                .font(PerchTheme.Font.caption)
                            Spacer()
                        }
                        .foregroundColor(palette.error)
                        .padding(PerchTheme.Spacing.small)
                        .background(palette.error.opacity(0.1))
                        .cornerRadius(PerchTheme.Card.cornerRadius)
                    }
                }

                Button(action: handlePrimaryAction) {
                    ZStack {
                        RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                            .fill(palette.kinetic)

                        HStack(spacing: PerchTheme.Spacing.small) {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(primaryButtonTitle)
                                .font(PerchTheme.Font.heading)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(height: 50)
                .disabled(isPrimaryDisabled)
                .opacity(isPrimaryDisabled ? 0.6 : 1)

                if authViewModel.isPasswordRecovery {
                    Button(action: handleCancelRecovery) {
                        Text("Cancel Recovery")
                            .font(PerchTheme.Font.body)
                            .fontWeight(.semibold)
                            .foregroundColor(palette.kinetic)
                    }
                } else {
                    if !isSignUp {
                        Button(action: handleSendPasswordReset) {
                            Text("Forgot password?")
                                .font(PerchTheme.Font.body)
                                .fontWeight(.semibold)
                                .foregroundColor(palette.kinetic)
                        }
                        .disabled(authViewModel.isLoading || authViewModel.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(authViewModel.isLoading || authViewModel.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.6 : 1)
                    }

                    HStack(spacing: PerchTheme.Spacing.xSmall) {
                        Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                            .font(PerchTheme.Font.body)
                            .foregroundColor(palette.muted)

                        Button(action: {
                            isSignUp.toggle()
                            authViewModel.clearError()
                            authViewModel.clearStatusMessage()
                        }) {
                            Text(isSignUp ? "Sign In" : "Create Account")
                                .font(PerchTheme.Font.body)
                                .fontWeight(.semibold)
                                .foregroundColor(palette.kinetic)
                        }
                    }
                }

                Spacer()
            }
            .padding(PerchTheme.Spacing.large)
        }
        .tint(palette.kinetic)
        .environment(\.perchPalette, palette)
        .environment(\.perchTimeOfDay, resolvedTOD)
        .preferredColorScheme(resolvedTOD.colorScheme)
    }

    private var screenTitle: String {
        if authViewModel.isPasswordRecovery {
            return "Set a New Password"
        }
        return isSignUp ? "Create Your Account" : "Welcome Back"
    }

    private var screenSubtitle: String {
        if authViewModel.isPasswordRecovery {
            let trimmedEmail = authViewModel.email.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedEmail.isEmpty
                ? "Choose a new password to finish signing back in."
                : "Choose a new password for \(trimmedEmail)."
        }
        return "Your personal AI dashboard"
    }

    private var passwordLabel: String {
        authViewModel.isPasswordRecovery ? "New Password" : "Password"
    }

    private var passwordPlaceholder: String {
        authViewModel.isPasswordRecovery ? "Choose a new password" : "••••••••"
    }

    private var primaryButtonTitle: String {
        if authViewModel.isPasswordRecovery {
            return "Set New Password"
        }
        return isSignUp ? "Create Account" : "Sign In"
    }

    private var isPrimaryDisabled: Bool {
        if authViewModel.isLoading {
            return true
        }

        if authViewModel.isPasswordRecovery {
            return authViewModel.password.isEmpty || authViewModel.confirmPassword.isEmpty
        }

        if isSignUp {
            return authViewModel.email.isEmpty || authViewModel.password.isEmpty || authViewModel.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return authViewModel.email.isEmpty || authViewModel.password.isEmpty
    }

    private func handlePrimaryAction() {
        if authViewModel.isPasswordRecovery {
            Task {
                await authViewModel.completePasswordRecovery()
            }
            return
        }

        if isSignUp {
            Task {
                await authViewModel.signUp()
            }
        } else {
            Task {
                await authViewModel.signIn()
            }
        }
    }

    private func handleSendPasswordReset() {
        authViewModel.clearError()
        authViewModel.clearStatusMessage()
        Task {
            await authViewModel.sendPasswordReset()
        }
    }

    private func handleCancelRecovery() {
        Task {
            await authViewModel.cancelPasswordRecovery()
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthViewModel())
}
