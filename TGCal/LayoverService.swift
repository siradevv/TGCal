import Foundation
import Supabase

/// Manages layover tips and voting via Supabase.
@MainActor
final class LayoverService: ObservableObject {

    static let shared = LayoverService()

    private var client: SupabaseClient { SupabaseService.shared.client }

    @Published var tips: [LayoverTip] = []
    @Published var isLoading = false

    /// Tracks which tips the current user has voted on.
    private var votedTipIds: Set<UUID> = []

    private init() {}

    // MARK: - Fetch Tips

    func fetchTips(airportCode: String, category: LayoverCategory? = nil) async {
        isLoading = tips.isEmpty
        defer { isLoading = false }

        do {
            var query = client
                .from("layover_tips")
                .select()
                .eq("airport_code", value: airportCode.uppercased())

            if let category {
                query = query.eq("category", value: category.rawValue)
            }

            tips = try await query
                .order("upvotes", ascending: false)
                .limit(100)
                .execute()
                .value
        } catch {
            // Keep existing tips on failure
        }
    }

    func fetchTipsForDestinations(_ codes: [String]) async -> [String: [LayoverTip]] {
        var result: [String: [LayoverTip]] = [:]
        for code in codes.prefix(10) {
            do {
                let codeTips: [LayoverTip] = try await client
                    .from("layover_tips")
                    .select()
                    .eq("airport_code", value: code.uppercased())
                    .order("upvotes", ascending: false)
                    .limit(5)
                    .execute()
                    .value
                result[code] = codeTips
            } catch {
                continue
            }
        }
        return result
    }

    // MARK: - Create Tip

    func createTip(_ tip: NewLayoverTip) async throws -> LayoverTip {
        let created: LayoverTip = try await client
            .from("layover_tips")
            .insert(tip)
            .select()
            .single()
            .execute()
            .value

        tips.insert(created, at: 0)
        return created
    }

    // MARK: - Photo Upload

    func uploadTipPhoto(imageData: Data, userId: UUID) async throws -> String {
        let photoId = UUID().uuidString.lowercased()
        let path = "\(userId.uuidString.lowercased())/\(photoId).jpg"

        try await client.storage
            .from("layover_photos")
            .upload(
                path: path,
                file: imageData,
                options: .init(contentType: "image/jpeg", upsert: false)
            )

        let publicURL = try client.storage
            .from("layover_photos")
            .getPublicURL(path: path)
            .absoluteString

        return publicURL
    }

    // MARK: - Voting

    func hasVoted(tipId: UUID) -> Bool {
        votedTipIds.contains(tipId)
    }

    func vote(tipId: UUID, isUpvote: Bool) async throws {
        guard let userId = SupabaseService.shared.currentUser?.id else {
            throw LayoverServiceError.notAuthenticated
        }

        let vote = LayoverVote(tipId: tipId, userId: userId, isUpvote: isUpvote)

        try await client
            .from("layover_votes")
            .upsert(vote)
            .execute()

        // Update local count
        if let index = tips.firstIndex(where: { $0.id == tipId }) {
            if isUpvote {
                tips[index].upvotes += 1
            } else {
                tips[index].downvotes += 1
            }
        }

        votedTipIds.insert(tipId)
    }

    // MARK: - Load User Votes

    func loadUserVotes(for tipIds: [UUID]) async {
        guard let userId = SupabaseService.shared.currentUser?.id else { return }

        do {
            let votes: [LayoverVote] = try await client
                .from("layover_votes")
                .select()
                .eq("user_id", value: userId.uuidString)
                .in("tip_id", values: tipIds.map(\.uuidString))
                .execute()
                .value

            votedTipIds.formUnion(votes.map(\.tipId))
        } catch {
            // Silent failure
        }
    }
}

enum LayoverServiceError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to submit tips."
        }
    }
}
