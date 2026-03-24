import Foundation
import Supabase

/// Matches crew members who are on the same flights.
/// Users opt in by uploading their flight codes to the `crew_flight_registry` table.
@MainActor
final class CrewPairingService: ObservableObject {

    static let shared = CrewPairingService()

    private var client: SupabaseClient { SupabaseService.shared.client }

    @Published var pairingsForNextFlight: [CrewPairing] = []
    @Published var isLoading = false

    private init() {}

    // MARK: - Register Flights

    /// Registers the user's flights so other crew can see who's on the same flight.
    func registerFlights(from month: RosterMonthRecord) async {
        guard let user = SupabaseService.shared.currentUser else { return }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = rosterTimeZone
        dateFormatter.calendar = .roster

        var registrations: [[String: String]] = []

        for (day, flightKeys) in month.flightsByDay {
            for flightKey in flightKeys {
                guard flightKey.isAlphabeticDutyCode == false else { continue }

                var comps = DateComponents()
                comps.year = month.year
                comps.month = month.month
                comps.day = day
                comps.calendar = .roster
                comps.timeZone = rosterTimeZone

                guard let date = comps.date else { continue }

                let number = flightKey.strippingLeadingZeros()
                let flightCode = "TG\(number.isEmpty ? "0" : number)"
                let dateString = dateFormatter.string(from: date)

                registrations.append([
                    "user_id": user.id.uuidString,
                    "display_name": user.displayName,
                    "crew_rank": user.crewRank.rawValue,
                    "flight_code": flightCode,
                    "flight_date": dateString
                ])
            }
        }

        guard registrations.isEmpty == false else { return }

        // Upsert in batches
        let batchSize = 50
        for batchStart in stride(from: 0, to: registrations.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, registrations.count)
            let batch = Array(registrations[batchStart..<batchEnd])

            try? await client
                .from("crew_flight_registry")
                .upsert(batch)
                .execute()
        }
    }

    // MARK: - Find Crew on Same Flight

    func findCrewOnFlight(flightCode: String, flightDate: String) async {
        guard let userId = SupabaseService.shared.currentUser?.id else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let allPairings: [CrewPairing] = try await client
                .from("crew_flight_registry")
                .select()
                .eq("flight_code", value: flightCode)
                .eq("flight_date", value: flightDate)
                .neq("user_id", value: userId.uuidString)
                .limit(50)
                .execute()
                .value

            pairingsForNextFlight = allPairings
        } catch {
            pairingsForNextFlight = []
        }
    }

    /// Removes the user's flight registrations (opt-out/privacy).
    func deregisterAllFlights() async {
        guard let userId = SupabaseService.shared.currentUser?.id else { return }

        try? await client
            .from("crew_flight_registry")
            .delete()
            .eq("user_id", value: userId.uuidString)
            .execute()
    }
}
