import Foundation

// MARK: - User Profile

struct UserProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var displayName: String
    var crewRank: CrewRank
    var avatarUrl: String?
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case crewRank = "crew_rank"
        case avatarUrl = "avatar_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum CrewRank: String, Codable, CaseIterable, Identifiable {
    case cabin
    case senior
    case purser

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cabin: return "Cabin Crew"
        case .senior: return "Senior Crew"
        case .purser: return "Purser"
        }
    }
}

// MARK: - Swap Listing

struct SwapListing: Codable, Identifiable, Equatable {
    let id: UUID
    let postedBy: UUID
    let postedByName: String
    let flightCode: String
    let origin: String
    let destination: String
    let flightDate: String // "YYYY-MM-DD"
    let departureTime: String?
    let note: String?
    var status: SwapStatus
    var matchedWith: UUID?
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case postedBy = "posted_by"
        case postedByName = "posted_by_name"
        case flightCode = "flight_code"
        case origin
        case destination
        case flightDate = "flight_date"
        case departureTime = "departure_time"
        case note
        case status
        case matchedWith = "matched_with"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var routeText: String {
        "\(origin) \u{2192} \(destination)"
    }

    var displayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: flightDate) else { return flightDate }
        let display = DateFormatter()
        display.dateFormat = "EEE, d MMM yyyy"
        display.locale = Locale(identifier: "en_US")
        return display.string(from: date)
    }
}

enum SwapStatus: String, Codable {
    case open
    case pending
    case confirmed
    case cancelled
}

struct NewSwapListing: Codable {
    let postedBy: UUID
    let postedByName: String
    let flightCode: String
    let origin: String
    let destination: String
    let flightDate: String
    let departureTime: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case postedBy = "posted_by"
        case postedByName = "posted_by_name"
        case flightCode = "flight_code"
        case origin
        case destination
        case flightDate = "flight_date"
        case departureTime = "departure_time"
        case note
    }
}

// MARK: - Conversation

struct Conversation: Codable, Identifiable, Equatable {
    let id: UUID
    let listingId: UUID
    let initiatorId: UUID
    let listingOwnerId: UUID
    var status: ConversationStatus
    var initiatorConfirmed: Bool
    var ownerConfirmed: Bool
    var lastMessage: String?
    var lastMessageAt: Date?
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case listingId = "listing_id"
        case initiatorId = "initiator_id"
        case listingOwnerId = "listing_owner_id"
        case status
        case initiatorConfirmed = "initiator_confirmed"
        case ownerConfirmed = "owner_confirmed"
        case lastMessage = "last_message"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func isParticipant(_ userId: UUID) -> Bool {
        userId == initiatorId || userId == listingOwnerId
    }

    func otherParticipantId(currentUser: UUID) -> UUID {
        currentUser == initiatorId ? listingOwnerId : initiatorId
    }

    func hasUserConfirmed(_ userId: UUID) -> Bool {
        if userId == initiatorId { return initiatorConfirmed }
        if userId == listingOwnerId { return ownerConfirmed }
        return false
    }
}

enum ConversationStatus: String, Codable {
    case active
    case confirmed
    case cancelled
}

struct NewConversation: Codable {
    let listingId: UUID
    let initiatorId: UUID
    let listingOwnerId: UUID

    enum CodingKeys: String, CodingKey {
        case listingId = "listing_id"
        case initiatorId = "initiator_id"
        case listingOwnerId = "listing_owner_id"
    }
}

// MARK: - Message

struct ChatMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let conversationId: UUID
    let senderId: UUID
    let text: String
    var isRead: Bool
    let sentAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case text
        case isRead = "is_read"
        case sentAt = "sent_at"
    }
}

struct NewChatMessage: Codable {
    let conversationId: UUID
    let senderId: UUID
    let text: String

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case senderId = "sender_id"
        case text
    }
}
