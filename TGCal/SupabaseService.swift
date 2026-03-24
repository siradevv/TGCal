import Foundation
import Supabase

/// Central Supabase client — configure URL and anon key before first use.
@MainActor
final class SupabaseService: ObservableObject {

    static let shared = SupabaseService()

    // MARK: - Configuration
    // Replace with your Supabase project values
    private static let supabaseURL = URL(string: "https://YOUR_PROJECT.supabase.co")!
    private static let supabaseAnonKey = "YOUR_ANON_KEY"

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

        if result.user != nil {
            try await loadProfile()
            PushNotificationManager.shared.registerTokenAfterLogin()
        }
    }

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
        try await loadProfile()
        PushNotificationManager.shared.registerTokenAfterLogin()
    }

    func signOut() async throws {
        await PushNotificationManager.shared.removeTokenOnLogout()
        try await client.auth.signOut()
        currentUser = nil
        isAuthenticated = false
    }

    func restoreSession() async {
        do {
            let session = try await client.auth.session
            if session.user.id.uuidString.isEmpty == false {
                try await loadProfile()
                PushNotificationManager.shared.registerTokenAfterLogin()
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
