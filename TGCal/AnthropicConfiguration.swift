import Foundation

enum AnthropicConfiguration {
    private static let apiKeyName = "ANTHROPIC_API_KEY"
    private static let secretsPlistName = "AnthropicSecrets"

    static var apiKey: String? {
        if let value = normalized(Bundle.main.object(forInfoDictionaryKey: apiKeyName) as? String) {
            return value
        }

        if let url = Bundle.main.url(forResource: secretsPlistName, withExtension: "plist"),
           let values = NSDictionary(contentsOf: url) as? [String: Any],
           let value = normalized(values[apiKeyName] as? String) {
            return value
        }

        if let value = normalized(ProcessInfo.processInfo.environment[apiKeyName]) {
            return value
        }

        return nil
    }

    private static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }

        if trimmed.hasPrefix("$("), trimmed.hasSuffix(")") {
            return nil
        }

        return trimmed
    }
}
