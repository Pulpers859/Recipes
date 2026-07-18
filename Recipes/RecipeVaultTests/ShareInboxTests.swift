import XCTest
@testable import Recipes

/// The share-extension inbox protocol: payload written first, envelope last,
/// so the envelope's existence is the commit marker. The reader must be
/// non-destructive toward anything it doesn't understand — damaged or
/// foreign files are skipped, never deleted.
final class ShareInboxTests: XCTestCase {

    private var inbox: URL!

    override func setUpWithError() throws {
        inbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-inbox-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let inbox { try? FileManager.default.removeItem(at: inbox) }
    }

    func testWriteThenListRoundTrip() throws {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        try ShareInbox.writeItem(kind: .image, payload: Data([3, 4]), in: inbox, createdAt: base.addingTimeInterval(20))
        try ShareInbox.writeItem(kind: .url, payload: Data("https://example.com/r".utf8), in: inbox, createdAt: base)
        try ShareInbox.writeItem(kind: .pdf, payload: Data([1, 2, 3]), in: inbox, createdAt: base.addingTimeInterval(10))

        let items = ShareInboxService.listItems(in: inbox)
        XCTAssertEqual(items.map { $0.envelope.kind }, [.url, .pdf, .image], "items must list oldest first")

        let urlItem = items[0]
        XCTAssertEqual(urlItem.envelope.version, ShareInbox.currentVersion)
        XCTAssertEqual(urlItem.payloadSizeBytes, "https://example.com/r".utf8.count)
        XCTAssertTrue(urlItem.envelope.payloadFilename.hasSuffix(".txt"))
        XCTAssertEqual(urlItem.envelope.createdAt.timeIntervalSince1970, base.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try ShareInboxService.payloadData(for: urlItem), Data("https://example.com/r".utf8))

        XCTAssertTrue(items[1].envelope.payloadFilename.hasSuffix(".pdf"))
        XCTAssertTrue(items[2].envelope.payloadFilename.hasSuffix(".img"))
        XCTAssertEqual(ShareInboxService.itemCount(in: inbox), 3)
    }

    func testPayloadWithoutEnvelopeIsInvisible() throws {
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try Data([9, 9]).write(to: inbox.appendingPathComponent("\(UUID().uuidString).pdf"))
        XCTAssertTrue(ShareInboxService.listItems(in: inbox).isEmpty,
                      "a payload with no envelope is an uncommitted write and must be ignored")
    }

    func testCorruptEnvelopeIsSkippedNotFatal() throws {
        try ShareInbox.writeItem(kind: .url, payload: Data("x".utf8), in: inbox)
        try Data("not json".utf8).write(to: inbox.appendingPathComponent("garbage\(ShareInbox.envelopeSuffix)"))

        let items = ShareInboxService.listItems(in: inbox)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: inbox.appendingPathComponent("garbage\(ShareInbox.envelopeSuffix)").path),
            "the reader must never delete what it can't parse"
        )
    }

    func testEnvelopeWithMissingPayloadIsSkipped() throws {
        let envelope = try ShareInbox.writeItem(kind: .image, payload: Data([1]), in: inbox)
        try FileManager.default.removeItem(at: inbox.appendingPathComponent(envelope.payloadFilename))
        XCTAssertTrue(ShareInboxService.listItems(in: inbox).isEmpty)
    }

    func testNewerEnvelopeVersionIsLeftPending() throws {
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let id = UUID()
        try Data([1]).write(to: inbox.appendingPathComponent("\(id.uuidString).pdf"))
        let futureEnvelope = """
        {"id":"\(id.uuidString)","version":99,"kind":"pdf","payloadFilename":"\(id.uuidString).pdf","createdAt":"2026-07-18T00:00:00Z"}
        """
        try Data(futureEnvelope.utf8).write(to: inbox.appendingPathComponent("\(id.uuidString)\(ShareInbox.envelopeSuffix)"))

        XCTAssertTrue(ShareInboxService.listItems(in: inbox).isEmpty,
                      "a newer app's envelope is skipped (and preserved) rather than misread")
    }

    func testTraversalPayloadFilenameIsSkipped() throws {
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let id = UUID()
        let evilEnvelope = """
        {"id":"\(id.uuidString)","version":1,"kind":"pdf","payloadFilename":"../evil.pdf","createdAt":"2026-07-18T00:00:00Z"}
        """
        try Data(evilEnvelope.utf8).write(to: inbox.appendingPathComponent("\(id.uuidString)\(ShareInbox.envelopeSuffix)"))
        XCTAssertTrue(ShareInboxService.listItems(in: inbox).isEmpty)
    }

    func testRemoveItemDeletesBothFiles() throws {
        try ShareInbox.writeItem(kind: .pdf, payload: Data([1, 2]), in: inbox)
        let item = try XCTUnwrap(ShareInboxService.listItems(in: inbox).first)

        ShareInboxService.removeItem(item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: item.envelopeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.payloadURL.path))
        XCTAssertTrue(ShareInboxService.listItems(in: inbox).isEmpty)
    }

    func testOversizePayloadRefusedAtWrite() throws {
        XCTAssertThrowsError(
            try ShareInbox.writeItem(kind: .image, payload: Data(count: 11), in: inbox, maxBytes: 10)
        ) { error in
            XCTAssertEqual(error as? ShareInbox.WriteError, .payloadTooLarge)
        }
        // A refused write must leave nothing behind.
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: inbox.path)) ?? []
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testOversizePayloadRefusedAtRead() throws {
        try ShareInbox.writeItem(kind: .pdf, payload: Data(count: 20), in: inbox)
        let item = try XCTUnwrap(ShareInboxService.listItems(in: inbox).first)

        XCTAssertThrowsError(try ShareInboxService.payloadData(for: item, maxBytes: 10)) { error in
            XCTAssertEqual(error as? ShareInboxService.ReadError, .payloadTooLarge)
        }
        XCTAssertEqual(ShareInboxService.listItems(in: inbox).count, 1,
                       "a refused read must not consume the item")
    }

    func testInboxFullRefusesNewWrites() throws {
        try ShareInbox.writeItem(kind: .url, payload: Data([1]), in: inbox, maxItems: 2)
        try ShareInbox.writeItem(kind: .url, payload: Data([2]), in: inbox, maxItems: 2)

        XCTAssertThrowsError(
            try ShareInbox.writeItem(kind: .url, payload: Data([3]), in: inbox, maxItems: 2)
        ) { error in
            XCTAssertEqual(error as? ShareInbox.WriteError, .inboxFull)
        }
        XCTAssertEqual(ShareInboxService.itemCount(in: inbox), 2)
    }

    func testMissingOrNilDirectoryReadsEmpty() {
        XCTAssertTrue(ShareInboxService.listItems(in: inbox).isEmpty, "directory was never created")
        XCTAssertTrue(ShareInboxService.listItems(in: nil).isEmpty, "nil means no App Group entitlement yet")
        XCTAssertEqual(ShareInboxService.itemCount(in: nil), 0)
    }
}
