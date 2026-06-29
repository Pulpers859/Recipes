import Foundation
import PDFKit
import UIKit

// MARK: - Recipe Export Service

class RecipeExportService {
    
    // MARK: - JSON Export/Import (Backup)
    
    /// Export all recipes as a JSON backup file
    static func exportAsJSON(recipes: [Recipe]) throws -> Data {
        let exportData = recipes.map { recipe -> ExportableRecipe in
            ExportableRecipe(
                recipeID: recipe.id,
                title: recipe.title,
                summary: recipe.summary,
                ingredients: recipe.ingredients,
                steps: recipe.steps.sorted { $0.order < $1.order },
                servings: recipe.servings,
                prepTime: recipe.prepTime,
                cookTime: recipe.cookTime,
                category: recipe.category.rawValue,
                tags: recipe.tags,
                cuisine: recipe.cuisine,
                difficulty: recipe.difficulty.rawValue,
                sourceURL: recipe.sourceURL,
                sourceType: recipe.sourceType.rawValue,
                notes: recipe.notes,
                rating: recipe.rating,
                isFavorite: recipe.isFavorite,
                photoData: recipe.photoData,
                dateLastCooked: recipe.dateLastCooked,
                originalPDFData: recipe.originalPDFData,
                dateAdded: recipe.dateAdded,
                timesCooked: recipe.timesCooked
            )
        }
        
        let wrapper = ExportWrapper(
            version: 3,
            exportDate: Date(),
            recipeCount: exportData.count,
            recipes: exportData
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(wrapper)
    }
    
    // MARK: - Automatic Safety Backup

    private static let backupDirectoryName = "RecipeVault/Backups"
    private static let automaticBackupFilename = "RecipeVault-Recipes-Latest.json"

    /// Writes an on-device safety backup so destructive bulk deletes have a
    /// recovery story. The file is restorable via "Import from JSON Backup".
    @discardableResult
    static func writeAutomaticBackup(recipes: [Recipe]) throws -> URL {
        let documentsDirectory = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let backupDirectory = documentsDirectory.appendingPathComponent(backupDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backupURL = backupDirectory.appendingPathComponent(automaticBackupFilename)
        let data = try exportAsJSON(recipes: recipes)
        try data.write(to: backupURL, options: .atomic)
        return backupURL
    }

    /// Current backup schema version produced by `exportAsJSON`.
    static let currentBackupVersion = 3

    /// Import recipes from a JSON backup.
    ///
    /// Resilience guarantees:
    /// - A backup whose `version` is newer than this build understands is
    ///   rejected with a clear error rather than silently mis-imported.
    /// - One malformed recipe record is skipped instead of throwing away the
    ///   entire file (each record decodes independently).
    static func importFromJSON(data: Data) throws -> [Recipe] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let wrapper = try decoder.decode(ImportWrapper.self, from: data)

        let version = wrapper.version ?? 1
        guard version <= currentBackupVersion else {
            throw ImportError.unsupportedVersion(found: version, supported: currentBackupVersion)
        }

        let decoded = wrapper.recipes.compactMap { $0.value }
        guard !decoded.isEmpty else {
            // Either an empty backup or every record failed to decode; both are
            // worth surfacing rather than returning a silent empty import.
            throw ImportError.noReadableRecipes
        }

        return decoded.map { exp in
            let recipe = Recipe(
                title: exp.title,
                summary: exp.summary,
                ingredients: exp.ingredients,
                steps: exp.steps,
                servings: min(max(exp.servings, 1), 1000),
                prepTime: min(max(exp.prepTime, 0), 100_000),
                cookTime: min(max(exp.cookTime, 0), 100_000),
                category: RecipeCategory(rawValue: exp.category) ?? .other,
                tags: exp.tags,
                cuisine: exp.cuisine,
                difficulty: Difficulty(rawValue: exp.difficulty) ?? .medium,
                sourceURL: exp.sourceURL,
                sourceType: SourceType(rawValue: exp.sourceType ?? "") ?? .manual,
                notes: exp.notes,
                rating: min(max(exp.rating, 0), 5),
                isFavorite: exp.isFavorite,
                photoData: exp.photoData ?? [],
                originalPDFData: exp.originalPDFData
            )
            if let exportedID = exp.recipeID {
                recipe.id = exportedID
            }
            recipe.dateAdded = exp.dateAdded
            recipe.dateLastCooked = exp.dateLastCooked
            recipe.timesCooked = max(exp.timesCooked, 0)
            return recipe
        }
    }
    
    // MARK: - PDF Cookbook Export
    
    /// Generate a formatted PDF cookbook from recipes
    static func exportAsPDFCookbook(recipes: [Recipe], title: String = "My Recipe Vault") -> Data {
        let pageWidth: CGFloat = 612   // US Letter
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 54       // 0.75 inch margins
        let contentWidth = pageWidth - (margin * 2)
        
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        
        let data = renderer.pdfData { context in
            // Title page
            context.beginPage()
            drawTitlePage(context: context, title: title, recipeCount: recipes.count,
                         pageWidth: pageWidth, pageHeight: pageHeight)
            
            // Table of contents
            context.beginPage()
            drawTableOfContents(context: context, recipes: recipes,
                               margin: margin, contentWidth: contentWidth, pageHeight: pageHeight)
            
            // Recipe pages
            for recipe in recipes.sorted(by: { $0.title < $1.title }) {
                context.beginPage()
                drawRecipePage(context: context, recipe: recipe,
                              margin: margin, contentWidth: contentWidth,
                              pageWidth: pageWidth, pageHeight: pageHeight)
            }
        }
        
        return data
    }
    
    // MARK: - PDF Drawing
    
    private static func drawTitlePage(context: UIGraphicsPDFRendererContext, title: String,
                                       recipeCount: Int, pageWidth: CGFloat, pageHeight: CGFloat) {
        let titleFont = UIFont.systemFont(ofSize: 36, weight: .bold)
        let subtitleFont = UIFont.systemFont(ofSize: 16, weight: .regular)
        let dateFont = UIFont.systemFont(ofSize: 12, weight: .light)
        
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor.label
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: UIColor.secondaryLabel
        ]
        let dateAttrs: [NSAttributedString.Key: Any] = [
            .font: dateFont,
            .foregroundColor: UIColor.tertiaryLabel
        ]
        
        let titleSize = title.size(withAttributes: titleAttrs)
        let titleY = pageHeight * 0.35
        title.draw(at: CGPoint(x: (pageWidth - titleSize.width) / 2, y: titleY), withAttributes: titleAttrs)
        
        // Decorative line
        let lineY = titleY + titleSize.height + 16
        let lineCtx = context.cgContext
        lineCtx.setStrokeColor(UIColor.systemOrange.cgColor)
        lineCtx.setLineWidth(2)
        lineCtx.move(to: CGPoint(x: pageWidth * 0.3, y: lineY))
        lineCtx.addLine(to: CGPoint(x: pageWidth * 0.7, y: lineY))
        lineCtx.strokePath()
        
        let subtitle = "\(recipeCount) Recipes"
        let subtitleSize = subtitle.size(withAttributes: subtitleAttrs)
        subtitle.draw(at: CGPoint(x: (pageWidth - subtitleSize.width) / 2, y: lineY + 16), withAttributes: subtitleAttrs)
        
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        let dateStr = "Exported \(formatter.string(from: Date()))"
        let dateSize = dateStr.size(withAttributes: dateAttrs)
        dateStr.draw(at: CGPoint(x: (pageWidth - dateSize.width) / 2, y: pageHeight - 72), withAttributes: dateAttrs)
    }
    
    private static func drawTableOfContents(context: UIGraphicsPDFRendererContext, recipes: [Recipe],
                                             margin: CGFloat, contentWidth: CGFloat, pageHeight: CGFloat) {
        let headerFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        let itemFont = UIFont.systemFont(ofSize: 11, weight: .regular)
        
        let headerAttrs: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: UIColor.label]
        let itemAttrs: [NSAttributedString.Key: Any] = [.font: itemFont, .foregroundColor: UIColor.secondaryLabel]
        
        "Table of Contents".draw(at: CGPoint(x: margin, y: margin), withAttributes: headerAttrs)
        
        var y = margin + 40
        let sorted = recipes.sorted { $0.title < $1.title }
        
        for (index, recipe) in sorted.enumerated() {
            if y > pageHeight - margin - 20 {
                context.beginPage()
                y = margin
            }
            
            let text = "\(index + 1). \(recipe.title)"
            let metaText = "\(recipe.category.displayName) · \(recipe.totalTime) min"
            
            text.draw(in: CGRect(x: margin, y: y, width: contentWidth * 0.7, height: 18), withAttributes: itemAttrs)
            metaText.draw(in: CGRect(x: margin + contentWidth * 0.7, y: y, width: contentWidth * 0.3, height: 18),
                         withAttributes: [.font: UIFont.systemFont(ofSize: 9, weight: .light),
                                         .foregroundColor: UIColor.tertiaryLabel])
            y += 22
        }
    }
    
    private static func drawRecipePage(context: UIGraphicsPDFRendererContext, recipe: Recipe,
                                        margin: CGFloat, contentWidth: CGFloat,
                                        pageWidth: CGFloat, pageHeight: CGFloat) {
        let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
        let sectionFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 11, weight: .regular)
        let metaFont = UIFont.systemFont(ofSize: 10, weight: .medium)
        
        var y = margin
        
        // Title
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.label]
        let titleRect = CGRect(x: margin, y: y, width: contentWidth, height: 60)
        recipe.title.draw(in: titleRect, withAttributes: titleAttrs)
        y += recipe.title.boundingRect(with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                                        options: .usesLineFragmentOrigin, attributes: titleAttrs, context: nil).height + 8
        
        // Summary
        if !recipe.summary.isEmpty {
            let summaryAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 11),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let summaryRect = recipe.summary.boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: summaryAttrs, context: nil
            )
            recipe.summary.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: summaryRect.height),
                               withAttributes: summaryAttrs)
            y += summaryRect.height + 12
        }
        
        // Meta line
        let metaAttrs: [NSAttributedString.Key: Any] = [.font: metaFont, .foregroundColor: UIColor.systemOrange]
        let meta = "Servings: \(recipe.servings) · Prep: \(recipe.prepTime)m · Cook: \(recipe.cookTime)m · \(recipe.difficulty.displayName)"
        meta.draw(at: CGPoint(x: margin, y: y), withAttributes: metaAttrs)
        y += 24
        
        // Orange divider
        let ctx = context.cgContext
        ctx.setStrokeColor(UIColor.systemOrange.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        ctx.strokePath()
        y += 12
        
        // Ingredients
        let sectionAttrs: [NSAttributedString.Key: Any] = [.font: sectionFont, .foregroundColor: UIColor.label]
        let bodyAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: UIColor.label]
        
        "Ingredients".draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
        y += 22
        
        for ingredient in recipe.ingredients {
            if y > pageHeight - margin - 20 {
                context.beginPage()
                y = margin
            }
            let text = "• \(ingredient.displayString)"
            text.draw(at: CGPoint(x: margin + 8, y: y), withAttributes: bodyAttrs)
            y += 16
        }
        
        y += 12
        
        // Instructions
        if y > pageHeight - margin - 60 {
            context.beginPage()
            y = margin
        }
        "Instructions".draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
        y += 22
        
        for step in recipe.steps.sorted(by: { $0.order < $1.order }) {
            if y > pageHeight - margin - 40 {
                context.beginPage()
                y = margin
            }
            
            let stepText = "\(step.order). \(step.instruction)"
            let stepRect = stepText.boundingRect(
                with: CGSize(width: contentWidth - 16, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: bodyAttrs, context: nil
            )
            stepText.draw(in: CGRect(x: margin + 8, y: y, width: contentWidth - 16, height: stepRect.height),
                         withAttributes: bodyAttrs)
            y += stepRect.height + 8
        }
        
        // Notes
        if !recipe.notes.isEmpty {
            y += 8
            if y > pageHeight - margin - 60 {
                context.beginPage()
                y = margin
            }
            "Notes".draw(at: CGPoint(x: margin, y: y), withAttributes: sectionAttrs)
            y += 22
            let noteAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.italicSystemFont(ofSize: 10),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let noteRect = recipe.notes.boundingRect(
                with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                options: .usesLineFragmentOrigin, attributes: noteAttrs, context: nil
            )
            recipe.notes.draw(in: CGRect(x: margin, y: y, width: contentWidth, height: noteRect.height),
                             withAttributes: noteAttrs)
        }
    }
}

// MARK: - Codable Types

private struct ExportWrapper: Codable {
    let version: Int
    let exportDate: Date
    let recipeCount: Int
    let recipes: [ExportableRecipe]
}

/// Lenient counterpart used only for import. `version` is optional (older
/// files may predate it) and each recipe is wrapped so a single corrupt
/// record can't fail the whole decode.
private struct ImportWrapper: Decodable {
    let version: Int?
    let recipes: [FailableDecodable<ExportableRecipe>]
}

/// Decodes to `nil` instead of throwing when the element is malformed.
private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(T.self)
    }
}

enum ImportError: LocalizedError {
    case unsupportedVersion(found: Int, supported: Int)
    case noReadableRecipes

    var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(found, supported):
            return "This backup was made by a newer version of Recipe Vault (format v\(found)). This app understands up to format v\(supported). Update the app, then import again."
        case .noReadableRecipes:
            return "No readable recipes were found in this backup file."
        }
    }
}

private struct ExportableRecipe: Codable {
    var recipeID: UUID?
    let title: String
    let summary: String
    let ingredients: [Ingredient]
    let steps: [RecipeStep]
    let servings: Int
    let prepTime: Int
    let cookTime: Int
    let category: String
    let tags: [String]
    let cuisine: String
    let difficulty: String
    let sourceURL: String?
    let sourceType: String?
    let notes: String
    let rating: Int
    let isFavorite: Bool
    let photoData: [Data]?
    let dateLastCooked: Date?
    let originalPDFData: Data?
    let dateAdded: Date
    let timesCooked: Int
}
