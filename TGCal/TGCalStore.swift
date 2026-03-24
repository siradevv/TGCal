import Foundation

struct RosterMonthRecord: Codable, Identifiable, Equatable {
    let id: String
    let year: Int
    let month: Int
    let createdAt: Date
    let flightsByDay: [Int: [String]]
    let detailsByFlight: [String: FlightLookupRecord]

    private enum CodingKeys: String, CodingKey {
        case id
        case year
        case month
        case createdAt
        case flightsByDay
        case detailsByFlight
    }

    init(
        id: String,
        year: Int,
        month: Int,
        createdAt: Date,
        flightsByDay: [Int: [String]],
        detailsByFlight: [String: FlightLookupRecord]
    ) {
        self.id = id
        self.year = year
        self.month = month
        self.createdAt = createdAt
        self.flightsByDay = flightsByDay
        self.detailsByFlight = detailsByFlight
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        year = try container.decode(Int.self, forKey: .year)
        month = try container.decode(Int.self, forKey: .month)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        flightsByDay = try container.decode([Int: [String]].self, forKey: .flightsByDay)

        let codableMap = try container.decode([String: FlightLookupRecordCodable].self, forKey: .detailsByFlight)
        detailsByFlight = codableMap.mapValues { $0.record }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(year, forKey: .year)
        try container.encode(month, forKey: .month)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(flightsByDay, forKey: .flightsByDay)

        let codableMap = detailsByFlight.mapValues(FlightLookupRecordCodable.init)
        try container.encode(codableMap, forKey: .detailsByFlight)
    }
}

struct TGCalStoreState: Codable {
    var activeMonthId: String?
    var months: [RosterMonthRecord]
}

@MainActor
final class TGCalStore: ObservableObject {
    @Published var activeMonthId: String?
    @Published var months: [RosterMonthRecord]

    var activeMonth: RosterMonthRecord? {
        months.first(where: { $0.id == activeMonthId })
    }

    init() {
        activeMonthId = nil
        months = []
        loadFromDisk()
    }

    func upsertMonth(_ record: RosterMonthRecord) {
        if let existingIndex = months.firstIndex(where: { $0.id == record.id }) {
            months[existingIndex] = record
        } else {
            months.append(record)
        }
        activeMonthId = record.id
        saveToDisk()
        WidgetDataService.updateNextFlight(from: months)
        NotificationService.shared.scheduleReminders(for: record)
    }

    func setActiveMonth(_ id: String?) {
        activeMonthId = id
        saveToDisk()
    }

    func loadFromDisk() {
        do {
            let url = try storeFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }

            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(TGCalStoreState.self, from: data)
            activeMonthId = decoded.activeMonthId
            months = decoded.months
        } catch {
            activeMonthId = nil
            months = []
        }
    }

    func saveToDisk() {
        do {
            let state = TGCalStoreState(activeMonthId: activeMonthId, months: months)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)

            let url = try storeFileURL()
            try data.write(to: url, options: [.atomic])
        } catch {
            return
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

        return directory.appendingPathComponent("tgcal_store.json", isDirectory: false)
    }
}

private struct FlightLookupRecordCodable: Codable, Equatable {
    let id: UUID
    let serviceDate: Date
    let flightNumber: String
    let origin: String?
    let destination: String?
    let departureTime: String?
    let arrivalTime: String?
    let stateRawValue: String
    let sourceLabel: String

    init(_ record: FlightLookupRecord) {
        id = record.id
        serviceDate = record.serviceDate
        flightNumber = record.flightNumber
        origin = record.origin
        destination = record.destination
        departureTime = record.departureTime
        arrivalTime = record.arrivalTime
        stateRawValue = record.state.rawValue
        sourceLabel = record.sourceLabel
    }

    var record: FlightLookupRecord {
        FlightLookupRecord(
            id: id,
            serviceDate: serviceDate,
            flightNumber: flightNumber,
            origin: origin,
            destination: destination,
            departureTime: departureTime,
            arrivalTime: arrivalTime,
            state: FlightLookupState(rawValue: stateRawValue) ?? .found,
            sourceLabel: sourceLabel
        )
    }
}
