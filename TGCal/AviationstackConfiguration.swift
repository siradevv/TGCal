import Foundation

enum AviationstackConfiguration {
    private static let infoPlistKey = "AVIATIONSTACK_API_KEY"

    static var apiKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
