import Foundation

struct LiveFlightDetails: Equatable {
    let departureAircraftType: String?
    let arrivalAircraftType: String?
    let departureGate: String?
    let arrivalGate: String?

    var aircraftType: String? {
        departureAircraftType ?? arrivalAircraftType
    }
}

enum AviationstackConnectionStatus: Equatable {
    case connected
    case unauthorized
    case quotaExceeded
    case restrictedPlan
    case noData
    case failed

    var message: String {
        switch self {
        case .connected:
            return "Connected successfully."
        case .unauthorized:
            return "API key is invalid."
        case .quotaExceeded:
            return "Monthly request quota reached."
        case .restrictedPlan:
            return "Current plan does not allow this request."
        case .noData:
            return "Connected, but no records returned."
        case .failed:
            return "Connection failed."
        }
    }
}

actor AviationstackService {
    static let shared = AviationstackService()

    private var cache: [String: (timestamp: Date, details: LiveFlightDetails, hasUsefulData: Bool)] = [:]
    private let cacheTTLWithData: TimeInterval = 15 * 60
    private let cacheTTLEmpty: TimeInterval = 2 * 60
    private typealias QueryAttempt = (name: String, items: [URLQueryItem])

    func nextFlightDetails(
        flightCode: String,
        originCode: String,
        destinationCode: String,
        serviceDate: Date,
        expectedDepartureDate: Date
    ) async throws -> LiveFlightDetails? {
        guard let apiKey = AviationstackConfiguration.apiKey else {
            return nil
        }

        let normalizedFlightCode = flightCode.uppercased()
        let normalizedOrigin = originCode.uppercased()
        let normalizedDestination = destinationCode.uppercased()
        let cacheKey = "\(normalizedFlightCode)|\(normalizedOrigin)|\(normalizedDestination)|\(serviceDateText(serviceDate))"
        if let cached = cache[cacheKey] {
            let ttl = cached.hasUsefulData ? cacheTTLWithData : cacheTTLEmpty
            guard Date().timeIntervalSince(cached.timestamp) >= ttl else {
                return cached.details
            }
        }
        guard let resolved = try await resolveBestCandidate(
            apiKey: apiKey,
            flightCode: normalizedFlightCode,
            originCode: normalizedOrigin,
            destinationCode: normalizedDestination,
            serviceDate: serviceDate,
            expectedDepartureDate: expectedDepartureDate
        ) else {
            return nil
        }

        let details = liveDetails(from: resolved.flight)

        let hasUsefulData = details.aircraftType != nil || details.departureGate != nil || details.arrivalGate != nil
        cache[cacheKey] = (Date(), details, hasUsefulData)
        return details
    }

    func probeNextFlightDetails(
        flightCode: String,
        originCode: String,
        destinationCode: String,
        serviceDate: Date,
        expectedDepartureDate: Date
    ) async -> String {
        guard let apiKey = AviationstackConfiguration.apiKey else {
            return "No Aviationstack key configured in app."
        }

        do {
            let normalizedFlightCode = flightCode.uppercased()
            let normalizedOrigin = originCode.uppercased()
            let normalizedDestination = destinationCode.uppercased()

            guard let resolved = try await resolveBestCandidate(
                apiKey: apiKey,
                flightCode: normalizedFlightCode,
                originCode: normalizedOrigin,
                destinationCode: normalizedDestination,
                serviceDate: serviceDate,
                expectedDepartureDate: expectedDepartureDate
            ) else {
                return "No matching Aviationstack record found for this flight/date."
            }

            let details = liveDetails(from: resolved.flight)
            let matchedFlightCode = resolved.flight.matchedFlightIATA ?? "nil"
            let matchedOrigin = resolved.flight.departure?.iata ?? "nil"
            let matchedDestination = resolved.flight.arrival?.iata ?? "nil"
            let scheduled = resolved.flight.departure?.scheduled ?? "nil"

            return """
            Strategy: \(resolved.strategy)
            Matched: \(matchedFlightCode) \(matchedOrigin) → \(matchedDestination)
            Scheduled: \(scheduled)
            Aircraft: \(details.aircraftType ?? "nil")
            Departure gate: \(details.departureGate ?? "nil")
            Arrival gate: \(details.arrivalGate ?? "nil")
            """
        } catch {
            return "Probe failed: \(error.localizedDescription)"
        }
    }

    func checkConnection() async -> AviationstackConnectionStatus {
        guard let apiKey = AviationstackConfiguration.apiKey else {
            return .unauthorized
        }

        do {
            let response = try await fetchFlights(
                apiKey: apiKey,
                queryItems: [URLQueryItem(name: "limit", value: "1")]
            )

            if let errorCode = response.error?.code?.lowercased() {
                if errorCode.contains("invalid_access_key") || errorCode.contains("unauthorized") {
                    return .unauthorized
                }
                if errorCode.contains("usage_limit") || errorCode.contains("quota") {
                    return .quotaExceeded
                }
                if errorCode.contains("function_access_restricted") || errorCode.contains("access_restricted") {
                    return .restrictedPlan
                }
                return .failed
            }

            if (response.data ?? []).isEmpty {
                return .noData
            }
            return .connected
        } catch {
            return .failed
        }
    }

    private func resolveBestCandidate(
        apiKey: String,
        flightCode: String,
        originCode: String,
        destinationCode: String,
        serviceDate: Date,
        expectedDepartureDate: Date
    ) async throws -> (flight: AviationstackFlight, strategy: String)? {
        for attempt in queryAttempts(
            flightCode: flightCode,
            originCode: originCode,
            destinationCode: destinationCode,
            serviceDate: serviceDate
        ) {
            let response = try await fetchFlights(apiKey: apiKey, queryItems: attempt.items)
            if response.error != nil {
                continue
            }

            let candidates = response.data ?? []
            if candidates.isEmpty {
                continue
            }

            if let best = bestMatch(
                from: candidates,
                expectedDepartureDate: expectedDepartureDate,
                flightCode: flightCode,
                originCode: originCode,
                destinationCode: destinationCode
            ) {
                return (best, attempt.name)
            }
        }

        return nil
    }

    private func queryAttempts(
        flightCode: String,
        originCode: String,
        destinationCode: String,
        serviceDate: Date
    ) -> [QueryAttempt] {
        let serviceDay = Calendar.roster.startOfDay(for: serviceDate)
        let flightNumberDigits = flightCode.filter(\.isNumber)
        let dateFormatter = serviceDateFormatter
        let dateCandidates: [Date] = [
            serviceDay,
            Calendar.roster.date(byAdding: .day, value: -1, to: serviceDay),
            Calendar.roster.date(byAdding: .day, value: 1, to: serviceDay)
        ]
        .compactMap { $0 }

        var attempts: [QueryAttempt] = []
        for candidateDate in dateCandidates {
            attempts.append((
                "flight_iata + route + date(\(dateFormatter.string(from: candidateDate)))",
                [
                    URLQueryItem(name: "flight_iata", value: flightCode),
                    URLQueryItem(name: "dep_iata", value: originCode),
                    URLQueryItem(name: "arr_iata", value: destinationCode),
                    URLQueryItem(name: "flight_date", value: dateFormatter.string(from: candidateDate)),
                    URLQueryItem(name: "limit", value: "25")
                ]
            ))
        }

        attempts.append((
            "flight_iata + date",
            [
                URLQueryItem(name: "flight_iata", value: flightCode),
                URLQueryItem(name: "flight_date", value: serviceDateText(serviceDay)),
                URLQueryItem(name: "limit", value: "25")
            ]
        ))

        if flightNumberDigits.isEmpty == false {
            attempts.append((
                "airline + flight_number + route + date",
                [
                    URLQueryItem(name: "airline_iata", value: "TG"),
                    URLQueryItem(name: "flight_number", value: flightNumberDigits),
                    URLQueryItem(name: "dep_iata", value: originCode),
                    URLQueryItem(name: "arr_iata", value: destinationCode),
                    URLQueryItem(name: "flight_date", value: serviceDateText(serviceDay)),
                    URLQueryItem(name: "limit", value: "25")
                ]
            ))
        }

        attempts.append((
            "flight_iata only",
            [
                URLQueryItem(name: "flight_iata", value: flightCode),
                URLQueryItem(name: "limit", value: "25")
            ]
        ))

        return attempts
    }

    private func liveDetails(from candidate: AviationstackFlight) -> LiveFlightDetails {
        let aircraft = candidate.aircraft?.iata ?? candidate.aircraft?.icao ?? candidate.aircraft?.registration
        return LiveFlightDetails(
            departureAircraftType: aircraft,
            arrivalAircraftType: aircraft,
            departureGate: formattedGate(terminal: candidate.departure?.terminal, gate: candidate.departure?.gate),
            arrivalGate: formattedGate(terminal: candidate.arrival?.terminal, gate: candidate.arrival?.gate)
        )
    }

    private func fetchFlights(apiKey: String, queryItems: [URLQueryItem]) async throws -> AviationstackFlightsResponse {
        var components = URLComponents(string: "https://api.aviationstack.com/v1/flights")
        components?.queryItems = [URLQueryItem(name: "access_key", value: apiKey)] + queryItems

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) == false {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(AviationstackFlightsResponse.self, from: data)
    }

    private func bestMatch(
        from candidates: [AviationstackFlight],
        expectedDepartureDate: Date,
        flightCode: String,
        originCode: String,
        destinationCode: String
    ) -> AviationstackFlight? {
        guard candidates.isEmpty == false else {
            return nil
        }

        return candidates.min { lhs, rhs in
            let lhsScore = matchScore(
                lhs,
                expectedDepartureDate: expectedDepartureDate,
                flightCode: flightCode,
                originCode: originCode,
                destinationCode: destinationCode
            )
            let rhsScore = matchScore(
                rhs,
                expectedDepartureDate: expectedDepartureDate,
                flightCode: flightCode,
                originCode: originCode,
                destinationCode: destinationCode
            )
            return lhsScore < rhsScore
        }
    }

    private func matchScore(
        _ candidate: AviationstackFlight,
        expectedDepartureDate: Date,
        flightCode: String,
        originCode: String,
        destinationCode: String
    ) -> Double {
        var score = 0.0
        if candidate.matchedFlightIATA?.uppercased() != flightCode {
            score += 100_000
        }
        if candidate.departure?.iata?.uppercased() != originCode {
            score += 10_000
        }
        if candidate.arrival?.iata?.uppercased() != destinationCode {
            score += 10_000
        }

        let departureDelta = departureDeltaSeconds(candidate, expectedDepartureDate: expectedDepartureDate)
        score += departureDelta / 60

        let hasUsefulData = (candidate.aircraft?.iata?.isEmpty == false)
            || (candidate.aircraft?.icao?.isEmpty == false)
            || (candidate.departure?.gate?.isEmpty == false)
            || (candidate.arrival?.gate?.isEmpty == false)
        if hasUsefulData == false {
            score += 500
        }

        return score
    }

    private func departureDeltaSeconds(_ candidate: AviationstackFlight, expectedDepartureDate: Date) -> Double {
        guard let scheduled = candidate.departure?.scheduled,
              let parsed = parseISO8601(scheduled) else {
            return 999_999
        }
        return abs(parsed.timeIntervalSince(expectedDepartureDate))
    }

    private func parseISO8601(_ value: String) -> Date? {
        if let parsed = iso8601WithFractional.date(from: value) {
            return parsed
        }
        return iso8601.date(from: value)
    }

    private func formattedGate(terminal: String?, gate: String?) -> String? {
        let trimmedTerminal = terminal?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedGate = gate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch (trimmedTerminal.isEmpty, trimmedGate.isEmpty) {
        case (false, false):
            return "Terminal \(trimmedTerminal) Gate \(trimmedGate)"
        case (false, true):
            return "Terminal \(trimmedTerminal)"
        case (true, false):
            return "Gate \(trimmedGate)"
        default:
            return nil
        }
    }

    private func serviceDateText(_ date: Date) -> String {
        serviceDateFormatter.string(from: date)
    }

    private var serviceDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = .roster
        formatter.timeZone = rosterTimeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private var iso8601WithFractional: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private var iso8601: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}

private struct AviationstackFlightsResponse: Decodable {
    let data: [AviationstackFlight]?
    let error: AviationstackError?
}

private struct AviationstackFlight: Decodable {
    let flight: AviationstackFlightIdentity?
    let aircraft: AviationstackAircraft?
    let departure: AviationstackStopInfo?
    let arrival: AviationstackStopInfo?

    var matchedFlightIATA: String? {
        flight?.iata ?? flight?.codeshared?.flight?.iata
    }
}

private struct AviationstackFlightIdentity: Decodable {
    let iata: String?
    let codeshared: AviationstackCodeshared?

    private enum CodingKeys: String, CodingKey {
        case iata
        case codeshared
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iata = container.decodeLossyString(forKey: .iata)
        codeshared = try? container.decodeIfPresent(AviationstackCodeshared.self, forKey: .codeshared)
    }
}

private struct AviationstackAircraft: Decodable {
    let iata: String?
    let icao: String?
    let registration: String?

    private enum CodingKeys: String, CodingKey {
        case iata
        case icao
        case registration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iata = container.decodeLossyString(forKey: .iata)
        icao = container.decodeLossyString(forKey: .icao)
        registration = container.decodeLossyString(forKey: .registration)
    }
}

private struct AviationstackStopInfo: Decodable {
    let iata: String?
    let terminal: String?
    let gate: String?
    let scheduled: String?

    private enum CodingKeys: String, CodingKey {
        case iata
        case terminal
        case gate
        case scheduled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iata = container.decodeLossyString(forKey: .iata)
        terminal = container.decodeLossyString(forKey: .terminal)
        gate = container.decodeLossyString(forKey: .gate)
        scheduled = container.decodeLossyString(forKey: .scheduled)
    }
}

private struct AviationstackError: Decodable {
    let code: String?

    private enum CodingKeys: String, CodingKey {
        case code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = container.decodeLossyString(forKey: .code)
    }
}

private struct AviationstackCodeshared: Decodable {
    let flight: AviationstackCodesharedFlightIdentity?
}

private struct AviationstackCodesharedFlightIdentity: Decodable {
    let iata: String?

    private enum CodingKeys: String, CodingKey {
        case iata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        iata = container.decodeLossyString(forKey: .iata)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: K) -> String? {
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return sanitizeString(stringValue)
        }

        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }

        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            if doubleValue.rounded() == doubleValue {
                return String(Int(doubleValue))
            }
            return String(doubleValue)
        }

        if let boolValue = try? decodeIfPresent(Bool.self, forKey: key) {
            return boolValue ? "true" : "false"
        }

        return nil
    }

    private func sanitizeString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let lowered = trimmed.lowercased()
        let placeholders = ["-", "--", "n/a", "na", "null", "nil", "unknown"]
        return placeholders.contains(lowered) ? nil : trimmed
    }
}
