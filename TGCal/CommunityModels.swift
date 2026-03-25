import Foundation

// MARK: - Crew Chat

struct CrewChannel: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let name: String
    let channelType: ChannelType
    let description: String?
    let createdBy: UUID?
    let memberCount: Int
    let lastMessageText: String?
    let lastMessageAt: Date?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case channelType = "channel_type"
        case createdBy = "created_by"
        case memberCount = "member_count"
        case lastMessageText = "last_message_text"
        case lastMessageAt = "last_message_at"
        case createdAt = "created_at"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum ChannelType: String, Codable, CaseIterable {
    case general
    case base
    case fleet
    case rank

    var displayName: String {
        switch self {
        case .general: return "General"
        case .base: return "Base"
        case .fleet: return "Fleet"
        case .rank: return "Rank"
        }
    }

    var icon: String {
        switch self {
        case .general: return "bubble.left.and.bubble.right"
        case .base: return "building.2"
        case .fleet: return "airplane"
        case .rank: return "person.3"
        }
    }
}

struct CrewChannelMessage: Codable, Identifiable, Equatable {
    let id: UUID
    let channelId: UUID
    let senderId: UUID
    let senderName: String
    let senderRank: String?
    let text: String
    let sentAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case channelId = "channel_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case senderRank = "sender_rank"
        case text
        case sentAt = "sent_at"
    }
}

struct NewCrewChannelMessage: Codable {
    let channelId: UUID
    let senderId: UUID
    let senderName: String
    let senderRank: String?
    let text: String

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case senderId = "sender_id"
        case senderName = "sender_name"
        case senderRank = "sender_rank"
        case text
    }
}

// MARK: - Layover Guide

struct LayoverTip: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    let airportCode: String
    let category: LayoverCategory
    let title: String
    let body: String
    let authorId: UUID
    let authorName: String
    var upvotes: Int
    var downvotes: Int
    let createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case airportCode = "airport_code"
        case category, title, body
        case authorId = "author_id"
        case authorName = "author_name"
        case upvotes, downvotes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var score: Int { upvotes - downvotes }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum LayoverCategory: String, Codable, CaseIterable, Identifiable {
    case hotel
    case food
    case transport
    case shopping
    case sim
    case crewDiscount
    case safety
    case general

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hotel: return "Hotels"
        case .food: return "Food & Drink"
        case .transport: return "Transport"
        case .shopping: return "Shopping"
        case .sim: return "SIM Cards"
        case .crewDiscount: return "Crew Discounts"
        case .safety: return "Safety"
        case .general: return "General"
        }
    }

    var icon: String {
        switch self {
        case .hotel: return "bed.double"
        case .food: return "fork.knife"
        case .transport: return "bus"
        case .shopping: return "bag"
        case .sim: return "simcard"
        case .crewDiscount: return "tag"
        case .safety: return "shield.checkered"
        case .general: return "info.circle"
        }
    }
}

struct NewLayoverTip: Codable {
    let airportCode: String
    let category: LayoverCategory
    let title: String
    let body: String
    let authorId: UUID
    let authorName: String

    enum CodingKeys: String, CodingKey {
        case airportCode = "airport_code"
        case category, title, body
        case authorId = "author_id"
        case authorName = "author_name"
    }
}

struct LayoverVote: Codable {
    let tipId: UUID
    let userId: UUID
    let isUpvote: Bool

    enum CodingKeys: String, CodingKey {
        case tipId = "tip_id"
        case userId = "user_id"
        case isUpvote = "is_upvote"
    }
}

// MARK: - Commute Tracker

struct CommuteRecord: Codable, Identifiable, Equatable {
    var id: UUID
    var date: Date
    var fromCity: String
    var toCity: String
    var mode: CommuteMode
    var durationMinutes: Int
    var cost: Double
    var currency: String
    var note: String?

    var costText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let formatted = formatter.string(from: NSNumber(value: cost)) ?? "\(Int(cost))"
        return "\(formatted) \(currency)"
    }
}

enum CommuteMode: String, Codable, CaseIterable, Identifiable {
    case flight
    case train
    case bus
    case taxi
    case car
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flight: return "Flight"
        case .train: return "Train"
        case .bus: return "Bus"
        case .taxi: return "Taxi"
        case .car: return "Car"
        case .other: return "Other"
        }
    }

    var icon: String {
        switch self {
        case .flight: return "airplane"
        case .train: return "tram"
        case .bus: return "bus"
        case .taxi: return "car"
        case .car: return "car.side"
        case .other: return "figure.walk"
        }
    }
}

// MARK: - Shared Roster

struct SharedRosterLink: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let monthId: String
    let shareToken: String
    let label: String
    let isActive: Bool
    let expiresAt: Date?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case monthId = "month_id"
        case shareToken = "share_token"
        case label
        case isActive = "is_active"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

// MARK: - Crew Pairing

struct CrewPairing: Codable, Identifiable, Equatable {
    let id: UUID
    let userId: UUID
    let displayName: String
    let crewRank: CrewRank
    let flightCode: String
    let flightDate: String

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case displayName = "display_name"
        case crewRank = "crew_rank"
        case flightCode = "flight_code"
        case flightDate = "flight_date"
    }
}

// MARK: - Flight Alert

struct FlightAlert: Identifiable, Equatable {
    let id: UUID
    let flightCode: String
    let alertType: FlightAlertType
    let message: String
    let timestamp: Date

    var isRecent: Bool {
        Date().timeIntervalSince(timestamp) < 3600
    }
}

enum FlightAlertType: String, Equatable {
    case delay
    case gateChange
    case cancellation
    case diversion

    var icon: String {
        switch self {
        case .delay: return "clock.badge.exclamationmark"
        case .gateChange: return "door.left.hand.open"
        case .cancellation: return "xmark.octagon"
        case .diversion: return "arrow.triangle.turn.up.right.diamond"
        }
    }

    var color: String {
        switch self {
        case .delay: return "orange"
        case .gateChange: return "blue"
        case .cancellation: return "red"
        case .diversion: return "red"
        }
    }

    var displayName: String {
        switch self {
        case .delay: return "Delayed"
        case .gateChange: return "Gate Changed"
        case .cancellation: return "Cancelled"
        case .diversion: return "Diverted"
        }
    }
}

// MARK: - Calendar Event Types

enum CalendarEventType: Equatable {
    case flight(FlightLookupRecord)
    case duty(FlightLookupRecord)
    case swap(SwapListing)
    case dayOff

    var displayColor: String {
        switch self {
        case .flight: return "indigo"
        case .duty: return "orange"
        case .swap: return "green"
        case .dayOff: return "gray"
        }
    }
}

struct CalendarDayEvents: Identifiable {
    let day: Int
    let date: Date
    let events: [CalendarEventType]

    var id: Int { day }

    var hasFlights: Bool {
        events.contains { if case .flight = $0 { return true }; return false }
    }

    var hasDuty: Bool {
        events.contains { if case .duty = $0 { return true }; return false }
    }

    var hasSwap: Bool {
        events.contains { if case .swap = $0 { return true }; return false }
    }

    var isDayOff: Bool {
        events.isEmpty || events.allSatisfy { if case .dayOff = $0 { return true }; return false }
    }
}
