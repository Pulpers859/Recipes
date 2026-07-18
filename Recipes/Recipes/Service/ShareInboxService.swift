import Foundation

/// A pending shared item: its committed envelope plus resolved file URLs.
nonisolated struct ShareInboxItem: Identifiable, Sendable, Equatable {
    let envelope: ShareInbox.Envelope
    let envelopeURL: URL
    let payloadURL: URL
    let payloadSizeBytes: Int

    var id: UUID { envelope.id }
}

/// App-side reader for the share-extension inbox. Non-destructive by design:
/// nothing here deletes user data except `removeItem`, which the UI calls
/// only after a successful import or an explicit user discard. Damaged
/// entries are skipped, never deleted — they stay on disk, reachable through
/// the Files app, for manual recovery.
nonisolated enum ShareInboxService {
    enum ReadError: Error, LocalizedError {
        case payloadTooLarge
        case unreadablePayload

        var errorDescription: String? {
            switch self {
            case .payloadTooLarge:
                return "This shared item is too large to import."
            case .unreadablePayload:
                return "This shared item could not be read."
            }
        }
    }

    /// Committed items, oldest first. Skips (but never deletes): corrupt
    /// envelopes, envelopes from a newer app version, envelopes whose payload
    /// is missing, and payload filenames that try to escape the inbox.
    static func listItems(in directory: URL? = ShareInbox.inboxDirectory()) -> [ShareInboxItem] {
        guard let directory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return [] }

        let decoder = ShareInbox.makeDecoder()
        var items: [ShareInboxItem] = []
        for name in names where name.hasSuffix(ShareInbox.envelopeSuffix) {
            let envelopeURL = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: envelopeURL),
                  let envelope = try? decoder.decode(ShareInbox.Envelope.self, from: data),
                  envelope.version <= ShareInbox.currentVersion
            else { continue }
            guard !envelope.payloadFilename.contains("/"),
                  !envelope.payloadFilename.contains("\\"),
                  !envelope.payloadFilename.contains("..")
            else { continue }
            let payloadURL = directory.appendingPathComponent(envelope.payloadFilename)
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: payloadURL.path),
                  let size = (attributes[.size] as? NSNumber)?.intValue
            else { continue }
            items.append(ShareInboxItem(
                envelope: envelope,
                envelopeURL: envelopeURL,
                payloadURL: payloadURL,
                payloadSizeBytes: size
            ))
        }
        return items.sorted {
            if $0.envelope.createdAt == $1.envelope.createdAt {
                return $0.envelope.id.uuidString < $1.envelope.id.uuidString
            }
            return $0.envelope.createdAt < $1.envelope.createdAt
        }
    }

    static func itemCount(in directory: URL? = ShareInbox.inboxDirectory()) -> Int {
        listItems(in: directory).count
    }

    /// Reads the payload, re-checking size on disk so a file grown after
    /// listing can't bypass the cap.
    static func payloadData(for item: ShareInboxItem, maxBytes: Int = ShareInbox.maxPayloadBytes) throws -> Data {
        guard item.payloadSizeBytes <= maxBytes else { throw ReadError.payloadTooLarge }
        do {
            let data = try Data(contentsOf: item.payloadURL)
            guard data.count <= maxBytes else { throw ReadError.payloadTooLarge }
            return data
        } catch let error as ReadError {
            throw error
        } catch {
            throw ReadError.unreadablePayload
        }
    }

    /// Envelope first — uncommitting the item — then payload. If the payload
    /// removal fails, the orphan is invisible to `listItems` and harmless.
    static func removeItem(_ item: ShareInboxItem) {
        try? FileManager.default.removeItem(at: item.envelopeURL)
        try? FileManager.default.removeItem(at: item.payloadURL)
    }
}
