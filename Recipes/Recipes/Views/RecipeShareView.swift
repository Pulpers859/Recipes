import SwiftUI

// MARK: - Recipe Share View

/// Generates a shareable formatted recipe card
struct RecipeShareView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    shareCard
                        .padding()
                }
            }
            .background(Color.rvBackground)
            .navigationTitle("Share Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.rvBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [formattedRecipeText])
            }
        }
    }
    
    // MARK: - Visual Card Preview
    
    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.system(.title2, design: .serif, weight: .bold))
                    .foregroundStyle(Color.rvInk)

                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.rvSubtleText)
                }

                HStack(spacing: 16) {
                    Label("\(recipe.servings) servings", systemImage: "person.2")
                    Label("\(recipe.totalTime) min", systemImage: "clock")
                    Label(recipe.difficulty.displayName, systemImage: "speedometer")
                }
                .font(.caption)
                .foregroundStyle(Color.rvSubtleText)
                .padding(.top, 4)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Ingredients")
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Color.rvInk)

                ForEach(recipe.normalizedIngredients) { ingredient in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .foregroundStyle(Color.rvAccent)
                        Text(ingredient.displayString)
                            .font(.subheadline)
                            .foregroundStyle(Color.rvInk)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions")
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(Color.rvInk)

                ForEach(Array(recipe.steps.sorted { $0.order < $1.order }.enumerated()), id: \.element.id) { idx, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(.subheadline.bold())
                            .foregroundStyle(Color.rvAccent)
                            .frame(width: 20, alignment: .trailing)
                        Text(step.instruction)
                            .font(.subheadline)
                            .foregroundStyle(Color.rvInk)
                    }
                }
            }

            if !recipe.notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Color.rvInk)
                    Text(recipe.notes)
                        .font(.subheadline)
                        .foregroundStyle(Color.rvSubtleText)
                }
            }

            HStack {
                Spacer()
                Text("Shared from Recipe Vault")
                    .font(.caption2)
                    .foregroundStyle(Color.rvMuted)
            }
            .padding(.top, 8)
        }
        .padding(RVDesign.cardPadding)
        .background(Color.rvPaper)
        .clipShape(RoundedRectangle(cornerRadius: RVDesign.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }
    
    // MARK: - Formatted Text
    
    private var formattedRecipeText: String {
        var text = """
        🍽️ \(recipe.title)
        
        """
        
        if !recipe.summary.isEmpty {
            text += "\(recipe.summary)\n\n"
        }
        
        text += "⏱ \(recipe.totalTime) min · 👥 \(recipe.servings) servings · \(recipe.difficulty.displayName)\n\n"
        
        text += "📋 INGREDIENTS\n"
        for ingredient in recipe.normalizedIngredients {
            text += "• \(ingredient.displayString)\n"
        }
        
        text += "\n👨‍🍳 INSTRUCTIONS\n"
        // Number sequentially (1,2,3…) like the on-screen card, rather than
        // echoing raw `order` values which can be non-contiguous after edits.
        for (idx, step) in recipe.steps.sorted(by: { $0.order < $1.order }).enumerated() {
            text += "\(idx + 1). \(step.instruction)\n"
        }
        
        if !recipe.notes.isEmpty {
            text += "\n📝 NOTES\n\(recipe.notes)\n"
        }
        
        text += "\n— Shared from Recipe Vault"
        
        return text
    }
}
