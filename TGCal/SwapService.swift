import Foundation
import Supabase

/// Handles CRUD operations for swap listings and conversations.
@MainActor
final class SwapService: ObservableObject {

    static let shared = SwapService()

    private var client: SupabaseClient { SupabaseService.shared.client }

    @Published var listings: [SwapListing] = []
    @Published var myListings: [SwapListing] = []
    @Published var conversations: [Conversation] = []

    private init() {}

    // MARK: - Swap Listings

    func fetchOpenListings(
        destination: String? = nil,
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        searchText: String? = nil
    ) async throws {
        var query = client
            .from("swap_listings")
            .select()
            .eq("status", value: "open")
            .order("flight_date", ascending: true)

        if let destination, destination.isEmpty == false {
            query = query.eq("destination", value: destination.uppercased())
        }

        if let dateFrom {
            let dateString = Self.dateFormatter.string(from: dateFrom)
            query = query.gte("flight_date", value: dateString)
        }

        if let dateTo {
            let dateString = Self.dateFormatter.string(from: dateTo)
            query = query.lte("flight_date", value: dateString)
        }

        if let searchText, searchText.isEmpty == false {
            query = query.or("flight_code.ilike.%\(searchText)%,destination.ilike.%\(searchText)%,origin.ilike.%\(searchText)%")
        }

        listings = try await query
            .limit(50)
            .execute()
            .value
    }

    func fetchMyListings() async throws {
        guard let userId = SupabaseService.shared.currentUser?.id else { return }

        myListings = try await client
            .from("swap_listings")
            .select()
            .eq("posted_by", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createListing(_ listing: NewSwapListing) async throws -> SwapListing {
        let created: SwapListing = try await client
            .from("swap_listings")
            .insert(listing)
            .select()
            .single()
            .execute()
            .value

        myListings.insert(created, at: 0)
        return created
    }

    func cancelListing(_ listingId: UUID) async throws {
        try await client
            .from("swap_listings")
            .update(["status": "cancelled"])
            .eq("id", value: listingId.uuidString)
            .execute()

        if let index = myListings.firstIndex(where: { $0.id == listingId }) {
            myListings[index].status = .cancelled
        }
        listings.removeAll { $0.id == listingId }
    }

    // MARK: - Conversations

    func fetchMyConversations() async throws {
        guard let userId = SupabaseService.shared.currentUser?.id else { return }

        conversations = try await client
            .from("conversations")
            .select()
            .or("initiator_id.eq.\(userId.uuidString),listing_owner_id.eq.\(userId.uuidString)")
            .order("last_message_at", ascending: false)
            .execute()
            .value
    }

    func startConversation(listing: SwapListing) async throws -> Conversation {
        guard let userId = SupabaseService.shared.currentUser?.id else {
            throw SwapServiceError.notAuthenticated
        }

        // Enforce 24-hour rule
        guard isSwappable(listing) else {
            throw SwapServiceError.tooCloseToDepature
        }

        // Check if conversation already exists
        let existing: [Conversation] = try await client
            .from("conversations")
            .select()
            .eq("listing_id", value: listing.id.uuidString)
            .eq("initiator_id", value: userId.uuidString)
            .execute()
            .value

        if let existingConversation = existing.first {
            return existingConversation
        }

        let newConversation = NewConversation(
            listingId: listing.id,
            initiatorId: userId,
            listingOwnerId: listing.postedBy
        )

        let created: Conversation = try await client
            .from("conversations")
            .insert(newConversation)
            .select()
            .single()
            .execute()
            .value

        conversations.insert(created, at: 0)

        // Notify the listing poster
        let initiatorName = SupabaseService.shared.currentUser?.displayName ?? "Someone"
        NotificationService.shared.notifyNewSwapConversation(
            listingFlightCode: listing.flightCode,
            fromName: initiatorName
        )

        return created
    }

    // MARK: - Swap Confirmation

    func confirmSwap(conversationId: UUID) async throws {
        guard let userId = SupabaseService.shared.currentUser?.id else { return }

        guard let conversation = conversations.first(where: { $0.id == conversationId }) else { return }

        let isInitiator = userId == conversation.initiatorId
        let field = isInitiator ? "initiator_confirmed" : "owner_confirmed"
        let otherConfirmed = isInitiator ? conversation.ownerConfirmed : conversation.initiatorConfirmed

        var updates: [String: String] = [field: "true"]

        // If both parties confirmed, mark as confirmed
        let bothConfirmed = otherConfirmed
        if bothConfirmed {
            updates["status"] = "confirmed"

            // Also update the listing status
            try await client
                .from("swap_listings")
                .update(["status": "confirmed", "matched_with": userId.uuidString])
                .eq("id", value: conversation.listingId.uuidString)
                .execute()
        }

        try await client
            .from("conversations")
            .update(updates)
            .eq("id", value: conversationId.uuidString)
            .execute()

        // When both confirmed: add calendar event + notify
        if bothConfirmed {
            if let listing = await fetchListing(id: conversation.listingId) {
                await SwapCalendarService.shared.addSwapEvent(listing: listing)

                let otherName = await otherPartyName(conversation: conversation, currentUser: userId)
                NotificationService.shared.notifySwapConfirmed(
                    flightCode: listing.flightCode,
                    otherPartyName: otherName
                )
            }
        }

        // Refresh
        try await fetchMyConversations()
    }

    func cancelSwap(conversationId: UUID) async throws {
        guard let userId = SupabaseService.shared.currentUser?.id else { return }

        try await client
            .from("conversations")
            .update(["status": "cancelled", "initiator_confirmed": "false", "owner_confirmed": "false"])
            .eq("id", value: conversationId.uuidString)
            .execute()

        guard let conversation = conversations.first(where: { $0.id == conversationId }) else { return }

        // Re-open the listing
        try await client
            .from("swap_listings")
            .update(["status": "open", "matched_with": NSNull()])
            .eq("id", value: conversation.listingId.uuidString)
            .execute()

        // Remove calendar event + notify the other party
        if let listing = await fetchListing(id: conversation.listingId) {
            await SwapCalendarService.shared.removeSwapEvent(listing: listing)

            let cancellerName = SupabaseService.shared.currentUser?.displayName ?? "Someone"
            NotificationService.shared.notifySwapCancelled(
                flightCode: listing.flightCode,
                cancelledByName: cancellerName
            )
        }

        try await fetchMyConversations()
    }

    // MARK: - Messages

    func fetchMessages(conversationId: UUID) async throws -> [ChatMessage] {
        try await client
            .from("messages")
            .select()
            .eq("conversation_id", value: conversationId.uuidString)
            .order("sent_at", ascending: true)
            .execute()
            .value
    }

    func sendMessage(conversationId: UUID, text: String) async throws -> ChatMessage {
        guard let userId = SupabaseService.shared.currentUser?.id else {
            throw SwapServiceError.notAuthenticated
        }

        let newMessage = NewChatMessage(
            conversationId: conversationId,
            senderId: userId,
            text: text
        )

        let sent: ChatMessage = try await client
            .from("messages")
            .insert(newMessage)
            .select()
            .single()
            .execute()
            .value

        // Update conversation's last message
        try await client
            .from("conversations")
            .update([
                "last_message": text,
                "last_message_at": ISO8601DateFormatter().string(from: Date())
            ])
            .eq("id", value: conversationId.uuidString)
            .execute()

        // Notify the other party about the new message
        let senderName = SupabaseService.shared.currentUser?.displayName ?? "Crew Member"
        NotificationService.shared.notifyNewSwapMessage(fromName: senderName, text: text)

        return sent
    }

    func markMessagesAsRead(conversationId: UUID) async throws {
        guard let userId = SupabaseService.shared.currentUser?.id else { return }

        try await client
            .from("messages")
            .update(["is_read": "true"])
            .eq("conversation_id", value: conversationId.uuidString)
            .neq("sender_id", value: userId.uuidString)
            .eq("is_read", value: "false")
            .execute()
    }

    // MARK: - Profile Lookup

    func fetchProfile(userId: UUID) async throws -> UserProfile {
        try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
    }

    // MARK: - Listing Lookup

    func fetchListing(id: UUID) async -> SwapListing? {
        try? await client
            .from("swap_listings")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
    }

    private func otherPartyName(conversation: Conversation, currentUser: UUID) async -> String {
        let otherId = conversation.otherParticipantId(currentUser: currentUser)
        if let profile = try? await fetchProfile(userId: otherId) {
            return profile.displayName
        }
        return "Crew Member"
    }

    // MARK: - Helpers

    /// Returns true if the listing's departure is more than 24 hours away.
    func isSwappable(_ listing: SwapListing) -> Bool {
        departureDate(for: listing).map { $0.timeIntervalSinceNow > 24 * 3600 } ?? false
    }

    /// Parses the listing's flight date + departure time into a Date.
    func departureDate(for listing: SwapListing) -> Date? {
        guard let baseDate = Self.dateFormatter.date(from: listing.flightDate) else { return nil }

        if let depTime = listing.departureTime, let minutes = depTime.hhmmMinutes {
            return Calendar.roster.date(
                bySettingHour: minutes / 60,
                minute: minutes % 60,
                second: 0,
                of: baseDate
            ) ?? baseDate
        }

        // If no departure time, use end of day as conservative estimate
        return Calendar.roster.date(bySettingHour: 23, minute: 59, second: 0, of: baseDate) ?? baseDate
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = rosterTimeZone
        return f
    }()
}

enum SwapServiceError: LocalizedError {
    case notAuthenticated
    case tooCloseToDepature

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to do this."
        case .tooCloseToDepature:
            return "Swaps must be initiated at least 24 hours before departure."
        }
    }
}
