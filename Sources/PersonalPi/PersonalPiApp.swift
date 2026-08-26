import SwiftUI

@main
struct PersonalPiApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1240, height: 800)
    }
}
