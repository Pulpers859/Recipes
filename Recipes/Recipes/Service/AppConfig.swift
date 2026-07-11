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
    static let anthropicAPIKeyEnvironmentKey = "ANTHROPIC_API_KEY"

    /// Development-only fallback: an environment variable set in the Xcode
    /// scheme (simulator/dev runs). The previous Info.plist path was removed
    /// deliberately — a key wired through build settings gets baked in
    /// plaintext into every shipped IPA, where it is trivially extractable.
    /// Real devices use the Keychain via Settings.
    static var anthropicAPIKeyFallback: String? {
        if let env = ProcessInfo.processInfo.environment[anthropicAPIKeyEnvironmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !env.isEmpty {
            return env
        }
        return nil
    }
}
