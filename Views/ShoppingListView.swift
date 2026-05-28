import SwiftUI
import SwiftData

struct ShoppingListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ShoppingItem.name) private var items: [ShoppingItem]
    @Query(sort: \PantryItem.name) private var pantryItems: [PantryItem]
    @Query(sort: \Recipe.title) private var recipes: [Recipe]

    @State private var newItemName = ""
    @State private var showClearConfirm = false
    @State private var showPickedUpItems = false

    private var activeItems: [ShoppingItem] {
        items.filter { !$0.isChecked }
    }

    private var pickedUpItems: [ShoppingItem] {
        items
            .filter { $0.isChecked }
            .sorted { lhs, rhs in
                if lhs.dateAdded == rhs.dateAdded {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.dateAdded > rhs.dateAdded
            }
    }

    private var groupedActiveItems: [(ShoppingCategory, [ShoppingItem])] {
        let grouped = Dictionary(grouping: activeItems) { $0.category }
        return ShoppingCategory.allCases.compactMap { category in
            guard let categoryItems = grouped[category], !categoryItems.isEmpty else { return nil }
            return (category, sortedItems(categoryItems, in: category))
        }
    }

    private var checkedCount: Int { pickedUpItems.count }
    private var totalCount: Int { items.count }
    private var remainingCount: Int { activeItems.count }
    private var generatedCount: Int { activeItems.filter { $0.isGenerated }.count }
    private var pantryAdjustedCount: Int { activeItems.filter { $0.pantryReductionAmount > 0 }.count }

    private var recipeLookup: [UUID: String] {
        Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0.title) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    heroHeader
                    quickAddCard

                    if activeItems.isEmpty && pickedUpItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(groupedActiveItems, id: \.0) { category, categoryItems in
                            categorySection(category, items: categoryItems)
                        }

                        if !pickedUpItems.isEmpty {
                            pickedUpSection
                        }
                    }
                }
                .padding()
                .padding(.bottom, 28)
            }
            .background(Color.rvBackground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.rvBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if !items.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Clear Picked Up", systemImage: "checkmark.circle") {
                                clearChecked()
                            }
                            .disabled(checkedCount == 0)

                            Button("Clear All", systemImage: "trash", role: .destructive) {
                                showClearConfirm = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(Color.rvAccent)
                        }
                    }
                }
            }
            .alert("Clear All Items?", isPresented: $showClearConfirm) {
                Button("Clear All", role: .destructive) { clearAll() }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shopping List")
                .font(.system(.largeTitle, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)

            Text("A cleaner market run: quantity up front, recipe context underneath, pantry-aware totals throughout.")
                .font(.subheadline)
                .foregroundStyle(Color.rvSubtleText)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(checkedCount) of \(totalCount) items picked up")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.rvInk)
                    Spacer()
                    Text(totalCount == 0 ? "Ready to build" : "\(remainingCount) left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.rvSubtleText)
                }

                ProgressView(value: Double(checkedCount), total: Double(max(totalCount, 1)))
                    .tint(Color.rvAccent)
            }

            HStack(spacing: 10) {
                summaryPill(title: "Remaining", value: "\(remainingCount)")
                summaryPill(title: "Picked Up", value: "\(checkedCount)")
                summaryPill(title: "Pantry Adjusted", value: "\(pantryAdjustedCount)")
            }

            if pantryAdjustedCount > 0 || generatedCount > 0 {
                Text(heroSupportLine)
                    .font(.caption)
                    .foregroundStyle(Color.rvSubtleText)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient.rvHeroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
        }
    }

    private var quickAddCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Add")
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)

            Text("Try 2 limes, 1 lb chicken, or 8 oz yogurt.")
                .font(.caption)
                .foregroundStyle(Color.rvSubtleText)

            HStack(spacing: 12) {
                TextField("Add item or quantity...", text: $newItemName)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.rvSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .onSubmit { addItem() }

                Button {
                    addItem()
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(LinearGradient.rvAccentGradient, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "cart")
                .font(.system(size: 44))
                .foregroundStyle(Color.rvAccent.opacity(0.7))

            Text("No Shopping Items")
                .font(.system(.title3, design: .serif, weight: .bold))
                .foregroundStyle(Color.rvInk)

            Text("Generate a list from your meal plan or start adding items here.")
                .font(.subheadline)
                .foregroundStyle(Color.rvSubtleText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .padding(.horizontal, 20)
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var pickedUpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisclosureGroup(isExpanded: $showPickedUpItems) {
                VStack(spacing: 12) {
                    ForEach(pickedUpItems) { item in
                        shoppingItemRow(item)
                    }
                }
                .padding(.top, 10)
            } label: {
                HStack {
                    Label("Picked Up", systemImage: "checkmark.circle.fill")
                        .font(.system(.title3, design: .serif, weight: .bold))
                        .foregroundStyle(Color.rvInk)

                    Spacer()

                    Text("\(pickedUpItems.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.rvSubtleText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.rvSurface, in: Capsule())
                }
            }
        }
        .padding(18)
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
    }

    private func categorySection(_ category: ShoppingCategory, items categoryItems: [ShoppingItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(category.displayName, systemImage: category.icon)
                    .font(.system(.title3, design: .serif, weight: .bold))
                    .foregroundStyle(Color.rvInk)

                Spacer()

                Text("\(categoryItems.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.rvSubtleText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.rvSurface, in: Capsule())
            }

            ForEach(categoryItems) { item in
                shoppingItemRow(item)
            }
        }
    }

    private func shoppingItemRow(_ item: ShoppingItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    item.isChecked.toggle()
                }
            } label: {
                Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.isChecked ? Color.rvPrimary : Color.rvMuted)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            if item.hasQuantity {
                quantityBadge(for: item)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .strikethrough(item.isChecked)
                    .foregroundStyle(item.isChecked ? Color.rvSubtleText : Color.rvInk)
                    .multilineTextAlignment(.leading)

                if let sourceLine = sourceRecipeLine(for: item) {
                    Label(sourceLine, systemImage: "fork.knife")
                        .font(.caption)
                        .foregroundStyle(Color.rvSubtleText)
                }

                if let pantryLine = item.pantryCoverageText {
                    Label(pantryLine, systemImage: "cabinet.fill")
                        .font(.caption)
                        .foregroundStyle(Color.rvSubtleText)
                }
            }

            Spacer(minLength: 10)

            Button {
                stockInPantry(item)
            } label: {
                Label(item.isChecked ? "Pantry" : "Stock", systemImage: "shippingbox.fill")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(item.isChecked ? Color.rvSecondary.opacity(0.35) : Color.rvSurface, in: Capsule())
                    .foregroundStyle(Color.rvInk)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(item.isChecked ? Color.rvSurface.opacity(0.9) : Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
    }

    private func quantityBadge(for item: ShoppingItem) -> some View {
        Text(item.quantityText)
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.rvPrimary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.rvSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.rvSecondary.opacity(0.6), lineWidth: 1)
            }
    }

    private func summaryPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.8)
                .foregroundStyle(Color.rvSubtleText)
            Text(value)
                .font(.headline)
                .foregroundStyle(Color.rvInk)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.rvPaper.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var heroSupportLine: String {
        if pantryAdjustedCount > 0 && generatedCount > 0 {
            return "\(pantryAdjustedCount) items were reduced by pantry stock, and \(generatedCount) are linked back to your meal plan recipes."
        }
        if pantryAdjustedCount > 0 {
            return "\(pantryAdjustedCount) items were reduced because your pantry already covers part of them."
        }
        return "\(generatedCount) items are linked back to recipes in your meal plan."
    }

    private func sortedItems(_ items: [ShoppingItem], in category: ShoppingCategory) -> [ShoppingItem] {
        items.sorted { lhs, rhs in
            let lhsPriority = aislePriority(for: lhs, in: category)
            let rhsPriority = aislePriority(for: rhs, in: category)
            if lhsPriority == rhsPriority {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhsPriority < rhsPriority
        }
    }

    private func aislePriority(for item: ShoppingItem, in category: ShoppingCategory) -> Int {
        let lower = item.name.lowercased()

        switch category {
        case .produce:
            if lower.contains("herb") || lower.contains("cilantro") || lower.contains("parsley") || lower.contains("basil") { return 0 }
            if lower.contains("jalape") || lower.contains("pepper") || lower.contains("onion") || lower.contains("garlic") || lower.contains("ginger") { return 1 }
            if lower.contains("lettuce") || lower.contains("spinach") || lower.contains("kale") { return 2 }
            if lower.contains("tomato") || lower.contains("cucumber") || lower.contains("zucchini") { return 3 }
            if lower.contains("lemon") || lower.contains("lime") || lower.contains("apple") || lower.contains("banana") { return 4 }
            return 5
        case .dairy:
            if lower.contains("milk") || lower.contains("cream") { return 0 }
            if lower.contains("yogurt") || lower.contains("egg") { return 1 }
            if lower.contains("butter") || lower.contains("cheese") { return 2 }
            return 3
        case .meat, .seafood:
            if lower.contains("ground") { return 0 }
            if lower.contains("breast") || lower.contains("thigh") || lower.contains("fillet") { return 1 }
            return 2
        case .bakery:
            if lower.contains("bread") || lower.contains("bun") || lower.contains("roll") { return 0 }
            return 1
        case .pantry:
            if lower.contains("tomato") || lower.contains("broth") || lower.contains("stock") || lower.contains("can") { return 0 }
            if lower.contains("rice") || lower.contains("pasta") || lower.contains("flour") || lower.contains("oat") { return 1 }
            if lower.contains("oil") || lower.contains("vinegar") || lower.contains("sauce") { return 2 }
            if lower.contains("sugar") || lower.contains("honey") || lower.contains("syrup") { return 3 }
            return 4
        case .spices:
            if lower.contains("salt") || lower.contains("pepper") { return 0 }
            if lower.contains("garlic") || lower.contains("onion") || lower.contains("paprika") { return 1 }
            return 2
        case .frozen, .beverages, .other:
            return 0
        }
    }

    private func sourceRecipeLine(for item: ShoppingItem) -> String? {
        let titles = item.sourceRecipeIDs
            .compactMap { recipeLookup[$0] }
            .sorted()

        guard !titles.isEmpty else { return nil }
        if titles.count == 1 {
            return "For \(titles[0])"
        }
        if titles.count == 2 {
            return "For \(titles[0]) and \(titles[1])"
        }
        return "For \(titles[0]), \(titles[1]) +\(titles.count - 2) more"
    }

    private func addItem() {
        let trimmed = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let parsed = parseManualEntry(trimmed)
        let item = ShoppingItem(
            name: parsed.name,
            amount: parsed.amount,
            unit: parsed.unit,
            category: ShoppingListService.suggestedCategory(for: parsed.name)
        )
        modelContext.insert(item)
        AnalyticsService.shared.track("shopping_item_added_manual")
        newItemName = ""
    }

    private func clearChecked() {
        let removed = pickedUpItems.count
        for item in pickedUpItems {
            modelContext.delete(item)
        }
        if removed > 0 {
            AnalyticsService.shared.track("shopping_clear_checked", metadata: ["count": "\(removed)"])
        }
    }

    private func clearAll() {
        let removed = items.count
        for item in items {
            modelContext.delete(item)
        }
        if removed > 0 {
            AnalyticsService.shared.track("shopping_clear_all", metadata: ["count": "\(removed)"])
        }
    }

    private func stockInPantry(_ shoppingItem: ShoppingItem) {
        let normalizedKey = ShoppingListService.normalizedIngredientKey(shoppingItem.name)
        if let pantryMatch = pantryItems.first(where: {
            ShoppingListService.normalizedIngredientKey($0.name) == normalizedKey
        }) {
            let incomingAmount = shoppingItem.amount > 0 ? shoppingItem.amount : 1
            pantryMatch.amount += incomingAmount
            if pantryMatch.unit.isEmpty {
                pantryMatch.unit = shoppingItem.unit
            }
            pantryMatch.category = shoppingItem.category
            pantryMatch.dateUpdated = Date()
        } else {
            let pantryItem = PantryItem(
                name: shoppingItem.name,
                amount: shoppingItem.amount > 0 ? shoppingItem.amount : 1,
                unit: shoppingItem.unit,
                category: shoppingItem.category
            )
            modelContext.insert(pantryItem)
        }

        modelContext.delete(shoppingItem)
        AnalyticsService.shared.track("shopping_item_stocked_to_pantry")
    }

    private func parseManualEntry(_ text: String) -> (name: String, amount: Double, unit: String) {
        let tokens = text
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)

        guard !tokens.isEmpty else {
            return (text, 0, "")
        }

        var consumedTokens = 0
        var amount = 0.0

        if tokens.count >= 2,
           let wholeAmount = Double(tokens[0]),
           let fractionAmount = parseFraction(tokens[1]) {
            amount = wholeAmount + fractionAmount
            consumedTokens = 2
        } else if let parsedAmount = parseAmountToken(tokens[0]) {
            amount = parsedAmount
            consumedTokens = 1
        } else {
            return (text, 0, "")
        }

        guard consumedTokens < tokens.count else {
            return (text, 0, "")
        }

        var unit = ""
        if let parsedUnit = ShoppingListService.parsedUnit(from: tokens[consumedTokens]) {
            unit = parsedUnit
            consumedTokens += 1
        }

        guard consumedTokens < tokens.count else {
            return (text, 0, "")
        }

        let name = tokens[consumedTokens...].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return (text, 0, "")
        }

        return (name, amount, unit)
    }

    private func parseAmountToken(_ token: String) -> Double? {
        if let direct = Double(token) {
            return direct
        }
        return parseFraction(token)
    }

    private func parseFraction(_ token: String) -> Double? {
        let pieces = token.split(separator: "/")
        guard pieces.count == 2,
              let numerator = Double(pieces[0]),
              let denominator = Double(pieces[1]),
              denominator != 0 else {
            return nil
        }
        return numerator / denominator
    }
}
