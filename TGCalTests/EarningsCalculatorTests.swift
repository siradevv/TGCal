import XCTest
@testable import TGCal

final class EarningsCalculatorTests: XCTestCase {
    func testLoadRateTablesFromDataLoadsBothSeasons() throws {
        let data = Data(sampleRatesJSON.utf8)
        let tables = try EarningsCalculator.loadRateTables(from: data)

        XCTAssertEqual(tables[.summer]?.ppbByFlight["560"], 3984)
        XCTAssertEqual(tables[.winter]?.ppbByFlight["560"], 4000)
    }

    func testWinterPairingsOverrideSingles() throws {
        let data = Data(sampleRatesJSON.utf8)
        let tables = try EarningsCalculator.loadRateTables(from: data)
        let winter = try XCTUnwrap(tables[.winter])

        XCTAssertEqual(winter.ppbByFlight["102"], 5938)
        XCTAssertEqual(winter.ppbByFlight["103"], 5938)
    }

    func testCalculateCountsEachOccurrenceAndExcludesDutyRows() throws {
        let tables = try EarningsCalculator.loadRateTables(from: Data(sampleRatesJSON.utf8))
        let month = makeMonthRecord()

        let result = EarningsCalculator.calculate(for: month, season: .summer, tables: tables)

        XCTAssertEqual(result.totalTHB, 7968)
        XCTAssertEqual(result.lineItems.first(where: { $0.flightNumber == "560" })?.count, 2)
        XCTAssertNil(result.lineItems.first(where: { $0.flightNumber == "CHMSBA" }))
    }

    func testCalculateMarksMissingFlightsAsZeroSubtotal() throws {
        let tables = try EarningsCalculator.loadRateTables(from: Data(sampleRatesJSON.utf8))
        let month = makeMonthRecord()

        let result = EarningsCalculator.calculate(for: month, season: .summer, tables: tables)
        let missing = try XCTUnwrap(result.lineItems.first(where: { $0.flightNumber == "999" }))

        XCTAssertEqual(missing.ppb, nil)
        XCTAssertEqual(missing.subtotal, 0)
        XCTAssertEqual(result.missingFlights["999"], 1)
    }

    func testCalculateSkipsReturnFlightWhenOutboundHasRate() throws {
        let tables = try EarningsCalculator.loadRateTables(from: Data(sampleRatesJSON.utf8))
        let month = makeMonthRecord()

        let result = EarningsCalculator.calculate(for: month, season: .summer, tables: tables)

        XCTAssertNil(result.lineItems.first(where: { $0.flightNumber == "561" }))
        XCTAssertNil(result.missingFlights["561"])
    }

    func testCalculateTotalMathWithMixedKnownAndMissing() throws {
        let tables = try EarningsCalculator.loadRateTables(from: Data(sampleRatesJSON.utf8))
        let month = makeMonthRecord()

        let result = EarningsCalculator.calculate(for: month, season: .winter, tables: tables)

        // winter sample maps 560 => 4000, unknown 999 => 0
        XCTAssertEqual(result.totalTHB, 8000)
    }

    func testFlightBreakdownIsSortedByFirstFlightDateOrder() throws {
        let tables = try EarningsCalculator.loadRateTables(from: Data(sampleRatesJSON.utf8))
        let month = makeDateOrderedMonthRecord()

        let result = EarningsCalculator.calculate(for: month, season: .summer, tables: tables)
        let orderedFlights = result.lineItems.map(\.flightNumber)

        XCTAssertEqual(orderedFlights, ["900", "560"])
    }

    private func makeMonthRecord() -> RosterMonthRecord {
        let serviceDate = Date(timeIntervalSince1970: 1_709_251_200) // 2024-03-01 00:00:00 +0000

        let details: [String: FlightLookupRecord] = [
            "560": FlightLookupRecord(
                serviceDate: serviceDate,
                flightNumber: "560",
                origin: "BKK",
                destination: "HAN",
                departureTime: "0745",
                arrivalTime: "0935",
                state: .found,
                sourceLabel: "Schedule"
            ),
            "0560": FlightLookupRecord(
                serviceDate: serviceDate,
                flightNumber: "560",
                origin: "BKK",
                destination: "HAN",
                departureTime: "0745",
                arrivalTime: "0935",
                state: .found,
                sourceLabel: "Schedule"
            ),
            "561": FlightLookupRecord(
                serviceDate: serviceDate,
                flightNumber: "561",
                origin: "HAN",
                destination: "BKK",
                departureTime: "1035",
                arrivalTime: "1225",
                state: .found,
                sourceLabel: "Schedule"
            ),
            "__DUTY_3_CHMSBA": FlightLookupRecord(
                serviceDate: serviceDate,
                flightNumber: "CHMSBA",
                origin: "",
                destination: "",
                departureTime: "0430",
                arrivalTime: "1630",
                state: .found,
                sourceLabel: "Schedule"
            ),
            "999": FlightLookupRecord(
                serviceDate: serviceDate,
                flightNumber: "999",
                origin: "BKK",
                destination: "ZZZ",
                departureTime: "1200",
                arrivalTime: "1400",
                state: .found,
                sourceLabel: "Schedule"
            )
        ]

        return RosterMonthRecord(
            id: "2026-03",
            year: 2026,
            month: 3,
            createdAt: Date(),
            flightsByDay: [
                1: ["560", "0560", "561", "__DUTY_3_CHMSBA", "999"]
            ],
            detailsByFlight: details
        )
    }

    private var sampleRatesJSON: String {
        """
        {
          "summer": {
            "singleFlights": [
              { "flight": "560", "ppb": 3984 },
              { "flight": "900", "ppb": 14558 }
            ],
            "pairings": []
          },
          "winter": {
            "singleFlights": [
              { "flight": "560", "ppb": 4000 },
              { "flight": "102", "ppb": 3550 }
            ],
            "pairings": [
              { "flights": ["102", "103"], "ppb": 5938 }
            ]
          }
        }
        """
    }

    private func makeDateOrderedMonthRecord() -> RosterMonthRecord {
        let serviceDate = Date(timeIntervalSince1970: 1_709_251_200)
        let details: [String: FlightLookupRecord] = [
            "900": FlightLookupRecord(
                serviceDate: serviceDate,
                flightNumber: "900",
                origin: "BKK",
                destination: "LHR",
                departureTime: "0100",
                arrivalTime: "0700",
                state: .found,
                sourceLabel: "Schedule"
            ),
            "560": FlightLookupRecord(
                serviceDate: serviceDate,
                flightNumber: "560",
                origin: "BKK",
                destination: "HAN",
                departureTime: "0745",
                arrivalTime: "0935",
                state: .found,
                sourceLabel: "Schedule"
            )
        ]

        return RosterMonthRecord(
            id: "2026-03",
            year: 2026,
            month: 3,
            createdAt: Date(),
            flightsByDay: [
                1: ["900"],
                3: ["560"]
            ],
            detailsByFlight: details
        )
    }
}
