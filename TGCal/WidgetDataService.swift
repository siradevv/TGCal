import Foundation

/// Writes next-flight data to the shared App Group container for the widget to read.
enum WidgetDataService {

    private static let appGroupIdentifier = "group.com.tgcal.shared"
    private static let fileName = "next_flight.json"

    /// Call after any store mutation to keep the widget in sync.
    static func updateNextFlight(from months: [RosterMonthRecord]) {
        guard let snapshot = resolveNextFlight(from: months) else {
            removeSharedFile()
            return
        }

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return
        }

        let fileURL = containerURL.appendingPathComponent(fileName)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Widget will show empty state
        }
    }

    // MARK: - Private

    private static func resolveNextFlight(from months: [RosterMonthRecord]) -> NextFlightWidgetSnapshot? {
        let now = Date()
        var best: (date: Date, snapshot: NextFlightWidgetSnapshot)?

        for month in months {
            for (day, flightKeys) in month.flightsByDay {
                for key in flightKeys {
                    guard key.isAlphabeticDutyCode == false else { continue }

                    let detail: FlightLookupRecord?
                    if let exact = month.detailsByFlight[key] {
                        detail = exact
                    } else {
                        let normalized = key.strippingLeadingZeros()
                        detail = month.detailsByFlight[normalized]
                    }

                    guard let detail else { continue }
                    guard let departureDate = computeDepartureDate(
                        day: day, month: month.month, year: month.year,
                        departureTime: detail.departureTime
                    ) else { continue }

                    guard departureDate > now else { continue }

                    if best == nil || departureDate < best!.date {
                        let rawFlight = detail.flightNumber.isEmpty ? key : detail.flightNumber
                        let digits = String(rawFlight.filter(\.isNumber)).strippingLeadingZeros()
                        let flightCode = "TG \(digits.isEmpty ? "0" : digits)"
                        let origin = (detail.origin ?? "BKK").uppercased()
                        let destination = (detail.destination ?? "").uppercased()
                        guard destination.isEmpty == false else { continue }

                        let info = DestinationMetadata.info(for: destination)

                        let snapshot = NextFlightWidgetSnapshot(
                            flightCode: flightCode,
                            originCode: origin,
                            destinationCode: destination,
                            departureTime: detail.departureTime,
                            departureDate: departureDate,
                            destinationCity: info.cityName,
                            countryCode: info.countryCode
                        )
                        best = (departureDate, snapshot)
                    }
                }
            }
        }

        return best?.snapshot
    }

    private static func computeDepartureDate(day: Int, month: Int, year: Int, departureTime: String?) -> Date? {
        var components = DateComponents()
        components.calendar = .roster
        components.timeZone = rosterTimeZone
        components.year = year
        components.month = month
        components.day = day

        guard let startOfDay = components.date else { return nil }

        if let minutes = departureTime?.hhmmMinutes {
            return Calendar.roster.date(byAdding: .minute, value: minutes, to: startOfDay)
        }

        return startOfDay
    }

    private static func removeSharedFile() {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return
        }

        let fileURL = containerURL.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// Codable snapshot shared between main app and widget extension.
struct NextFlightWidgetSnapshot: Codable {
    let flightCode: String
    let originCode: String
    let destinationCode: String
    let departureTime: String?
    let departureDate: Date
    let destinationCity: String
    let countryCode: String
}
