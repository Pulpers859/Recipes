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
    /// Zero until the extension target ships (the App Group container doesn't
    /// exist yet, so the inbox reads as empty).
    @Published var shareInboxCount: Int = 0

    func refreshShareInboxCount() {
        shareInboxCount = ShareInboxService.itemCount()
    }
}
