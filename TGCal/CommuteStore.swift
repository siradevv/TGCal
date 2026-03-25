import Foundation

/// Locally persisted commute records. No Supabase dependency — all data stays on-device.
@MainActor
final class CommuteStore: ObservableObject {

    static let shared = CommuteStore()

    @Published var records: [CommuteRecord] = []

    private init() {
        loadFromDisk()
    }

    // MARK: - CRUD

    func add(_ record: CommuteRecord) {
        records.append(record)
        records.sort { $0.date > $1.date }
        saveToDisk()
    }

    func update(_ record: CommuteRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
            saveToDisk()
        }
    }

    func delete(_ id: UUID) {
        records.removeAll { $0.id == id }
        saveToDisk()
    }

    // MARK: - Summary

    var totalCostTHB: Double {
        records.filter { $0.currency == "THB" }.reduce(0) { $0 + $1.cost }
    }

    var totalMinutes: Int {
        records.reduce(0) { $0 + $1.durationMinutes }
    }

    var totalTrips: Int {
        records.count
    }

    func monthlyRecords(year: Int, month: Int) -> [CommuteRecord] {
        records.filter { record in
            let comps = Calendar.roster.dateComponents([.year, .month], from: record.date)
            return comps.year == year && comps.month == month
        }
    }

    // MARK: - Persistence

    private func saveToDisk() {
        do {
            let url = try storeFileURL()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(records)
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private func loadFromDisk() {
        do {
            let url = try storeFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            let data = try Data(contentsOf: url)
            records = try JSONDecoder().decode([CommuteRecord].self, from: data)
        } catch {
            records = []
        }
    }

    private func storeFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("TGCal", isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) == false {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("commute_records.json", isDirectory: false)
    }
}
