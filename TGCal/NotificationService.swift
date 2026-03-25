import Foundation
import UserNotifications

final class NotificationService {

    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let categoryIdentifier = "FLIGHT_REMINDER"
    private let identifierPrefix = "tgcal-"

    private init() {}

    // MARK: - Permission

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error {
                print("[NotificationService] Authorization error: \(error.localizedDescription)")
            } else {
                print("[NotificationService] Authorization granted: \(granted)")
            }
        }
    }

    // MARK: - Schedule Reminders

    func scheduleReminders(for month: RosterMonthRecord) {
        let monthId = month.id

        // Collect all eligible flights with their computed departure dates.
        var flights: [(day: Int, flightNumber: String, detail: FlightLookupRecord, departureDate: Date)] = []

        let calendar = Calendar.roster

        for (day, flightNumbers) in month.flightsByDay {
            for flightNumber in flightNumbers {
                guard !flightNumber.isAlphabeticDutyCode else { continue }
                guard let detail = month.detailsByFlight[flightNumber] else { continue }
                guard let departureTime = detail.departureTime,
                      let minutes = departureTime.hhmmMinutes else { continue }

                let hour = minutes / 60
                let minute = minutes % 60

                var comps = DateComponents()
                comps.calendar = calendar
                comps.timeZone = rosterTimeZone
                comps.year = month.year
                comps.month = month.month
                comps.day = day
                comps.hour = hour
                comps.minute = minute

                guard let departureDate = calendar.date(from: comps) else { continue }

                flights.append((day: day, flightNumber: flightNumber, detail: detail, departureDate: departureDate))
            }
        }

        // Sort by departure date ascending and take nearest 30.
        flights.sort { $0.departureDate < $1.departureDate }
        let capped = flights.prefix(30)

        // Cancel existing notifications for this month before scheduling new ones.
        // Use completion handler to ensure cancellation finishes before scheduling.
        let prefix = "\(identifierPrefix)\(monthId)-"
        center.getPendingNotificationRequests { [weak self] requests in
            let matching = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            self?.center.removePendingNotificationRequests(withIdentifiers: matching)
        }

        // Small delay to let cancel complete before scheduling new ones
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            self.scheduleNewReminders(capped: Array(capped), monthId: monthId)
        }
    }

    private func scheduleNewReminders(
        capped: [(day: Int, flightNumber: String, detail: FlightLookupRecord, departureDate: Date)],
        monthId: String
    ) {
        for entry in capped {
            let detail = entry.detail
            let number = entry.flightNumber.strippingLeadingZeros()
            let displayNumber = number.isEmpty ? "0" : number
            let origin = detail.origin ?? "???"
            let destination = detail.destination ?? "???"
            let depTime = detail.departureTime ?? ""

            // 12-hour-before notification
            let twelveHBefore = entry.departureDate.addingTimeInterval(-12 * 3600)
            let twelveHId = "\(identifierPrefix)\(monthId)-\(entry.day)-\(entry.flightNumber)-12h"
            let twelveHBody = "TG \(displayNumber) \(origin)\u{2192}\(destination) departs tomorrow at \(depTime)"
            scheduleNotification(
                identifier: twelveHId,
                body: twelveHBody,
                fireDate: twelveHBefore
            )

            // 3-hour-before notification
            let threeHBefore = entry.departureDate.addingTimeInterval(-3 * 3600)
            let threeHId = "\(identifierPrefix)\(monthId)-\(entry.day)-\(entry.flightNumber)-3h"
            let threeHBody = "TG \(displayNumber) \(origin)\u{2192}\(destination) departs in 3 hours"
            scheduleNotification(
                identifier: threeHId,
                body: threeHBody,
                fireDate: threeHBefore
            )
        }
    }

    // MARK: - Cancel

    func cancelReminders(for monthId: String) {
        let prefix = "\(identifierPrefix)\(monthId)-"
        center.getPendingNotificationRequests { [weak self] requests in
            let matching = requests
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            self?.center.removePendingNotificationRequests(withIdentifiers: matching)
        }
    }

    func cancelAllReminders() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: - Import Notification

    func scheduleImportNotification(monthName: String, flightCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Roster Imported"
        content.body = "\(monthName): \(flightCount) flight\(flightCount == 1 ? "" : "s") added to your calendar."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)import-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[NotificationService] Import notification error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Swap Notifications

    /// Notify the listing poster that someone wants to swap.
    func notifyNewSwapConversation(listingFlightCode: String, fromName: String) {
        let content = UNMutableNotificationContent()
        content.title = "New Swap Interest"
        content.body = "\(fromName) wants to swap \(listingFlightCode) with you."
        content.sound = .default
        content.categoryIdentifier = "SWAP_CONVERSATION"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)swap-conv-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[NotificationService] Swap conversation notification error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Flight Disruption Alerts

    func scheduleFlightAlert(_ alert: FlightAlert) {
        let content = UNMutableNotificationContent()
        content.title = "Flight \(alert.alertType.displayName)"
        content.body = alert.message
        content.sound = .default
        content.categoryIdentifier = "FLIGHT_ALERT"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)alert-\(alert.id.uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[NotificationService] Flight alert notification error: \(error.localizedDescription)")
            }
        }
    }

    /// Notify the other party about a new chat message.
    func notifyNewSwapMessage(fromName: String, text: String) {
        let content = UNMutableNotificationContent()
        content.title = fromName
        content.body = text
        content.sound = .default
        content.categoryIdentifier = "SWAP_MESSAGE"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)swap-msg-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[NotificationService] Swap message notification error: \(error.localizedDescription)")
            }
        }
    }

    /// Notify both parties that a swap has been confirmed.
    func notifySwapConfirmed(flightCode: String, otherPartyName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Swap Confirmed"
        content.body = "\(flightCode) swap with \(otherPartyName) is confirmed. Check your calendar."
        content.sound = .default
        content.categoryIdentifier = "SWAP_CONFIRMED"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)swap-confirmed-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[NotificationService] Swap confirmed notification error: \(error.localizedDescription)")
            }
        }
    }

    /// Notify the other party that a swap was cancelled.
    func notifySwapCancelled(flightCode: String, cancelledByName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Swap Cancelled"
        content.body = "\(cancelledByName) cancelled the \(flightCode) swap."
        content.sound = .default
        content.categoryIdentifier = "SWAP_CANCELLED"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(identifierPrefix)swap-cancelled-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[NotificationService] Swap cancelled notification error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private func scheduleNotification(identifier: String, body: String, fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Flight Reminder"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier

        let comps = Calendar.roster.dateComponents(
            in: rosterTimeZone,
            from: fireDate
        )
        var triggerComps = DateComponents()
        triggerComps.year = comps.year
        triggerComps.month = comps.month
        triggerComps.day = comps.day
        triggerComps.hour = comps.hour
        triggerComps.minute = comps.minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComps, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error {
                print("[NotificationService] Schedule error for \(identifier): \(error.localizedDescription)")
            }
        }
    }
}
