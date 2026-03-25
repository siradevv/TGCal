import Foundation
import Supabase
import AuthenticationServices
import CryptoKit

/// Central Supabase client — configure URL and anon key before first use.
@MainActor
final class SupabaseService: ObservableObject {

    static let shared = SupabaseService()

    // MARK: - Configuration
    // Replace with your Supabase project values
    private static let supabaseURL = URL(string: "https://lbcdmhytzenmjukkgnej.supabase.co")!
    private static let supabaseAnonKey = "sb_publishable_Zi9KeOLzZuhm0l30ZuyFdw_Lll1PNLK"

    let client: SupabaseClient

    @Published var currentUser: UserProfile?
    @Published var isAuthenticated = false

    private init() {
        client = SupabaseClient(
            supabaseURL: Self.supabaseURL,
            supabaseKey: Self.supabaseAnonKey
        )
    }

    // MARK: - Auth

    func signUp(email: String, password: String, displayName: String) async throws {
        let result = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["display_name": .string(displayName)]
        )

        let _ = result.user
        try await completeAuthentication()
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
        try await completeAuthentication()
    }

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    // MARK: - Social Auth

    /// Current nonce for Apple Sign In (hashed nonce sent to Apple, raw nonce sent to Supabase)
    private var currentNonce: String?

    /// Generate a cryptographically secure random nonce
    private func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess { random = UInt8.random(in: 0...255) }
                return random
            }
            for random in randoms {
                if remainingLength == 0 { break }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Prepare a Sign in with Apple request — call this from the ASAuthorizationController delegate
    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
    }

    /// Complete Sign in with Apple using the authorization credential
    func handleAppleSignIn(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let identityToken = credential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8),
              let nonce = currentNonce else {
            throw AuthError.missingToken
        }

        try await client.auth.signInWithIdToken(
            credentials: .init(
                provider: .apple,
                idToken: tokenString,
                nonce: nonce
            )
        )

        // If Apple provides a name on first sign-in, update the profile
        if let fullName = credential.fullName {
            let name = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
            if !name.isEmpty {
                try? await ensureProfileDisplayName(name)
            }
        }

        try await completeAuthentication()
        currentNonce = nil
    }

    /// Sign in with Google via Supabase OAuth (opens in-app browser)
    func signInWithGoogle() async throws {
        try await client.auth.signInWithOAuth(provider: .google)
        try await completeAuthentication()
    }

    /// Ensure the profile has a display name (for social sign-in where name comes from provider)
    private func ensureProfileDisplayName(_ name: String) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("profiles")
            .update(["display_name": name])
            .eq("id", value: userId.uuidString)
            .is("display_name", value: nil)
            .execute()
    }

    // MARK: - Sign Out & Delete

    func signOut() async throws {
        await PushNotificationManager.shared.removeTokenOnLogout()
        try await client.auth.signOut()
        currentUser = nil
        isAuthenticated = false
    }

    /// Permanently delete the current user's account and all associated data
    func deleteAccount() async throws {
        guard let userId = currentUser?.id else { return }

        // Remove push token first
        await PushNotificationManager.shared.removeTokenOnLogout()

        // Delete profile (cascade will clean up related rows)
        try await client
            .from("profiles")
            .delete()
            .eq("id", value: userId.uuidString)
            .execute()

        // Sign out locally
        try await client.auth.signOut()
        currentUser = nil
        isAuthenticated = false
    }

    enum AuthError: LocalizedError {
        case missingToken

        var errorDescription: String? {
            switch self {
            case .missingToken:
                return "Unable to retrieve authentication token. Please try again."
            }
        }
    }

    func restoreSession() async {
        do {
            let session = try await client.auth.session
            if session.user.id.uuidString.isEmpty == false {
                try await completeAuthentication()
            }
        } catch {
            currentUser = nil
            isAuthenticated = false
        }
    }

    // MARK: - Profile

    func loadProfile() async throws {
        let userId = try await client.auth.session.user.id

        let profile: UserProfile = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value

        currentUser = profile
        isAuthenticated = true
    }

    /// Shared post-auth logic: load profile and register push token
    private func completeAuthentication() async throws {
        try await loadProfile()
        PushNotificationManager.shared.registerTokenAfterLogin()
    }

    func updateProfile(displayName: String, crewRank: CrewRank) async throws {
        guard let userId = currentUser?.id else { return }

        try await client
            .from("profiles")
            .update([
                "display_name": displayName,
                "crew_rank": crewRank.rawValue
            ])
            .eq("id", value: userId.uuidString)
            .execute()

        currentUser?.displayName = displayName
        currentUser?.crewRank = crewRank
    }
}
