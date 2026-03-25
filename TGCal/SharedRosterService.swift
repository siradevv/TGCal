import Foundation
import Supabase

/// Manages shared roster links so crew can share schedules with family/partners.
@MainActor
final class SharedRosterService: ObservableObject {

    static let shared = SharedRosterService()

    private var client: SupabaseClient { SupabaseService.shared.client }

    @Published var activeLinks: [SharedRosterLink] = []
    @Published var isLoading = false

    private init() {}

    // MARK: - Fetch Links

    func fetchMyLinks() async {
        guard let userId = SupabaseService.shared.currentUser?.id else { return }

        isLoading = activeLinks.isEmpty
        defer { isLoading = false }

        do {
            activeLinks = try await client
                .from("shared_roster_links")
                .select()
                .eq("user_id", value: userId.uuidString)
                .eq("is_active", value: "true")
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            // Keep existing links on failure
        }
    }

    // MARK: - Create Link

    func createLink(monthId: String, label: String, expiresInDays: Int? = nil) async throws -> SharedRosterLink {
        guard let userId = SupabaseService.shared.currentUser?.id else {
            throw SharedRosterError.notAuthenticated
        }

        let token = generateShareToken()
        var expiresAt: String? = nil
        if let days = expiresInDays {
            let expiry = Calendar.current.date(byAdding: .day, value: days, to: Date())!
            expiresAt = ISO8601DateFormatter().string(from: expiry)
        }

        var insert: [String: String] = [
            "user_id": userId.uuidString,
            "month_id": monthId,
            "share_token": token,
            "label": label,
            "is_active": "true"
        ]
        if let expiresAt {
            insert["expires_at"] = expiresAt
        }

        let created: SharedRosterLink = try await client
            .from("shared_roster_links")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value

        activeLinks.insert(created, at: 0)
        return created
    }

    // MARK: - Deactivate Link

    func deactivateLink(_ linkId: UUID) async throws {
        try await client
            .from("shared_roster_links")
            .update(["is_active": "false"])
            .eq("id", value: linkId.uuidString)
            .execute()

        activeLinks.removeAll { $0.id == linkId }
    }

    // MARK: - Public Roster Fetch (for viewers)

    func fetchSharedRoster(token: String) async throws -> RosterMonthRecord? {
        let links: [SharedRosterLink] = try await client
            .from("shared_roster_links")
            .select()
            .eq("share_token", value: token)
            .eq("is_active", value: "true")
            .limit(1)
            .execute()
            .value

        guard let link = links.first else { return nil }

        // Check expiry
        if let expiry = link.expiresAt, expiry < Date() { return nil }

        // The month data is stored locally on the sharer's device.
        // In a production system, you'd store roster snapshots server-side.
        // For now, return nil as the roster data lives on the owner's device.
        return nil
    }

    // MARK: - Share URL

    func shareURL(for link: SharedRosterLink) -> URL? {
        // Deep link format: tgcal://shared-roster/{token}
        URL(string: "tgcal://shared-roster/\(link.shareToken)")
    }

    /// Generates an iCal (.ics) file from a roster month for sharing.
    func generateICalFile(for month: RosterMonthRecord) -> URL? {
        var icsContent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//TGCal//Shared Roster//EN
        CALSCALE:GREGORIAN
        METHOD:PUBLISH
        X-WR-CALNAME:TG Roster \(month.month)/\(month.year)

        """

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
        dateFormatter.timeZone = rosterTimeZone

        for (day, flightKeys) in month.flightsByDay.sorted(by: { $0.key < $1.key }) {
            for flightKey in flightKeys {
                guard let detail = month.detailsByFlight[flightKey] else { continue }
                guard detail.flightNumber.isAlphabeticDutyCode == false else { continue }

                let number = detail.flightNumber.strippingLeadingZeros()
                let displayNumber = number.isEmpty ? "0" : number
                let summary = "TG \(displayNumber) \(detail.origin ?? "???") → \(detail.destination ?? "???")"

                var dateComps = DateComponents()
                dateComps.year = month.year
                dateComps.month = month.month
                dateComps.day = day
                dateComps.hour = 0
                dateComps.minute = 0
                dateComps.calendar = .roster
                dateComps.timeZone = rosterTimeZone

                guard let startDate = dateComps.date else { continue }

                let dtStart: String
                let dtEnd: String

                if let depTime = detail.departureTime, let depMinutes = depTime.hhmmMinutes {
                    var depComps = dateComps
                    depComps.hour = depMinutes / 60
                    depComps.minute = depMinutes % 60
                    if let depDate = depComps.date {
                        dtStart = dateFormatter.string(from: depDate)
                    } else {
                        dtStart = dateFormatter.string(from: startDate)
                    }
                } else {
                    dtStart = dateFormatter.string(from: startDate)
                }

                if let arrTime = detail.arrivalTime, let arrMinutes = arrTime.hhmmMinutes {
                    var arrComps = dateComps
                    arrComps.hour = arrMinutes / 60
                    arrComps.minute = arrMinutes % 60
                    if let arrDate = arrComps.date {
                        dtEnd = dateFormatter.string(from: arrDate)
                    } else {
                        dtEnd = dtStart
                    }
                } else {
                    dtEnd = dtStart
                }

                icsContent += """
                BEGIN:VEVENT
                UID:\(UUID().uuidString)@tgcal
                DTSTART;TZID=Asia/Bangkok:\(dtStart)
                DTEND;TZID=Asia/Bangkok:\(dtEnd)
                SUMMARY:\(summary)
                DESCRIPTION:Flight \(detail.flightNumber) - \(detail.sourceLabel)
                END:VEVENT

                """
            }
        }

        icsContent += "END:VCALENDAR\n"

        do {
            let tempDir = FileManager.default.temporaryDirectory
            let filename = "TG_Roster_\(month.year)_\(String(format: "%02d", month.month)).ics"
            let fileURL = tempDir.appendingPathComponent(filename)
            try icsContent.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func generateShareToken() -> String {
        let chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<24).map { _ in chars.randomElement()! })
    }
}

enum SharedRosterError: LocalizedError {
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to share your roster."
        }
    }
}
