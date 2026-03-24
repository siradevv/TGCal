import Foundation
import WidgetKit

struct NextFlightEntry: TimelineEntry {
    let date: Date
    let flight: NextFlightSnapshot?
}

struct NextFlightSnapshot: Codable {
    let flightCode: String
    let originCode: String
    let destinationCode: String
    let departureTime: String?
    let departureDate: Date
    let destinationCity: String
    let countryCode: String

    var routeText: String {
        "\(originCode) \u{2192} \(destinationCode)"
    }

    var relativeDateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(departureDate) {
            return "Today"
        } else if calendar.isDateInTomorrow(departureDate) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, d MMM"
            return formatter.string(from: departureDate)
        }
    }

    var departureTimeText: String {
        guard let time = departureTime else { return "--:--" }
        return time
    }

    var flagEmoji: String {
        let uppercased = countryCode.uppercased()
        guard uppercased.count == 2 else { return "" }
        var scalars = String.UnicodeScalarView()
        let base: UInt32 = 127397
        for scalar in uppercased.unicodeScalars {
            guard let flagScalar = UnicodeScalar(base + scalar.value) else { return "" }
            scalars.append(flagScalar)
        }
        return String(scalars)
    }
}
