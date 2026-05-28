import Foundation
import Security

// MARK: - Keychain Service

/// Lightweight wrapper for storing small secrets in the iOS Keychain.
enum KeychainService {
    private static let defaultService = "com.recipevault.app"

    static func readString(forKey key: String) -> String? {
        readString(forKey: key, service: defaultService)
    }

    static func readString(forKey key: String, service: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveString(_ value: String, forKey key: String) throws {
        try saveString(
            value,
            forKey: key,
            service: defaultService,
            accessibility: kSecAttrAccessibleAfterFirstUnlock
        )
    }

    static func saveString(
        _ value: String,
        forKey key: String,
        service: String,
        accessibility: CFString = kSecAttrAccessibleAfterFirstUnlock
    ) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus == errSecItemNotFound {
            var createQuery = query
            createQuery[kSecValueData as String] = data
            createQuery[kSecAttrAccessible as String] = accessibility
            let createStatus = SecItemAdd(createQuery as CFDictionary, nil)
            guard createStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(createStatus)
            }
            return
        }

        throw KeychainError.unhandledStatus(updateStatus)
    }

    static func deleteValue(forKey key: String) throws {
        try deleteValue(forKey: key, service: defaultService)
    }

    static func deleteValue(forKey key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }
}

enum APIKeyStore {
    private static let apiKeyAccount = "claude_api_key"
    private static let legacyServices = ["com.recipevault.app"]

    enum KeySource {
        case keychain
        case bundledConfig
    }

    static func loadClaudeKey() -> String? {
        migrateLegacyClaudeKeyIfNeeded()
        return storedClaudeKey() ?? AppConfig.anthropicAPIKeyFallback
    }

    static func currentClaudeKeySource() -> KeySource? {
        migrateLegacyClaudeKeyIfNeeded()
        if storedClaudeKey() != nil {
            return .keychain
        }
        if AppConfig.anthropicAPIKeyFallback != nil {
            return .bundledConfig
        }
        return nil
    }

    static func storedClaudeKey() -> String? {
        let primary = primaryServiceName
        guard let value = KeychainService.readString(forKey: apiKeyAccount, service: primary)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static func saveClaudeKey(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        try KeychainService.saveString(
            trimmed,
            forKey: apiKeyAccount,
            service: primaryServiceName,
            accessibility: kSecAttrAccessibleAfterFirstUnlock
        )
        UserDefaults.standard.removeObject(forKey: apiKeyAccount)
    }

    static func deleteClaudeKey() throws {
        try KeychainService.deleteValue(forKey: apiKeyAccount, service: primaryServiceName)
        for service in legacyServices where service != primaryServiceName {
            try KeychainService.deleteValue(forKey: apiKeyAccount, service: service)
        }
        UserDefaults.standard.removeObject(forKey: apiKeyAccount)
    }

    @discardableResult
    static func migrateLegacyClaudeKeyIfNeeded() -> Bool {
        let primary = primaryServiceName
        if let current = KeychainService.readString(forKey: apiKeyAccount, service: primary)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !current.isEmpty {
            return false
        }

        let legacyCandidates = legacyServices.filter { $0 != primary }
        for service in legacyCandidates {
            if let legacy = KeychainService.readString(forKey: apiKeyAccount, service: service)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !legacy.isEmpty {
                try? saveClaudeKey(legacy)
                return true
            }
        }

        if let defaultsValue = UserDefaults.standard.string(forKey: apiKeyAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !defaultsValue.isEmpty {
            try? saveClaudeKey(defaultsValue)
            return true
        }

        return false
    }

    private static var primaryServiceName: String {
        if let bundleID = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleID.isEmpty {
            return bundleID
        }
        return legacyServices[0]
    }
}

enum KeychainError: LocalizedError {
    case unhandledStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandledStatus(let status):
            return "Keychain error (status \(status))"
        }
    }
}
