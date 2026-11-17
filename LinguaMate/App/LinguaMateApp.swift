import SwiftUI

@main
struct LinguaMateApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(Theme.accent)
        }
    }
}