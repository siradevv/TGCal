import Foundation
import EventKit

/// Manages iPhone calendar events for confirmed flight swaps.
@MainActor
final class SwapCalendarService {

    static let shared = SwapCalendarService()

    private let eventStore = EKEventStore()
    private let swapNote = "TGCal Flight Swap"

    private init() {}

    // MARK: - Add Swap Event(s)

    /// Creates calendar events for a confirmed swap (outbound + return if round-trip).
    func addSwapEvent(listing: SwapListing) async {
        guard await requestAccess() else { return }
        guard let calendar = writableCalendar() else { return }

        // Outbound event
        if let (start, end) = parseDates(flightDate: listing.flightDate, departureTime: listing.departureTime) {
            createEventIfNeeded(
                calendar: calendar,
                title: "\(listing.flightCode) \(listing.origin)\u{2192}\(listing.destination) (Swap)",
                start: start,
                end: end,
                location: listing.destination,
                flightCode: listing.flightCode
            )
        }

        // Return event
        if listing.isRoundTrip,
           let returnCode = listing.returnFlightCode,
           let returnOrigin = listing.returnOrigin,
           let returnDest = listing.returnDestination,
           let returnDate = listing.returnFlightDate,
           let (start, end) = parseDates(flightDate: returnDate, departureTime: listing.returnDepartureTime) {
            createEventIfNeeded(
                calendar: calendar,
                title: "\(returnCode) \(returnOrigin)\u{2192}\(returnDest) (Swap)",
                start: start,
                end: end,
                location: returnDest,
                flightCode: returnCode
            )
        }
    }

    // MARK: - Remove Swap Event(s)

    /// Removes calendar events for a cancelled swap (both legs).
    func removeSwapEvent(listing: SwapListing) async {
        guard await requestAccess() else { return }
        guard let calendar = writableCalendar() else { return }

        // Remove outbound
        if let (start, _) = parseDates(flightDate: listing.flightDate, departureTime: listing.departureTime) {
            removeEvents(calendar: calendar, near: start, flightCode: listing.flightCode)
        }

        // Remove return
        if listing.isRoundTrip,
           let returnCode = listing.returnFlightCode,
           let returnDate = listing.returnFlightDate,
           let (start, _) = parseDates(flightDate: returnDate, departureTime: listing.returnDepartureTime) {
            removeEvents(calendar: calendar, near: start, flightCode: returnCode)
        }
    }

    // MARK: - Helpers

    private func createEventIfNeeded(calendar: EKCalendar, title: String, start: Date, end: Date, location: String, flightCode: String) {
        // Check for existing to avoid duplicates
        let predicate = eventStore.predicateForEvents(
            withStart: start.addingTimeInterval(-60),
            end: end.addingTimeInterval(60),
            calendars: [calendar]
        )
        let existing = eventStore.events(matching: predicate)
        let alreadyExists = existing.contains { event in
            event.title?.contains(flightCode) == true
                && (event.notes ?? "").contains(swapNote)
        }
        guard alreadyExists == false else { return }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = title
        event.startDate = start
        event.endDate = end
        event.timeZone = rosterTimeZone
        event.location = location
        event.notes = swapNote
        event.addAlarm(EKAlarm(relativeOffset: -3 * 3600))

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            print("[SwapCalendarService] Failed to save event: \(error.localizedDescription)")
        }
    }

    private func removeEvents(calendar: EKCalendar, near date: Date, flightCode: String) {
        let dayStart = Calendar.roster.startOfDay(for: date)
        let dayEnd = Calendar.roster.date(byAdding: .day, value: 2, to: dayStart) ?? date.addingTimeInterval(48 * 3600)

        let predicate = eventStore.predicateForEvents(
            withStart: dayStart,
            end: dayEnd,
            calendars: [calendar]
        )

        for event in eventStore.events(matching: predicate) {
            guard (event.notes ?? "").contains(swapNote),
                  event.title?.contains(flightCode) == true else { continue }

            do {
                try eventStore.remove(event, span: .thisEvent, commit: true)
            } catch {
                print("[SwapCalendarService] Failed to remove event: \(error.localizedDescription)")
            }
        }
    }

    private func requestAccess() async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess || status == .writeOnly { return true }
        if status == .notDetermined {
            return (try? await eventStore.requestFullAccessToEvents()) ?? false
        }
        return false
    }

    private func writableCalendar() -> EKCalendar? {
        if let defaultCal = eventStore.defaultCalendarForNewEvents,
           defaultCal.allowsContentModifications {
            return defaultCal
        }
        return eventStore
            .calendars(for: .event)
            .first(where: { $0.allowsContentModifications })
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = rosterTimeZone
        return f
    }()

    /// Parses a flight_date + departure_time into start/end Date values.
    private func parseDates(flightDate: String, departureTime: String?) -> (start: Date, end: Date)? {
        guard let baseDate = Self.dateFormatter.date(from: flightDate) else { return nil }

        var startDate = baseDate
        if let depTime = departureTime, let minutes = depTime.hhmmMinutes {
            startDate = Calendar.roster.date(
                bySettingHour: minutes / 60,
                minute: minutes % 60,
                second: 0,
                of: baseDate
            ) ?? baseDate
        }

        let endDate = startDate.addingTimeInterval(4 * 3600)
        return (startDate, endDate)
    }
}
