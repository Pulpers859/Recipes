import Foundation

enum PantryBackupService {
    private static let backupDirectoryName = "RecipeVault/Backups"
    private static let automaticBackupFilename = "RecipeVault-Pantry-Latest.json"
    // A separate snapshot taken right before a destructive clear. The rolling
    // automatic backup gets overwritten with the (now empty) pantry the instant
    // items are cleared, so it can't be the recovery story for a clear-all —
    // this file is, and nothing else writes to it.
    private static let preClearBackupFilename = "RecipeVault-Pantry-BeforeClear.json"

    static let currentBackupVersion = 1

    static func exportAsJSON(pantryItems: [PantryItem]) throws -> Data {
        let exportItems = pantryItems.map { item in
            ExportablePantryItem(
                id: item.id,
                name: item.name,
                amount: item.amount,
                unit: item.unit,
                category: item.category.rawValue,
                isStaple: item.isStaple,
                dateUpdated: item.dateUpdated
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let wrapper = PantryExportWrapper(
            version: 1,
            exportDate: Date(),
            pantryItemCount: exportItems.count,
            pantryItems: exportItems
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(wrapper)
    }

    static func writeAutomaticBackup(pantryItems: [PantryItem]) throws -> URL {
        let backupURL = try automaticBackupURL()
        let data = try exportAsJSON(pantryItems: pantryItems)
        try data.write(to: backupURL, options: .atomic)
        return backupURL
    }

    static func makeShareableExportFile(pantryItems: [PantryItem]) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "RecipeVault-Pantry-Backup-\(formatter.string(from: Date())).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        let data = try exportAsJSON(pantryItems: pantryItems)
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }

    static func automaticBackupURL() throws -> URL {
        try backupDirectoryURL().appendingPathComponent(automaticBackupFilename)
    }

    /// URL of the snapshot captured immediately before a destructive clear.
    static func preClearBackupURL() throws -> URL {
        try backupDirectoryURL().appendingPathComponent(preClearBackupFilename)
    }

    /// Writes the pre-clear recovery snapshot. Call this with the *current*
    /// items just before deleting them.
    @discardableResult
    static func writePreClearBackup(pantryItems: [PantryItem]) throws -> URL {
        let backupURL = try preClearBackupURL()
        let data = try exportAsJSON(pantryItems: pantryItems)
        try data.write(to: backupURL, options: .atomic)
        return backupURL
    }

    /// True when a non-empty pre-clear snapshot exists to restore from.
    static func hasRestorableBackup() -> Bool {
        guard let url = try? preClearBackupURL(),
              let data = try? Data(contentsOf: url),
              let items = try? importFromJSON(data: data) else { return false }
        return !items.isEmpty
    }

    /// Restores items from the pre-clear snapshot file.
    static func restoreFromPreClearBackup() throws -> [PantryItem] {
        let url = try preClearBackupURL()
        let data = try Data(contentsOf: url)
        return try importFromJSON(data: data)
    }

    /// Decodes a pantry backup into fresh `PantryItem`s. Version-aware and
    /// tolerant of a single corrupt record so one bad row can't fail the whole
    /// restore.
    static func importFromJSON(data: Data) throws -> [PantryItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let wrapper = try decoder.decode(PantryImportWrapper.self, from: data)
        let version = wrapper.version ?? 1
        guard version <= currentBackupVersion else {
            throw PantryBackupError.unsupportedVersion(found: version, supported: currentBackupVersion)
        }

        return wrapper.pantryItems.compactMap { $0.value }.map { exp in
            let item = PantryItem(
                name: exp.name,
                amount: max(exp.amount, 0),
                unit: exp.unit,
                category: ShoppingCategory(rawValue: exp.category) ?? .other,
                isStaple: exp.isStaple
            )
            item.dateUpdated = exp.dateUpdated
            return item
        }
    }

    private static func backupDirectoryURL() throws -> URL {
        let documentsDirectory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let backupDirectory = documentsDirectory.appendingPathComponent(backupDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        return backupDirectory
    }
}

enum PantryBackupError: LocalizedError {
    case unsupportedVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(found, supported):
            return "This pantry backup uses a newer format (v\(found)) than this app supports (v\(supported)). Update the app and try again."
        }
    }
}

/// Lenient decode counterpart of `PantryExportWrapper`.
private struct PantryImportWrapper: Decodable {
    let version: Int?
    let pantryItems: [PantryFailableDecodable<ExportablePantryItem>]
}

private struct PantryFailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}

private struct PantryExportWrapper: Codable {
    let version: Int
    let exportDate: Date
    let pantryItemCount: Int
    let pantryItems: [ExportablePantryItem]
}

private struct ExportablePantryItem: Codable {
    let id: UUID
    let name: String
    let amount: Double
    let unit: String
    let category: String
    let isStaple: Bool
    let dateUpdated: Date
}
