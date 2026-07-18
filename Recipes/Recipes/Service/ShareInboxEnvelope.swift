import Foundation

/// On-disk protocol between the share extension (writer) and the app (reader).
///
/// The payload file is written first and the envelope last, so an envelope's
/// existence is the commit marker: a payload with no envelope is a failed or
/// in-flight write and must be ignored by readers. This file will be compiled
/// into BOTH the app and the share extension target (see
/// the `RecipeVaultShare` target — keep it Foundation-only and free of app
/// dependencies.
nonisolated enum ShareInbox {
    static let appGroupIdentifier = "group.Patrick-App.Recipes"
    static let inboxDirectoryName = "ImportInbox"
    static let envelopeSuffix = ".envelope.json"
    static let currentVersion = 1
    /// Hard ceiling for any payload; the per-kind app limits (25 MB PDF,
    /// 15 MB photo) are enforced again at import time.
    static let maxPayloadBytes = 25 * 1024 * 1024
    /// Writers refuse new items beyond this many pending envelopes so a
    /// misbehaving share loop can't fill the App Group container.
    static let maxItemCount = 20

    enum Kind: String, Codable, Sendable, CaseIterable {
        case url
        case pdf
        case image

        var payloadExtension: String {
            switch self {
            case .url: return "txt"
            case .pdf: return "pdf"
            case .image: return "img"
            }
        }

        var displayLabel: String {
            switch self {
            case .url: return "Recipe link"
            case .pdf: return "PDF"
            case .image: return "Photo"
            }
        }

        var icon: String {
            switch self {
            case .url: return "link"
            case .pdf: return "doc.fill"
            case .image: return "photo"
            }
        }
    }

    struct Envelope: Codable, Sendable, Equatable, Identifiable {
        let id: UUID
        let version: Int
        let kind: Kind
        let payloadFilename: String
        let createdAt: Date
    }

    enum WriteError: Error, LocalizedError {
        case payloadTooLarge
        case inboxFull

        var errorDescription: String? {
            switch self {
            case .payloadTooLarge:
                return "That item is too large to share into Recipe Vault."
            case .inboxFull:
                return "Recipe Vault has too many shared items waiting. Open the app and import or discard them first."
            }
        }
    }

    /// The App Group inbox, or nil when the entitlement or shared container is
    /// unavailable. Callers treat nil as an unavailable feature, not a reason
    /// to create a private fallback directory the extension cannot access.
    static func inboxDirectory(fileManager: FileManager = .default) -> URL? {
        #if canImport(Darwin)
        return fileManager
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(inboxDirectoryName, isDirectory: true)
        #else
        return nil
        #endif
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Writer side, used by the share extension and exercised by unit tests.
    /// Payload first, envelope last; if the envelope write fails the payload
    /// is cleaned up so it can't linger as an orphan.
    @discardableResult
    static func writeItem(
        kind: Kind,
        payload: Data,
        in directory: URL,
        createdAt: Date = Date(),
        maxBytes: Int = maxPayloadBytes,
        maxItems: Int = maxItemCount
    ) throws -> Envelope {
        guard payload.count <= maxBytes else { throw WriteError.payloadTooLarge }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let pendingEnvelopes = ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(envelopeSuffix) }
        guard pendingEnvelopes.count < maxItems else { throw WriteError.inboxFull }

        let id = UUID()
        let payloadFilename = "\(id.uuidString).\(kind.payloadExtension)"
        let payloadURL = directory.appendingPathComponent(payloadFilename)
        let envelopeURL = directory.appendingPathComponent("\(id.uuidString)\(envelopeSuffix)")
        let envelope = Envelope(
            id: id,
            version: currentVersion,
            kind: kind,
            payloadFilename: payloadFilename,
            createdAt: createdAt
        )

        try payload.write(to: payloadURL, options: .atomic)
        do {
            try makeEncoder().encode(envelope).write(to: envelopeURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: payloadURL)
            throw error
        }
        return envelope
    }
}
