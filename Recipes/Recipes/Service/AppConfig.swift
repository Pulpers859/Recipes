import Foundation

/// Central source of truth for which Claude model the app calls.
/// Old model IDs get retired by the API (returning 404s that silently degrade
/// AI parsing to the manual fallback), so stored values are migrated on read.
enum AIModelSettings {
    static let storageKey = "ai_model_id"
    static let defaultModelID = "claude-sonnet-4-6"

    /// Deprecated/retired model IDs mapped to their drop-in replacements.
    private static let legacyModelReplacements: [String: String] = [
        "claude-sonnet-4-20250514": "claude-sonnet-4-6",
        "claude-opus-4-20250514": "claude-opus-4-8",
        "claude-3-5-sonnet-20241022": "claude-sonnet-4-6",
        "claude-3-5-haiku-20241022": "claude-haiku-4-5-20251001"
    ]

    /// The model ID to use for API calls. Migrates any stored legacy ID first.
    static var currentModelID: String {
        migrateStoredModelIfNeeded()
        return UserDefaults.standard.string(forKey: storageKey) ?? defaultModelID
    }

    /// Rewrites a stored deprecated model ID to its replacement so existing
    /// installs don't keep calling a retired model.
    static func migrateStoredModelIfNeeded() {
        guard let stored = UserDefaults.standard.string(forKey: storageKey),
              let replacement = legacyModelReplacements[stored] else { return }
        UserDefaults.standard.set(replacement, forKey: storageKey)
    }
}

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
