import Foundation

enum PantryBackupService {
    private static let backupDirectoryName = "RecipeVault/Backups"
    private static let automaticBackupFilename = "RecipeVault-Pantry-Latest.json"

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
        let documentsDirectory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let backupDirectory = documentsDirectory.appendingPathComponent(backupDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        return backupDirectory.appendingPathComponent(automaticBackupFilename)
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
