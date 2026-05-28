import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject private var navigationState: AppNavigationState
    
    @State private var selectedTab: Tab = .recipes
    
    enum Tab: String, CaseIterable {
        case recipes, mealPlan, pantry, shopping, settings
        
        var title: String {
            switch self {
            case .recipes: return "Recipes"
            case .mealPlan: return "Meal Plan"
            case .pantry: return "Pantry"
            case .shopping: return "Shopping"
            case .settings: return "Settings"
            }
        }
        
        var icon: String {
            switch self {
            case .recipes: return "book.fill"
            case .mealPlan: return "calendar"
            case .pantry: return "archivebox.fill"
            case .shopping: return "cart.fill"
            case .settings: return "gearshape.fill"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            RecipeListView()
                .tabItem {
                    Label(Tab.recipes.title, systemImage: Tab.recipes.icon)
                }
                .tag(Tab.recipes)
            
            MealPlanView {
                selectedTab = .shopping
            }
                .tabItem {
                    Label(Tab.mealPlan.title, systemImage: Tab.mealPlan.icon)
                }
                .tag(Tab.mealPlan)
            
            PantryView()
                .tabItem {
                    Label(Tab.pantry.title, systemImage: Tab.pantry.icon)
                }
                .tag(Tab.pantry)
            
            ShoppingListView()
                .tabItem {
                    Label(Tab.shopping.title, systemImage: Tab.shopping.icon)
                }
                .tag(Tab.shopping)
            
            SettingsView()
                .tabItem {
                    Label(Tab.settings.title, systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
        .tint(Color.rvAccent)
        .toolbarBackground(Color.rvBackground, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .onChange(of: navigationState.spotlightRecipeID) { _, recipeID in
            if recipeID != nil {
                selectedTab = .recipes
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppNavigationState())
        .modelContainer(for: [Recipe.self, MealPlan.self, PantryItem.self, ShoppingItem.self], inMemory: true)
}
