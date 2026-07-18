import XCTest
@testable import Recipes

/// Tests for the timestamped safety-snapshot scheme: filename round-tripping,
/// pruning, and migration of the old single rolling backup file. All paths
/// are exercised against a throwaway temp directory — never the real backup
/// location.
final class BackupSnapshotTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupSnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Filename round trip

    func testSnapshotFilenameRoundTripsDateAndKind() {
        let date = Date(timeIntervalSince1970: 1_784_000_000.123)
        for kind in [RecipeExportService.SnapshotKind.safety, .auto] {
            let name = RecipeExportService.snapshotFilename(for: date, kind: kind)
            let url = tempDirectory.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data("{}".utf8))

            let parsed = RecipeExportService.snapshot(fromFileURL: url)
            XCTAssertNotNil(parsed, "\(name) should parse back into a snapshot")
            XCTAssertEqual(parsed?.kind, kind)
            // Millisecond precision is all the filename carries.
            XCTAssertEqual(parsed?.date.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.005)
            XCTAssertEqual(parsed?.sizeBytes, 2)
        }
    }

    func testForeignAndMalformedFilenamesAreIgnored() {
        let names = [
            "notes.json",
            "RecipeVault-Recipes-Latest.json",
            "RecipeVault-Snapshot-garbage.json",
            "RecipeVault-Snapshot-20260717-121212-123-unknownkind.json",
            "RecipeVault-Snapshot-20260717-121212-123-safety.txt"
        ]
        for name in names {
            let url = tempDirectory.appendingPathComponent(name)
            XCTAssertNil(RecipeExportService.snapshot(fromFileURL: url), "\(name) must not parse as a snapshot")
        }
    }

    // MARK: - Pruning

    func testPruneKeepsOnlyTheNewestSnapshots() throws {
        let total = RecipeExportService.maxSnapshotCount + 3
        var expectedSurvivors: [String] = []
        for index in 0..<total {
            let date = Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index) * 60)
            let name = RecipeExportService.snapshotFilename(for: date, kind: index.isMultiple(of: 2) ? .safety : .auto)
            FileManager.default.createFile(
                atPath: tempDirectory.appendingPathComponent(name).path,
                contents: Data("{}".utf8)
            )
            if index >= total - RecipeExportService.maxSnapshotCount {
                expectedSurvivors.append(name)
            }
        }
        // A file that doesn't match the snapshot pattern must never be pruned.
        FileManager.default.createFile(
            atPath: tempDirectory.appendingPathComponent("keep-me.json").path,
            contents: Data("{}".utf8)
        )

        RecipeExportService.pruneSnapshots(in: tempDirectory)

        let remaining = Set(try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path))
        XCTAssertEqual(remaining, Set(expectedSurvivors + ["keep-me.json"]))
    }

    func testPruneLeavesDirectoriesWithFewSnapshotsAlone() throws {
        let name = RecipeExportService.snapshotFilename(for: Date(), kind: .safety)
        FileManager.default.createFile(
            atPath: tempDirectory.appendingPathComponent(name).path,
            contents: Data("{}".utf8)
        )

        RecipeExportService.pruneSnapshots(in: tempDirectory)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(remaining, [name])
    }

    // MARK: - Legacy migration

    func testLegacyRollingBackupIsMigratedIntoSnapshotScheme() throws {
        let payload = Data(#"{"version":4,"recipes":[]}"#.utf8)
        let legacy = tempDirectory.appendingPathComponent("RecipeVault-Recipes-Latest.json")
        try payload.write(to: legacy)

        RecipeExportService.migrateLegacyBackupIfNeeded(in: tempDirectory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "legacy file should be renamed")
        let contents = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
        let snapshots = contents.compactMap(RecipeExportService.snapshot(fromFileURL:))
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.kind, .safety)
        XCTAssertEqual(try Data(contentsOf: snapshots[0].url), payload, "contents must survive the rename byte-for-byte")
    }

    func testMigrationIsNoOpWithoutLegacyFile() {
        RecipeExportService.migrateLegacyBackupIfNeeded(in: tempDirectory)
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)) ?? []
        XCTAssertTrue(contents.isEmpty)
    }
}
