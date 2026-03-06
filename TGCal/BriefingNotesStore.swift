import Foundation

enum BriefingNotesStore {
    static func hasNote(for flightID: String) -> Bool {
        let trimmed = note(for: flightID)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty == false
    }

    static func note(for flightID: String) -> String? {
        storedNotes()[flightID]
    }

    static func save(note: String, for flightID: String) {
        var notes = storedNotes()
        notes[flightID] = note
        UserDefaults.standard.set(notes, forKey: storageKey)
    }

    private static func storedNotes() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    private static let storageKey = "overview.briefingNotesByFlightID"
}
