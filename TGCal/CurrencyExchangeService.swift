import Foundation

struct CurrencyQuickConversion: Equatable {
    let sourceAmountTHB: Double
    let destinationAmount: Double
    let destinationCurrencyCode: String
}

actor CurrencyExchangeService {
    static let shared = CurrencyExchangeService()

    private var cachedRates: [String: Double] = [:]
    private var ratesUpdatedAt: Date?

    func convertTHBToDestination(amountTHB: Double, destinationCurrencyCode: String) async throws -> CurrencyQuickConversion {
        let destination = destinationCurrencyCode.uppercased()
        if destination == "THB" {
            return CurrencyQuickConversion(
                sourceAmountTHB: amountTHB,
                destinationAmount: amountTHB,
                destinationCurrencyCode: destination
            )
        }

        let rates = try await loadRatesIfNeeded()
        guard let destinationRate = rates[destination] else {
            throw URLError(.cannotParseResponse)
        }

        return CurrencyQuickConversion(
            sourceAmountTHB: amountTHB,
            destinationAmount: amountTHB * destinationRate,
            destinationCurrencyCode: destination
        )
    }

    func convertDestinationToTHB(amount: Double, sourceCurrencyCode: String) async throws -> Double {
        let source = sourceCurrencyCode.uppercased()
        if source == "THB" { return amount }

        let rates = try await loadRatesIfNeeded()
        guard let sourceRate = rates[source], sourceRate > 0 else {
            throw URLError(.cannotParseResponse)
        }

        return amount / sourceRate
    }

    private func loadRatesIfNeeded() async throws -> [String: Double] {
        if let ratesUpdatedAt,
           Date().timeIntervalSince(ratesUpdatedAt) < 6 * 60 * 60,
           cachedRates.isEmpty == false {
            return cachedRates
        }

        guard let url = URL(string: "https://open.er-api.com/v6/latest/THB") else {
            throw URLError(.badURL)
        }

        let (data, urlResponse) = try await URLSession.shared.data(from: url)
        if let http = urlResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let response = try JSONDecoder().decode(ExchangeRateAPIResponse.self, from: data)
        guard response.rates.isEmpty == false else {
            throw URLError(.cannotParseResponse)
        }

        cachedRates = response.rates
        ratesUpdatedAt = Date()
        return response.rates
    }
}

private struct ExchangeRateAPIResponse: Decodable {
    let rates: [String: Double]
}
