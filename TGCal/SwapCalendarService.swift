import Foundation
import EventKit

/// Manages iPhone calendar events for confirmed flight swaps.
@MainActor
final class SwapCalendarService {

    static let shared = SwapCalendarService()

    private let eventStore = EKEventStore()
    private let swapNote = "TGCal Flight Swap"

    private init() {}

    // MARK: - Add Swap Event

    /// Creates a calendar event for a confirmed swap flight.
    func addSwapEvent(listing: SwapListing) async {
        guard await requestAccess() else { return }

        guard let calendar = writableCalendar() else { return }
        guard let (start, end) = flightDates(from: listing) else { return }

        // Check for existing swap event to avoid duplicates
        let predicate = eventStore.predicateForEvents(
            withStart: start.addingTimeInterval(-60),
            end: end.addingTimeInterval(60),
            calendars: [calendar]
        )
        let existing = eventStore.events(matching: predicate)
        let alreadyExists = existing.contains { event in
            event.title?.contains(listing.flightCode) == true
                && (event.notes ?? "").contains(swapNote)
        }
        guard alreadyExists == false else { return }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = calendar
        event.title = "\(listing.flightCode) \(listing.origin)\u{2192}\(listing.destination) (Swap)"
        event.startDate = start
        event.endDate = end
        event.timeZone = rosterTimeZone
        event.location = listing.destination
        event.notes = swapNote

        // Add an alert 3 hours before departure
        event.addAlarm(EKAlarm(relativeOffset: -3 * 3600))

        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
        } catch {
            print("[SwapCalendarService] Failed to save event: \(error.localizedDescription)")
        }
    }

    // MARK: - Remove Swap Event

    /// Removes the calendar event for a swap that was cancelled.
    func removeSwapEvent(listing: SwapListing) async {
        guard await requestAccess() else { return }

        guard let calendar = writableCalendar() else { return }
        guard let (start, _) = flightDates(from: listing) else { return }

        // Search around the flight date
        let dayStart = Calendar.roster.startOfDay(for: start)
        let dayEnd = Calendar.roster.date(byAdding: .day, value: 2, to: dayStart) ?? start.addingTimeInterval(48 * 3600)

        let predicate = eventStore.predicateForEvents(
            withStart: dayStart,
            end: dayEnd,
            calendars: [calendar]
        )

        let events = eventStore.events(matching: predicate)

        for event in events {
            guard (event.notes ?? "").contains(swapNote),
                  event.title?.contains(listing.flightCode) == true else { continue }

            do {
                try eventStore.remove(event, span: .thisEvent, commit: true)
            } catch {
                print("[SwapCalendarService] Failed to remove event: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Helpers

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

    /// Parses the listing's flight_date + departure_time into start/end Date values.
    private func flightDates(from listing: SwapListing) -> (start: Date, end: Date)? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = rosterTimeZone

        guard let baseDate = formatter.date(from: listing.flightDate) else { return nil }

        var startDate = baseDate
        if let depTime = listing.departureTime, let minutes = depTime.hhmmMinutes {
            startDate = Calendar.roster.date(
                bySettingHour: minutes / 60,
                minute: minutes % 60,
                second: 0,
                of: baseDate
            ) ?? baseDate
        }

        // Default flight duration: 4 hours
        let endDate = startDate.addingTimeInterval(4 * 3600)

        return (startDate, endDate)
    }
}
