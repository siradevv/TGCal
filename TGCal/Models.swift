import Foundation
import CoreGraphics

let rosterTimeZone = TimeZone(identifier: "Asia/Bangkok") ?? .current

extension Calendar {
    static var roster: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = rosterTimeZone
        return calendar
    }
}

struct OCRLine: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let confidence: Double
    let boundingBox: CGRect
}

struct OCRResult {
    let lines: [OCRLine]

    var strings: [String] {
        lines.map(\.text)
    }

    var averageConfidence: Double {
        guard lines.isEmpty == false else { return 0 }
        return lines.map(\.confidence).reduce(0, +) / Double(lines.count)
    }
}

struct DetectedMonthYear: Equatable {
    let month: Int
    let year: Int

    var displayText: String {
        var comps = DateComponents()
        comps.month = month
        comps.year = year
        let date = Calendar.roster.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
}

struct ParseResult {
    let drafts: [FlightEventDraft]
    let detectedMonthYear: DetectedMonthYear?
}

enum FlightLookupState: String, Hashable {
    case found
    case notFound
    case failed
}

struct FlightLookupRecord: Identifiable, Hashable {
    var id = UUID()
    var serviceDate: Date
    var flightNumber: String
    var origin: String?
    var destination: String?
    var departureTime: String?
    var arrivalTime: String?
    var state: FlightLookupState
    var sourceLabel: String

    var day: Int {
        Calendar.roster.component(.day, from: serviceDate)
    }

    var isDutyRow: Bool {
        flightNumber.isAlphabeticDutyCode
    }

    var listPrimaryText: String {
        if isDutyRow {
            return flightNumber.uppercased()
        }
        return routeText
    }

    var showsCodeBadge: Bool {
        isDutyRow == false
    }

    var flightCode: String {
        if flightNumber.isAlphabeticDutyCode {
            return flightNumber.uppercased()
        }
        let number = flightNumber.strippingLeadingZeros()
        return "TG \(number.isEmpty ? "0" : number)"
    }

    var routeText: String {
        guard let origin, let destination else { return "Route unavailable" }
        return "\(origin) → \(destination)"
    }

    var scheduleText: String {
        switch (departureTime, arrivalTime) {
        case let (.some(dep), .some(arr)):
            if let depMinutes = dep.hhmmMinutes,
               let arrMinutes = arr.hhmmMinutes,
               arrMinutes < depMinutes {
                return "\(dep) - \(arr) (+1d)"
            }
            return "\(dep) - \(arr)"
        case let (.some(dep), .none):
            return "Dep \(dep)"
        case let (.none, .some(arr)):
            return "Arr \(arr)"
        default:
            return "Time unavailable"
        }
    }
}

struct StyledRosterRow: Identifiable, Hashable {
    var id: Int { day }
    let day: Int
    let date: Date
    let weekdayText: String
    let valueText: String
}

struct FlightEventDraft: Identifiable, Hashable {
    var id = UUID()
    var serviceDate: Date
    var flightNumber: String
    var origin: String
    var destination: String
    var departure: Date
    var arrival: Date
    var hasDepartureTime: Bool = true
    var hasArrivalTime: Bool = true
    var confidence: Double
    var rawLines: [String]

    var needsReview: Bool {
        confidence < 0.6
    }

    var displayFlightNumber: String {
        if flightNumber.isAlphabeticDutyCode {
            return flightNumber.uppercased()
        }
        let digits = flightNumber.strippingLeadingZeros()
        return "TG \(digits.isEmpty ? "0" : digits)"
    }

    var title: String {
        if flightNumber.isAlphabeticDutyCode {
            return flightNumber.uppercased()
        }
        return "✈️ \(destination)"
    }

    var routeText: String {
        "\(origin) → \(destination)"
    }

    var confidenceText: String {
        "\(Int((confidence * 100).rounded()))%"
    }

    var timeSummaryText: String {
        if hasDepartureTime && hasArrivalTime {
            return "\(departure.rosterTimeText) - \(arrival.rosterTimeText)"
        }
        if hasDepartureTime {
            return "Dep \(departure.rosterTimeText)"
        }
        if hasArrivalTime {
            return "Arr \(arrival.rosterTimeText)"
        }
        return "Time not set"
    }

    mutating func normalize() {
        if flightNumber.isAlphabeticDutyCode {
            flightNumber = flightNumber.uppercased()

            let filteredOrigin = origin.uppercased().filter { $0.isLetter }
            let filteredDestination = destination.uppercased().filter { $0.isLetter }
            origin = String(filteredOrigin.prefix(3))
            destination = String(filteredDestination.prefix(3))

            let calendar = Calendar.roster
            serviceDate = calendar.startOfDay(for: serviceDate)
            departure = calendar.merging(date: serviceDate, withTimeFrom: departure)
            arrival = calendar.merging(date: serviceDate, withTimeFrom: arrival)

            if hasDepartureTime == false && hasArrivalTime {
                departure = arrival
            }

            if hasArrivalTime == false {
                arrival = departure
            }

            if hasDepartureTime && hasArrivalTime && arrival <= departure {
                arrival = calendar.date(byAdding: .day, value: 1, to: arrival) ?? arrival.addingTimeInterval(24 * 3600)
            }
            return
        }

        let digits = String(flightNumber.filter(\.isNumber).prefix(5))
        flightNumber = digits.strippingLeadingZeros().isEmpty ? "0" : digits.strippingLeadingZeros()

        let filteredOrigin = origin.uppercased().filter { $0.isLetter }
        let filteredDestination = destination.uppercased().filter { $0.isLetter }
        origin = String(filteredOrigin.prefix(3))
        destination = String(filteredDestination.prefix(3))

        if origin.isEmpty { origin = "BKK" }
        if destination.isEmpty { destination = origin }

        // User preference: only keep arrival time for returns to BKK.
        if destination != "BKK" {
            hasArrivalTime = false
        }

        let calendar = Calendar.roster
        serviceDate = calendar.startOfDay(for: serviceDate)

        departure = calendar.merging(date: serviceDate, withTimeFrom: departure)
        arrival = calendar.merging(date: serviceDate, withTimeFrom: arrival)

        if hasDepartureTime == false && hasArrivalTime {
            departure = arrival
        }

        if hasArrivalTime == false {
            arrival = departure
        }

        if hasDepartureTime && hasArrivalTime && arrival <= departure {
            arrival = calendar.date(byAdding: .day, value: 1, to: arrival) ?? arrival.addingTimeInterval(24 * 3600)
        }
    }
}

struct CalendarInsertResult {
    let addedCount: Int
    let skippedDuplicateCount: Int
    let failedCount: Int
}

extension Calendar {
    func merging(date: Date, withTimeFrom source: Date) -> Date {
        let dayComps = dateComponents([.year, .month, .day], from: date)
        let timeComps = dateComponents([.hour, .minute], from: source)

        var merged = DateComponents()
        merged.year = dayComps.year
        merged.month = dayComps.month
        merged.day = dayComps.day
        merged.hour = timeComps.hour
        merged.minute = timeComps.minute

        return self.date(from: merged) ?? date
    }

    func date(on date: Date, hhmm: Int) -> Date? {
        let hour = hhmm / 100
        let minute = hhmm % 100

        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }

        var comps = dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = minute
        return self.date(from: comps)
    }
}

extension DateFormatter {
    static let rosterDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let rosterTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

extension Date {
    var rosterDateText: String {
        DateFormatter.rosterDate.string(from: self)
    }

    var rosterTimeText: String {
        DateFormatter.rosterTime.string(from: self)
    }
}

extension String {
    func strippingLeadingZeros() -> String {
        let trimmed = drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    func paddedFlightNumber(width: Int = 4) -> String {
        let digits = String(filter(\.isNumber))
        let stripped = digits.strippingLeadingZeros()
        if stripped.count >= width {
            return stripped
        }
        return String(repeating: "0", count: max(0, width - stripped.count)) + stripped
    }

    var hhmmMinutes: Int? {
        let digits = String(filter(\.isNumber))
        guard digits.count == 4,
              let hour = Int(digits.prefix(2)),
              let minute = Int(digits.suffix(2)),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }
        return hour * 60 + minute
    }

    var isAlphabeticDutyCode: Bool {
        let upper = uppercased()
        guard (3...10).contains(upper.count) else { return false }
        return upper.allSatisfy { $0 >= "A" && $0 <= "Z" }
    }
}
