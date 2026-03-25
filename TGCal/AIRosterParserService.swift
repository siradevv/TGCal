import Foundation
import UIKit

/// Parses a Thai Airways crew roster PDF page image using Claude AI vision.
/// Returns structured flight data or throws on failure, allowing fallback to OCR.
struct AIRosterParserService {

    enum AIParseError: LocalizedError {
        case noAPIKey
        case imageConversionFailed
        case networkError(Error)
        case apiError(statusCode: Int, message: String)
        case invalidResponse
        case jsonDecodingFailed(Error)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .noAPIKey: return "No Anthropic API key configured."
            case .imageConversionFailed: return "Could not convert page image to JPEG."
            case .networkError(let e): return "Network error: \(e.localizedDescription)"
            case .apiError(let code, let msg): return "API error \(code): \(msg)"
            case .invalidResponse: return "Invalid response from AI parser."
            case .jsonDecodingFailed(let e): return "JSON decoding failed: \(e.localizedDescription)"
            case .emptyResult: return "AI parser returned no flights."
            }
        }
    }

    // MARK: - Response Models

    private struct AIParseResponse: Decodable {
        let month: Int
        let year: Int
        let flights: [AIFlight]
        let dutyCodes: [AIDutyCode]?
    }

    private struct AIFlight: Decodable {
        let day: Int
        let flightNumber: String
        let origin: String
        let destination: String
        let departureTime: String
        let arrivalTime: String
    }

    private struct AIDutyCode: Decodable {
        let day: Int
        let code: String
    }

    private struct ClaudeResponse: Decodable {
        let content: [ContentBlock]

        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }
    }

    // MARK: - Public

    func parse(
        pageImage: UIImage,
        fallbackMonth: Int,
        fallbackYear: Int
    ) async throws -> ScheduleSlipParseResult {
        guard let apiKey = AnthropicConfiguration.apiKey else {
            throw AIParseError.noAPIKey
        }

        let imageData = try prepareImage(pageImage)
        let base64Image = imageData.base64EncodedString()

        let responseText = try await callClaudeAPI(
            apiKey: apiKey,
            base64Image: base64Image
        )

        let parsed = try decodeResponse(responseText)

        let result = buildResult(
            from: parsed,
            fallbackMonth: fallbackMonth,
            fallbackYear: fallbackYear
        )

        guard result.flightsByDay.isEmpty == false,
              result.detailsByFlight.isEmpty == false else {
            throw AIParseError.emptyResult
        }

        return result
    }

    // MARK: - Image Preparation

    private func prepareImage(_ image: UIImage) throws -> Data {
        var targetImage = image

        // Downscale if too large (width > 2000px)
        if image.size.width > 2000 {
            let scale = 2000 / image.size.width
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )
            let renderer = UIGraphicsImageRenderer(size: newSize)
            targetImage = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        }

        guard let jpegData = targetImage.jpegData(compressionQuality: 0.7) else {
            throw AIParseError.imageConversionFailed
        }

        return jpegData
    }

    // MARK: - Claude API Call

    private func callClaudeAPI(
        apiKey: String,
        base64Image: String
    ) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": "Extract all flight data from this Thai Airways crew roster page. Return ONLY the JSON object."
                        ]
                    ]
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIParseError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIParseError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIParseError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)

        guard let textBlock = claudeResponse.content.first(where: { $0.type == "text" }),
              let text = textBlock.text else {
            throw AIParseError.invalidResponse
        }

        return text
    }

    // MARK: - Response Decoding

    private func decodeResponse(_ text: String) throws -> AIParseResponse {
        // Strip markdown fencing if present
        var jsonText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if jsonText.hasPrefix("```") {
            // Remove opening fence (```json or ```)
            if let firstNewline = jsonText.firstIndex(of: "\n") {
                jsonText = String(jsonText[jsonText.index(after: firstNewline)...])
            }
            // Remove closing fence
            if jsonText.hasSuffix("```") {
                jsonText = String(jsonText.dropLast(3))
            }
            jsonText = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let jsonData = jsonText.data(using: .utf8) else {
            throw AIParseError.invalidResponse
        }

        do {
            return try JSONDecoder().decode(AIParseResponse.self, from: jsonData)
        } catch {
            throw AIParseError.jsonDecodingFailed(error)
        }
    }

    // MARK: - Result Building

    private func buildResult(
        from parsed: AIParseResponse,
        fallbackMonth: Int,
        fallbackYear: Int
    ) -> ScheduleSlipParseResult {
        var flightsByDay: [Int: [String]] = [:]
        var detailsByFlight: [String: ScheduleFlightDetail] = [:]

        for flight in parsed.flights {
            let number = flight.flightNumber
                .replacingOccurrences(of: "TG", with: "")
                .strippingLeadingZeros()

            guard number.isEmpty == false else { continue }

            // Build flightsByDay
            var dayFlights = flightsByDay[flight.day, default: []]
            if dayFlights.contains(number) == false {
                dayFlights.append(number)
            }
            flightsByDay[flight.day] = dayFlights

            // Build detailsByFlight (first occurrence wins)
            if detailsByFlight[number] == nil {
                detailsByFlight[number] = ScheduleFlightDetail(
                    flightNumber: number,
                    origin: flight.origin.uppercased(),
                    destination: flight.destination.uppercased(),
                    departureTime: normalizeTime(flight.departureTime),
                    arrivalTime: normalizeTime(flight.arrivalTime)
                )
            }
        }

        // Add duty codes to flightsByDay
        if let dutyCodes = parsed.dutyCodes {
            for duty in dutyCodes {
                let code = duty.code.uppercased()
                guard code.isEmpty == false else { continue }
                var dayFlights = flightsByDay[duty.day, default: []]
                if dayFlights.contains(code) == false {
                    dayFlights.append(code)
                }
                flightsByDay[duty.day] = dayFlights
            }
        }

        let month = (1...12).contains(parsed.month) ? parsed.month : fallbackMonth
        let year = parsed.year >= 2020 ? parsed.year : fallbackYear

        return ScheduleSlipParseResult(
            month: month,
            year: year,
            flightsByDay: flightsByDay,
            detailsByFlight: detailsByFlight
        )
    }

    /// Normalizes time strings like "7:45" → "07:45", "0745" → "07:45".
    private func normalizeTime(_ time: String) -> String {
        let digits = time.filter(\.isNumber)

        let hhmm: String
        if digits.count == 3 {
            hhmm = "0" + digits
        } else if digits.count == 4 {
            hhmm = digits
        } else {
            return time
        }

        let h = String(hhmm.prefix(2))
        let m = String(hhmm.suffix(2))
        return "\(h):\(m)"
    }

    // MARK: - System Prompt

    private var systemPrompt: String {
        """
        You are an airline roster PDF parser for Thai Airways (TG). Extract ALL flight data from this crew roster page image.

        The roster has two sections:
        1. DUTY GRID (top): A calendar grid with columns for days 1-31, showing flight numbers, destinations, and duty codes
        2. FLIGHT DETAIL TABLE (bottom): Rows labeled FLT/DEP/ARR showing exact flight numbers, origins, destinations, and times

        Use the FLIGHT DETAIL TABLE as the primary source for flight details (times, origins, destinations). Use the DUTY GRID to determine which day each flight is assigned to.

        Return ONLY valid JSON with this exact structure:
        {
          "month": 3,
          "year": 2026,
          "flights": [
            {
              "day": 1,
              "flightNumber": "560",
              "origin": "BKK",
              "destination": "HAN",
              "departureTime": "07:45",
              "arrivalTime": "09:35"
            }
          ],
          "dutyCodes": [
            {
              "day": 8,
              "code": "OFF"
            }
          ]
        }

        Rules:
        - Strip the "TG" prefix and leading zeros from flight numbers (TG0560 → 560)
        - Times must be in HH:mm 24-hour format
        - Origin and destination must be 3-letter IATA airport codes
        - Include ALL flights for every day, including multi-leg days (a day can have multiple flights)
        - For round-trip same-day flights (e.g., BKK→HAN then HAN→BKK), list both as separate flight entries on the same day
        - For multi-day trips (depart day X, arrive day Y), assign the flight to the DEPARTURE day
        - "----" in the duty grid means a rest/off day, add it to dutyCodes with code "OFF"
        - "*****" indicates a note marker, ignore it
        - Alphabetic codes like CHMSBA, SBY, REST, LD are duty codes, not flights — put them in dutyCodes
        - The month and year can be found in the EFFECTIVE date range at the top of the roster
        - Return ONLY the JSON object, no markdown fencing, no explanation
        """
    }
}

