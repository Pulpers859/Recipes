import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct RecipeVaultApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navigationState = AppNavigationState()
    
    init() {
        AnalyticsService.shared.configureLaunchTracking()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(navigationState)
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    // Handle Spotlight search result taps
                    if let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String {
                        navigationState.handleSpotlightIdentifier(identifier)
                        AnalyticsService.shared.track("spotlight_open_request")
                        #if DEBUG
                        print("Opening recipe from Spotlight: \(identifier)")
                        #endif
                    }
                }
        }
        .modelContainer(AppDataStack.sharedContainer)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AnalyticsService.shared.markSessionActive()
                navigationState.refreshShareInboxCount()
            } else if phase == .background || phase == .inactive {
                AnalyticsService.shared.markCleanExit()
                if phase == .background {
                    // Recovery point for ordinary edits/imports — destructive
                    // actions write their own snapshot before acting.
                    RecipeAutoSnapshotService.snapshotIfChanged(modelContext: AppDataStack.sharedContainer.mainContext)
                }
            }
        }
    }
}
