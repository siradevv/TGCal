import XCTest
@testable import TGCal

final class TGCalTests: XCTestCase {
    func testStrippingLeadingZeros() {
        XCTAssertEqual("0007".strippingLeadingZeros(), "7")
        XCTAssertEqual("0".strippingLeadingZeros(), "0")
        XCTAssertEqual("001230".strippingLeadingZeros(), "1230")
    }

    func testPaddedFlightNumber() {
        XCTAssertEqual("7".paddedFlightNumber(), "0007")
        XCTAssertEqual("0560".paddedFlightNumber(), "0560")
        XCTAssertEqual("12345".paddedFlightNumber(), "12345")
    }

    func testHHmmMinutes() {
        XCTAssertEqual("0745".hhmmMinutes, 465)
        XCTAssertEqual("23:59".hhmmMinutes, 1439)
        XCTAssertNil("2460".hhmmMinutes)
    }

    func testFlightLookupRecordDutyDisplayHelpers() {
        let now = Date()
        let record = FlightLookupRecord(
            serviceDate: now,
            flightNumber: "CHMSBA",
            origin: "",
            destination: "",
            departureTime: "0430",
            arrivalTime: "1630",
            state: .found,
            sourceLabel: "Schedule"
        )

        XCTAssertTrue(record.isDutyRow)
        XCTAssertFalse(record.showsCodeBadge)
        XCTAssertEqual(record.listPrimaryText, "CHMSBA")
    }

    func testFlightLookupRecordFlightDisplayHelpers() {
        let now = Date()
        let record = FlightLookupRecord(
            serviceDate: now,
            flightNumber: "560",
            origin: "BKK",
            destination: "HAN",
            departureTime: "0745",
            arrivalTime: "0935",
            state: .found,
            sourceLabel: "Schedule"
        )

        XCTAssertFalse(record.isDutyRow)
        XCTAssertTrue(record.showsCodeBadge)
        XCTAssertEqual(record.listPrimaryText, "BKK → HAN")
    }

    func testResolveScheduleDetailFallsBackToNormalizedFlightKey() {
        let details: [String: ScheduleFlightDetail] = [
            "560": ScheduleFlightDetail(
                flightNumber: "560",
                origin: "BKK",
                destination: "HAN",
                departureTime: "0745",
                arrivalTime: "0935"
            )
        ]

        let resolved = ContentView.resolveScheduleDetail(
            for: "0560",
            detailsByFlight: details
        )

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.key, "560")
        XCTAssertEqual(resolved?.detail.flightNumber, "560")
    }

    func testResolveScheduleDetailUsesRawDutyKey() {
        let dutyKey = "__DUTY_3_CHMSBA"
        let details: [String: ScheduleFlightDetail] = [
            dutyKey: ScheduleFlightDetail(
                flightNumber: "CHMSBA",
                origin: "",
                destination: "",
                departureTime: "0430",
                arrivalTime: "1630"
            )
        ]

        let resolved = ContentView.resolveScheduleDetail(
            for: dutyKey,
            detailsByFlight: details
        )

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.key, dutyKey)
        XCTAssertEqual(resolved?.detail.flightNumber, "CHMSBA")
    }

    func testFlightDraftNormalizeAdjustsArrivalAcrossMidnight() {
        var comps = DateComponents()
        comps.calendar = .roster
        comps.timeZone = rosterTimeZone
        comps.year = 2026
        comps.month = 2
        comps.day = 20
        comps.hour = 0
        comps.minute = 0
        let serviceDate = comps.date!

        var departureComps = comps
        departureComps.hour = 23
        departureComps.minute = 15
        let departure = departureComps.date!

        var arrivalComps = comps
        arrivalComps.hour = 1
        arrivalComps.minute = 5
        let arrival = arrivalComps.date!

        var draft = FlightEventDraft(
            serviceDate: serviceDate,
            flightNumber: "0560",
            origin: "HND",
            destination: "BKK",
            departure: departure,
            arrival: arrival,
            hasDepartureTime: true,
            hasArrivalTime: true,
            confidence: 1,
            rawLines: []
        )

        draft.normalize()

        XCTAssertGreaterThan(draft.arrival, draft.departure)
        XCTAssertEqual(Calendar.roster.component(.day, from: draft.arrival), 21)
    }

    func testFlightDraftNormalizeRemovesArrivalForNonBKKDestination() {
        var comps = DateComponents()
        comps.calendar = .roster
        comps.timeZone = rosterTimeZone
        comps.year = 2026
        comps.month = 2
        comps.day = 20
        comps.hour = 10
        comps.minute = 30
        let departure = comps.date!

        var draft = FlightEventDraft(
            serviceDate: departure,
            flightNumber: "0560",
            origin: "BKK",
            destination: "SIN",
            departure: departure,
            arrival: departure.addingTimeInterval(2_400),
            hasDepartureTime: true,
            hasArrivalTime: true,
            confidence: 1,
            rawLines: []
        )

        draft.normalize()

        XCTAssertFalse(draft.hasArrivalTime)
        XCTAssertEqual(draft.arrival, draft.departure)
    }

    func testSchedulePDFExtractsStandbyDutyCodeForMarch3() async throws {
        let pdfURL = URL(fileURLWithPath: "/Users/sira27/Downloads/individual-report.pdf")
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            throw XCTSkip("PDF not found at \(pdfURL.path)")
        }

        let pdfData = try Data(contentsOf: pdfURL)
        let service = ScheduleSlipService()
        let parsed = try await service.parse(pdfData: pdfData, fallbackMonth: 3, fallbackYear: 2026)

        guard let day3Entries = parsed.flightsByDay[3], day3Entries.isEmpty == false else {
            XCTFail("Expected entries on March 3")
            return
        }

        let dutyEntries = day3Entries.filter { $0.hasPrefix("__DUTY_") }
        XCTAssertEqual(dutyEntries.count, 1)

        guard let dutyKey = dutyEntries.first,
              let detail = parsed.detailsByFlight[dutyKey] else {
            XCTFail("Expected standby detail for March 3")
            return
        }

        XCTAssertEqual(detail.flightNumber, "CHMSBA")
        XCTAssertEqual(detail.origin, "")
        XCTAssertEqual(detail.destination, "")
        XCTAssertEqual(detail.departureTime, "0430")
        XCTAssertEqual(detail.arrivalTime, "1630")

        let invalidDutyCodes = parsed.detailsByFlight.values.filter {
            $0.flightNumber == "BKK" && $0.origin.isEmpty && $0.destination.isEmpty
        }
        XCTAssertTrue(invalidDutyCodes.isEmpty, "Airport code should never be used as duty code")
    }

    func testSchedulePDFExtractsExpectedMarchMapping() async throws {
        let pdfURL = URL(fileURLWithPath: "/Users/sira27/Downloads/individual-report.pdf")
        guard FileManager.default.fileExists(atPath: pdfURL.path) else {
            throw XCTSkip("PDF not found at \(pdfURL.path)")
        }

        let pdfData = try Data(contentsOf: pdfURL)
        let service = ScheduleSlipService()
        let parsed = try await service.parse(pdfData: pdfData, fallbackMonth: 3, fallbackYear: 2026)

        func dayFlights(_ day: Int) -> [String] {
            let entries = parsed.flightsByDay[day] ?? []
            return entries.compactMap { key in
                parsed.detailsByFlight[key]?.flightNumber
            }
        }

        XCTAssertEqual(Set(dayFlights(1)), Set(["560", "561"]))
        XCTAssertEqual(Set(dayFlights(3)), Set(["CHMSBA"]))
        XCTAssertEqual(Set(dayFlights(8)), Set(["660"]))
        XCTAssertEqual(Set(dayFlights(10)), Set(["661"]))
        XCTAssertEqual(Set(dayFlights(11)), Set(["325"]))
        XCTAssertEqual(Set(dayFlights(12)), Set(["326"]))
        XCTAssertEqual(Set(dayFlights(14)), Set(["614", "615"]))
        XCTAssertEqual(Set(dayFlights(20)), Set(["401"]))
        XCTAssertEqual(Set(dayFlights(21)), Set(["402"]))
        XCTAssertEqual(Set(dayFlights(23)), Set(["916"]))
        XCTAssertEqual(Set(dayFlights(24)), Set(["917"]))
        XCTAssertEqual(Set(dayFlights(29)), Set(["602"]))
        XCTAssertEqual(Set(dayFlights(30)), Set(["603"]))
        XCTAssertTrue(dayFlights(19).isEmpty)
        XCTAssertTrue(dayFlights(28).isEmpty)
    }
}
