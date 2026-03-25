import Foundation
import PDFKit
import UIKit

enum ScheduleSlipServiceError: LocalizedError {
    case invalidDocument
    case noPages
    case tooManyPages(maxPages: Int)
    case couldNotRenderPage
    case noFlightDetailsDetected
    case noRosterFlightsDetected

    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return "Could not read the selected PDF."
        case .noPages:
            return "The selected PDF does not contain any pages."
        case let .tooManyPages(maxPages):
            return "PDF has too many pages. Please import a roster PDF with up to \(maxPages) pages."
        case .couldNotRenderPage:
            return "Could not render the schedule page for parsing."
        case .noFlightDetailsDetected:
            return "Could not detect flight details in this schedule source."
        case .noRosterFlightsDetected:
            return "Could not detect day-by-day flight numbers in this schedule source."
        }
    }
}

struct ScheduleFlightDetail: Hashable {
    let flightNumber: String
    let origin: String
    let destination: String
    let departureTime: String
    let arrivalTime: String
}

struct ScheduleSlipParseResult {
    let month: Int
    let year: Int
    let flightsByDay: [Int: [String]]
    let detailsByFlight: [String: ScheduleFlightDetail]
}

struct ScheduleSlipService {
    private static let maxPDFPages = 20
    private static let maxTextExtractionPages = 5
    private static let maxRenderDimension: CGFloat = 4096
    private static let maxRenderPixels: CGFloat = 28_000_000
    private static let excludedDutyTokens: Set<String> = [
        "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT",
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "SEPT", "OCT", "NOV", "DEC",
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER",
        "DATE", "DUTY", "FLT", "DEP", "ARR", "REMARK", "TG", "BLOCK", "BLOCKTIME"
    ]

    private struct DayHeader {
        let day: Int
        let weekday: Int?
        let x: CGFloat
        let y: CGFloat
    }

    private struct PDFToken {
        let text: String
        let boundingBox: CGRect

        var x: CGFloat { boundingBox.midX }
        var y: CGFloat { boundingBox.midY }
    }

    private struct FlightGridHit {
        let day: Int
        let flightNumber: String
        let y: CGFloat
        let x: CGFloat
        let tokenIndex: Int
    }

    private struct OCRDepartureCandidate {
        let flightNumber: String
        let origin: String
        let departureTime: String
        let x: CGFloat
        let y: CGFloat
    }

    private struct OCRArrivalCandidate {
        let destination: String
        let arrivalTime: String
        let x: CGFloat
        let y: CGFloat
    }

    private enum OCRGridTokenKind {
        case number
        case airport
        case time
        case duty
    }

    private struct OCRGridToken {
        let day: Int
        let text: String
        let x: CGFloat
        let y: CGFloat
        let kind: OCRGridTokenKind
    }

    private struct OCRFlightRowBundle {
        let fltY: CGFloat
        let depY: CGFloat
        let arrY: CGFloat
    }

    private struct OCRRowSlot {
        var flightNumber: String?
        var origin: String?
        var departureTime: String?
        var destination: String?
        var arrivalTime: String?

        var isEmpty: Bool {
            flightNumber == nil &&
            origin == nil &&
            departureTime == nil &&
            destination == nil &&
            arrivalTime == nil
        }
    }

    private struct OCRPendingDetail {
        let day: Int
        let flightNumber: String
        let origin: String
        let departureTime: String
        let destination: String?
        let arrivalTime: String?
    }

    private let ocrService: OCRService
    private let flightNumberParser: FlightNumberRosterParser

    init(
        ocrService: OCRService = OCRService(),
        flightNumberParser: FlightNumberRosterParser = FlightNumberRosterParser()
    ) {
        self.ocrService = ocrService
        self.flightNumberParser = flightNumberParser
    }

    func parse(
        pdfData: Data,
        fallbackMonth: Int,
        fallbackYear: Int
    ) async throws -> ScheduleSlipParseResult {
        guard let document = PDFDocument(data: pdfData) else {
            throw ScheduleSlipServiceError.invalidDocument
        }

        guard document.pageCount > 0 else {
            throw ScheduleSlipServiceError.noPages
        }

        guard document.pageCount <= Self.maxPDFPages else {
            throw ScheduleSlipServiceError.tooManyPages(maxPages: Self.maxPDFPages)
        }

        let rawText = extractText(from: document)

        guard let firstPage = document.page(at: 0) else {
            throw ScheduleSlipServiceError.noPages
        }

        let monthYear = detectMonthYear(in: rawText)
            ?? (month: fallbackMonth, year: fallbackYear)

        // Try position-based parsing first (handles Thai Airways roster layout correctly)
        var detailsByFlight = parseFlightDetailsFromPDFPage(page: firstPage, month: monthYear.month, year: monthYear.year)

        // Fallback to regex-based parsing if position-based found nothing
        if detailsByFlight.isEmpty {
            detailsByFlight = parseFlightDetails(in: rawText)
        }

        var flightsByDay: [Int: [String]] = [:]
        var ocrLines: [OCRLine] = []
        var ocrText = ""

        if detailsByFlight.isEmpty == false {
            flightsByDay = parseFlightsByDayFromPDFPage(
                page: firstPage,
                month: monthYear.month,
                year: monthYear.year,
                validFlightNumbers: Set(detailsByFlight.keys)
            )

            // Add duty entries (e.g. __DUTY_5_TRG) directly to flightsByDay.
            // These have the day encoded in their key, so no grid search needed.
            for key in detailsByFlight.keys where isDutyKey(key) {
                // Parse day from "__DUTY_{day}_{code}"
                // split(separator: "_") omits empty subsequences, so
                // "__DUTY_7_TRG" → ["DUTY", "7", "TRG"] — day is at index 1.
                let parts = key.split(separator: "_").map(String.init)
                guard parts.count >= 3, let day = Int(parts[1]) else { continue }
                var dayEntries = flightsByDay[day, default: []]
                if !dayEntries.contains(key) {
                    dayEntries.append(key)
                    flightsByDay[day] = dayEntries
                }
            }
        }

        if let renderedImage = render(page: firstPage, scale: 3.0) {
            if let ocrResult = try? await ocrService.recognizeText(from: renderedImage) {
                ocrLines = ocrResult.lines
                ocrText = ocrResult.lines.map(\.text).joined(separator: "\n")
            }
        } else if detailsByFlight.isEmpty || flightsByDay.isEmpty {
            throw ScheduleSlipServiceError.couldNotRenderPage
        }

        if ocrLines.isEmpty == false {
            let structured = parseScheduleTableFromOCRLines(
                lines: ocrLines,
                month: monthYear.month,
                year: monthYear.year
            )
            detailsByFlight = mergeDetailsByFlight(primary: detailsByFlight, secondary: structured.detailsByFlight)
            flightsByDay = mergeFlightsByDay(primary: flightsByDay, secondary: structured.flightsByDay)

            if detailsByFlight.isEmpty {
                detailsByFlight = parseFlightDetails(in: ocrText)
            }

            if flightsByDay.isEmpty, detailsByFlight.isEmpty == false {
                flightsByDay = parseFlightsByDayFromScheduleSheet(
                    lines: ocrLines,
                    month: monthYear.month,
                    year: monthYear.year,
                    validFlightNumbers: Set(detailsByFlight.keys)
                )
            }

            if flightsByDay.isEmpty {
                let fallback = flightNumberParser.parse(
                    lines: ocrLines,
                    fallbackMonth: monthYear.month,
                    fallbackYear: monthYear.year
                )
                flightsByDay = normalizeFlightsByDay(fallback.flightsByDay)
            }
        }

        let sanitized = sanitizeDutyEntries(
            flightsByDay: flightsByDay,
            detailsByFlight: detailsByFlight
        )
        flightsByDay = sanitized.flightsByDay
        detailsByFlight = sanitized.detailsByFlight

        guard detailsByFlight.isEmpty == false else {
            throw ScheduleSlipServiceError.noFlightDetailsDetected
        }

        guard flightsByDay.isEmpty == false else {
            throw ScheduleSlipServiceError.noRosterFlightsDetected
        }

        return ScheduleSlipParseResult(
            month: monthYear.month,
            year: monthYear.year,
            flightsByDay: flightsByDay,
            detailsByFlight: detailsByFlight
        )
    }

    func parse(
        scheduleImage: UIImage,
        fallbackMonth: Int,
        fallbackYear: Int
    ) async throws -> ScheduleSlipParseResult {
        let ocrResult = try await ocrService.recognizeText(from: scheduleImage)
        let textFromOCR = ocrResult.lines.map(\.text).joined(separator: "\n")

        return try buildResult(
            rawText: textFromOCR,
            ocrLines: ocrResult.lines,
            fallbackMonth: fallbackMonth,
            fallbackYear: fallbackYear,
            preferStructuredOCRDetails: true
        )
    }

    private func buildResult(
        rawText: String,
        ocrLines: [OCRLine],
        fallbackMonth: Int,
        fallbackYear: Int,
        preferStructuredOCRDetails: Bool = false
    ) throws -> ScheduleSlipParseResult {
        let ocrText = ocrLines.map(\.text).joined(separator: "\n")

        let monthYear = detectMonthYear(in: rawText)
            ?? detectMonthYear(in: ocrText)
            ?? (month: fallbackMonth, year: fallbackYear)

        var detailsByFlight: [String: ScheduleFlightDetail] = [:]
        var flightsByDay: [Int: [String]] = [:]

        if preferStructuredOCRDetails {
            let structured = parseScheduleTableFromOCRLines(
                lines: ocrLines,
                month: monthYear.month,
                year: monthYear.year
            )
            detailsByFlight = structured.detailsByFlight
            flightsByDay = structured.flightsByDay
        }

        if detailsByFlight.isEmpty {
            detailsByFlight = parseFlightDetailsFromOCRLines(lines: ocrLines)
        }
        if detailsByFlight.isEmpty {
            detailsByFlight = parseFlightDetails(in: rawText)
        }
        if detailsByFlight.isEmpty {
            detailsByFlight = parseFlightDetails(in: ocrText)
        }
        if detailsByFlight.isEmpty, preferStructuredOCRDetails == false {
            detailsByFlight = parseFlightDetailsFromOCRLines(lines: ocrLines)
        }

        let structured = parseScheduleTableFromOCRLines(
            lines: ocrLines,
            month: monthYear.month,
            year: monthYear.year
        )
        detailsByFlight = mergeDetailsByFlight(primary: detailsByFlight, secondary: structured.detailsByFlight)
        flightsByDay = mergeFlightsByDay(primary: flightsByDay, secondary: structured.flightsByDay)

        if flightsByDay.isEmpty, detailsByFlight.isEmpty == false {
            flightsByDay = parseFlightsByDayFromScheduleSheet(
                lines: ocrLines,
                month: monthYear.month,
                year: monthYear.year,
                validFlightNumbers: Set(detailsByFlight.keys)
            )
        }

        if flightsByDay.isEmpty {
            let fallback = flightNumberParser.parse(
                lines: ocrLines,
                fallbackMonth: monthYear.month,
                fallbackYear: monthYear.year
            )
            flightsByDay = normalizeFlightsByDay(fallback.flightsByDay)
        }

        if flightsByDay.isEmpty == false {
            detailsByFlight = fillMissingDetails(
                flightsByDay: flightsByDay,
                existing: detailsByFlight,
                rawText: rawText,
                ocrText: ocrText,
                ocrLines: ocrLines
            )
        }

        let sanitized = sanitizeDutyEntries(
            flightsByDay: flightsByDay,
            detailsByFlight: detailsByFlight
        )
        flightsByDay = sanitized.flightsByDay
        detailsByFlight = sanitized.detailsByFlight

        guard flightsByDay.isEmpty == false else {
            throw ScheduleSlipServiceError.noRosterFlightsDetected
        }

        guard detailsByFlight.isEmpty == false else {
            throw ScheduleSlipServiceError.noFlightDetailsDetected
        }

        return ScheduleSlipParseResult(
            month: monthYear.month,
            year: monthYear.year,
            flightsByDay: flightsByDay,
            detailsByFlight: detailsByFlight
        )
    }

    private func parseScheduleTableFromOCRLines(
        lines: [OCRLine],
        month: Int,
        year: Int
    ) -> (detailsByFlight: [String: ScheduleFlightDetail], flightsByDay: [Int: [String]]) {
        let headers = extractDayHeaders(from: lines)
        guard headers.isEmpty == false else { return ([:], [:]) }

        let dayCenters = buildDayCenters(headers: headers, month: month, year: year)
        guard dayCenters.count >= 7 else { return ([:], [:]) }

        let dayBounds = buildDayBounds(from: dayCenters)
        guard dayBounds.isEmpty == false else { return ([:], [:]) }

        let dayStartX = dayCenters.map(\.x).min() ?? 0.0
        let gridTopY = detectRosterGridTopY(in: lines, fallback: (headers.map(\.y).max() ?? 0.85) - 0.06)
        let gridBottomY = detectFlightGridBottomY(in: lines, fallback: 0.08)
        guard gridTopY > gridBottomY else { return ([:], [:]) }

        let tokens = extractGridTokens(
            from: lines,
            dayBounds: dayBounds,
            gridTopY: gridTopY,
            gridBottomY: gridBottomY
        )
        guard tokens.isEmpty == false else { return ([:], [:]) }

        let adjustedTokens = rebalanceLeadingDayTokens(tokens: tokens, dayCenters: dayCenters)
        let tokensByDay = Dictionary(grouping: adjustedTokens, by: \.day)
        var detailsByFlight: [String: ScheduleFlightDetail] = [:]
        var flightsByDay: [Int: [String]] = [:]

        var rowBundles = extractFlightRowBundles(from: lines, dayStartX: dayStartX)
        if rowBundles.isEmpty {
            rowBundles = inferFlightRowBundles(from: adjustedTokens)
        }

        if rowBundles.isEmpty == false {
            let rowParsed = parseUsingRowBundles(tokensByDay: tokensByDay, rowBundles: rowBundles)
            detailsByFlight = rowParsed.detailsByFlight
            flightsByDay = rowParsed.flightsByDay
        }

        flightsByDay = assignUnmappedFlightsToDays(
            flightsByDay: flightsByDay,
            detailsByFlight: detailsByFlight,
            tokensByDay: tokensByDay
        )

        return (detailsByFlight, flightsByDay)
    }

    private func parseUsingRowBundles(
        tokensByDay: [Int: [OCRGridToken]],
        rowBundles: [OCRFlightRowBundle]
    ) -> (detailsByFlight: [String: ScheduleFlightDetail], flightsByDay: [Int: [String]]) {
        let yTolerance = rowTolerance(from: rowBundles)
        var slotsByDay: [Int: [Int: OCRRowSlot]] = [:]

        for day in tokensByDay.keys.sorted() {
            guard let dayTokens = tokensByDay[day], dayTokens.isEmpty == false else { continue }

            var rowSlots: [Int: OCRRowSlot] = [:]
            for (bundleIndex, bundle) in rowBundles.enumerated() {
                var slot = OCRRowSlot()
                slot.flightNumber = nearestFlightNumber(in: dayTokens, near: bundle.fltY, tolerance: yTolerance)
                if slot.flightNumber == nil {
                    slot.flightNumber = nearestDutyCode(in: dayTokens, bundle: bundle, tolerance: yTolerance)
                }
                slot.origin = nearestAirportCode(in: dayTokens, near: bundle.depY, tolerance: yTolerance)
                slot.departureTime = nearestTime(in: dayTokens, near: bundle.depY, tolerance: yTolerance)
                slot.destination = nearestAirportCode(in: dayTokens, near: bundle.arrY, tolerance: yTolerance)
                slot.arrivalTime = nearestTime(in: dayTokens, near: bundle.arrY, tolerance: yTolerance)

                if slot.isEmpty == false {
                    rowSlots[bundleIndex] = slot
                }
            }

            if rowSlots.isEmpty == false {
                slotsByDay[day] = rowSlots
            }
        }

        guard slotsByDay.isEmpty == false else { return ([:], [:]) }

        var flightsByDay: [Int: [String]] = [:]
        var detailsByFlight: [String: ScheduleFlightDetail] = [:]

        for day in slotsByDay.keys.sorted() {
            guard let rowSlots = slotsByDay[day] else { continue }

            var dayFlights: [String] = []
            var seenDayFlights = Set<String>()

            for bundleIndex in rowBundles.indices {
                guard let slot = rowSlots[bundleIndex],
                      let flightNumber = slot.flightNumber else {
                    continue
                }

                let isDutyCode = flightNumber.isAlphabeticDutyCode
                let detailKey = isDutyCode ? "__DUTY_\(day)_\(flightNumber.uppercased())" : flightNumber

                if seenDayFlights.insert(detailKey).inserted {
                    dayFlights.append(detailKey)
                }

                let arrival = resolveArrival(
                    forDay: day,
                    bundleIndex: bundleIndex,
                    slotsByDay: slotsByDay
                )

                if isDutyCode {
                    guard let departureTime = slot.departureTime,
                          let arrivalTime = arrival.arrivalTime ?? slot.arrivalTime else {
                        continue
                    }

                    if detailsByFlight[detailKey] == nil {
                        detailsByFlight[detailKey] = ScheduleFlightDetail(
                            flightNumber: flightNumber.uppercased(),
                            origin: "",
                            destination: "",
                            departureTime: departureTime,
                            arrivalTime: arrivalTime
                        )
                    }
                    continue
                }

                guard let origin = slot.origin,
                      let departureTime = slot.departureTime,
                      let destination = arrival.destination ?? slot.destination,
                      let arrivalTime = arrival.arrivalTime ?? slot.arrivalTime else {
                    continue
                }

                let correctedArrival = correctedArrivalTime(
                    departure: departureTime,
                    arrival: arrivalTime,
                    origin: origin,
                    destination: destination
                )

                if detailsByFlight[detailKey] == nil {
                    detailsByFlight[detailKey] = ScheduleFlightDetail(
                        flightNumber: flightNumber,
                        origin: origin,
                        destination: destination,
                        departureTime: departureTime,
                        arrivalTime: correctedArrival
                    )
                }
            }

            if dayFlights.isEmpty == false {
                flightsByDay[day] = dayFlights
            }
        }

        return (detailsByFlight, flightsByDay)
    }

    private func parseUsingDayTokenSequence(
        tokensByDay: [Int: [OCRGridToken]]
    ) -> (detailsByFlight: [String: ScheduleFlightDetail], flightsByDay: [Int: [String]]) {
        var flightsByDay: [Int: [String]] = [:]
        var detailsByFlight: [String: ScheduleFlightDetail] = [:]
        var pending: [OCRPendingDetail] = []

        for day in tokensByDay.keys.sorted() {
            guard let rawTokens = tokensByDay[day], rawTokens.isEmpty == false else { continue }
            let dayTokens = rawTokens.sorted {
                if abs($0.y - $1.y) > 0.001 {
                    return $0.y > $1.y
                }
                return $0.x < $1.x
            }

            var dayFlights: [String] = []
            var seenDayFlights = Set<String>()
            var usedDepartureIndices = Set<Int>()

            for index in dayTokens.indices {
                guard usedDepartureIndices.contains(index) == false,
                      let departureTime = timeCandidate(in: dayTokens, at: index),
                      let originIndex = previousAirportIndex(in: dayTokens, from: index, maxDistance: 3),
                      let flightIndex = previousFlightIndex(in: dayTokens, from: originIndex, maxDistance: 4),
                      let flightNumber = normalizeFlightNumberToken(dayTokens[flightIndex].text) else {
                    continue
                }

                let origin = dayTokens[originIndex].text
                guard isAirportCodeToken(origin) else { continue }

                usedDepartureIndices.insert(index)

                if seenDayFlights.insert(flightNumber).inserted {
                    dayFlights.append(flightNumber)
                }

                let destinationIndex = nextAirportIndex(in: dayTokens, from: index, maxDistance: 4)
                let arrivalIndex = destinationIndex.flatMap {
                    nextTimeIndex(in: dayTokens, from: $0, maxDistance: 4)
                }

                let destination = destinationIndex.map { dayTokens[$0].text }
                let arrivalTime = arrivalIndex.flatMap { timeCandidate(in: dayTokens, at: $0) }

                if let destination, let arrivalTime {
                    let correctedArrival = correctedArrivalTime(
                        departure: departureTime,
                        arrival: arrivalTime,
                        origin: origin,
                        destination: destination
                    )
                    if detailsByFlight[flightNumber] == nil {
                        detailsByFlight[flightNumber] = ScheduleFlightDetail(
                            flightNumber: flightNumber,
                            origin: origin,
                            destination: destination,
                            departureTime: departureTime,
                            arrivalTime: correctedArrival
                        )
                    }
                } else {
                    pending.append(
                        OCRPendingDetail(
                            day: day,
                            flightNumber: flightNumber,
                            origin: origin,
                            departureTime: departureTime,
                            destination: destination,
                            arrivalTime: arrivalTime
                        )
                    )
                }
            }

            if dayFlights.isEmpty == false {
                flightsByDay[day] = dayFlights
            }
        }

        for item in pending where detailsByFlight[item.flightNumber] == nil {
            let carry = carryArrivalFromNextDay(day: item.day, tokensByDay: tokensByDay)
            guard let destination = item.destination ?? carry.destination,
                  let arrivalTime = item.arrivalTime ?? carry.arrivalTime else {
                continue
            }

            let correctedArrival = correctedArrivalTime(
                departure: item.departureTime,
                arrival: arrivalTime,
                origin: item.origin,
                destination: destination
            )

            detailsByFlight[item.flightNumber] = ScheduleFlightDetail(
                flightNumber: item.flightNumber,
                origin: item.origin,
                destination: destination,
                departureTime: item.departureTime,
                arrivalTime: correctedArrival
            )
        }

        return (detailsByFlight, flightsByDay)
    }

    private func mergeFlightsByDay(
        primary: [Int: [String]],
        secondary: [Int: [String]]
    ) -> [Int: [String]] {
        var merged = primary

        // Anchor numeric flight numbers to their primary day mapping.
        // OCR can occasionally shift a flight into the previous/next day.
        var anchoredPrimaryDaysByFlight: [String: Set<Int>] = [:]
        for (day, values) in primary {
            for value in values where isDutyKey(value) == false {
                anchoredPrimaryDaysByFlight[value, default: []].insert(day)
            }
        }

        for day in secondary.keys.sorted() {
            let existing = merged[day, default: []]
            var seen = Set(existing)
            var dayFlights = existing

            for value in secondary[day, default: []] {
                if seen.contains(value) {
                    continue
                }

                if isDutyKey(value) == false,
                   let anchoredDays = anchoredPrimaryDaysByFlight[value],
                   anchoredDays.contains(day) == false {
                    continue
                }

                seen.insert(value)
                dayFlights.append(value)
            }

            if dayFlights.isEmpty == false {
                merged[day] = dayFlights
            }
        }

        return merged
    }

    private func mergeDetailsByFlight(
        primary: [String: ScheduleFlightDetail],
        secondary: [String: ScheduleFlightDetail]
    ) -> [String: ScheduleFlightDetail] {
        var merged = primary
        for key in secondary.keys where merged[key] == nil {
            merged[key] = secondary[key]
        }
        return merged
    }

    private func isDutyKey(_ value: String) -> Bool {
        value.hasPrefix("__DUTY_")
    }

    private func sanitizeDutyEntries(
        flightsByDay: [Int: [String]],
        detailsByFlight: [String: ScheduleFlightDetail]
    ) -> (flightsByDay: [Int: [String]], detailsByFlight: [String: ScheduleFlightDetail]) {
        var cleanedFlightsByDay = flightsByDay
        var cleanedDetailsByFlight = detailsByFlight

        let airportCodes = Set(
            detailsByFlight.compactMap { key, detail -> [String]? in
                guard isDutyKey(key) == false else { return nil }
                let origin = detail.origin.uppercased()
                let destination = detail.destination.uppercased()
                let values = [origin, destination].filter { isAirportCodeToken($0) }
                return values.isEmpty ? nil : values
            }.flatMap { $0 }
        )

        var removedDutyKeys = Set<String>()

        for (key, detail) in detailsByFlight where isDutyKey(key) {
            let dutyCode = detail.flightNumber.uppercased()
            if airportCodes.contains(dutyCode) {
                cleanedDetailsByFlight.removeValue(forKey: key)
                removedDutyKeys.insert(key)
            }
        }

        for day in cleanedFlightsByDay.keys.sorted() {
            let filtered = cleanedFlightsByDay[day, default: []].filter { value in
                guard isDutyKey(value) else { return true }
                if removedDutyKeys.contains(value) {
                    return false
                }
                return cleanedDetailsByFlight[value] != nil
            }

            if filtered.isEmpty {
                cleanedFlightsByDay.removeValue(forKey: day)
            } else {
                cleanedFlightsByDay[day] = filtered
            }
        }

        return (cleanedFlightsByDay, cleanedDetailsByFlight)
    }

    private func assignUnmappedFlightsToDays(
        flightsByDay: [Int: [String]],
        detailsByFlight: [String: ScheduleFlightDetail],
        tokensByDay: [Int: [OCRGridToken]]
    ) -> [Int: [String]] {
        var merged = flightsByDay
        let assigned = Set(merged.values.flatMap { $0 })
        let missing = Set(detailsByFlight.keys).subtracting(assigned)
        guard missing.isEmpty == false else { return merged }

        for flight in missing {
            let candidates = tokensByDay.keys.sorted().filter { day in
                tokensByDay[day, default: []].contains(where: { token in
                    token.kind == .number &&
                    normalizeFlightNumberToken(token.text) == flight
                })
            }

            guard let day = candidates.first else { continue }
            var dayFlights = merged[day, default: []]
            if dayFlights.contains(flight) == false {
                dayFlights.append(flight)
                merged[day] = dayFlights
            }
        }

        return merged
    }

    private func rebalanceLeadingDayTokens(
        tokens: [OCRGridToken],
        dayCenters: [(day: Int, x: CGFloat)]
    ) -> [OCRGridToken] {
        guard tokens.isEmpty == false, dayCenters.count >= 2 else { return tokens }

        let centerByDay = Dictionary(uniqueKeysWithValues: dayCenters.map { ($0.day, $0.x) })
        var adjusted = tokens

        for day in dayCenters.map(\.day).sorted() where day > 1 {
            let previousDay = day - 1
            guard let previousCenter = centerByDay[previousDay],
                  let currentCenter = centerByDay[day] else {
                continue
            }

            let previousCount = adjusted.filter { $0.day == previousDay }.count
            let currentCount = adjusted.filter { $0.day == day }.count
            guard previousCount == 0, currentCount > 0 else { continue }

            let span = abs(currentCenter - previousCenter)
            guard span > 0 else { continue }
            let threshold = min(currentCenter, previousCenter) + span * 0.68

            for index in adjusted.indices where adjusted[index].day == day && adjusted[index].x < threshold {
                adjusted[index] = OCRGridToken(
                    day: previousDay,
                    text: adjusted[index].text,
                    x: adjusted[index].x,
                    y: adjusted[index].y,
                    kind: adjusted[index].kind
                )
            }
        }

        return adjusted
    }

    private func rebalanceLeadingDayHits(
        hits: [FlightGridHit],
        dayCenters: [(day: Int, x: CGFloat)]
    ) -> [FlightGridHit] {
        guard hits.isEmpty == false, dayCenters.count >= 2 else { return hits }

        let centerByDay = Dictionary(uniqueKeysWithValues: dayCenters.map { ($0.day, $0.x) })
        var adjusted = hits

        for day in dayCenters.map(\.day).sorted() where day > 1 {
            let previousDay = day - 1
            guard let previousCenter = centerByDay[previousDay],
                  let currentCenter = centerByDay[day] else {
                continue
            }

            let previousCount = adjusted.filter { $0.day == previousDay }.count
            let currentCount = adjusted.filter { $0.day == day }.count
            guard previousCount == 0, currentCount > 0 else { continue }

            let span = abs(currentCenter - previousCenter)
            guard span > 0 else { continue }
            let threshold = min(currentCenter, previousCenter) + span * 0.68

            for index in adjusted.indices where adjusted[index].day == day && adjusted[index].x < threshold {
                let item = adjusted[index]
                adjusted[index] = FlightGridHit(
                    day: previousDay,
                    flightNumber: item.flightNumber,
                    y: item.y,
                    x: item.x,
                    tokenIndex: item.tokenIndex
                )
            }
        }

        return adjusted
    }

    private func correctedArrivalTime(
        departure: String,
        arrival: String,
        origin: String,
        destination: String
    ) -> String {
        guard departure.count == 4, arrival.count == 4 else { return arrival }

        // Common OCR issue in schedule pages: 22:20 read as 02:20.
        guard arrival.hasPrefix("0"),
              let depMinutes = departure.hhmmMinutes,
              let arrMinutes = arrival.hhmmMinutes else {
            return arrival
        }

        let fixed = "2" + arrival.dropFirst()
        guard let fixedMinutes = fixed.hhmmMinutes else { return arrival }

        let originalDuration = arrMinutes >= depMinutes
            ? arrMinutes - depMinutes
            : arrMinutes + 24 * 60 - depMinutes
        let fixedDuration = fixedMinutes >= depMinutes
            ? fixedMinutes - depMinutes
            : fixedMinutes + 24 * 60 - depMinutes

        let isLongHaulRoute = Set(["LHR", "CDG", "FRA", "MUC", "SYD", "MEL", "AKL"]).contains(origin)
            || Set(["LHR", "CDG", "FRA", "MUC", "SYD", "MEL", "AKL"]).contains(destination)
        let maxReasonableDuration = isLongHaulRoute ? 9 * 60 : 6 * 60

        if originalDuration > maxReasonableDuration,
           (45...maxReasonableDuration).contains(fixedDuration) {
            return String(fixed)
        }

        return arrival
    }

    private func timeCandidate(in tokens: [OCRGridToken], at index: Int) -> String? {
        let token = tokens[index]
        if token.kind == .time {
            return token.text
        }

        guard token.kind == .number,
              token.text.count == 4,
              let hhmm = normalizedTime(token.text),
              hasNearbyAirport(token, in: tokens, xTolerance: 0.09, yTolerance: 0.008) else {
            return nil
        }
        return hhmm
    }

    private func hasNearbyAirport(
        _ token: OCRGridToken,
        in tokens: [OCRGridToken],
        xTolerance: CGFloat,
        yTolerance: CGFloat
    ) -> Bool {
        tokens.contains { candidate in
            candidate.kind == .airport &&
            candidate.day == token.day &&
            abs(candidate.y - token.y) <= yTolerance &&
            abs(candidate.x - token.x) <= xTolerance
        }
    }

    private func previousAirportIndex(
        in tokens: [OCRGridToken],
        from index: Int,
        maxDistance: Int
    ) -> Int? {
        guard index > 0 else { return nil }
        let lower = max(0, index - maxDistance)
        for candidate in stride(from: index - 1, through: lower, by: -1) {
            if tokens[candidate].kind == .airport {
                return candidate
            }
        }
        return nil
    }

    private func previousFlightIndex(
        in tokens: [OCRGridToken],
        from index: Int,
        maxDistance: Int
    ) -> Int? {
        guard index > 0 else { return nil }
        let lower = max(0, index - maxDistance)
        for candidate in stride(from: index - 1, through: lower, by: -1) {
            guard isLikelyFlightToken(tokens[candidate]) else { continue }
            return candidate
        }
        return nil
    }

    private func nextAirportIndex(
        in tokens: [OCRGridToken],
        from index: Int,
        maxDistance: Int
    ) -> Int? {
        guard index < tokens.count - 1 else { return nil }
        let upper = min(tokens.count - 1, index + maxDistance)
        for candidate in (index + 1)...upper where tokens[candidate].kind == .airport {
            return candidate
        }
        return nil
    }

    private func nextTimeIndex(
        in tokens: [OCRGridToken],
        from index: Int,
        maxDistance: Int
    ) -> Int? {
        guard index < tokens.count - 1 else { return nil }
        let upper = min(tokens.count - 1, index + maxDistance)
        for candidate in (index + 1)...upper where timeCandidate(in: tokens, at: candidate) != nil {
            return candidate
        }
        return nil
    }

    private func isLikelyFlightToken(_ token: OCRGridToken) -> Bool {
        guard token.kind == .number,
              let normalized = normalizeFlightNumberToken(token.text),
              normalized.isEmpty == false else {
            return false
        }

        // Avoid treating 4-digit HHmm values as flight numbers in sequence fallback.
        return token.text.count <= 3
    }

    private func carryArrivalFromNextDay(
        day: Int,
        tokensByDay: [Int: [OCRGridToken]]
    ) -> (destination: String?, arrivalTime: String?) {
        for delta in 1...2 {
            guard let rawTokens = tokensByDay[day + delta], rawTokens.isEmpty == false else {
                continue
            }

            let dayTokens = rawTokens.sorted {
                if abs($0.y - $1.y) > 0.001 {
                    return $0.y > $1.y
                }
                return $0.x < $1.x
            }

            let firstFlightIndex = dayTokens.firstIndex(where: { isLikelyFlightToken($0) }) ?? dayTokens.count
            guard firstFlightIndex > 0 else { continue }

            let prefix = Array(dayTokens[..<firstFlightIndex])
            let destination = prefix.first(where: { $0.kind == .airport })?.text
            let arrival = prefix.indices.compactMap { timeCandidate(in: prefix, at: $0) }.first

            if destination != nil || arrival != nil {
                return (destination, arrival)
            }
        }

        return (nil, nil)
    }

    private func fillMissingDetails(
        flightsByDay: [Int: [String]],
        existing: [String: ScheduleFlightDetail],
        rawText: String,
        ocrText: String,
        ocrLines: [OCRLine]
    ) -> [String: ScheduleFlightDetail] {
        let requiredFlights = Set(
            flightsByDay.values
                .flatMap { $0 }
                .map { $0.strippingLeadingZeros() }
                .filter { $0.isEmpty == false }
        )
        guard requiredFlights.isEmpty == false else { return existing }

        var merged = existing

        let candidates: [[String: ScheduleFlightDetail]] = [
            parseFlightDetailsFromOCRLines(lines: ocrLines),
            parseFlightDetails(in: rawText),
            parseFlightDetails(in: ocrText)
        ]

        for source in candidates {
            for flight in requiredFlights {
                guard let detail = source[flight] else { continue }
                if let current = merged[flight] {
                    if shouldReplaceDetail(current: current, with: detail) {
                        merged[flight] = detail
                    }
                } else {
                    merged[flight] = detail
                }
            }
        }

        return merged
    }

    private func shouldReplaceDetail(
        current: ScheduleFlightDetail,
        with candidate: ScheduleFlightDetail
    ) -> Bool {
        let currentScore = detailQualityScore(current)
        let candidateScore = detailQualityScore(candidate)
        if candidateScore > currentScore {
            return true
        }

        if current.origin == current.destination,
           candidate.origin != candidate.destination {
            return true
        }

        if isFlightNumberEcho(time: current.departureTime, flightNumber: current.flightNumber),
           isFlightNumberEcho(time: candidate.departureTime, flightNumber: candidate.flightNumber) == false {
            return true
        }

        return false
    }

    private func detailQualityScore(_ detail: ScheduleFlightDetail) -> Int {
        var score = 0

        if detail.origin != detail.destination {
            score += 3
        } else {
            score -= 3
        }

        if detail.departureTime != detail.arrivalTime {
            score += 1
        }

        if isFlightNumberEcho(time: detail.departureTime, flightNumber: detail.flightNumber) == false {
            score += 2
        } else {
            score -= 2
        }

        if isFlightNumberEcho(time: detail.arrivalTime, flightNumber: detail.flightNumber) == false {
            score += 1
        } else {
            score -= 1
        }

        if let departureMinutes = detail.departureTime.hhmmMinutes,
           let arrivalMinutes = detail.arrivalTime.hhmmMinutes {
            let duration = arrivalMinutes >= departureMinutes
                ? arrivalMinutes - departureMinutes
                : arrivalMinutes + 24 * 60 - departureMinutes
            if (20...16 * 60).contains(duration) {
                score += 1
            } else {
                score -= 1
            }
        }

        return score
    }

    private func isFlightNumberEcho(time: String, flightNumber: String) -> Bool {
        let digits = String(flightNumber.filter(\.isNumber))
        guard digits.isEmpty == false else { return false }
        let padded = String(repeating: "0", count: max(0, 4 - digits.count)) + digits
        return time == padded
    }

    private func extractFlightRowBundles(from lines: [OCRLine], dayStartX: CGFloat) -> [OCRFlightRowBundle] {
        let labelMaxX = max(0.04, dayStartX - 0.01)

        var labels: [(label: String, y: CGFloat)] = lines.compactMap { line in
            guard line.boundingBox.midX <= labelMaxX else { return nil }
            let normalized = normalizedLine(line.text)
            guard normalized == "FLT" || normalized == "DEP" || normalized == "ARR" else {
                return nil
            }
            return (label: normalized, y: line.boundingBox.midY)
        }

        guard labels.isEmpty == false else { return [] }

        labels.sort { $0.y > $1.y }

        var deduped: [(label: String, y: CGFloat)] = []
        for label in labels {
            if let last = deduped.last,
               last.label == label.label,
               abs(last.y - label.y) < 0.006 {
                continue
            }
            deduped.append(label)
        }

        var bundles: [OCRFlightRowBundle] = []
        var index = 0

        while index < deduped.count {
            guard deduped[index].label == "FLT" else {
                index += 1
                continue
            }

            var depIndex: Int?
            var arrIndex: Int?
            var seek = index + 1

            while seek < deduped.count {
                let candidate = deduped[seek]

                if depIndex == nil {
                    if candidate.label == "DEP", candidate.y < deduped[index].y {
                        depIndex = seek
                    } else if candidate.label == "FLT" {
                        break
                    }
                } else if arrIndex == nil, let depIndex {
                    if candidate.label == "ARR", candidate.y < deduped[depIndex].y {
                        arrIndex = seek
                        break
                    } else if candidate.label == "FLT" {
                        break
                    }
                }

                seek += 1
            }

            if let depIndex, let arrIndex {
                let fltY = deduped[index].y
                let depY = deduped[depIndex].y
                let arrY = deduped[arrIndex].y

                if fltY > depY,
                   depY > arrY,
                   (fltY - depY) <= 0.09,
                   (depY - arrY) <= 0.09 {
                    bundles.append(OCRFlightRowBundle(fltY: fltY, depY: depY, arrY: arrY))
                    index = arrIndex + 1
                    continue
                }
            }

            index += 1
        }

        if bundles.isEmpty {
            let fltYs = clusteredValues(labels.filter { $0.label == "FLT" }.map { $0.y }, tolerance: 0.006)
            let depYs = clusteredValues(labels.filter { $0.label == "DEP" }.map { $0.y }, tolerance: 0.006)
            let arrYs = clusteredValues(labels.filter { $0.label == "ARR" }.map { $0.y }, tolerance: 0.006)

            let count = min(fltYs.count, depYs.count, arrYs.count)
            for index in 0..<count {
                let fltY = fltYs[index]
                let depY = depYs[index]
                let arrY = arrYs[index]
                if fltY > depY, depY > arrY {
                    bundles.append(OCRFlightRowBundle(fltY: fltY, depY: depY, arrY: arrY))
                }
            }
        }

        return bundles
    }

    private func inferFlightRowBundles(from tokens: [OCRGridToken]) -> [OCRFlightRowBundle] {
        guard tokens.isEmpty == false else { return [] }

        let rowTolerance: CGFloat = 0.008
        let rowYs = clusteredValues(tokens.map(\.y), tolerance: rowTolerance)
        guard rowYs.count >= 3 else { return [] }

        struct RowStats {
            let y: CGFloat
            let numberCount: Int
            let airportCount: Int
            let timeCount: Int
        }

        let rows: [RowStats] = rowYs.compactMap { y in
            let rowTokens = tokens.filter { abs($0.y - y) <= rowTolerance }
            guard rowTokens.isEmpty == false else { return nil }

            let numberCount = Set(rowTokens.filter { $0.kind == .number }.map { "\($0.day):\($0.text)" }).count
            let airportCount = Set(rowTokens.filter { $0.kind == .airport }.map { "\($0.day):\($0.text)" }).count
            let timeCount = Set(rowTokens.filter { $0.kind == .time }.map { "\($0.day):\($0.text)" }).count

            guard numberCount + airportCount + timeCount > 0 else { return nil }
            return RowStats(
                y: y,
                numberCount: numberCount,
                airportCount: airportCount,
                timeCount: timeCount
            )
        }
        .sorted(by: { $0.y > $1.y })

        guard rows.count >= 3 else { return [] }

        func isTimeRow(_ row: RowStats) -> Bool {
            row.timeCount >= 1 && row.airportCount >= 1
        }

        func isFlightRow(_ row: RowStats) -> Bool {
            row.numberCount >= 1 &&
            row.timeCount == 0 &&
            row.airportCount <= max(1, row.numberCount / 2)
        }

        var bundles: [OCRFlightRowBundle] = []
        var usedTimeRows = Set<Int>()

        for index in rows.indices {
            let flightRow = rows[index]
            guard isFlightRow(flightRow) else { continue }

            var depIndex: Int?
            for candidate in (index + 1)..<rows.count {
                guard usedTimeRows.contains(candidate) == false,
                      isTimeRow(rows[candidate]) else {
                    continue
                }
                let delta = flightRow.y - rows[candidate].y
                if delta > 0.11 { break }
                if delta >= 0.003 {
                    depIndex = candidate
                    break
                }
            }

            guard let depIndex else { continue }

            var arrIndex: Int?
            for candidate in (depIndex + 1)..<rows.count {
                guard usedTimeRows.contains(candidate) == false,
                      isTimeRow(rows[candidate]) else {
                    continue
                }
                let delta = rows[depIndex].y - rows[candidate].y
                if delta > 0.11 { break }
                if delta >= 0.003 {
                    arrIndex = candidate
                    break
                }
            }

            guard let arrIndex else { continue }

            let bundle = OCRFlightRowBundle(
                fltY: flightRow.y,
                depY: rows[depIndex].y,
                arrY: rows[arrIndex].y
            )
            bundles.append(bundle)
            usedTimeRows.insert(depIndex)
            usedTimeRows.insert(arrIndex)
        }

        return bundles.sorted(by: { $0.fltY > $1.fltY })
    }

    private func extractGridTokens(
        from lines: [OCRLine],
        dayBounds: [(day: Int, range: ClosedRange<CGFloat>)],
        gridTopY: CGFloat,
        gridBottomY: CGFloat
    ) -> [OCRGridToken] {
        var tokens: [OCRGridToken] = []

        for line in lines {
            let y = line.boundingBox.midY
            guard y <= gridTopY + 0.02, y >= gridBottomY - 0.01 else { continue }
            guard line.boundingBox.width > 0 else { continue }

            let matches = extractGridTokenMatches(from: line.text)
            guard matches.isEmpty == false else { continue }

            let lineLength = max(1, (line.text as NSString).length)
            for match in matches {
                let leading = CGFloat(match.range.location) + max(1, CGFloat(match.range.length) * 0.2)
                let ratio = max(0, min(1, leading / CGFloat(lineLength)))
                let x = line.boundingBox.minX + ratio * line.boundingBox.width
                guard let day = dayForX(x, in: dayBounds) else { continue }

                let token = match.value.uppercased()

                if token.contains(":") || token.contains(".") {
                    if let time = normalizedTime(token) {
                        tokens.append(
                            OCRGridToken(day: day, text: time, x: x, y: y, kind: .time)
                        )
                    }
                    continue
                }

                if token.isAlphabeticDutyCode,
                   isExcludedDutyToken(token) == false {
                    tokens.append(
                        OCRGridToken(day: day, text: token, x: x, y: y, kind: .duty)
                    )
                }

                if isAirportCodeToken(token) {
                    tokens.append(
                        OCRGridToken(day: day, text: token, x: x, y: y, kind: .airport)
                    )
                    continue
                }

                if token.allSatisfy(\.isNumber), token.count <= 4 {
                    tokens.append(
                        OCRGridToken(day: day, text: token, x: x, y: y, kind: .number)
                    )
                }
            }
        }

        return tokens
    }

    private func extractGridTokenMatches(from text: String) -> [(value: String, range: NSRange)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"[A-Z]{3,10}|[0-2]?\d[:.][0-5]\d|\d{1,4}"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let upper = text.uppercased()
        let ns = upper as NSString
        let range = NSRange(location: 0, length: ns.length)

        return regex.matches(in: upper, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 0 else { return nil }
            return (value: ns.substring(with: match.range(at: 0)), range: match.range(at: 0))
        }
    }

    private func isAirportCodeToken(_ token: String) -> Bool {
        guard token.count == 3, token.allSatisfy(\.isLetter) else { return false }

        let blocked: Set<String> = [
            "FLT", "DEP", "ARR", "DUT", "DAY", "DAT", "REM",
            "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"
        ]

        return blocked.contains(token) == false
    }

    private func isExcludedDutyToken(_ token: String) -> Bool {
        Self.excludedDutyTokens.contains(token)
    }

    private func rowTolerance(from bundles: [OCRFlightRowBundle]) -> CGFloat {
        let distances = bundles.flatMap { [abs($0.fltY - $0.depY), abs($0.depY - $0.arrY)] }
        guard distances.isEmpty == false else { return 0.012 }
        let average = distances.reduce(0, +) / CGFloat(distances.count)
        return max(0.006, min(0.02, average * 0.55))
    }

    private func nearestFlightNumber(
        in tokens: [OCRGridToken],
        near y: CGFloat,
        tolerance: CGFloat
    ) -> String? {
        let candidates = tokens
            .filter { $0.kind == .number && abs($0.y - y) <= tolerance }
            .compactMap { token -> (number: String, yDelta: CGFloat, x: CGFloat)? in
                let normalized = token.text.strippingLeadingZeros()
                guard normalized.isEmpty == false, normalized != "0" else { return nil }
                // Reject single-digit numbers — TG flights are 2+ digits (e.g. TG 102).
                // Stray "1", "2" etc. are misread day labels or OCR artifacts.
                guard let value = Int(normalized), value >= 10 else { return nil }
                return (number: normalized, yDelta: abs(token.y - y), x: token.x)
            }
            .sorted {
                if $0.yDelta != $1.yDelta { return $0.yDelta < $1.yDelta }
                return $0.x < $1.x
            }

        return candidates.first?.number
    }

    private func nearestDutyCode(
        in tokens: [OCRGridToken],
        bundle: OCRFlightRowBundle,
        tolerance: CGFloat
    ) -> String? {
        let candidates = tokens
            .filter { $0.kind == .duty && abs($0.y - bundle.fltY) <= tolerance }
            .sorted {
                let lhsDelta = abs($0.y - bundle.fltY)
                let rhsDelta = abs($1.y - bundle.fltY)
                if lhsDelta != rhsDelta { return lhsDelta < rhsDelta }
                return $0.x < $1.x
            }

        for candidate in candidates
            where isExcludedDutyToken(candidate.text) == false {
            let airportMatches = tokens.filter {
                $0.kind == .airport && $0.text == candidate.text
            }.count
            if candidate.text.count == 3 && airportMatches >= 2 {
                continue
            }

            let departure = nearestTime(
                in: tokens,
                near: bundle.depY,
                tolerance: tolerance,
                xHint: candidate.x
            )
            let arrival = nearestTime(
                in: tokens,
                near: bundle.arrY,
                tolerance: tolerance,
                xHint: candidate.x
            )
            guard departure != nil, arrival != nil else { continue }
            return candidate.text
        }

        return nil
    }

    private func nearestAirportCode(
        in tokens: [OCRGridToken],
        near y: CGFloat,
        tolerance: CGFloat
    ) -> String? {
        let candidates = tokens
            .filter { $0.kind == .airport && abs($0.y - y) <= tolerance }
            .sorted {
                let lhsDelta = abs($0.y - y)
                let rhsDelta = abs($1.y - y)
                if lhsDelta != rhsDelta { return lhsDelta < rhsDelta }
                return $0.x < $1.x
            }

        return candidates.first?.text
    }

    private func nearestTime(
        in tokens: [OCRGridToken],
        near y: CGFloat,
        tolerance: CGFloat,
        xHint: CGFloat? = nil
    ) -> String? {
        let xTolerance: CGFloat = 0.045

        let exact = tokens
            .filter {
                guard $0.kind == .time, abs($0.y - y) <= tolerance else { return false }
                if let xHint { return abs($0.x - xHint) <= xTolerance }
                return true
            }
            .sorted {
                let lhsDelta = abs($0.y - y)
                let rhsDelta = abs($1.y - y)
                if lhsDelta != rhsDelta { return lhsDelta < rhsDelta }
                if let xHint {
                    let lhsX = abs($0.x - xHint)
                    let rhsX = abs($1.x - xHint)
                    if lhsX != rhsX { return lhsX < rhsX }
                }
                return $0.x < $1.x
            }

        if let value = exact.first?.text {
            return value
        }

        let fromNumbers = tokens
            .filter { token in
                guard token.kind == .number,
                      token.text.count == 4,
                      abs(token.y - y) <= tolerance,
                      hasNearbyAirport(token, in: tokens, xTolerance: 0.09, yTolerance: max(0.008, tolerance)) else {
                    return false
                }
                if let xHint { return abs(token.x - xHint) <= xTolerance }
                return true
            }
            .compactMap { token -> (time: String, yDelta: CGFloat, x: CGFloat)? in
                guard let normalized = normalizedTime(token.text) else { return nil }
                return (time: normalized, yDelta: abs(token.y - y), x: token.x)
            }
            .sorted {
                if $0.yDelta != $1.yDelta { return $0.yDelta < $1.yDelta }
                if let xHint {
                    let lhsX = abs($0.x - xHint)
                    let rhsX = abs($1.x - xHint)
                    if lhsX != rhsX { return lhsX < rhsX }
                }
                return $0.x < $1.x
            }

        return fromNumbers.first?.time
    }

    private func resolveArrival(
        forDay day: Int,
        bundleIndex: Int,
        slotsByDay: [Int: [Int: OCRRowSlot]]
    ) -> (destination: String?, arrivalTime: String?) {
        var destination = slotsByDay[day]?[bundleIndex]?.destination
        var arrivalTime = slotsByDay[day]?[bundleIndex]?.arrivalTime

        guard destination == nil || arrivalTime == nil else {
            return (destination, arrivalTime)
        }

        for delta in 1...2 {
            guard let nextSlot = slotsByDay[day + delta]?[bundleIndex],
                  nextSlot.flightNumber == nil else {
                continue
            }
            if destination == nil {
                destination = nextSlot.destination
            }
            if arrivalTime == nil {
                arrivalTime = nextSlot.arrivalTime
            }
            if destination != nil, arrivalTime != nil {
                break
            }
        }

        return (destination, arrivalTime)
    }

    private func clusteredValues(_ values: [CGFloat], tolerance: CGFloat) -> [CGFloat] {
        guard values.isEmpty == false else { return [] }

        let sorted = values.sorted(by: >)
        var clusters: [[CGFloat]] = []

        for value in sorted {
            if let index = clusters.firstIndex(where: { cluster in
                let avg = cluster.reduce(0, +) / CGFloat(cluster.count)
                return abs(avg - value) <= tolerance
            }) {
                clusters[index].append(value)
            } else {
                clusters.append([value])
            }
        }

        return clusters.map { cluster in
            cluster.reduce(0, +) / CGFloat(cluster.count)
        }
        .sorted(by: >)
    }

    private func parseFlightDetailsFromOCRLines(lines: [OCRLine]) -> [String: ScheduleFlightDetail] {
        guard lines.isEmpty == false else { return [:] }

        let gridTopY = detectFlightGridTopY(
            in: lines,
            fallback: lines.map(\.boundingBox.midY).max() ?? 0.9
        )
        let gridBottomY = detectFlightGridBottomY(in: lines, fallback: 0.06)
        guard gridTopY > gridBottomY else { return [:] }

        let gridLines = lines.filter { line in
            let y = line.boundingBox.midY
            return y <= gridTopY + 0.02 && y >= gridBottomY - 0.02 && line.boundingBox.width > 0
        }
        guard gridLines.isEmpty == false else { return [:] }

        let depPattern = #"\b(\d{1,4})\s+([A-Z]{3})\s+([0-2]?\d[:.]?[0-5]\d)\b"#
        let arrPattern = #"\b([A-Z]{3})\s+([0-2]?\d[:.]?[0-5]\d)\b"#
        guard let depRegex = try? NSRegularExpression(pattern: depPattern, options: []),
              let arrRegex = try? NSRegularExpression(pattern: arrPattern, options: []) else {
            return [:]
        }

        var departures: [OCRDepartureCandidate] = []
        var arrivals: [OCRArrivalCandidate] = []

        for line in gridLines {
            let text = line.text.uppercased()
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            let lineLength = max(1, nsText.length)

            for match in depRegex.matches(in: text, options: [], range: fullRange) {
                guard match.numberOfRanges == 4 else { continue }

                let rawNumber = nsText.substring(with: match.range(at: 1))
                let origin = nsText.substring(with: match.range(at: 2))
                let departureRaw = nsText.substring(with: match.range(at: 3))
                guard let departureTime = normalizedTime(departureRaw) else { continue }

                let normalizedNumber = rawNumber.strippingLeadingZeros()
                guard normalizedNumber.isEmpty == false, normalizedNumber != "0" else { continue }

                let center = CGFloat(match.range(at: 1).location) + (CGFloat(match.range(at: 1).length) / 2)
                let ratio = max(0, min(1, center / CGFloat(lineLength)))
                let x = line.boundingBox.minX + ratio * line.boundingBox.width

                departures.append(
                    OCRDepartureCandidate(
                        flightNumber: normalizedNumber,
                        origin: origin,
                        departureTime: departureTime,
                        x: x,
                        y: line.boundingBox.midY
                    )
                )
            }

            for match in arrRegex.matches(in: text, options: [], range: fullRange) {
                guard match.numberOfRanges == 3 else { continue }

                let destination = nsText.substring(with: match.range(at: 1))
                if ["FLT", "DEP", "ARR", "DUTY", "DATE", "REMARK"].contains(destination) {
                    continue
                }

                let arrivalRaw = nsText.substring(with: match.range(at: 2))
                guard let arrivalTime = normalizedTime(arrivalRaw) else { continue }

                let center = CGFloat(match.range(at: 1).location) + (CGFloat(match.range(at: 1).length) / 2)
                let ratio = max(0, min(1, center / CGFloat(lineLength)))
                let x = line.boundingBox.minX + ratio * line.boundingBox.width

                arrivals.append(
                    OCRArrivalCandidate(
                        destination: destination,
                        arrivalTime: arrivalTime,
                        x: x,
                        y: line.boundingBox.midY
                    )
                )
            }
        }

        guard departures.isEmpty == false, arrivals.isEmpty == false else { return [:] }

        let orderedDepartures = departures.sorted {
            if abs($0.y - $1.y) > 0.001 {
                return $0.y > $1.y
            }
            return $0.x < $1.x
        }

        var usedArrivals = Set<Int>()
        var detailsByFlight: [String: ScheduleFlightDetail] = [:]

        for departure in orderedDepartures {
            if detailsByFlight[departure.flightNumber] != nil {
                continue
            }

            let candidates = arrivals.enumerated().filter { item in
                let index = item.offset
                let arrival = item.element
                if usedArrivals.contains(index) {
                    return false
                }

                let xDistance = abs(arrival.x - departure.x)
                let yDelta = departure.y - arrival.y
                return xDistance <= 0.08 && yDelta >= 0.003 && yDelta <= 0.15
            }

            guard let best = candidates.min(by: { lhs, rhs in
                let lhsX = abs(lhs.element.x - departure.x)
                let rhsX = abs(rhs.element.x - departure.x)
                if lhsX != rhsX { return lhsX < rhsX }
                let lhsY = departure.y - lhs.element.y
                let rhsY = departure.y - rhs.element.y
                return lhsY < rhsY
            }) else {
                continue
            }

            usedArrivals.insert(best.offset)

            let correctedArrival = correctedArrivalTime(
                departure: departure.departureTime,
                arrival: best.element.arrivalTime,
                origin: departure.origin,
                destination: best.element.destination
            )

            detailsByFlight[departure.flightNumber] = ScheduleFlightDetail(
                flightNumber: departure.flightNumber,
                origin: departure.origin,
                destination: best.element.destination,
                departureTime: departure.departureTime,
                arrivalTime: correctedArrival
            )
        }

        return detailsByFlight
    }

    private func parseFlightsByDayFromScheduleSheet(
        lines: [OCRLine],
        month: Int,
        year: Int,
        validFlightNumbers: Set<String>
    ) -> [Int: [String]] {
        let headers = extractDayHeaders(from: lines)
        guard headers.isEmpty == false else { return [:] }

        let dayCenters = buildDayCenters(headers: headers, month: month, year: year)
        guard dayCenters.count >= 7 else { return [:] }

        let dayBounds = buildDayBounds(from: dayCenters)
        guard dayBounds.isEmpty == false else { return [:] }

        let normalizedValidFlights = Set(
            validFlightNumbers
                .map { $0.strippingLeadingZeros() }
                .filter { $0.isEmpty == false }
        )
        guard normalizedValidFlights.isEmpty == false else { return [:] }

        let gridTopY = detectRosterGridTopY(in: lines, fallback: (headers.map(\.y).max() ?? 0.85) - 0.06)
        let gridBottomY = detectFlightGridBottomY(in: lines, fallback: 0.08)
        guard gridTopY > gridBottomY else { return [:] }

        var hits: [FlightGridHit] = []

        for line in lines {
            let y = line.boundingBox.midY
            guard y <= gridTopY + 0.02, y >= gridBottomY - 0.01 else { continue }
            guard line.boundingBox.width > 0 else { continue }

            let numberMatches = extractNumericTokenMatches(from: line.text)
            guard numberMatches.isEmpty == false else { continue }

            let lineLength = max(1, (line.text as NSString).length)
            for (index, numberMatch) in numberMatches.enumerated() {
                let normalized = numberMatch.value.strippingLeadingZeros()
                guard normalized.isEmpty == false, normalizedValidFlights.contains(normalized) else {
                    continue
                }

                let leading = CGFloat(numberMatch.range.location) + max(1, CGFloat(numberMatch.range.length) * 0.2)
                let ratio = max(0, min(1, leading / CGFloat(lineLength)))
                let x = line.boundingBox.minX + ratio * line.boundingBox.width
                guard let day = dayForX(x, in: dayBounds) else { continue }

                hits.append(
                    FlightGridHit(
                        day: day,
                        flightNumber: normalized,
                        y: y,
                        x: x,
                        tokenIndex: index
                    )
                )
            }
        }

        guard hits.isEmpty == false else { return [:] }

        let adjustedHits = rebalanceLeadingDayHits(hits: hits, dayCenters: dayCenters)

        let grouped = Dictionary(grouping: adjustedHits, by: \.day)
        var byDay: [Int: [String]] = [:]

        for day in grouped.keys.sorted() {
            let ordered = grouped[day, default: []].sorted {
                if abs($0.y - $1.y) > 0.001 {
                    return $0.y > $1.y
                }
                if abs($0.x - $1.x) > 0.001 {
                    return $0.x < $1.x
                }
                return $0.tokenIndex < $1.tokenIndex
            }

            var seen = Set<String>()
            var values: [String] = []

            for hit in ordered {
                if seen.contains(hit.flightNumber) { continue }
                seen.insert(hit.flightNumber)
                values.append(hit.flightNumber)
            }

            if values.isEmpty == false {
                byDay[day] = values
            }
        }

        return byDay
    }

    private func parseFlightsByDayFromPDFPage(
        page: PDFPage,
        month: Int,
        year: Int,
        validFlightNumbers: Set<String>
    ) -> [Int: [String]] {
        let tokens = extractPDFTokens(from: page)
        guard tokens.isEmpty == false else { return [:] }

        let headers = extractPDFDayHeaders(from: tokens, month: month, year: year)
        guard headers.isEmpty == false else { return [:] }

        let dayCenters = buildDayCenters(headers: headers, month: month, year: year)
        guard dayCenters.count >= 7 else { return [:] }

        let dayBounds = buildUnclampedDayBounds(from: dayCenters)
        guard dayBounds.isEmpty == false else { return [:] }

        let validNumbers = Set(
            validFlightNumbers
                .map { $0.strippingLeadingZeros() }
                .filter { $0.isEmpty == false }
        )
        guard validNumbers.isEmpty == false else { return [:] }

        let dayStartX = dayCenters.map(\.x).min() ?? 0
        let flightRowYs = extractFlightNumberRowYs(
            from: tokens,
            minX: dayStartX,
            validFlightNumbers: validNumbers
        )
        guard flightRowYs.isEmpty == false else { return [:] }

        var byDay: [Int: [String]] = [:]

        for rowY in flightRowYs {
            let rowTokens = tokens
                .filter {
                    abs($0.y - rowY) <= 1.6 &&
                    $0.x >= dayStartX - 6
                }
                .sorted(by: { $0.x < $1.x })

            for token in rowTokens {
                guard let number = normalizeFlightNumberToken(token.text),
                      validNumbers.contains(number),
                      let day = dayForX(token.x, in: dayBounds) else {
                    continue
                }

                var dayValues = byDay[day, default: []]
                if dayValues.contains(number) == false {
                    dayValues.append(number)
                    byDay[day] = dayValues
                }
            }
        }

        return byDay
    }

    private func extractPDFTokens(from page: PDFPage) -> [PDFToken] {
        guard let rawText = page.attributedString?.string, rawText.isEmpty == false else {
            return []
        }

        guard let regex = try? NSRegularExpression(pattern: #"\S+"#, options: []) else {
            return []
        }

        let ns = rawText as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: rawText, options: [], range: range)

        var tokens: [PDFToken] = []

        for match in matches {
            let tokenRange = match.range
            guard tokenRange.location != NSNotFound, tokenRange.length > 0 else { continue }

            let text = ns.substring(with: tokenRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.isEmpty == false else { continue }

            guard let selection = page.selection(for: tokenRange) else { continue }
            let bounds = selection.bounds(for: page)
            guard bounds.isEmpty == false else { continue }

            tokens.append(PDFToken(text: text, boundingBox: bounds))
        }

        return tokens
    }

    private func extractPDFDayHeaders(
        from tokens: [PDFToken],
        month: Int,
        year: Int
    ) -> [DayHeader] {
        let dayCount = numberOfDaysInMonth(month: month, year: year)

        let candidates = tokens.compactMap { token -> DayHeader? in
            guard let day = dayFromPDFHeaderToken(token.text),
                  (1...dayCount).contains(day) else {
                return nil
            }
            return DayHeader(day: day, weekday: nil, x: token.x, y: token.y)
        }

        guard candidates.isEmpty == false else { return [] }

        let buckets = clusterYValues(candidates, tolerance: 2.8)
        guard let best = buckets.max(by: { uniqueDayCount($0) < uniqueDayCount($1) }),
              uniqueDayCount(best) >= 7 else {
            return []
        }

        var grouped: [Int: [DayHeader]] = [:]
        for item in best {
            grouped[item.day, default: []].append(item)
        }

        return grouped.keys.sorted().compactMap { day in
            let items = grouped[day, default: []]
            guard items.isEmpty == false else { return nil }
            let avgX = items.map(\.x).reduce(0, +) / CGFloat(items.count)
            let avgY = items.map(\.y).reduce(0, +) / CGFloat(items.count)
            return DayHeader(day: day, weekday: nil, x: avgX, y: avgY)
        }
    }

    private func dayFromPDFHeaderToken(_ value: String) -> Int? {
        let token = value
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9]", with: "", options: .regularExpression)

        guard let regex = try? NSRegularExpression(
            pattern: #"^([12]?\d|3[01])(SUN|MON|TUE|WED|THU|FRI|SAT)$"#,
            options: []
        ) else {
            return nil
        }

        let ns = token as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: token, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }

        let dayText = ns.substring(with: match.range(at: 1))
        return Int(dayText)
    }

    private func extractFlightNumberRowYs(
        from tokens: [PDFToken],
        minX: CGFloat,
        validFlightNumbers: Set<String>
    ) -> [CGFloat] {
        let fltTokens = tokens.filter {
            normalizedLine($0.text) == "FLT" && $0.x < minX
        }

        guard fltTokens.isEmpty == false else { return [] }

        let fltYs = fltTokens.map(\.y).sorted(by: >)

        let validNumberTokens = tokens.filter { token in
            guard token.x >= minX - 6,
                  let number = normalizeFlightNumberToken(token.text),
                  validFlightNumbers.contains(number) else {
                return false
            }
            return true
        }

        guard validNumberTokens.isEmpty == false else { return [] }

        let clusters = clusterPDFTokensByY(validNumberTokens, tolerance: 1.3)

        let linkedClusters = clusters.compactMap { cluster -> CGFloat? in
            let avgY = cluster.map(\.y).reduce(0, +) / CGFloat(cluster.count)
            let hasFltLabelBelow = fltYs.contains(where: { fltY in
                avgY > fltY && (avgY - fltY) <= 12.5
            })
            return hasFltLabelBelow ? avgY : nil
        }

        return linkedClusters.sorted(by: >)
    }

    // MARK: - Position-Based Flight Detail Parsing

    /// Parses the FLT/DEP/ARR detail table from the PDF page using token positions.
    /// This avoids the text-flattening issue where regex matches across row boundaries.
    private func parseFlightDetailsFromPDFPage(page: PDFPage, month: Int = 0, year: Int = 0) -> [String: ScheduleFlightDetail] {
        let tokens = extractPDFTokens(from: page)
        guard tokens.isEmpty == false else { return [:] }

        // Build day bounds for duty code day assignment
        let pdfDayHeaders = extractPDFDayHeaders(from: tokens, month: month, year: year)
        let pdfDayCenters = buildDayCenters(headers: pdfDayHeaders, month: month, year: year)
        let pdfDayBounds = buildUnclampedDayBounds(from: pdfDayCenters)

        // Find FLT/DEP/ARR label tokens (always at x < 80, on the left side)
        let fltLabels = tokens
            .filter { normalizedLine($0.text) == "FLT" && $0.x < 80 }
            .sorted(by: { $0.y > $1.y }) // PDFKit: higher y = higher on page
        let depLabels = tokens
            .filter { normalizedLine($0.text) == "DEP" && $0.x < 80 }
            .sorted(by: { $0.y > $1.y })
        let arrLabels = tokens
            .filter { normalizedLine($0.text) == "ARR" && $0.x < 80 }
            .sorted(by: { $0.y > $1.y })

        guard fltLabels.isEmpty == false else { return [:] }

        var result: [String: ScheduleFlightDetail] = [:]
        var usedDepYs: Set<Int> = []
        var usedArrYs: Set<Int> = []

        for fltLabel in fltLabels {
            // Find the DEP label closest below the FLT label (lower y in PDFKit)
            // Skip labels already claimed by a previous FLT block.
            guard let depLabel = depLabels.first(where: {
                $0.y < fltLabel.y && (fltLabel.y - $0.y) < 40
                && !usedDepYs.contains(Int($0.y * 1000))
            }) else { continue }

            // Find the ARR label closest below DEP
            guard let arrLabel = arrLabels.first(where: {
                $0.y < depLabel.y && (depLabel.y - $0.y) < 40
                && !usedArrYs.contains(Int($0.y * 1000))
            }) else { continue }

            usedDepYs.insert(Int(depLabel.y * 1000))
            usedArrYs.insert(Int(arrLabel.y * 1000))

            // PDFKit: origin at bottom-left, y increases upward.
            // Layout per block: FLT data → FLT label → DEP data → DEP label → ARR data → ARR label → ARR times
            // Note: ARR times can extend BELOW the ARR label.

            let fltMidY = fltLabel.y
            let depMidY = depLabel.y
            let arrMidY = arrLabel.y

            // Extract tokens in the data area (x >= 80, in the grid columns)
            let dataTokens = tokens.filter { $0.x >= 80 }

            // FLT row: tokens near the fltLabel y-level (within ±4 units, or up to 8 above)
            let fltRowTokens = dataTokens
                .filter { abs($0.y - fltMidY) < 4 || ($0.y > fltMidY && ($0.y - fltMidY) < 8) }
                .sorted(by: { $0.x < $1.x })

            // DEP band: all tokens between FLT label and DEP label (with a small margin)
            let depBandTokens = dataTokens
                .filter { $0.y < (fltMidY - 2) && $0.y > depMidY }
                .sorted(by: { $0.x < $1.x })

            // ARR band: all tokens between DEP label and below ARR label (within 10 below)
            let arrBandTokens = dataTokens
                .filter { $0.y < depMidY && $0.y > (arrMidY - 10) }
                .sorted(by: { $0.x < $1.x })

            // Use x-proximity matching instead of index-based matching.
            // Index matching breaks when duty codes (TRG, SBY) in the FLT row
            // have no airport codes in the DEP band, causing array length mismatches.
            let depOrigins = depBandTokens.filter { isAirportCodeToken($0.text.uppercased()) }
            let depTimes = depBandTokens.filter { isTimeToken($0.text) }
            let arrDests = arrBandTokens.filter { isAirportCodeToken($0.text.uppercased()) }
            let arrTimes = arrBandTokens.filter { isTimeToken($0.text) }

            // Estimate column width from day headers for ARR tolerance (overnight flights
            // have ARR data in the next day's column, so allow wider x-search)
            let estimatedColumnWidth: CGFloat = fltRowTokens.count >= 2
                ? (fltRowTokens.last!.x - fltRowTokens.first!.x) / CGFloat(fltRowTokens.count - 1)
                : 30.0

            for fltToken in fltRowTokens {
                guard let flightNumber = normalizeFlightNumberToken(fltToken.text) else { continue }
                guard result[flightNumber] == nil else { continue }

                let fx = fltToken.x
                let depProximity: CGFloat = 15.0
                let arrProximity: CGFloat = max(20.0, estimatedColumnWidth * 1.5)

                // Find nearest DEP origin and time by x-proximity (same column)
                guard let origin = depOrigins.min(by: { abs($0.x - fx) < abs($1.x - fx) }),
                      abs(origin.x - fx) < depProximity else { continue }
                guard let depTime = depTimes.min(by: { abs($0.x - fx) < abs($1.x - fx) }),
                      abs(depTime.x - fx) < depProximity else { continue }

                // For ARR, only search RIGHTWARD (same column or next day).
                // Overnight flights have arrival data in the next day's column (higher x).
                // Without this filter, a previous flight's arrival (to the left) can be
                // fractionally closer and incorrectly matched (e.g. TG 325 BKK→BKK instead of BKK→BLR).
                let arrDestsRight = arrDests.filter { $0.x >= fx - 5 }
                let arrTimesRight = arrTimes.filter { $0.x >= fx - 5 }
                guard let dest = arrDestsRight.min(by: { abs($0.x - fx) < abs($1.x - fx) }),
                      abs(dest.x - fx) < arrProximity else { continue }
                guard let arrTime = arrTimesRight.min(by: { abs($0.x - fx) < abs($1.x - fx) }),
                      abs(arrTime.x - fx) < arrProximity else { continue }

                result[flightNumber] = ScheduleFlightDetail(
                    flightNumber: flightNumber,
                    origin: origin.text.uppercased(),
                    destination: dest.text.uppercased(),
                    departureTime: normalizeDetailTime(depTime.text),
                    arrivalTime: normalizeDetailTime(arrTime.text)
                )
            }

            // Duty code detection: TRG, SBY, REST, OFF, etc. in the FLT row.
            // These are alphabetic tokens that have NO origin airport nearby
            // (flights always have an origin, duties only have times).
            //
            // IMPORTANT: Duty code times may NOT be in the DEP/ARR bands.
            // Thai Airways rosters have a DUTY area ABOVE the FLT row (y > fltMidY)
            // where duty codes and their times are stacked vertically per day column.
            // We search both the DEP/ARR bands AND the DUTY area above.
            if pdfDayBounds.isEmpty == false {
                // Extract time tokens from the DUTY area above the FLT row.
                // This area sits between the FLT row and the day headers (~60pt above).
                let dutyAreaTimes = dataTokens
                    .filter { $0.y > (fltMidY + 8) && $0.y < (fltMidY + 70) }
                    .filter { isTimeToken($0.text) }

                for fltToken in fltRowTokens {
                    // Skip if it was already matched as a flight number
                    if normalizeFlightNumberToken(fltToken.text) != nil { continue }

                    let code = fltToken.text.uppercased()
                        .replacingOccurrences(of: "[^A-Z]", with: "", options: .regularExpression)
                    guard (2...10).contains(code.count),
                          code.allSatisfy({ $0 >= "A" && $0 <= "Z" }),
                          !isExcludedDutyToken(code) else { continue }

                    let fx = fltToken.x
                    guard let day = dayForX(fx, in: pdfDayBounds) else { continue }

                    // If there's an origin airport near this x-position, it's likely
                    // a misread flight, not a duty code — skip it.
                    let nearOrigin = depOrigins.min(by: { abs($0.x - fx) < abs($1.x - fx) })
                    if let origin = nearOrigin, abs(origin.x - fx) < 10 { continue }

                    let dutyKey = "__DUTY_\(day)_\(code)"

                    // Find nearest dep/arr times by x-proximity.
                    // Try DEP/ARR bands first, then fall back to DUTY area above.
                    let nearDepTime = depTimes.min(by: { abs($0.x - fx) < abs($1.x - fx) })
                    let nearArrTime = arrTimes.min(by: { abs($0.x - fx) < abs($1.x - fx) })

                    var depTimeStr: String?
                    var arrTimeStr: String?

                    // Strategy 1: DEP/ARR band times (standard FLT block layout)
                    if let dep = nearDepTime, abs(dep.x - fx) < 20 {
                        depTimeStr = normalizeDetailTime(dep.text)
                    }
                    if let arr = nearArrTime, abs(arr.x - fx) < 20 {
                        arrTimeStr = normalizeDetailTime(arr.text)
                    }

                    // Strategy 2: DUTY area above FLT row (Thai Airways compact layout)
                    // Times are stacked vertically per day column: dep at higher y, arr at lower y.
                    if depTimeStr == nil || arrTimeStr == nil {
                        let columnTimes = dutyAreaTimes
                            .filter { abs($0.x - fx) < 8 }
                            .sorted { $0.y > $1.y } // highest y first = earliest time (dep)

                        if columnTimes.count >= 2 {
                            if depTimeStr == nil {
                                depTimeStr = normalizeDetailTime(columnTimes.first!.text)
                            }
                            if arrTimeStr == nil {
                                arrTimeStr = normalizeDetailTime(columnTimes.last!.text)
                            }
                        } else if columnTimes.count == 1 {
                            // Single time — use as both dep and arr
                            let t = normalizeDetailTime(columnTimes[0].text)
                            if depTimeStr == nil { depTimeStr = t }
                            if arrTimeStr == nil { arrTimeStr = t }
                        }
                    }

                    guard let finalDep = depTimeStr, let finalArr = arrTimeStr else { continue }

                    // If duty key already exists (e.g. TRG has morning + afternoon sessions
                    // in separate FLT blocks), extend the time range to cover all sessions.
                    if let existing = result[dutyKey] {
                        let earlierDep = min(existing.departureTime, finalDep)
                        let laterArr = max(existing.arrivalTime, finalArr)
                        result[dutyKey] = ScheduleFlightDetail(
                            flightNumber: code,
                            origin: "",
                            destination: "",
                            departureTime: earlierDep,
                            arrivalTime: laterArr
                        )
                    } else {
                        result[dutyKey] = ScheduleFlightDetail(
                            flightNumber: code,
                            origin: "",
                            destination: "",
                            departureTime: finalDep,
                            arrivalTime: finalArr
                        )
                    }
                }
            }
        }

        return result
    }

    private func isTimeToken(_ text: String) -> Bool {
        let digits = text.filter(\.isNumber)
        if digits.count == 4 || digits.count == 3 {
            return true
        }
        if text.contains(":"), digits.count >= 3 {
            return true
        }
        return false
    }

    private func normalizeDetailTime(_ text: String) -> String {
        let digits = text.filter(\.isNumber)
        let hhmm: String
        if digits.count == 3 {
            hhmm = "0" + digits
        } else if digits.count == 4 {
            hhmm = digits
        } else {
            return text
        }
        let h = String(hhmm.prefix(2))
        let m = String(hhmm.suffix(2))
        return "\(h):\(m)"
    }

    private func clusterPDFTokensByY(
        _ tokens: [PDFToken],
        tolerance: CGFloat
    ) -> [[PDFToken]] {
        var buckets: [[PDFToken]] = []

        for token in tokens.sorted(by: { $0.y > $1.y }) {
            if let index = buckets.firstIndex(where: { bucket in
                let avgY = bucket.map(\.y).reduce(0, +) / CGFloat(bucket.count)
                return abs(avgY - token.y) <= tolerance
            }) {
                buckets[index].append(token)
            } else {
                buckets.append([token])
            }
        }

        return buckets
    }

    private func buildUnclampedDayBounds(
        from centers: [(day: Int, x: CGFloat)]
    ) -> [(day: Int, range: ClosedRange<CGFloat>)] {
        guard centers.isEmpty == false else { return [] }

        let orderedCenters = centers.sorted(by: { $0.x < $1.x })
        var bounds: [(day: Int, range: ClosedRange<CGFloat>)] = []

        for index in orderedCenters.indices {
            let current = orderedCenters[index]

            let left: CGFloat
            if index == 0 {
                if orderedCenters.count > 1 {
                    let delta = orderedCenters[1].x - current.x
                    left = current.x - delta / 2
                } else {
                    left = current.x - 10
                }
            } else {
                left = (orderedCenters[index - 1].x + current.x) / 2
            }

            let right: CGFloat
            if index == orderedCenters.count - 1 {
                if orderedCenters.count > 1 {
                    let delta = current.x - orderedCenters[index - 1].x
                    right = current.x + delta / 2
                } else {
                    right = current.x + 10
                }
            } else {
                right = (current.x + orderedCenters[index + 1].x) / 2
            }

            let lower = min(left, right)
            let upper = max(left, right)
            bounds.append((day: current.day, range: lower...upper))
        }

        return bounds
    }

    private func clusterYValues(_ headers: [DayHeader], tolerance: CGFloat) -> [[DayHeader]] {
        var buckets: [[DayHeader]] = []

        for header in headers.sorted(by: { $0.y > $1.y }) {
            if let index = buckets.firstIndex(where: { bucket in
                let avgY = bucket.map(\.y).reduce(0, +) / CGFloat(bucket.count)
                return abs(avgY - header.y) <= tolerance
            }) {
                buckets[index].append(header)
            } else {
                buckets.append([header])
            }
        }

        return buckets
    }

    private func normalizeFlightNumberToken(_ token: String) -> String? {
        let cleaned = token
            .replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        guard cleaned.isEmpty == false, cleaned.count <= 4 else { return nil }
        let normalized = cleaned.strippingLeadingZeros()
        guard normalized != "0" else { return nil }
        // TG flights are 3+ digits (e.g. TG 102). Reject single-digit numbers
        // which are almost always misread day labels or stray OCR artifacts.
        guard let value = Int(normalized), value >= 10 else { return nil }
        return normalized
    }

    private func extractDayHeaders(from lines: [OCRLine]) -> [DayHeader] {
        var candidates: [DayHeader] = []

        for line in lines {
            let dayMatches = extractDayTokenMatches(from: line.text)
            guard dayMatches.isEmpty == false else { continue }

            let minX = line.boundingBox.minX
            let maxX = line.boundingBox.maxX
            let width = maxX - minX
            guard width > 0 else { continue }

            let textLength = max(1, (line.text as NSString).length)
            for match in dayMatches {
                let center = CGFloat(match.range.location) + (CGFloat(match.range.length) / 2)
                let ratio = max(0, min(1, center / CGFloat(textLength)))
                let x = minX + ratio * width
                candidates.append(
                    DayHeader(
                        day: match.day,
                        weekday: match.weekday,
                        x: x,
                        y: line.boundingBox.midY
                    )
                )
            }
        }

        if candidates.isEmpty {
            candidates = extractLooseDayHeaders(from: lines)
        }

        guard candidates.isEmpty == false else { return [] }

        var buckets: [[DayHeader]] = []

        for candidate in candidates.sorted(by: { $0.y > $1.y }) {
            if let index = buckets.firstIndex(where: { bucket in
                let avg = bucket.map(\.y).reduce(0, +) / CGFloat(bucket.count)
                return abs(avg - candidate.y) < 0.03
            }) {
                buckets[index].append(candidate)
            } else {
                buckets.append([candidate])
            }
        }

        guard let bestBucket = buckets.max(by: { uniqueDayCount($0) < uniqueDayCount($1) }),
              uniqueDayCount(bestBucket) >= 7 else {
            return []
        }

        var grouped: [Int: [DayHeader]] = [:]
        for header in bestBucket {
            grouped[header.day, default: []].append(header)
        }

        var normalized: [DayHeader] = []
        for day in grouped.keys.sorted() {
            let items = grouped[day, default: []]
            let avgX = items.map(\.x).reduce(0, +) / CGFloat(items.count)
            let avgY = items.map(\.y).reduce(0, +) / CGFloat(items.count)
            let weekday = mostCommonWeekday(in: items)
            normalized.append(DayHeader(day: day, weekday: weekday, x: avgX, y: avgY))
        }

        return normalized
    }

    private func buildDayCenters(
        headers: [DayHeader],
        month: Int,
        year: Int
    ) -> [(day: Int, x: CGFloat)] {
        guard headers.isEmpty == false else { return [] }

        let dayCount = numberOfDaysInMonth(month: month, year: year)

        var dayXs: [Int: [CGFloat]] = [:]
        for header in headers {
            guard let correctedDay = correctedDay(for: header, month: month, year: year, dayCount: dayCount),
                  (1...dayCount).contains(correctedDay) else {
                continue
            }
            dayXs[correctedDay, default: []].append(header.x)
        }

        var byDay: [Int: CGFloat] = [:]
        for day in dayXs.keys {
            let xs = dayXs[day, default: []]
            guard xs.isEmpty == false else { continue }
            byDay[day] = xs.reduce(0, +) / CGFloat(xs.count)
        }

        if byDay.count < 7 {
            let inferred = inferredDayMappingFromSequence(
                headers: headers,
                month: month,
                year: year,
                dayCount: dayCount
            )
            for (day, x) in inferred where byDay[day] == nil {
                byDay[day] = x
            }
        }

        let sortedKnown = byDay.keys.sorted()
        guard sortedKnown.isEmpty == false else { return [] }

        if sortedKnown.count >= 2,
           let firstDay = sortedKnown.first,
           let lastDay = sortedKnown.last,
           let firstX = byDay[firstDay],
           let lastX = byDay[lastDay] {
            let divisor = max(1, lastDay - firstDay)
            let step = (lastX - firstX) / CGFloat(divisor)

            for day in 1...dayCount where byDay[day] == nil {
                byDay[day] = firstX + CGFloat(day - firstDay) * step
            }
        }

        return (1...dayCount)
            .compactMap { day in
                guard let x = byDay[day] else { return nil }
                return (day: day, x: x)
            }
            .sorted(by: { $0.day < $1.day })
    }

    private func correctedDay(
        for header: DayHeader,
        month: Int,
        year: Int,
        dayCount: Int
    ) -> Int? {
        let base = header.day
        guard (1...dayCount).contains(base) else { return nil }

        guard let observedWeekday = header.weekday else {
            return base
        }

        if weekdayForDay(base, month: month, year: year) == observedWeekday {
            return base
        }

        let candidates = (1...dayCount).filter { day in
            weekdayForDay(day, month: month, year: year) == observedWeekday
        }
        guard candidates.isEmpty == false else { return base }

        return candidates.min(by: { lhs, rhs in
            abs(lhs - base) < abs(rhs - base)
        })
    }

    private func inferredDayMappingFromSequence(
        headers: [DayHeader],
        month: Int,
        year: Int,
        dayCount: Int
    ) -> [Int: CGFloat] {
        guard headers.isEmpty == false else { return [:] }

        let ordered = dedupeHeadersByX(headers)
        guard ordered.count >= 2 else { return [:] }

        var bestStartDay: Int?
        var bestScore = Int.min

        for (index, header) in ordered.enumerated() {
            let candidateStart = header.day - index
            let score = scoreDaySequence(
                startDay: candidateStart,
                orderedHeaders: ordered,
                month: month,
                year: year,
                dayCount: dayCount
            )
            if score > bestScore {
                bestScore = score
                bestStartDay = candidateStart
            }
        }

        guard let startDay = bestStartDay else { return [:] }

        var dayXs: [Int: [CGFloat]] = [:]
        for (index, header) in ordered.enumerated() {
            let day = startDay + index
            guard (1...dayCount).contains(day) else { continue }
            dayXs[day, default: []].append(header.x)
        }

        var mapped: [Int: CGFloat] = [:]
        for day in dayXs.keys {
            let xs = dayXs[day, default: []]
            guard xs.isEmpty == false else { continue }
            mapped[day] = xs.reduce(0, +) / CGFloat(xs.count)
        }
        return mapped
    }

    private func dedupeHeadersByX(_ headers: [DayHeader]) -> [DayHeader] {
        let ordered = headers.sorted { $0.x < $1.x }
        var deduped: [DayHeader] = []

        for header in ordered {
            if let last = deduped.last, abs(last.x - header.x) < 0.006 {
                // Keep the one with a weekday label if available.
                if last.weekday == nil, header.weekday != nil {
                    deduped.removeLast()
                    deduped.append(header)
                }
            } else {
                deduped.append(header)
            }
        }

        return deduped
    }

    private func scoreDaySequence(
        startDay: Int,
        orderedHeaders: [DayHeader],
        month: Int,
        year: Int,
        dayCount: Int
    ) -> Int {
        var score = 0

        for (index, header) in orderedHeaders.enumerated() {
            let inferredDay = startDay + index
            guard (1...dayCount).contains(inferredDay) else {
                score -= 2
                continue
            }

            let distance = abs(inferredDay - header.day)
            if distance == 0 {
                score += 3
            } else if distance == 1 {
                score += 2
            } else if distance <= 2 {
                score += 1
            } else {
                score -= 2
            }

            if let observedWeekday = header.weekday,
               let expectedWeekday = weekdayForDay(inferredDay, month: month, year: year) {
                score += (observedWeekday == expectedWeekday) ? 4 : -3
            }
        }

        return score
    }

    private func weekdayForDay(_ day: Int, month: Int, year: Int) -> Int? {
        var components = DateComponents()
        components.calendar = .roster
        components.timeZone = rosterTimeZone
        components.year = year
        components.month = month
        components.day = day

        guard let date = components.date else { return nil }
        return Calendar.roster.component(.weekday, from: date)
    }

    private func mostCommonWeekday(in headers: [DayHeader]) -> Int? {
        var counts: [Int: Int] = [:]
        for weekday in headers.compactMap(\.weekday) {
            counts[weekday, default: 0] += 1
        }

        return counts.max(by: { $0.value < $1.value })?.key
    }

    private func buildDayBounds(from centers: [(day: Int, x: CGFloat)]) -> [(day: Int, range: ClosedRange<CGFloat>)] {
        guard centers.isEmpty == false else { return [] }

        let orderedCenters = centers.sorted(by: { $0.x < $1.x })
        var bounds: [(day: Int, range: ClosedRange<CGFloat>)] = []

        for index in orderedCenters.indices {
            let current = orderedCenters[index]

            let left: CGFloat
            if index == 0 {
                if orderedCenters.count > 1 {
                    let delta = orderedCenters[1].x - current.x
                    left = max(0, current.x - delta / 2)
                } else {
                    left = 0
                }
            } else {
                left = (orderedCenters[index - 1].x + current.x) / 2
            }

            let right: CGFloat
            if index == orderedCenters.count - 1 {
                if orderedCenters.count > 1 {
                    let delta = current.x - orderedCenters[index - 1].x
                    right = min(1, current.x + delta / 2)
                } else {
                    right = 1
                }
            } else {
                right = (current.x + orderedCenters[index + 1].x) / 2
            }

            let lower = min(left, right)
            let upper = max(left, right)
            bounds.append((day: current.day, range: lower...upper))
        }

        return bounds
    }

    private func dayForX(_ x: CGFloat, in dayBounds: [(day: Int, range: ClosedRange<CGFloat>)]) -> Int? {
        for item in dayBounds where item.range.contains(x) {
            return item.day
        }

        let nearest = dayBounds.min { lhs, rhs in
            abs(lhs.range.lowerBound + lhs.range.upperBound - 2 * x)
                < abs(rhs.range.lowerBound + rhs.range.upperBound - 2 * x)
        }
        return nearest?.day
    }

    private func detectFlightGridTopY(in lines: [OCRLine], fallback: CGFloat) -> CGFloat {
        let fltCandidates = lines
            .filter {
                let normalized = normalizedLine($0.text)
                return normalized == "FLT" || normalized.hasPrefix("FLT ") || normalized.contains(" FLT ")
            }
            .map { $0.boundingBox.midY }

        if let top = fltCandidates.max() {
            return top
        }

        return fallback
    }

    private func detectRosterGridTopY(in lines: [OCRLine], fallback: CGFloat) -> CGFloat {
        let dutyCandidates = lines
            .filter {
                let normalized = normalizedLine($0.text)
                return normalized == "DUTY"
                    || normalized.hasPrefix("DUTY ")
                    || normalized.contains(" DUTY ")
            }
            .map { $0.boundingBox.midY }

        if let dutyTop = dutyCandidates.max() {
            return dutyTop
        }

        return detectFlightGridTopY(in: lines, fallback: fallback)
    }

    private func detectFlightGridBottomY(in lines: [OCRLine], fallback: CGFloat) -> CGFloat {
        let blockCandidates = lines
            .filter {
                let normalized = normalizedLine($0.text)
                return normalized == "FLT"
                    || normalized == "DEP"
                    || normalized == "ARR"
                    || normalized.hasPrefix("FLT ")
                    || normalized.hasPrefix("DEP ")
                    || normalized.hasPrefix("ARR ")
            }
            .map { $0.boundingBox.midY }

        if let bottom = blockCandidates.min() {
            return max(0, bottom - 0.03)
        }

        return fallback
    }

    private func extractDayTokenMatches(from text: String) -> [(day: Int, weekday: Int?, range: NSRange)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([12]?\d|3[01])\s*(SUN|MON|TUE|WED|THU|FRI|SAT)\b"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let upper = text.uppercased()
        let ns = upper as NSString
        let range = NSRange(location: 0, length: ns.length)

        return regex.matches(in: upper, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            let dayText = ns.substring(with: match.range(at: 1))
            let weekdayText = ns.substring(with: match.range(at: 2))
            guard let day = Int(dayText), (1...31).contains(day) else { return nil }
            return (
                day: day,
                weekday: weekdayIndex(from: weekdayText),
                range: match.range(at: 0)
            )
        }
    }

    private func extractLooseDayHeaders(from lines: [OCRLine]) -> [DayHeader] {
        guard lines.isEmpty == false else { return [] }
        guard let regex = try? NSRegularExpression(pattern: #"\b([12]?\d|3[01])\b"#, options: []) else {
            return []
        }

        let maxY = lines.map { $0.boundingBox.maxY }.max() ?? 1
        let topThreshold = max(0.45, maxY - 0.25)
        var headers: [DayHeader] = []

        for line in lines where line.boundingBox.midY >= topThreshold {
            let normalized = normalizedLine(line.text)
            if normalized.contains("FLT") || normalized.contains("DEP") || normalized.contains("ARR") {
                continue
            }

            let upper = line.text.uppercased()
            let ns = upper as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            let matches = regex.matches(in: upper, options: [], range: fullRange)
            guard matches.isEmpty == false else { continue }

            let minX = line.boundingBox.minX
            let width = line.boundingBox.width
            guard width > 0 else { continue }
            let lineLength = max(1, ns.length)

            for match in matches where match.numberOfRanges > 1 {
                let value = ns.substring(with: match.range(at: 1))
                guard let day = Int(value), (1...31).contains(day) else { continue }
                let center = CGFloat(match.range(at: 1).location) + (CGFloat(match.range(at: 1).length) / 2)
                let ratio = max(0, min(1, center / CGFloat(lineLength)))
                let x = minX + ratio * width
                headers.append(
                    DayHeader(day: day, weekday: nil, x: x, y: line.boundingBox.midY)
                )
            }
        }

        return headers
    }

    private func weekdayIndex(from text: String) -> Int? {
        switch text.uppercased() {
        case "SUN": return 1
        case "MON": return 2
        case "TUE": return 3
        case "WED": return 4
        case "THU": return 5
        case "FRI": return 6
        case "SAT": return 7
        default: return nil
        }
    }

    private func extractNumericTokenMatches(from text: String) -> [(value: String, range: NSRange)] {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{1,4})\b"#, options: []) else {
            return []
        }

        let upper = text.uppercased()
        let ns = upper as NSString
        let range = NSRange(location: 0, length: ns.length)

        return regex.matches(in: upper, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return (value: ns.substring(with: match.range(at: 1)), range: match.range(at: 1))
        }
    }

    private func parseFlightDetails(in text: String) -> [String: ScheduleFlightDetail] {
        let flattened = text
            .uppercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard flattened.isEmpty == false else { return [:] }

        // Prefer explicit time separators first (e.g., 07:45) to avoid
        // accidentally reading DUTY row flight numbers as times.
        let strictPattern = #"(?:ARR\s+)?(\d{1,4})\s+([A-Z]{3})\s+([0-2]?\d[:.][0-5]\d)\s+([A-Z]{3})\s+([0-2]?\d[:.][0-5]\d)"#
        let strict = parseFlightDetails(in: flattened, pattern: strictPattern)
        if strict.isEmpty == false {
            return strict
        }

        // OCR fallback: allow HHmm only (4 digits), but still reject 3-digit
        // values that commonly come from flight numbers in DUTY row (e.g., 628).
        let loosePattern = #"(?:ARR\s+)?(\d{1,4})\s+([A-Z]{3})\s+(\d{4})\s+([A-Z]{3})\s+(\d{4})"#
        return parseFlightDetails(in: flattened, pattern: loosePattern)
    }

    private func parseFlightDetails(in flattenedText: String, pattern: String) -> [String: ScheduleFlightDetail] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [:]
        }

        let nsText = flattenedText as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var result: [String: ScheduleFlightDetail] = [:]

        for match in regex.matches(in: flattenedText, options: [], range: fullRange) {
            guard match.numberOfRanges == 6 else { continue }

            let rawNumber = nsText.substring(with: match.range(at: 1))
            let origin = nsText.substring(with: match.range(at: 2))
            let departureRaw = nsText.substring(with: match.range(at: 3))
            let destination = nsText.substring(with: match.range(at: 4))
            let arrivalRaw = nsText.substring(with: match.range(at: 5))

            let number = rawNumber.strippingLeadingZeros()
            guard number.isEmpty == false,
                  let departure = normalizedTime(departureRaw),
                  let arrival = normalizedTime(arrivalRaw) else {
                continue
            }

            let correctedArrival = correctedArrivalTime(
                departure: departure,
                arrival: arrival,
                origin: origin,
                destination: destination
            )

            let detail = ScheduleFlightDetail(
                flightNumber: number,
                origin: origin,
                destination: destination,
                departureTime: departure,
                arrivalTime: correctedArrival
            )

            if result[number] == nil {
                result[number] = detail
            }
        }

        return result
    }

    private func normalizedTime(_ value: String) -> String? {
        let digits = value.filter(\.isNumber)
        guard digits.isEmpty == false else { return nil }

        let hhmm: String
        if digits.count == 3 {
            hhmm = "0" + digits
        } else if digits.count == 4 {
            hhmm = digits
        } else {
            return nil
        }

        guard let hour = Int(hhmm.prefix(2)),
              let minute = Int(hhmm.suffix(2)),
              (0...23).contains(hour),
              (0...59).contains(minute) else {
            return nil
        }

        return hhmm
    }

    private func extractText(from document: PDFDocument) -> String {
        var chunks: [String] = []
        let pagesToInspect = min(document.pageCount, Self.maxTextExtractionPages)
        for index in 0..<pagesToInspect {
            guard let page = document.page(at: index),
                  let text = page.string,
                  text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                continue
            }
            chunks.append(text)
        }

        return chunks.joined(separator: "\n")
    }

    private func render(page: PDFPage, scale: CGFloat) -> UIImage? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.isEmpty == false else { return nil }
        guard pageBounds.width.isFinite, pageBounds.height.isFinite,
              pageBounds.width > 0, pageBounds.height > 0 else {
            return nil
        }

        let baseWidth = pageBounds.width
        let baseHeight = pageBounds.height

        var safeScale = scale
        let maxSide = max(baseWidth, baseHeight)
        if maxSide * safeScale > Self.maxRenderDimension {
            safeScale = Self.maxRenderDimension / maxSide
        }

        let basePixels = baseWidth * baseHeight
        if basePixels > 0 {
            let scaledPixels = basePixels * safeScale * safeScale
            if scaledPixels > Self.maxRenderPixels {
                safeScale = min(safeScale, sqrt(Self.maxRenderPixels / basePixels))
            }
        }

        guard safeScale.isFinite, safeScale > 0 else { return nil }

        let size = CGSize(width: baseWidth * safeScale, height: baseHeight * safeScale)
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let cg = context.cgContext
            cg.saveGState()
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: safeScale, y: -safeScale)
            cg.translateBy(x: -pageBounds.origin.x, y: -pageBounds.origin.y)
            page.draw(with: .mediaBox, to: cg)
            cg.restoreGState()
        }

        return image
    }

    private func normalizeFlightsByDay(_ raw: [Int: [String]]) -> [Int: [String]] {
        var output: [Int: [String]] = [:]

        for day in raw.keys.sorted() {
            let values = raw[day, default: []]
            var seen = Set<String>()
            var normalizedDay: [String] = []

            for rawNumber in values {
                let digits = String(rawNumber.filter(\.isNumber).prefix(5)).strippingLeadingZeros()
                guard digits.isEmpty == false else { continue }
                if seen.contains(digits) { continue }
                seen.insert(digits)
                normalizedDay.append(digits)
            }

            if normalizedDay.isEmpty == false {
                output[day] = normalizedDay
            }
        }

        return output
    }

    private func detectMonthYear(in text: String) -> (month: Int, year: Int)? {
        let upper = text.uppercased()

        if let effective = detectMonthYearFromEffectiveLine(in: upper) {
            return effective
        }

        if let named = detectNamedMonthYear(in: upper) {
            return named
        }

        return nil
    }

    private func detectMonthYearFromEffectiveLine(in text: String) -> (month: Int, year: Int)? {
        let pattern = #"EFFECTIVE\s*:\s*\d{1,2}([A-Z]{3,9})(\d{2,4})\s*-\s*\d{1,2}[A-Z]{3,9}\d{2,4}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges == 3 else {
            return nil
        }

        let monthText = nsText.substring(with: match.range(at: 1))
        let yearText = nsText.substring(with: match.range(at: 2))

        guard let month = monthFromName(monthText),
              let year = normalizedYear(yearText) else {
            return nil
        }

        return (month: month, year: year)
    }

    private func detectNamedMonthYear(in text: String) -> (month: Int, year: Int)? {
        let pattern = #"\b(JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|APR(?:IL)?|MAY|JUN(?:E)?|JUL(?:Y)?|AUG(?:UST)?|SEP(?:T)?(?:EMBER)?|OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)\s*(20\d{2}|\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges == 3 else {
            return nil
        }

        let monthText = nsText.substring(with: match.range(at: 1))
        let yearText = nsText.substring(with: match.range(at: 2))

        guard let month = monthFromName(monthText),
              let year = normalizedYear(yearText) else {
            return nil
        }

        return (month: month, year: year)
    }

    private func monthFromName(_ monthText: String) -> Int? {
        let normalized = monthText.trimmingCharacters(in: .whitespacesAndNewlines)
        let mapping: [String: Int] = [
            "JAN": 1, "JANUARY": 1,
            "FEB": 2, "FEBRUARY": 2,
            "MAR": 3, "MARCH": 3,
            "APR": 4, "APRIL": 4,
            "MAY": 5,
            "JUN": 6, "JUNE": 6,
            "JUL": 7, "JULY": 7,
            "AUG": 8, "AUGUST": 8,
            "SEP": 9, "SEPT": 9, "SEPTEMBER": 9,
            "OCT": 10, "OCTOBER": 10,
            "NOV": 11, "NOVEMBER": 11,
            "DEC": 12, "DECEMBER": 12
        ]

        return mapping[normalized]
    }

    private func normalizedYear(_ value: String) -> Int? {
        guard let raw = Int(value) else { return nil }
        if value.count == 2 {
            return raw >= 70 ? 1900 + raw : 2000 + raw
        }
        return raw
    }

    private func numberOfDaysInMonth(month: Int, year: Int) -> Int {
        var comps = DateComponents()
        comps.calendar = .roster
        comps.timeZone = rosterTimeZone
        comps.year = year
        comps.month = month
        comps.day = 1

        guard let date = comps.date,
              let range = Calendar.roster.range(of: .day, in: .month, for: date) else {
            return 31
        }
        return range.count
    }

    private func uniqueDayCount(_ headers: [DayHeader]) -> Int {
        Set(headers.map(\.day)).count
    }

    private func normalizedLine(_ text: String) -> String {
        text
            .uppercased()
            .replacingOccurrences(of: "[^A-Z0-9: ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
