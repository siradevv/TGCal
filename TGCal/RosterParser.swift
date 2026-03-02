import Foundation

final class RosterParser {
    private let monthLookup: [String: Int] = [
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

    private let excludedDutyTokens: Set<String> = [
        "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT",
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "SEPT", "OCT", "NOV", "DEC",
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER",
        "DEP", "ARR", "TG"
    ]

    func parse(lines: [OCRLine], fallbackMonth: Int, fallbackYear: Int) -> ParseResult {
        let detectedMonthYear = detectMonthYear(in: lines.map(\.text))
        let month = detectedMonthYear?.month ?? fallbackMonth
        let year = detectedMonthYear?.year ?? fallbackYear

        let rowsByDay = buildDayRows(from: lines)

        var drafts: [FlightEventDraft] = []
        var lastKnownAirport = "BKK"
        var pendingFlightNumber: String?

        for day in rowsByDay.keys.sorted() {
            guard let date = buildServiceDate(day: day, month: month, year: year) else { continue }
            guard let rowLines = rowsByDay[day], rowLines.isEmpty == false else { continue }

            let combinedText = normalizeSpaces(rowLines.map(\.text).joined(separator: " "))
            guard combinedText.isEmpty == false else { continue }
            let normalizedText = normalizeOCRText(combinedText)

            let baseConfidence = rowLines.map(\.confidence).reduce(0, +) / Double(rowLines.count)
            var pendingForDay = pendingFlightNumber
            let legs = parseLegs(
                from: normalizedText,
                defaultOrigin: lastKnownAirport,
                pendingFlightNumber: &pendingForDay
            )

            if let dutyDraft = draftForDutyCode(
                in: normalizedText,
                on: date,
                baseConfidence: baseConfidence,
                rawLines: rowLines.map(\.text),
                existingLegs: legs
            ) {
                drafts.append(dutyDraft)
                pendingFlightNumber = nil
                continue
            }

            pendingFlightNumber = pendingForDay

            if legs.isEmpty, let standalone = extractStandaloneFlight(in: combinedText) {
                pendingFlightNumber = standalone
            }

            for leg in legs {
                guard let draft = draft(from: leg, on: date, baseConfidence: baseConfidence, rawLines: rowLines.map(\.text)) else {
                    continue
                }
                drafts.append(draft)
                lastKnownAirport = draft.destination
            }

            if let lastAirportMentioned = lastAirportCode(in: combinedText) {
                lastKnownAirport = lastAirportMentioned
            }
        }

        return ParseResult(drafts: drafts, detectedMonthYear: detectedMonthYear)
    }

    private func draftForDutyCode(
        in normalizedText: String,
        on serviceDate: Date,
        baseConfidence: Double,
        rawLines: [String],
        existingLegs: [LegCandidate]
    ) -> FlightEventDraft? {
        guard existingLegs.isEmpty else { return nil }
        guard let dutyCode = extractDutyCode(in: normalizedText),
              let timeRange = extractDutyTimeRange(in: normalizedText) else {
            return nil
        }

        let calendar = Calendar.roster
        guard let departure = calendar.date(on: serviceDate, hhmm: timeRange.start),
              let rawArrival = calendar.date(on: serviceDate, hhmm: timeRange.end) else {
            return nil
        }

        var arrival = rawArrival
        if arrival <= departure {
            arrival = calendar.date(byAdding: .day, value: 1, to: arrival) ?? arrival.addingTimeInterval(24 * 3600)
        }

        var draft = FlightEventDraft(
            serviceDate: calendar.startOfDay(for: serviceDate),
            flightNumber: dutyCode,
            origin: "",
            destination: "",
            departure: departure,
            arrival: arrival,
            hasDepartureTime: true,
            hasArrivalTime: true,
            confidence: min(max(baseConfidence + 0.16, 0.10), 0.99),
            rawLines: rawLines
        )
        draft.normalize()
        return draft
    }

    private func extractDutyCode(in normalizedText: String) -> String? {
        let candidates = matches(in: normalizedText, pattern: #"\b([A-Z]{3,10})\b"#)
            .compactMap { $0.captures.first }
            .filter { excludedDutyTokens.contains($0) == false }

        if let preferred = candidates.first(where: { $0.count >= 4 }) {
            return preferred
        }
        return candidates.first
    }

    private func extractDutyTimeRange(in normalizedText: String) -> (start: Int, end: Int)? {
        if let depMatch = firstMatch(in: normalizedText, pattern: #"\bDEP\b\s*\(?([0-9OQILDS]{3,4})\)?"#),
           let arrMatch = firstMatch(in: normalizedText, pattern: #"\bARR\b\s*\(?([0-9OQILDS]{3,4})\)?"#),
           let depRaw = depMatch.first,
           let arrRaw = arrMatch.first,
           let start = parseHHmm(depRaw),
           let end = parseHHmm(arrRaw) {
            return (start, end)
        }

        if let rangeMatch = firstMatch(
            in: normalizedText,
            pattern: #"\(?([0-9OQILDS]{3,4})\)?\s*(?:-|TO|~|–|—)\s*\(?([0-9OQILDS]{3,4})\)?"#
        ),
           rangeMatch.count == 2,
           let start = parseHHmm(rangeMatch[0]),
           let end = parseHHmm(rangeMatch[1]) {
            return (start, end)
        }

        let orderedTimes = matches(in: normalizedText, pattern: #"\(?([0-9OQILDS]{3,4})\)?"#)
            .compactMap { match -> Int? in
                guard let raw = match.captures.first else { return nil }
                return parseHHmm(raw)
            }

        guard orderedTimes.count >= 2 else { return nil }
        return (orderedTimes[0], orderedTimes[1])
    }

    private func detectMonthYear(in lines: [String]) -> DetectedMonthYear? {
        let fullText = lines.joined(separator: " ").uppercased()

        if let match = firstMatch(
            in: fullText,
            pattern: #"\b(JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|APR(?:IL)?|MAY|JUN(?:E)?|JUL(?:Y)?|AUG(?:UST)?|SEP(?:TEMBER)?|SEPT|OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)\s*[-/]?\s*(20\d{2}|\d{2})\b"#
        ),
           match.count == 2,
           let month = monthLookup[match[0]],
           let year = normalizedYear(match[1]) {
            return DetectedMonthYear(month: month, year: year)
        }

        if let match = firstMatch(
            in: fullText,
            pattern: #"\b\d{1,2}(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)(20\d{2}|\d{2})\b"#
        ),
           match.count == 2,
           let month = monthLookup[match[0]],
           let year = normalizedYear(match[1]) {
            return DetectedMonthYear(month: month, year: year)
        }

        return nil
    }

    private func buildDayRows(from lines: [OCRLine]) -> [Int: [OCRLine]] {
        let ordered = lines.sorted { lhs, rhs in
            let yDiff = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
            if yDiff > 0.02 {
                return lhs.boundingBox.midY > rhs.boundingBox.midY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }

        var rows: [[OCRLine]] = []
        for line in ordered {
            if let index = rows.firstIndex(where: { abs(rowMidY($0) - line.boundingBox.midY) < 0.012 }) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }

        rows.sort { rowMidY($0) > rowMidY($1) }

        var rowsByDay: [Int: [OCRLine]] = [:]
        var currentDay: Int?

        for row in rows {
            let sorted = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let leftDay = sorted
                .filter { $0.boundingBox.minX < 0.22 }
                .compactMap { dayPrefix(from: $0.text)?.0 }
                .first

            if let leftDay, (1...31).contains(leftDay) {
                currentDay = leftDay
            }

            guard let day = currentDay else { continue }

            for line in sorted {
                let text = normalizeSpaces(line.text)
                guard text.isEmpty == false else { continue }
                if isDayOnlyLabel(text) { continue }
                if looksLikeRosterContent(text) == false { continue }

                rowsByDay[day, default: []].append(
                    OCRLine(text: text, confidence: line.confidence, boundingBox: line.boundingBox)
                )
            }
        }

        return rowsByDay
    }

    private func rowMidY(_ row: [OCRLine]) -> CGFloat {
        guard row.isEmpty == false else { return 0 }
        return row.map { $0.boundingBox.midY }.reduce(0, +) / CGFloat(row.count)
    }

    private func dayPrefix(from text: String) -> (Int, String)? {
        guard let match = firstMatch(
            in: text,
            pattern: #"^\s*(\d{1,2})(?:\s*(?:SUN|MON|TUE|WED|THU|FRI|SAT))?\s*(.*)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        guard match.count == 2, let day = Int(match[0]) else { return nil }
        return (day, match[1])
    }

    private func isDayOnlyLabel(_ text: String) -> Bool {
        let upper = text.uppercased()
        if upper.range(of: #"^\s*\d{1,2}\s*(SUN|MON|TUE|WED|THU|FRI|SAT)?\s*$"#, options: .regularExpression) != nil {
            return true
        }
        if upper.range(of: #"^\s*(SUN|MON|TUE|WED|THU|FRI|SAT)\s*$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func buildServiceDate(day: Int, month: Int, year: Int) -> Date? {
        var comps = DateComponents()
        comps.calendar = .roster
        comps.timeZone = rosterTimeZone
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 0
        comps.minute = 0
        return comps.date
    }

    private func parseLegs(
        from text: String,
        defaultOrigin: String,
        pendingFlightNumber: inout String?
    ) -> [LegCandidate] {
        let normalized = normalizeOCRText(text)

        var consumed: [NSRange] = []
        var legs: [LegCandidate] = []

        // Example: 0560(0745) HAN 0561 BKK(1225)
        let roundTripPattern = #"([0-9OQILDS]{3,5})\(([0-9OQILDS]{3,4})\)\s*([A-Z]{3})\s*([0-9OQILDS]{3,5})\s*([A-Z]{3})\(([0-9OQILDS]{3,4})\)"#
        for match in matches(in: normalized, pattern: roundTripPattern) {
            guard overlapsAny(match.range, consumed) == false else { continue }
            guard match.captures.count == 6 else { continue }

            guard let outboundFlight = normalizeFlight(match.captures[0]),
                  let depart = parseHHmm(match.captures[1]),
                  let returnFlight = normalizeFlight(match.captures[3]),
                  let returnArrive = parseHHmm(match.captures[5]) else {
                continue
            }

            let firstDestination = match.captures[2]
            let secondDestination = match.captures[4]

            legs.append(
                LegCandidate(
                    flightNumber: outboundFlight,
                    origin: defaultOrigin,
                    destination: firstDestination,
                    departureTime: depart,
                    arrivalTime: nil,
                    confidenceBoost: 0.24
                )
            )

            legs.append(
                LegCandidate(
                    flightNumber: returnFlight,
                    origin: firstDestination,
                    destination: secondDestination,
                    departureTime: nil,
                    arrivalTime: returnArrive,
                    confidenceBoost: 0.24
                )
            )

            consumed.append(match.range)
        }

        // Example: 0660(1450) HND
        let outboundPattern = #"([0-9OQILDS]{3,5})\(([0-9OQILDS]{3,4})\)\s*([A-Z]{3})"#
        for match in matches(in: normalized, pattern: outboundPattern) {
            guard overlapsAny(match.range, consumed) == false else { continue }
            guard match.captures.count == 3 else { continue }

            guard let flight = normalizeFlight(match.captures[0]),
                  let depart = parseHHmm(match.captures[1]) else {
                continue
            }

            legs.append(
                LegCandidate(
                    flightNumber: flight,
                    origin: defaultOrigin,
                    destination: match.captures[2],
                    departureTime: depart,
                    arrivalTime: nil,
                    confidenceBoost: 0.16
                )
            )

            consumed.append(match.range)
        }

        // Example: 0661 BKK(0525)
        let arrivalPattern = #"([0-9OQILDS]{3,5})\s*([A-Z]{3})\(([0-9OQILDS]{3,4})\)"#
        for match in matches(in: normalized, pattern: arrivalPattern) {
            guard overlapsAny(match.range, consumed) == false else { continue }
            guard match.captures.count == 3 else { continue }

            guard let flight = normalizeFlight(match.captures[0]),
                  let arrive = parseHHmm(match.captures[2]) else {
                continue
            }

            let destination = match.captures[1]
            let origin = defaultOrigin == destination ? "BKK" : defaultOrigin

            legs.append(
                LegCandidate(
                    flightNumber: flight,
                    origin: origin,
                    destination: destination,
                    departureTime: nil,
                    arrivalTime: arrive,
                    confidenceBoost: 0.14
                )
            )

            consumed.append(match.range)
        }

        // Example with carried flight number: day 24 has 0917, day 25 has BKK(1600)
        if let pending = pendingFlightNumber,
           legs.isEmpty,
           let match = matches(in: normalized, pattern: #"([A-Z]{3})\(([0-9OQILDS]{3,4})\)"#).first,
           match.captures.count == 2,
           let arrive = parseHHmm(match.captures[1]) {
            let destination = match.captures[0]
            let origin = defaultOrigin == destination ? "BKK" : defaultOrigin

            legs.append(
                LegCandidate(
                    flightNumber: pending,
                    origin: origin,
                    destination: destination,
                    departureTime: nil,
                    arrivalTime: arrive,
                    confidenceBoost: 0.10
                )
            )
            pendingFlightNumber = nil
        }

        if legs.isEmpty, let standalone = extractStandaloneFlight(in: normalized) {
            pendingFlightNumber = standalone
        }

        return legs
    }

    private func draft(
        from leg: LegCandidate,
        on serviceDate: Date,
        baseConfidence: Double,
        rawLines: [String]
    ) -> FlightEventDraft? {
        let flightNumber = leg.flightNumber
        guard flightNumber.isEmpty == false else { return nil }

        let origin = leg.origin.isEmpty ? "BKK" : leg.origin
        let destination = leg.destination.isEmpty ? origin : leg.destination

        let calendar = Calendar.roster

        let parsedDeparture = leg.departureTime.flatMap { calendar.date(on: serviceDate, hhmm: $0) }
        let parsedArrival = leg.arrivalTime.flatMap { calendar.date(on: serviceDate, hhmm: $0) }

        let hasDepartureTime = parsedDeparture != nil
        let hasArrivalTime = destination == "BKK" && parsedArrival != nil

        guard hasDepartureTime || hasArrivalTime else {
            return nil
        }

        guard let departureDate = parsedDeparture ?? parsedArrival else {
            return nil
        }
        var arrivalDate = hasArrivalTime ? (parsedArrival ?? departureDate) : departureDate

        if hasDepartureTime && hasArrivalTime && arrivalDate <= departureDate {
            arrivalDate = calendar.date(byAdding: .day, value: 1, to: arrivalDate) ?? arrivalDate.addingTimeInterval(24 * 3600)
        }

        var draft = FlightEventDraft(
            serviceDate: calendar.startOfDay(for: serviceDate),
            flightNumber: flightNumber,
            origin: origin,
            destination: destination,
            departure: departureDate,
            arrival: arrivalDate,
            hasDepartureTime: hasDepartureTime,
            hasArrivalTime: hasArrivalTime,
            confidence: confidenceScore(base: baseConfidence, leg: leg),
            rawLines: rawLines
        )

        draft.normalize()
        return draft
    }

    private func confidenceScore(base: Double, leg: LegCandidate) -> Double {
        var score = base + leg.confidenceBoost
        if leg.departureTime != nil { score += 0.10 } else { score -= 0.06 }
        if leg.arrivalTime != nil { score += 0.10 } else { score -= 0.04 }
        if leg.origin.isEmpty == false { score += 0.04 }
        if leg.destination.isEmpty == false { score += 0.06 }
        return min(max(score, 0.10), 0.99)
    }

    private func matches(in text: String, pattern: String) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        return regex.matches(in: text, options: [], range: range).map { match in
            var captures: [String] = []
            for i in 1..<match.numberOfRanges {
                let captureRange = match.range(at: i)
                guard captureRange.location != NSNotFound else { continue }
                captures.append(nsText.substring(with: captureRange))
            }
            return RegexMatch(range: match.range, captures: captures)
        }
    }

    private func overlapsAny(_ range: NSRange, _ existing: [NSRange]) -> Bool {
        existing.contains { current in
            NSIntersectionRange(range, current).length > 0
        }
    }

    private func extractStandaloneFlight(in text: String) -> String? {
        if let match = firstMatch(in: text, pattern: #"\b([0-9OQILDS]{3,5})\b"#),
           let first = match.first,
           let flight = normalizeFlight(first) {
            return flight
        }
        return nil
    }

    private func parseHHmm(_ raw: String) -> Int? {
        var digits = normalizeDigits(raw)
        if digits.count == 3 {
            digits = "0\(digits)"
        }
        guard digits.count == 4, let value = Int(digits) else { return nil }

        let hour = value / 100
        let minute = value % 100
        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }
        return value
    }

    private func normalizeFlight(_ raw: String) -> String? {
        let digits = normalizeDigits(raw)
        guard (3...5).contains(digits.count), digits.allSatisfy(\.isNumber) else {
            return nil
        }
        return String(digits.prefix(5))
    }

    private func normalizeDigits(_ text: String) -> String {
        var output = ""
        for char in text {
            switch char {
            case "0"..."9": output.append(char)
            case "O", "Q", "D": output.append("0")
            case "I", "L": output.append("1")
            case "S": output.append("5")
            case "B": output.append("8")
            default: break
            }
        }
        return output
    }

    private func looksLikeRosterContent(_ text: String) -> Bool {
        let upper = text.uppercased()
        if upper.contains("---") { return false }
        if firstMatch(in: upper, pattern: #"\d{3,5}\s*\(\d{3,4}\)"#) != nil { return true }
        if firstMatch(in: upper, pattern: #"\d{3,5}"#) != nil,
           firstMatch(in: upper, pattern: #"[A-Z]{3}"#) != nil {
            return true
        }
        if firstMatch(in: upper, pattern: #"[A-Z]{3}\(\d{3,4}\)"#) != nil { return true }
        return false
    }

    private func lastAirportCode(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b([A-Z]{3})\b"#, options: []) else {
            return nil
        }
        let upper = text.uppercased() as NSString
        let matches = regex.matches(in: upper as String, options: [], range: NSRange(location: 0, length: upper.length))
        guard let last = matches.last else { return nil }
        return upper.substring(with: last.range(at: 1))
    }

    private func normalizedYear(_ raw: String) -> Int? {
        guard let yearValue = Int(raw) else { return nil }
        if raw.count == 2 {
            return 2000 + yearValue
        }
        return yearValue
    }

    private func normalizeSpaces(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeOCRText(_ text: String) -> String {
        text
            .uppercased()
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: "[^A-Z0-9() ]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstMatch(
        in text: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        var captures: [String] = []
        for captureIndex in 1..<match.numberOfRanges {
            let captureRange = match.range(at: captureIndex)
            guard captureRange.location != NSNotFound else { continue }
            captures.append(nsText.substring(with: captureRange))
        }
        return captures
    }
}

private struct RegexMatch {
    let range: NSRange
    let captures: [String]
}

private struct LegCandidate {
    let flightNumber: String
    let origin: String
    let destination: String
    let departureTime: Int?
    let arrivalTime: Int?
    let confidenceBoost: Double
}
