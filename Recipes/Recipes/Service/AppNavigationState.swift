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

    /// Pending share-extension inbox items; drives the Recipes-tab banner.
    @Published var shareInboxCount: Int = 0

    func refreshShareInboxCount() {
        shareInboxCount = ShareInboxService.itemCount()
    }
}
