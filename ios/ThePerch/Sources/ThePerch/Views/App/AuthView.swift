import SwiftUI

/// Sign-in / sign-up screen with clean, centered layout.
struct AuthView: View {
    @Environment(AuthViewModel.self) var authViewModel

    @State private var isSignUp = false

    var body: some View {
        @Bindable var vm = authViewModel

        ZStack {
            PerchTheme.background.ignoresSafeArea()

            VStack(spacing: PerchTheme.Spacing.large) {
                Spacer()

                // App name and icon
                VStack(spacing: PerchTheme.Spacing.medium) {
                    Image(systemName: "bird.fill")
                        .font(.system(size: 48))
                        .foregroundColor(PerchTheme.accent)

                    VStack(spacing: PerchTheme.Spacing.xSmall) {
                        Text("The Perch")
                            .font(PerchTheme.Font.largeTitle)
                            .foregroundColor(PerchTheme.textPrimary)

                        Text("Your personal AI dashboard")
                            .font(PerchTheme.Font.subheadline)
                            .foregroundColor(PerchTheme.textSecondary)
                    }
                }

                Spacer()

                // Form fields
                VStack(spacing: PerchTheme.Spacing.medium) {
                    // Email field
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                        Text("Email")
                            .font(PerchTheme.Font.caption1)
                            .foregroundColor(PerchTheme.textSecondary)

                        TextField("you@example.com", text: $vm.email)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .padding(PerchTheme.Spacing.small)
                            .background(PerchTheme.cardBackground)
                            .cornerRadius(PerchTheme.Card.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                                    .stroke(PerchTheme.border, lineWidth: 1)
                            )
                    }

                    // Display name field (sign up only)
                    if isSignUp {
                        VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                            Text("Display Name")
                                .font(PerchTheme.Font.caption1)
                                .foregroundColor(PerchTheme.textSecondary)

                            TextField("Fabio", text: $vm.displayName)
                                .padding(PerchTheme.Spacing.small)
                                .background(PerchTheme.cardBackground)
                                .cornerRadius(PerchTheme.Card.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                                        .stroke(PerchTheme.border, lineWidth: 1)
                                )
                        }
                    }

                    // Password field
                    VStack(alignment: .leading, spacing: PerchTheme.Spacing.xSmall) {
                        Text("Password")
                            .font(PerchTheme.Font.caption1)
                            .foregroundColor(PerchTheme.textSecondary)

                        SecureField("••••••••", text: $vm.password)
                            .padding(PerchTheme.Spacing.small)
                            .background(PerchTheme.cardBackground)
                            .cornerRadius(PerchTheme.Card.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                                    .stroke(PerchTheme.border, lineWidth: 1)
                            )
                    }

                    // Error message
                    if let error = authViewModel.error {
                        HStack(spacing: PerchTheme.Spacing.small) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.system(size: PerchTheme.Icon.small))
                            Text(error.errorDescription ?? "Unknown error")
                                .font(PerchTheme.Font.caption1)
                            Spacer()
                        }
                        .foregroundColor(PerchTheme.error)
                        .padding(PerchTheme.Spacing.small)
                        .background(PerchTheme.error.opacity(0.1))
                        .cornerRadius(PerchTheme.Card.cornerRadius)
                    }
                }

                // Action button
                Button(action: isSignUp ? handleSignUp : handleSignIn) {
                    ZStack {
                        RoundedRectangle(cornerRadius: PerchTheme.Card.cornerRadius)
                            .fill(PerchTheme.accent)

                        HStack(spacing: PerchTheme.Spacing.small) {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .tint(.white)
                            }

                            Text(isSignUp ? "Create Account" : "Sign In")
                                .font(PerchTheme.Font.headline)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(height: 50)
                .disabled(authViewModel.isLoading || authViewModel.email.isEmpty || authViewModel.password.isEmpty)
                .opacity(authViewModel.isLoading || authViewModel.email.isEmpty || authViewModel.password.isEmpty ? 0.6 : 1)

                // Toggle between sign in and sign up
                HStack(spacing: PerchTheme.Spacing.xSmall) {
                    Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                        .font(PerchTheme.Font.body)
                        .foregroundColor(PerchTheme.textSecondary)

                    Button(action: {
                        isSignUp.toggle()
                        authViewModel.clearError()
                    }) {
                        Text(isSignUp ? "Sign In" : "Create Account")
                            .font(PerchTheme.Font.body)
                            .fontWeight(.semibold)
                            .foregroundColor(PerchTheme.accent)
                    }
                }

                Spacer()
            }
            .padding(PerchTheme.Spacing.large)
        }
    }

    private func handleSignIn() {
        Task {
            await authViewModel.signIn()
        }
    }

    private func handleSignUp() {
        Task {
            await authViewModel.signUp()
        }
    }
}

// MARK: - Preview

#Preview {
    AuthView()
        .environment(AuthViewModel())
}
