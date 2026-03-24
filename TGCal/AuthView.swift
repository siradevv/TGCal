import SwiftUI

struct AuthView: View {
    @ObservedObject private var supabase = SupabaseService.shared
    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

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

                    // Form
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
