import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var parser: RecipeParserService
    
    @State private var selectedTab: ImportTab = .pdf
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var importedRecipe: Recipe?
    @State private var showEditor = false
    @State private var showFilePicker = false
    @State private var urlText = ""
    @StateObject private var scraper = URLRecipeScraperService()
    @State private var showImportSummary = false
    @State private var importedCount = 0
    @AppStorage("parse_mode") private var parseModeSetting = "auto"
    
    private let maxPDFImportBytes = 25 * 1024 * 1024
    private let maxPhotoImportBytes = 15 * 1024 * 1024
    
    enum ImportTab: String, CaseIterable {
        case pdf = "PDF"
        case photo = "Photo"
        case url = "URL"
        
        var icon: String {
            switch self {
            case .pdf: return "doc.fill"
            case .photo: return "camera.fill"
            case .url: return "link"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Tab picker
                Picker("Import Method", selection: $selectedTab) {
                    ForEach(ImportTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Content
                switch selectedTab {
                case .pdf:
                    pdfImportView
                case .photo:
                    photoImportView
                case .url:
                    urlImportView
                }
                
                // Progress indicator
                if parser.isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(parser.parseProgress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                
                if let error = parser.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Parse mode toggle
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: parser.hasAPIKey ? "brain.fill" : "brain")
                            .foregroundStyle(parser.hasAPIKey ? .green : .gray)
                        Text(parser.hasAPIKey ? "AI Parsing Enabled" : "AI Parsing Unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !parser.hasAPIKey {
                        Text("Add your Claude API key in Settings for smart recipe extraction")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            }
            .navigationTitle("Import Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showFilePicker) {
                PDFImportDocumentPicker { pickedURL in
                    showFilePicker = false
                    handlePickedPDF(url: pickedURL)
                } onCancel: {
                    showFilePicker = false
                }
            }
            .sheet(isPresented: $showEditor) {
                if let recipe = importedRecipe {
                    NavigationStack {
                        RecipeEditorView(recipe: recipe, isNewImport: true)
                    }
                }
            }
            .alert("Import Complete", isPresented: $showImportSummary) {
                Button("OK") { dismiss() }
            } message: {
                Text("Successfully imported \(importedCount) recipes from this PDF. You can review and edit each one from the Recipes tab.")
            }
        }
    }
    
    // MARK: - PDF Import
    
    private var pdfImportView: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .foregroundStyle(Color.rvAccent.opacity(0.5))
                    .frame(height: 200)
                
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.arrow.up.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.rvAccent)
                    
                    Text("Tap to select a PDF")
                        .font(.headline)
                    
                    Text("Recipe will be extracted automatically")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onTapGesture { showFilePicker = true }
            .padding(.horizontal)
        }
    }
    
    // MARK: - Photo Import
    
    private var photoImportView: some View {
        VStack(spacing: 16) {
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images
            ) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                        .foregroundStyle(Color.rvAccent.opacity(0.5))
                        .frame(height: 200)
                    
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.rvAccent)
                        
                        Text("Select a Photo")
                            .font(.headline)
                        
                        Text("Recipe card, screenshot, or cookbook page")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .onChange(of: selectedPhotoItem) { _, newItem in
                handlePhotoSelection(newItem)
            }
        }
    }
    
    // MARK: - URL Import
    
    private var urlImportView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recipe URL")
                    .font(.headline)
                
                HStack {
                    TextField("https://example.com/recipe", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                    
                    Button("Import") {
                        Task {
                            scraper.lastError = nil
                            do {
                                let recipe = try await scraper.scrapeRecipe(
                                    from: urlText,
                                    allowAI: parseModeSetting != "manual"
                                )
                                modelContext.insert(recipe)
                                AnalyticsService.shared.track("import_url_success", metadata: [
                                    "mode": parseModeSetting
                                ])
                                importedRecipe = recipe
                                showEditor = true
                                urlText = ""
                            } catch {
                                scraper.lastError = error.localizedDescription
                                AnalyticsService.shared.track("import_url_failed")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.rvAccent)
                    .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || scraper.isLoading)
                }
            }
            .padding(.horizontal)
            
            if scraper.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(scraper.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let error = scraper.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
            
            Text("Paste a link to any recipe page. Works best with sites that use structured recipe data (JSON-LD). Falls back to AI extraction if available.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Handlers
    
    private func handlePickedPDF(url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            parser.lastError = "Permission denied: unable to access the selected file."
            return
        }

        // Read data synchronously while we still have security scope access
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            url.stopAccessingSecurityScopedResource()
            parser.lastError = "Could not read file: \(error.localizedDescription)"
            return
        }
        url.stopAccessingSecurityScopedResource()

        guard data.count <= maxPDFImportBytes else {
            parser.lastError = "PDF is too large. Please choose a file under 25 MB."
            return
        }

        // Parse — may return 1 or many recipes
        Task {
            do {
                let mode = parseMode()
                let recipes = try await parser.parseRecipes(from: data, mode: mode)
                await MainActor.run {
                    for recipe in recipes {
                        modelContext.insert(recipe)
                    }
                    AnalyticsService.shared.track("import_pdf_success", metadata: [
                        "count": "\(recipes.count)",
                        "mode": parseModeSetting
                    ])

                    if recipes.count == 1 {
                        // Single recipe — open editor for review
                        importedRecipe = recipes.first
                        showEditor = true
                    } else {
                        // Multiple recipes — show summary
                        importedCount = recipes.count
                        showImportSummary = true
                    }
                }
            } catch {
                await MainActor.run {
                    parser.lastError = error.localizedDescription
                    AnalyticsService.shared.track("import_pdf_failed")
                }
            }
        }
    }
    
    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item else { return }
        
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { return }
                guard data.count <= maxPhotoImportBytes else {
                    await MainActor.run {
                        parser.lastError = "Image is too large. Please choose a file under 15 MB."
                    }
                    return
                }
                let recipe = try await parser.parseRecipeFromImage(data, mode: parseMode())
                await MainActor.run {
                    modelContext.insert(recipe)
                    AnalyticsService.shared.track("import_photo_success", metadata: [
                        "mode": parseModeSetting
                    ])
                    importedRecipe = recipe
                    showEditor = true
                }
            } catch {
                await MainActor.run {
                    parser.lastError = error.localizedDescription
                    AnalyticsService.shared.track("import_photo_failed")
                }
            }
        }
    }
    
    private func parseMode() -> RecipeParserService.ParseMode {
        switch parseModeSetting {
        case "ai":
            return .ai
        case "manual":
            return .manual
        default:
            return .auto
        }
    }
}

struct PDFImportDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.pdf], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: (URL) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping (URL) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let firstURL = urls.first else {
                onCancel()
                return
            }
            onPick(firstURL)
        }
    }
}
