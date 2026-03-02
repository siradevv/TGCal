import Foundation
import CoreGraphics

struct FlightNumberRosterParseResult {
    let month: Int
    let year: Int
    let flightsByDay: [Int: [String]]
}

final class FlightNumberRosterParser {
    private let weekdays = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    private struct WeekdayHeader {
        let index: Int
        let x: CGFloat
        let y: CGFloat
    }

    func parse(lines: [OCRLine], fallbackMonth: Int, fallbackYear: Int) -> FlightNumberRosterParseResult {
        let detectedMonthYear = detectMonthYear(in: lines.map(\.text))
        let month = detectedMonthYear?.month ?? fallbackMonth
        let year = detectedMonthYear?.year ?? fallbackYear

        let gridResult = parseCalendarGrid(lines: lines, month: month, year: year)
        if gridResult.isEmpty == false {
            return FlightNumberRosterParseResult(month: month, year: year, flightsByDay: gridResult)
        }

        let rowResult = parseDayRows(lines: lines)
        return FlightNumberRosterParseResult(month: month, year: year, flightsByDay: rowResult)
    }

    private func parseCalendarGrid(lines: [OCRLine], month: Int, year: Int) -> [Int: [String]] {
        let headers: [WeekdayHeader] = lines.compactMap { line in
            guard let index = weekdayIndex(in: line.text) else { return nil }
            return WeekdayHeader(index: index, x: line.boundingBox.midX, y: line.boundingBox.midY)
        }

        guard headers.count >= 5, let columnCenters = buildColumnCenters(from: headers) else {
            return [:]
        }

        let headerY = headers.map(\.y).reduce(0, +) / CGFloat(headers.count)

        struct DayLabel {
            let day: Int
            let x: CGFloat
            let y: CGFloat
        }

        let dayLabels: [DayLabel] = lines.compactMap { line in
            let text = normalized(line.text)
            guard let day = Int(text), (1...31).contains(day) else { return nil }
            guard line.boundingBox.midY < headerY - 0.01 else { return nil }
            return DayLabel(day: day, x: line.boundingBox.midX, y: line.boundingBox.midY)
        }

        let rowCenters = clusterRows(dayLabels.map(\.y))
        guard rowCenters.count >= 4 else { return [:] }

        let dayCount = numberOfDaysInMonth(month: month, year: year)
        let firstWeekdayMonBased = firstWeekdayColumn(month: month, year: year)
        let colBounds = columnBounds(from: columnCenters)
        let rowBounds = rowVerticalBounds(from: rowCenters)

        struct Cell {
            let day: Int
            let xMin: CGFloat
            let xMax: CGFloat
            let yTop: CGFloat
            let yBottom: CGFloat
            let labelY: CGFloat
        }

        var cells: [Cell] = []
        for day in 1...dayCount {
            let position = firstWeekdayMonBased + (day - 1)
            let row = position / 7
            let col = position % 7

            guard row < rowBounds.count else { continue }

            let bounds = rowBounds[row]
            let xRange = colBounds[col]

            let labelY: CGFloat = dayLabels
                .filter { label in
                    label.day == day &&
                    label.x >= xRange.lowerBound &&
                    label.x <= xRange.upperBound &&
                    label.y <= bounds.upper &&
                    label.y >= bounds.lower
                }
                .sorted { abs($0.y - rowCenters[row]) < abs($1.y - rowCenters[row]) }
                .first?
                .y ?? rowCenters[row]

            cells.append(
                Cell(
                    day: day,
                    xMin: xRange.lowerBound,
                    xMax: xRange.upperBound,
                    yTop: bounds.upper,
                    yBottom: bounds.lower,
                    labelY: labelY
                )
            )
        }

        struct TokenHit {
            let day: Int
            let number: String
            let y: CGFloat
            let x: CGFloat
            let tokenIndex: Int
        }

        var hits: [TokenHit] = []

        for line in lines {
            let text = normalized(line.text)
            guard text.isEmpty == false else { continue }
            guard line.boundingBox.midY < headerY - 0.01 else { continue }
            guard text.range(of: #"^(OFF|BLOCK)$"#, options: [.regularExpression, .caseInsensitive]) == nil else { continue }
            guard text.range(of: #"^\d{1,2}$"#, options: .regularExpression) == nil else { continue }

            let numbers = extractFlightNumbers(from: text)
            guard numbers.isEmpty == false else { continue }

            guard let cell = cells.first(where: { cell in
                line.boundingBox.midX >= cell.xMin &&
                line.boundingBox.midX <= cell.xMax &&
                line.boundingBox.midY <= cell.yTop &&
                line.boundingBox.midY >= cell.yBottom
            }) else {
                continue
            }

            // Day numbers sit above tags. Keep only values rendered below the day label baseline.
            guard line.boundingBox.midY < cell.labelY - 0.005 else { continue }

            for (index, number) in numbers.enumerated() {
                hits.append(
                    TokenHit(
                        day: cell.day,
                        number: number,
                        y: line.boundingBox.midY,
                        x: line.boundingBox.midX,
                        tokenIndex: index
                    )
                )
            }
        }

        guard hits.isEmpty == false else { return [:] }

        let grouped = Dictionary(grouping: hits, by: \.day)
        var result: [Int: [String]] = [:]

        for (day, dayHits) in grouped {
            let ordered = dayHits.sorted {
                if abs($0.y - $1.y) > 0.001 {
                    return $0.y > $1.y
                }
                if abs($0.x - $1.x) > 0.001 {
                    return $0.x < $1.x
                }
                return $0.tokenIndex < $1.tokenIndex
            }

            var seen = Set<String>()
            var numbers: [String] = []
            for hit in ordered {
                if seen.contains(hit.number) { continue }
                seen.insert(hit.number)
                numbers.append(hit.number)
            }

            if numbers.isEmpty == false {
                result[day] = numbers
            }
        }

        return result
    }

    private func parseDayRows(lines: [OCRLine]) -> [Int: [String]] {
        let sorted = lines.sorted {
            let yDiff = abs($0.boundingBox.midY - $1.boundingBox.midY)
            if yDiff > 0.015 {
                return $0.boundingBox.midY > $1.boundingBox.midY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }

        var rows: [[OCRLine]] = []
        for line in sorted {
            if let index = rows.firstIndex(where: { abs(rowMidY($0) - line.boundingBox.midY) < 0.012 }) {
                rows[index].append(line)
            } else {
                rows.append([line])
            }
        }

        rows.sort { rowMidY($0) > rowMidY($1) }

        var byDay: [Int: [String]] = [:]

        for row in rows {
            let ordered = row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            let combined = ordered.map(\.text).joined(separator: " ")
            let normalizedCombined = normalized(combined)

            guard let day = rowDay(from: normalizedCombined) else { continue }
            let numbers = extractFlightNumbers(from: normalizedCombined)
            guard numbers.isEmpty == false else { continue }

            var existing = byDay[day, default: []]
            for number in numbers where existing.contains(number) == false {
                existing.append(number)
            }
            byDay[day] = existing
        }

        return byDay
    }

    private func rowDay(from text: String) -> Int? {
        guard let match = firstMatch(in: text, pattern: #"^\s*(\d{1,2})\b"#),
              let value = Int(match),
              (1...31).contains(value) else {
            return nil
        }
        return value
    }

    private func extractFlightNumbers(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b(?:TG\s*)?(\d{1,4})\b"#, options: [.caseInsensitive]) else {
            return []
        }

        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)

        var numbers: [String] = []
        for match in regex.matches(in: text, options: [], range: range) {
            guard match.numberOfRanges > 1 else { continue }
            let captureRange = match.range(at: 1)
            guard captureRange.location != NSNotFound else { continue }

            let raw = ns.substring(with: captureRange)
            let normalized = raw.strippingLeadingZeros()
            guard normalized != "0" else { continue }
            numbers.append(normalized)
        }

        return numbers
    }

    private func weekdayIndex(in text: String) -> Int? {
        let upper = normalized(text)
        return weekdays.firstIndex(of: upper)
    }

    private func buildColumnCenters(from headers: [WeekdayHeader]) -> [CGFloat]? {
        var buckets: [[CGFloat]] = Array(repeating: [], count: 7)
        for header in headers where (0...6).contains(header.index) {
            buckets[header.index].append(header.x)
        }

        var centers: [CGFloat?] = buckets.map { bucket in
            guard bucket.isEmpty == false else { return nil }
            return bucket.reduce(0, +) / CGFloat(bucket.count)
        }

        let known = centers.enumerated().compactMap { index, value -> (Int, CGFloat)? in
            guard let value else { return nil }
            return (index, value)
        }

        guard known.count >= 2 else { return nil }

        guard
            let minKnown = known.min(by: { $0.0 < $1.0 }),
            let maxKnown = known.max(by: { $0.0 < $1.0 })
        else {
            return nil
        }

        let denominator = max(1, maxKnown.0 - minKnown.0)
        let step = (maxKnown.1 - minKnown.1) / CGFloat(denominator)

        for index in 0..<7 where centers[index] == nil {
            centers[index] = minKnown.1 + CGFloat(index - minKnown.0) * step
        }

        return centers.compactMap { $0 }
    }

    private func columnBounds(from centers: [CGFloat]) -> [ClosedRange<CGFloat>] {
        var bounds: [ClosedRange<CGFloat>] = []

        for index in centers.indices {
            let left: CGFloat
            if index == 0 {
                let delta = centers[1] - centers[0]
                left = max(0, centers[0] - delta / 2)
            } else {
                left = (centers[index - 1] + centers[index]) / 2
            }

            let right: CGFloat
            if index == centers.count - 1 {
                let delta = centers[index] - centers[index - 1]
                right = min(1, centers[index] + delta / 2)
            } else {
                right = (centers[index] + centers[index + 1]) / 2
            }

            bounds.append(left...right)
        }

        return bounds
    }

    private func rowVerticalBounds(from centers: [CGFloat]) -> [(upper: CGFloat, lower: CGFloat)] {
        var bounds: [(upper: CGFloat, lower: CGFloat)] = []

        for index in centers.indices {
            let upper: CGFloat
            if index == 0 {
                let delta = centers[0] - centers[min(1, centers.count - 1)]
                upper = min(1, centers[0] + delta / 2)
            } else {
                upper = (centers[index - 1] + centers[index]) / 2
            }

            let lower: CGFloat
            if index == centers.count - 1 {
                let delta = centers[max(0, index - 1)] - centers[index]
                lower = max(0, centers[index] - delta / 2)
            } else {
                lower = (centers[index] + centers[index + 1]) / 2
            }

            bounds.append((upper: upper, lower: lower))
        }

        return bounds
    }

    private func clusterRows(_ yValues: [CGFloat]) -> [CGFloat] {
        guard yValues.isEmpty == false else { return [] }

        var buckets: [[CGFloat]] = []

        for y in yValues.sorted(by: >) {
            if let index = buckets.firstIndex(where: { abs(($0.reduce(0, +) / CGFloat($0.count)) - y) < 0.05 }) {
                buckets[index].append(y)
            } else {
                buckets.append([y])
            }
        }

        return buckets
            .map { $0.reduce(0, +) / CGFloat($0.count) }
            .sorted(by: >)
    }

    private func firstWeekdayColumn(month: Int, year: Int) -> Int {
        var comps = DateComponents()
        comps.calendar = .roster
        comps.timeZone = rosterTimeZone
        comps.year = year
        comps.month = month
        comps.day = 1

        guard let date = comps.date else { return 0 }
        let weekday = Calendar.roster.component(.weekday, from: date) // 1=Sun ... 7=Sat
        return (weekday + 5) % 7 // 0=Mon ... 6=Sun
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

    private func rowMidY(_ row: [OCRLine]) -> CGFloat {
        guard row.isEmpty == false else { return 0 }
        return row.map { $0.boundingBox.midY }.reduce(0, +) / CGFloat(row.count)
    }

    private func detectMonthYear(in strings: [String]) -> (month: Int, year: Int)? {
        let text = strings.joined(separator: " ").uppercased()

        if let monthYear = detectNumericMonthYear(in: text) {
            return monthYear
        }

        if let monthYear = detectNamedMonthYear(in: text) {
            return monthYear
        }

        return nil
    }

    private func detectNumericMonthYear(in text: String) -> (month: Int, year: Int)? {
        let patterns = [
            #"\b(0?[1-9]|1[0-2])\s*[-/]\s*(20\d{2})\b"#,
            #"\b(20\d{2})\s*[-/]\s*(0?[1-9]|1[0-2])\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let ns = text as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges >= 3 else { continue }

            let first = ns.substring(with: match.range(at: 1))
            let second = ns.substring(with: match.range(at: 2))

            if pattern.contains("(20\\d{2})"), let year = Int(first), let month = Int(second) {
                return (month: month, year: year)
            }

            if let month = Int(first), let year = Int(second) {
                return (month: month, year: year)
            }
        }

        return nil
    }

    private func detectNamedMonthYear(in text: String) -> (month: Int, year: Int)? {
        let monthLookup: [String: Int] = [
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

        let pattern = #"\b(JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|APR(?:IL)?|MAY|JUN(?:E)?|JUL(?:Y)?|AUG(?:UST)?|SEP(?:TEMBER)?|SEPT|OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)\s*[-/]?\s*(20\d{2})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }

        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3 else {
            return nil
        }

        let monthText = ns.substring(with: match.range(at: 1))
        let yearText = ns.substring(with: match.range(at: 2))

        guard let month = monthLookup[monthText], let year = Int(yearText) else {
            return nil
        }

        return (month: month, year: year)
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else {
            return nil
        }

        let capture = match.range(at: 1)
        guard capture.location != NSNotFound else { return nil }
        return ns.substring(with: capture)
    }

    private func normalized(_ text: String) -> String {
        text
            .uppercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
