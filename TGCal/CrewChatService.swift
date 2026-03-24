import Foundation
import Supabase

/// Manages crew chat channels and messages via Supabase.
@MainActor
final class CrewChatService: ObservableObject {

    static let shared = CrewChatService()

    private var client: SupabaseClient { SupabaseService.shared.client }

    @Published var channels: [CrewChannel] = []
    @Published var isLoadingChannels = false

    private init() {}

    // MARK: - Channels

    func fetchChannels() async {
        isLoadingChannels = channels.isEmpty
        defer { isLoadingChannels = false }

        do {
            channels = try await client
                .from("crew_channels")
                .select()
                .order("last_message_at", ascending: false)
                .execute()
                .value
        } catch {
            // Keep existing channels on failure
        }
    }

    // MARK: - Messages

    func fetchMessages(channelId: UUID, limit: Int = 50, before: Date? = nil) async throws -> [CrewChannelMessage] {
        var query = client
            .from("crew_channel_messages")
            .select()
            .eq("channel_id", value: channelId.uuidString)
            .order("sent_at", ascending: true)
            .limit(limit)

        if let before {
            query = query.lt("sent_at", value: ISO8601DateFormatter().string(from: before))
        }

        return try await query.execute().value
    }

    func sendMessage(channelId: UUID, text: String) async throws -> CrewChannelMessage {
        guard let user = SupabaseService.shared.currentUser else {
            throw CrewChatError.notAuthenticated
        }

        let newMessage = NewCrewChannelMessage(
            channelId: channelId,
            senderId: user.id,
            senderName: user.displayName,
            senderRank: user.crewRank.rawValue,
            text: text
        )

        let sent: CrewChannelMessage = try await client
            .from("crew_channel_messages")
            .insert(newMessage)
            .select()
            .single()
            .execute()
            .value

        // Update channel last message
        try? await client
            .from("crew_channels")
            .update([
                "last_message_text": text,
                "last_message_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: channelId.uuidString)
            .execute()

        return sent
    }

    // MARK: - Channel Membership

    func joinChannel(_ channelId: UUID) async throws {
        guard let userId = SupabaseService.shared.currentUser?.id else {
            throw CrewChatError.notAuthenticated
        }

        try await client
            .from("crew_channel_members")
            .upsert([
                "channel_id": channelId.uuidString,
                "user_id": userId.uuidString
            ])
            .execute()
    }
}

enum CrewChatError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to chat."
        }
    }
}
