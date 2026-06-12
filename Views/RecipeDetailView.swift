import SwiftUI
import SwiftData
import UIKit

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var recipe: Recipe

    @State private var targetServings: Int
    @State private var showCookingMode = false
    @State private var showEditor = false
    @State private var showDeleteConfirmation = false
    @State private var showShareRecipe = false
    @State private var selectedPhotoIndex = 0
    @State private var showPhotoViewer = false

    init(recipe: Recipe) {
        self.recipe = recipe
        self._targetServings = State(initialValue: recipe.servings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                photoSection
                headlineCard
                metadataCard
                servingScalerCard
                ingredientsCard
                stepsCard
                notesCard
            }
            .padding()
            .padding(.bottom, 32)
        }
        .background(Color.rvBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.rvBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        // Keep the scaler in sync when the recipe's base servings are edited.
        .onChange(of: recipe.servings) { _, newValue in
            targetServings = newValue
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    recipe.isFavorite.toggle()
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(recipe.isFavorite ? .red : Color.rvSubtleText)
                }

                Button {
                    showCookingMode = true
                } label: {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Color.rvAccent)
                }

                Menu {
                    Button("Edit Recipe", systemImage: "pencil") {
                        showEditor = true
                    }
                    Button("Share Recipe", systemImage: "square.and.arrow.up") {
                        showShareRecipe = true
                    }
                    Button("Mark as Cooked", systemImage: "checkmark.circle") {
                        recipe.timesCooked += 1
                        recipe.dateLastCooked = Date()
                    }

                    Divider()

                    Button("Delete Recipe", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Color.rvSubtleText)
                }
            }
        }
        .fullScreenCover(isPresented: $showCookingMode) {
            CookingModeView(recipe: recipe, servings: targetServings)
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            RecipePhotoViewer(photoData: recipe.photoData, selectedIndex: $selectedPhotoIndex)
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                RecipeEditorView(recipe: recipe)
            }
        }
        .alert("Delete Recipe?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                SpotlightIndexingService.shared.removeRecipe(recipe)
                modelContext.delete(recipe)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }
        .sheet(isPresented: $showShareRecipe) {
            RecipeShareView(recipe: recipe)
        }
    }

    // MARK: - Photos

    @ViewBuilder
    private var photoSection: some View {
        if !recipe.photoData.isEmpty {
            TabView(selection: $selectedPhotoIndex) {
                ForEach(Array(recipe.photoData.enumerated()), id: \.offset) { index, data in
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 280)
                            .clipped()
                            .tag(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPhotoIndex = index
                                showPhotoViewer = true
                            }
                    } else {
                        ZStack {
                            Color.rvSurface
                            Image(systemName: "photo")
                                .font(.title)
                                .foregroundStyle(Color.rvSubtleText)
                        }
                        .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 280)
                        .tag(index)
                    }
                }
            }
            .frame(height: 280)
            .tabViewStyle(.page(indexDisplayMode: recipe.photoData.count > 1 ? .automatic : .never))
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Label("Tap to enlarge", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.45), in: Capsule())
                    .padding(14)
            }
            .overlay(alignment: .bottomTrailing) {
                if recipe.photoData.count > 1 {
                    Text("\(selectedPhotoIndex + 1)/\(recipe.photoData.count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(14)
                }
            }
            .shadow(color: .black.opacity(0.08), radius: 18, y: 10)
        }
    }

    // MARK: - Cards

    private var headlineCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(recipe.title)
                    .font(.system(.largeTitle, design: .serif, weight: .bold))
                    .foregroundStyle(Color.rvInk)

                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.body)
                        .foregroundStyle(Color.rvSubtleText)
                }

                if !recipe.tags.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(recipe.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.rvSurface, in: Capsule())
                                .foregroundStyle(Color.rvInk)
                        }
                    }
                }
            }
        }
    }

    private var metadataCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("At a Glance")

                HStack(spacing: 10) {
                    metadataPill(icon: "clock", title: "Prep", value: "\(recipe.prepTime) min")
                    metadataPill(icon: "flame.fill", title: "Cook", value: "\(recipe.cookTime) min")
                }

                HStack(spacing: 10) {
                    metadataPill(icon: "speedometer", title: "Level", value: recipe.difficulty.displayName)

                    if recipe.timesCooked > 0 {
                        metadataPill(icon: "checkmark.circle", title: "Cooked", value: "\(recipe.timesCooked)x")
                    } else if recipe.rating > 0 {
                        metadataPill(icon: "star.fill", title: "Rating", value: "\(recipe.rating)/5")
                    }
                }
            }
        }
    }

    private var servingScalerCard: some View {
        surfaceCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Servings")
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(Color.rvInk)
                    Text("Scale ingredients without changing the original recipe.")
                        .font(.subheadline)
                        .foregroundStyle(Color.rvSubtleText)
                }

                Spacer()

                HStack(spacing: 14) {
                    Button {
                        if targetServings > 1 { targetServings -= 1 }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(targetServings > 1 ? Color.rvAccent : Color.rvMuted)
                    }
                    .disabled(targetServings <= 1)

                    Text("\(targetServings)")
                        .font(.title2.bold().monospacedDigit())
                        .foregroundStyle(Color.rvInk)
                        .frame(minWidth: 34)

                    Button {
                        targetServings += 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.rvAccent)
                    }
                }

                if targetServings != recipe.servings {
                    Button("Reset") {
                        targetServings = recipe.servings
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.rvAccent)
                }
            }
        }
    }

    private var ingredientsCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Ingredients")

                let scaled = recipe.scaledIngredients(for: targetServings)
                let sections = Dictionary(grouping: scaled) { $0.section }
                let sortedKeys = sections.keys.sorted { a, b in
                    if a.isEmpty { return false }
                    if b.isEmpty { return true }
                    return a < b
                }

                ForEach(sortedKeys, id: \.self) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        if !section.isEmpty {
                            ingredientSectionHeader(section)
                                .padding(.top, 6)
                        }

                        ForEach(sections[section] ?? []) { ingredient in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(Color.rvPrimary.opacity(0.35))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 6)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ingredient.displayString)
                                        .font(.body)
                                        .foregroundStyle(Color.rvInk)

                                    if ingredient.isOptional {
                                        Text("Optional")
                                            .font(.caption)
                                            .foregroundStyle(Color.rvSubtleText)
                                            .italic()
                                    }
                                }

                                Spacer()
                            }
                        }
                    }
                }
            }
        }
    }

    private var stepsCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle("Instructions")

                ForEach(Array(recipe.steps.sorted(by: { $0.order < $1.order }).enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(LinearGradient.rvAccentGradient, in: Circle())

                        VStack(alignment: .leading, spacing: 6) {
                            Text(step.instruction)
                                .font(.body)
                                .foregroundStyle(Color.rvInk)

                            if let timerStr = step.timerFormatted {
                                Label(timerStr, systemImage: "timer")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.rvSurface, in: Capsule())
                                    .foregroundStyle(Color.rvInk)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notesCard: some View {
        surfaceCard {
            VStack(alignment: .leading, spacing: 14) {
                if !recipe.notes.isEmpty {
                    sectionTitle("Notes")
                    Text(recipe.notes)
                        .font(.body)
                        .foregroundStyle(Color.rvSubtleText)
                }

                if !recipe.notes.isEmpty {
                    Divider()
                }

                Text("Rating")
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(Color.rvInk)

                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= recipe.rating ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundStyle(star <= recipe.rating ? Color.rvAccent : Color.rvMuted.opacity(0.55))
                            .onTapGesture {
                                recipe.rating = star == recipe.rating ? 0 : star
                            }
                    }
                }
            }
        }
    }

    private func surfaceCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rvPaper)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 16, y: 8)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .serif, weight: .bold))
            .foregroundStyle(Color.rvInk)
    }
    
    private func ingredientSectionHeader(_ title: String) -> some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(LinearGradient.rvAccentGradient)
                .frame(width: 30, height: 6)
            
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Color.rvPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.rvSurface.opacity(0.95), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.rvSecondary.opacity(0.65), lineWidth: 1)
        }
    }

    private func metadataPill(icon: String, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.rvSubtleText)
            Text(value)
                .font(.headline)
                .foregroundStyle(Color.rvInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rvSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Flow Layout (for tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (positions, CGSize(width: maxWidth, height: y + rowHeight))
    }
}
