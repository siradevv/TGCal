import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @ObservedObject private var supabase = SupabaseService.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showForgotPassword = false
    @State private var resetEmail = ""
    @State private var resetSent = false

    var body: some View {
        ZStack {
            TGBackgroundView()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 40)

                    // Logo & Title
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundStyle(TGTheme.indigo)

                        Text("TGCal Swap")
                            .font(.title.weight(.bold))

                        Text(isSignUp ? "Create your account to start swapping flights" : "Sign in to access flight swaps")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // Social Sign In
                    VStack(spacing: 12) {
                        SignInWithAppleButton(
                            .signIn,
                            onRequest: { request in
                                supabase.prepareAppleSignInRequest(request)
                            },
                            onCompletion: { result in
                                Task { await handleAppleResult(result) }
                            }
                        )
                        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                        .frame(height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            Task { await signInWithGoogle() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "g.circle.fill")
                                    .font(.title3)
                                Text("Sign in with Google")
                                    .font(.headline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.systemBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color(.separator), lineWidth: 1)
                                    )
                            )
                            .foregroundStyle(.primary)
                        }
                        .disabled(isLoading)
                    }
                    .padding(.horizontal, 16)

                    // Divider
                    HStack(spacing: 12) {
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 1)
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Rectangle()
                            .fill(Color(.separator))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 32)

                    // Email/Password Form
                    VStack(spacing: 14) {
                        if isSignUp {
                            AuthTextField(
                                icon: "person",
                                placeholder: "Display Name",
                                text: $displayName
                            )
                        }

                        AuthTextField(
                            icon: "envelope",
                            placeholder: "Email",
                            text: $email,
                            keyboardType: .emailAddress,
                            autocapitalization: .never
                        )

                        AuthSecureField(
                            icon: "lock",
                            placeholder: "Password",
                            text: $password
                        )

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await submit() }
                        } label: {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(isSignUp ? "Create Account" : "Sign In")
                                        .font(.headline.weight(.semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(TGTheme.indigo)
                        .disabled(isLoading || !isFormValid)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .tgOverviewCard(verticalPadding: 20)

                    // Forgot password (only in sign-in mode)
                    if !isSignUp {
                        Button {
                            resetEmail = email
                            showForgotPassword = true
                        } label: {
                            Text("Forgot Password?")
                                .font(.subheadline)
                                .foregroundStyle(TGTheme.indigo)
                        }
                    }

                    // Toggle sign-in / sign-up
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSignUp.toggle()
                            errorMessage = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                                .foregroundStyle(.secondary)
                            Text(isSignUp ? "Sign In" : "Sign Up")
                                .foregroundStyle(TGTheme.indigo)
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
            }
        }
        .alert("Reset Password", isPresented: $showForgotPassword) {
            TextField("Email", text: $resetEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            Button("Send Reset Link") {
                Task {
                    do {
                        try await supabase.resetPassword(email: resetEmail.trimmingCharacters(in: .whitespaces).lowercased())
                        resetSent = true
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter your email address and we'll send you a password reset link.")
        }
        .alert("Check Your Email", isPresented: $resetSent) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("If an account exists for \(resetEmail), a password reset link has been sent.")
        }
    }

    private var isFormValid: Bool {
        let hasEmail = email.contains("@") && email.count >= 5
        let hasPassword = password.count >= 6
        if isSignUp {
            return hasEmail && hasPassword && displayName.trimmingCharacters(in: .whitespaces).count >= 2
        }
        return hasEmail && hasPassword
    }

    private func submit() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if isSignUp {
                try await supabase.signUp(
                    email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                    password: password,
                    displayName: displayName.trimmingCharacters(in: .whitespaces)
                )
            } else {
                try await supabase.signIn(
                    email: email.trimmingCharacters(in: .whitespaces).lowercased(),
                    password: password
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleAppleResult(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Invalid Apple credential."
                return
            }
            do {
                try await supabase.handleAppleSignIn(credential: credential)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            let asError = error as? ASAuthorizationError
            // User cancelled or dismissed — don't show error
            if asError?.code == .canceled { return }
            // Unknown error (often means capability not configured)
            if asError?.code == .unknown {
                errorMessage = "Sign in with Apple is not available. Please use email or check that Sign in with Apple is enabled in Apple Developer portal."
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await supabase.signInWithGoogle()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Custom Text Fields

private struct AuthTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .words

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TGTheme.insetFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TGTheme.insetStroke, lineWidth: 1)
                )
        )
    }
}

private struct AuthSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Group {
                if isVisible {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash" : "eye")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TGTheme.insetFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(TGTheme.insetStroke, lineWidth: 1)
                )
        )
    }
}
