import Foundation

enum EarningsCalculatorError: LocalizedError {
    case missingRatesFile
    case invalidRatesData

    var errorDescription: String? {
        switch self {
        case .missingRatesFile:
            return "Could not load earnings rate table."
        case .invalidRatesData:
            return "Earnings rate table is invalid."
        }
    }
}

struct EarningsCalculator {
    private struct RatesCatalogDTO: Decodable {
        let summer: SeasonRatesDTO
        let winter: SeasonRatesDTO
    }

    private struct SeasonRatesDTO: Decodable {
        let singleFlights: [SingleFlightRateDTO]
        let pairings: [PairingRateDTO]
    }

    private struct SingleFlightRateDTO: Decodable {
        let flight: String
        let ppb: Int
    }

    private struct PairingRateDTO: Decodable {
        let flights: [String]
        let ppb: Int
    }

    static func loadRateTables(bundle: Bundle = .main, resourceName: String = "EarningsRates") throws -> [PPBSeason: PPBRateTable] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw EarningsCalculatorError.missingRatesFile
        }

        let data = try Data(contentsOf: url)
        return try loadRateTables(from: data)
    }

    static func loadRateTables(from data: Data) throws -> [PPBSeason: PPBRateTable] {
        let decoder = JSONDecoder()
        let catalog: RatesCatalogDTO

        do {
            catalog = try decoder.decode(RatesCatalogDTO.self, from: data)
        } catch {
            throw EarningsCalculatorError.invalidRatesData
        }

        return [
            .summer: buildTable(for: .summer, from: catalog.summer),
            .winter: buildTable(for: .winter, from: catalog.winter)
        ]
    }

    static func calculate(
        for month: RosterMonthRecord,
        season: PPBSeason,
        rank: PPBRank = .scc,
        tables: [PPBSeason: PPBRateTable]
    ) -> MonthEarningsResult {
        let table = tables[season] ?? PPBRateTable(season: season, ppbByFlight: [:])

        var flightCounts: [String: Int] = [:]
        var firstSeenOrder: [String: Int] = [:]
        var nextOrderIndex = 0

        for day in month.flightsByDay.keys.sorted() {
            for key in month.flightsByDay[day, default: []] {
                guard let detail = resolveDetail(for: key, detailsByFlight: month.detailsByFlight) else {
                    continue
                }

                let rawFlight = detail.flightNumber.isEmpty ? key : detail.flightNumber
                guard let normalizedFlight = normalizeFlightNumber(rawFlight) else {
                    continue
                }

                // Skip secondary pairing flights (counted via the primary flight)
                if table.secondaryPairingFlights.contains(normalizedFlight) {
                    continue
                }

                // TPI tables list outbound sectors; the paired return is outbound + 1.
                // If this flight is a return leg with a known outbound PPB, skip it.
                if table.ppbByFlight[normalizedFlight] == nil,
                   isReturnLeg(normalizedFlight, in: table) {
                    continue
                }

                if firstSeenOrder[normalizedFlight] == nil {
                    firstSeenOrder[normalizedFlight] = nextOrderIndex
                    nextOrderIndex += 1
                }
                flightCounts[normalizedFlight, default: 0] += 1
            }
        }

        let sortedFlights = flightCounts.keys.sorted { lhs, rhs in
            let left = Int(lhs) ?? .max
            let right = Int(rhs) ?? .max
            if left != right { return left < right }
            return lhs < rhs
        }

        let deduction = rank.ppbDeduction
        var lineItems: [EarningsLineItem] = []
        var missingFlights: [String: Int] = [:]

        for flight in sortedFlights {
            let count = flightCounts[flight, default: 0]
            let basePPB = table.ppbByFlight[flight]
            let adjustedPPB = basePPB.map { max(0, $0 - deduction) }
            let subtotal = count * (adjustedPPB ?? 0)

            lineItems.append(
                EarningsLineItem(
                    flightNumber: flight,
                    count: count,
                    ppb: adjustedPPB,
                    subtotal: subtotal
                )
            )

            if basePPB == nil {
                missingFlights[flight] = count
            }
        }

        lineItems.sort { lhs, rhs in
            let leftOrder = firstSeenOrder[lhs.flightNumber] ?? .max
            let rightOrder = firstSeenOrder[rhs.flightNumber] ?? .max
            if leftOrder != rightOrder {
                return leftOrder < rightOrder
            }

            let left = Int(lhs.flightNumber) ?? .max
            let right = Int(rhs.flightNumber) ?? .max
            if left != right { return left < right }
            return lhs.flightNumber < rhs.flightNumber
        }

        let total = lineItems.reduce(0) { $0 + $1.subtotal }

        return MonthEarningsResult(
            season: season,
            monthId: month.id,
            totalTHB: total,
            lineItems: lineItems,
            missingFlights: missingFlights
        )
    }

    private static func buildTable(for season: PPBSeason, from seasonDTO: SeasonRatesDTO) -> PPBRateTable {
        var map: [String: Int] = [:]
        var secondaryFlights: Set<String> = []

        for item in seasonDTO.singleFlights {
            guard let normalized = normalizeFlightNumber(item.flight) else { continue }
            map[normalized] = item.ppb
        }

        for pairing in seasonDTO.pairings {
            let normalizedFlights = pairing.flights.compactMap { normalizeFlightNumber($0) }
            guard let primary = normalizedFlights.first else { continue }

            // Only the first flight in the pairing gets the PPB entry.
            // All others are secondary — they'll be skipped during calculation.
            map[primary] = pairing.ppb

            for flight in normalizedFlights.dropFirst() {
                secondaryFlights.insert(flight)
                map.removeValue(forKey: flight)
            }
        }

        return PPBRateTable(season: season, ppbByFlight: map, secondaryPairingFlights: secondaryFlights)
    }

    private static func resolveDetail(
        for key: String,
        detailsByFlight: [String: FlightLookupRecord]
    ) -> FlightLookupRecord? {
        if let exact = detailsByFlight[key] {
            return exact
        }

        let normalized = key.strippingLeadingZeros()
        if let normalizedDetail = detailsByFlight[normalized] {
            return normalizedDetail
        }

        return nil
    }

    private static func normalizeFlightNumber(_ raw: String) -> String? {
        let digits = String(raw.filter(\.isNumber))
        guard digits.isEmpty == false else { return nil }

        let normalized = digits.strippingLeadingZeros()
        if normalized == "0" {
            return nil
        }

        return normalized
    }

    private static func isReturnLeg(_ normalizedFlight: String, in table: PPBRateTable) -> Bool {
        guard let flightNumber = Int(normalizedFlight), flightNumber > 1 else {
            return false
        }

        let outboundCandidate = String(flightNumber - 1)
        return table.ppbByFlight[outboundCandidate] != nil
    }
}
