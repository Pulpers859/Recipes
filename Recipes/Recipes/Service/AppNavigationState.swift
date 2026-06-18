import Foundation
import Combine

@MainActor
final class AppNavigationState: ObservableObject {
    @Published var spotlightRecipeID: UUID?
    
    func handleSpotlightIdentifier(_ identifier: String) {
        spotlightRecipeID = UUID(uuidString: identifier)
    }
    
    func clearSpotlightRequest() {
        spotlightRecipeID = nil
    }
}
