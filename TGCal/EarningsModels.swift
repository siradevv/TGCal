import Foundation

enum PPBSeason: String, CaseIterable, Identifiable, Codable {
    case summer
    case winter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .summer: return "Summer"
        case .winter: return "Winter"
        }
    }
}

struct PPBRateTable: Equatable {
    var season: PPBSeason
    var ppbByFlight: [String: Int]
}

struct EarningsLineItem: Identifiable, Equatable {
    let id = UUID()
    let flightNumber: String
    let count: Int
    let ppb: Int?
    let subtotal: Int
}

struct MonthEarningsResult: Equatable {
    let season: PPBSeason
    let monthId: String
    let totalTHB: Int
    let lineItems: [EarningsLineItem]
    let missingFlights: [String: Int]
}
