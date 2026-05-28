import Foundation

enum AppConfig {
    // Optional built-in fallback for personal use in Xcode.
    // Leave empty if you prefer Keychain or Info.plist only.
    static let bundledAnthropicAPIKey = ""

    static let anthropicAPIKeyInfoPlistKey = "ANTHROPIC_API_KEY"

    static var anthropicAPIKeyFallback: String? {
        if let env = ProcessInfo.processInfo.environment[anthropicAPIKeyInfoPlistKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }

        if let plistValue = Bundle.main.object(forInfoDictionaryKey: anthropicAPIKeyInfoPlistKey) as? String {
            let cleaned = plistValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        let bundled = bundledAnthropicAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return bundled.isEmpty ? nil : bundled
    }
}
