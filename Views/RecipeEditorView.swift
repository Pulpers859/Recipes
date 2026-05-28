import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct RecipeEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var recipe: Recipe
    let isNewImport: Bool
    
    // Local editing state
    @State private var title: String
    @State private var summary: String
    @State private var servings: Int
    @State private var prepTime: Int
    @State private var cookTime: Int
    @State private var category: RecipeCategory
    @State private var cuisine: String
    @State private var difficulty: Difficulty
    @State private var tagText: String
    @State private var notes: String
    @State private var ingredients: [Ingredient]
    @State private var steps: [RecipeStep]
    @State private var photoData: [Data]
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showPhotoViewer = false
    @State private var selectedPhotoIndex = 0
    
    @State private var newIngredientName = ""
    @State private var newIngredientAmount = ""
    @State private var newIngredientUnit = ""
    
    init(recipe: Recipe?, isNewImport: Bool = false) {
        let r = recipe ?? Recipe()
        self.recipe = r
        self.isNewImport = isNewImport
        
        _title = State(initialValue: r.title)
        _summary = State(initialValue: r.summary)
        _servings = State(initialValue: r.servings)
        _prepTime = State(initialValue: r.prepTime)
        _cookTime = State(initialValue: r.cookTime)
        _category = State(initialValue: r.category)
        _cuisine = State(initialValue: r.cuisine)
        _difficulty = State(initialValue: r.difficulty)
        _tagText = State(initialValue: r.tags.joined(separator: ", "))
        _notes = State(initialValue: r.notes)
        _ingredients = State(initialValue: r.ingredients)
        _steps = State(initialValue: r.steps.sorted { $0.order < $1.order })
        _photoData = State(initialValue: r.photoData)
    }
    
    var body: some View {
        Form {
            // MARK: - Basic Info
            Section("Basic Info") {
                TextField("Recipe Title", text: $title)
                    .font(.headline)
                
                TextField("Brief description", text: $summary, axis: .vertical)
                    .lineLimit(2...4)
                
                Picker("Category", selection: $category) {
                    ForEach(RecipeCategory.allCases) { cat in
                        Label(cat.displayName, systemImage: cat.icon).tag(cat)
                    }
                }
                
                TextField("Cuisine (e.g. Italian, Mexican)", text: $cuisine)
                
                Picker("Difficulty", selection: $difficulty) {
                    ForEach(Difficulty.allCases, id: \.self) { d in
                        Text(d.displayName).tag(d)
                    }
                }
                
                TextField("Tags (comma separated)", text: $tagText)
                    .textInputAutocapitalization(.never)
            }
            
            // MARK: - Photos
            Section("Photos") {
                if photoData.isEmpty {
                    Label("No photos yet", systemImage: "photo")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap a photo to view full size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(photoData.enumerated()), id: \.offset) { index, data in
                                photoThumbnail(data: data, index: index)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                PhotosPicker(
                    selection: $selectedPhotoItems,
                    maxSelectionCount: 12,
                    matching: .images
                ) {
                    Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                        .foregroundStyle(Color.rvAccent)
                }
                .onChange(of: selectedPhotoItems) { _, newItems in
                    Task {
                        await loadSelectedPhotos(newItems)
                        await MainActor.run {
                            selectedPhotoItems = []
                        }
                    }
                }
            }
            
            // MARK: - Timing
            Section("Timing & Servings") {
                Stepper("Servings: \(servings)", value: $servings, in: 1...100)
                
                HStack {
                    Text("Prep")
                    Spacer()
                    TextField("min", value: $prepTime, format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("min")
                        .foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Cook")
                    Spacer()
                    TextField("min", value: $cookTime, format: .number)
                        .keyboardType(.numberPad)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                    Text("min")
                        .foregroundStyle(.secondary)
                }
            }
            
            // MARK: - Ingredients
            Section("Ingredients") {
                ForEach($ingredients) { $ingredient in
                    HStack {
                        TextField("Amount", text: Binding(
                            get: { ingredient.amount > 0 ? String(ingredient.amount) : "" },
                            set: { ingredient.amount = Double($0) ?? 0 }
                        ))
                        .frame(width: 50)
                        .keyboardType(.decimalPad)
                        
                        TextField("Unit", text: $ingredient.unit)
                            .frame(width: 50)
                        
                        TextField("Ingredient name", text: $ingredient.name)
                    }
                    .font(.body)
                }
                .onDelete { indexSet in
                    ingredients.remove(atOffsets: indexSet)
                }
                .onMove { from, to in
                    ingredients.move(fromOffsets: from, toOffset: to)
                }
                
                // Quick add
                HStack {
                    TextField("Amt", text: $newIngredientAmount)
                        .frame(width: 50)
                        .keyboardType(.decimalPad)
                    TextField("Unit", text: $newIngredientUnit)
                        .frame(width: 50)
                    TextField("New ingredient", text: $newIngredientName)
                    
                    Button {
                        guard !newIngredientName.isEmpty else { return }
                        let ing = Ingredient(
                            name: newIngredientName,
                            amount: Double(newIngredientAmount) ?? 0,
                            unit: newIngredientUnit
                        )
                        ingredients.append(ing)
                        newIngredientName = ""
                        newIngredientAmount = ""
                        newIngredientUnit = ""
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.rvAccent)
                    }
                    .disabled(newIngredientName.isEmpty)
                }
                .font(.body)
            }
            
            // MARK: - Steps
            Section("Instructions") {
                ForEach($steps) { $step in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Step \(step.order)")
                                .font(.caption.bold())
                                .foregroundStyle(Color.rvAccent)
                            Spacer()
                            if let secs = step.timerSeconds {
                                Label("\(secs / 60)m", systemImage: "timer")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        TextField("Instruction", text: $step.instruction, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
                .onDelete { indexSet in
                    steps.remove(atOffsets: indexSet)
                    reorderSteps()
                }
                .onMove { from, to in
                    steps.move(fromOffsets: from, toOffset: to)
                    reorderSteps()
                }
                
                Button {
                    let newStep = RecipeStep(order: steps.count + 1, instruction: "")
                    steps.append(newStep)
                } label: {
                    Label("Add Step", systemImage: "plus.circle.fill")
                        .foregroundStyle(Color.rvAccent)
                }
            }
            
            // MARK: - Notes
            Section("Notes") {
                TextField("Personal notes, tips, variations...", text: $notes, axis: .vertical)
                    .lineLimit(3...10)
            }
        }
        .navigationTitle(isNewImport ? "Review Import" : (recipe.title.isEmpty ? "New Recipe" : "Edit Recipe"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveRecipe() }
                    .bold()
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            Group {
                if photoData.isEmpty {
                    Color.black.ignoresSafeArea()
                } else {
                    RecipePhotoViewer(photoData: photoData, selectedIndex: $selectedPhotoIndex)
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func saveRecipe() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedTags = tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let cleanedIngredients = Ingredient.normalizedList(
            ingredients
                .map { ingredient in
                    Ingredient(
                        name: ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines),
                        amount: ingredient.amount,
                        unit: ingredient.unit.trimmingCharacters(in: .whitespacesAndNewlines),
                        section: ingredient.section.trimmingCharacters(in: .whitespacesAndNewlines),
                        isOptional: ingredient.isOptional
                    )
                }
                .filter { !$0.name.isEmpty }
        )
        
        let cleanedSteps = steps
            .compactMap { step -> RecipeStep? in
                let instruction = step.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !instruction.isEmpty else { return nil }
                return RecipeStep(
                    order: 0,
                    instruction: instruction,
                    timerSeconds: step.timerSeconds,
                    timerLabel: step.timerLabel
                )
            }
            .enumerated()
            .map { index, step in
                RecipeStep(
                    order: index + 1,
                    instruction: step.instruction,
                    timerSeconds: step.timerSeconds,
                    timerLabel: step.timerLabel
                )
            }
        
        recipe.title = trimmedTitle
        recipe.summary = summary
        recipe.servings = max(servings, 1)
        recipe.prepTime = max(prepTime, 0)
        recipe.cookTime = max(cookTime, 0)
        recipe.category = category
        recipe.cuisine = cuisine.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.difficulty = difficulty
        recipe.tags = cleanedTags
        recipe.notes = notes
        recipe.ingredients = cleanedIngredients
        recipe.steps = cleanedSteps
        recipe.photoData = photoData
        
        // Insert if new
        let isNewRecipe = recipe.modelContext == nil
        if isNewRecipe {
            modelContext.insert(recipe)
        }
        
        AnalyticsService.shared.track("recipe_saved", metadata: [
            "mode": isNewRecipe ? (isNewImport ? "import_new" : "manual_new") : "edit_existing",
            "ingredient_count": "\(recipe.ingredients.count)",
            "step_count": "\(recipe.steps.count)"
        ])
        
        dismiss()
    }
    
    private func reorderSteps() {
        for i in steps.indices {
            steps[i].order = i + 1
        }
    }
    
    @ViewBuilder
    private func photoThumbnail(data: Data, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                selectedPhotoIndex = index
                showPhotoViewer = true
            } label: {
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.systemGray5))
                        .frame(width: 96, height: 96)
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .buttonStyle(.plain)
            
            Button(role: .destructive) {
                removePhoto(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .offset(x: 6, y: -6)
        }
    }
    
    @MainActor
    private func loadSelectedPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let rawData = try await item.loadTransferable(type: Data.self),
                      let normalized = normalizedPhotoData(from: rawData) else {
                    continue
                }
                
                // Avoid duplicate images when a user re-selects the same photo.
                if !photoData.contains(normalized) {
                    photoData.append(normalized)
                }
            } catch {
                continue
            }
        }
    }
    
    private func normalizedPhotoData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return data }
        
        let maxDimension: CGFloat = 2000
        let largestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / max(largestSide, 1))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        
        return resized.jpegData(compressionQuality: 0.85) ?? data
    }
    
    private func removePhoto(at index: Int) {
        guard photoData.indices.contains(index) else { return }
        photoData.remove(at: index)
        
        if selectedPhotoIndex >= photoData.count {
            selectedPhotoIndex = max(photoData.count - 1, 0)
        }
        
        if photoData.isEmpty {
            showPhotoViewer = false
        }
    }
}
