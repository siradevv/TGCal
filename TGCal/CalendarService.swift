import Foundation
import EventKit
import UIKit

enum CalendarServiceError: LocalizedError {
    case noWritableCalendar
    case accessDenied
    case createCalendarFailed

    var errorDescription: String? {
        switch self {
        case .noWritableCalendar:
            return "No writable calendar was found on this iPhone."
        case .accessDenied:
            return "Calendar access is denied. Please enable access in Settings."
        case .createCalendarFailed:
            return "Could not create a new calendar."
        }
    }
}

@MainActor
final class CalendarService: ObservableObject {
    private let maxCalendarNameLength = 60
    private let tgCalImportedNote = "Imported by TGCal"

    private let eventStore = EKEventStore()
    private var hasPresentedSettingsAlert = false

    func authorizationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    func requestCalendarAccess() async throws -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)

        if status == .fullAccess || status == .writeOnly {
            hasPresentedSettingsAlert = false
            return true
        }

        if status == .notDetermined {
            let granted = try await eventStore.requestFullAccessToEvents()
            if granted {
                hasPresentedSettingsAlert = false
                return true
            }
            presentSettingsRedirectAlertIfNeeded()
            return false
        }

        presentSettingsRedirectAlertIfNeeded()
        return false
    }

    // Backward-compatible call site used by ContentView.
    func requestAccessIfNeeded() async throws -> Bool {
        try await requestCalendarAccess()
    }

    func writableCalendars() -> [EKCalendar] {
        guard hasCalendarReadWriteAccess else {
            return []
        }

        return eventStore
            .calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func defaultCalendarIdentifier() -> String? {
        guard hasCalendarReadWriteAccess else {
            return nil
        }

        if let defaultCalendar = eventStore.defaultCalendarForNewEvents,
           defaultCalendar.allowsContentModifications {
            return defaultCalendar.calendarIdentifier
        }

        return eventStore
            .calendars(for: .event)
            .first(where: { $0.allowsContentModifications })?
            .calendarIdentifier
    }

    func createCalendar(named name: String) throws -> EKCalendar {
        guard hasCalendarReadWriteAccess else {
            presentSettingsRedirectAlertIfNeeded()
            throw CalendarServiceError.accessDenied
        }

        let trimmed = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let sanitizedName = String(trimmed.prefix(maxCalendarNameLength))

        guard sanitizedName.isEmpty == false else {
            throw CalendarServiceError.createCalendarFailed
        }

        guard let source = preferredCalendarSource() else {
            throw CalendarServiceError.noWritableCalendar
        }

        let calendar = EKCalendar(for: .event, eventStore: eventStore)
        calendar.title = sanitizedName
        calendar.source = source

        do {
            try eventStore.saveCalendar(calendar, commit: true)
            return calendar
        } catch {
            throw CalendarServiceError.createCalendarFailed
        }
    }

    func addEvents(
        from drafts: [FlightEventDraft],
        to selectedCalendarIdentifier: String?,
        replaceTGCalEventsInMonth monthScope: CalendarMonthScope? = nil
    ) throws -> CalendarInsertResult {
        guard hasCalendarReadWriteAccess else {
            presentSettingsRedirectAlertIfNeeded()
            throw CalendarServiceError.accessDenied
        }

        let targetCalendar = resolvedTargetCalendar(selectedCalendarIdentifier: selectedCalendarIdentifier)
        guard let targetCalendar else {
            throw CalendarServiceError.noWritableCalendar
        }

        var removed = 0
        var added = 0
        var skippedDuplicates = 0
        var failed = 0

        var importedKeys = Set<String>()
        var dayCache: [Date: [EKEvent]] = [:]

        do {
            if let monthScope {
                removed = try removeImportedTGCalEvents(in: monthScope, from: targetCalendar)
            }

            for originalDraft in drafts {
                var draft = originalDraft
                draft.normalize()

                let dayStart = Calendar.roster.startOfDay(for: draft.departure)
                let dayEnd = Calendar.roster.date(byAdding: .day, value: 1, to: dayStart) ?? draft.departure.addingTimeInterval(24 * 3600)

                if dayCache[dayStart] == nil {
                    let predicate = eventStore.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: [targetCalendar])
                    dayCache[dayStart] = eventStore.events(matching: predicate)
                }

                let title = draft.title
                let key = duplicateKey(title: title, startDate: draft.departure)

                if importedKeys.contains(key) {
                    skippedDuplicates += 1
                    continue
                }

                if let sameDayEvents = dayCache[dayStart],
                   hasDuplicate(
                    title: title,
                    startDate: draft.departure,
                    events: sameDayEvents,
                    ignoreImportedTGCal: monthScope != nil
                   ) {
                    skippedDuplicates += 1
                    continue
                }

                let event = EKEvent(eventStore: eventStore)
                event.calendar = targetCalendar
                event.title = title
                event.startDate = draft.departure
                event.endDate = draft.arrival
                event.timeZone = rosterTimeZone
                event.location = draft.destination
                event.notes = tgCalImportedNote

                do {
                    try eventStore.save(event, span: .thisEvent, commit: false)
                    dayCache[dayStart, default: []].append(event)
                    importedKeys.insert(key)
                    added += 1
                } catch {
                    failed += 1
                }
            }

            if removed > 0 || added > 0 {
                try eventStore.commit()
            }
        } catch {
            eventStore.reset()
            throw error
        }

        return CalendarInsertResult(
            removedCount: removed,
            addedCount: added,
            skippedDuplicateCount: skippedDuplicates,
            failedCount: failed
        )
    }

    private var hasCalendarReadWriteAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .fullAccess || status == .writeOnly
    }

    private func hasDuplicate(
        title: String,
        startDate: Date,
        events: [EKEvent],
        ignoreImportedTGCal: Bool = false
    ) -> Bool {
        for event in events {
            if ignoreImportedTGCal, isImportedByTGCal(event) {
                continue
            }
            guard event.title == title else { continue }
            if abs(event.startDate.timeIntervalSince(startDate)) <= 5 * 60 {
                return true
            }
        }
        return false
    }

    private func duplicateKey(title: String, startDate: Date) -> String {
        let roundedWindow = Int(startDate.timeIntervalSince1970 / (5 * 60))
        return "\(title)|\(roundedWindow)"
    }

    private func removeImportedTGCalEvents(in monthScope: CalendarMonthScope, from calendar: EKCalendar) throws -> Int {
        guard let monthInterval = dateInterval(for: monthScope) else { return 0 }

        let predicate = eventStore.predicateForEvents(
            withStart: monthInterval.start,
            end: monthInterval.end,
            calendars: [calendar]
        )

        let existingEvents = eventStore.events(matching: predicate)
        var removedCount = 0

        for event in existingEvents where isImportedByTGCal(event) {
            try eventStore.remove(event, span: .thisEvent, commit: false)
            removedCount += 1
        }

        return removedCount
    }

    private func dateInterval(for monthScope: CalendarMonthScope) -> DateInterval? {
        var components = DateComponents()
        components.calendar = Calendar.roster
        components.timeZone = rosterTimeZone
        components.year = monthScope.year
        components.month = monthScope.month
        components.day = 1

        guard let start = Calendar.roster.date(from: components),
              let end = Calendar.roster.date(byAdding: .month, value: 1, to: start) else {
            return nil
        }

        return DateInterval(start: start, end: end)
    }

    private func isImportedByTGCal(_ event: EKEvent) -> Bool {
        (event.notes ?? "").contains(tgCalImportedNote)
    }

    private func resolvedTargetCalendar(selectedCalendarIdentifier: String?) -> EKCalendar? {
        let writable = eventStore
            .calendars(for: .event)
            .filter { $0.allowsContentModifications }

        let defaultCalendar = eventStore.defaultCalendarForNewEvents
        let targetCalendar = writable.first { $0.calendarIdentifier == selectedCalendarIdentifier }
            ?? (defaultCalendar?.allowsContentModifications == true ? defaultCalendar : nil)
            ?? writable.first

        return targetCalendar
    }

    private func preferredCalendarSource() -> EKSource? {
        if let source = eventStore.defaultCalendarForNewEvents?.source {
            return source
        }

        let sources = eventStore.sources

        if let local = sources.first(where: { $0.sourceType == .local }) {
            return local
        }

        if let calDAV = sources.first(where: { $0.sourceType == .calDAV }) {
            return calDAV
        }

        if let exchange = sources.first(where: { $0.sourceType == .exchange }) {
            return exchange
        }

        return sources.first
    }

    private func presentSettingsRedirectAlertIfNeeded() {
        guard hasPresentedSettingsAlert == false else { return }
        hasPresentedSettingsAlert = true

        guard let presenter = topViewController() else { return }

        let alert = UIAlertController(
            title: "Calendar Access Needed",
            message: "Enable calendar access in Settings to add flights.",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "Not now", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            guard let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) else {
                return
            }
            UIApplication.shared.open(url)
        })

        presenter.present(alert, animated: true)
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })

        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }

        return top
    }
}
