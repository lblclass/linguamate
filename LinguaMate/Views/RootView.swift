import SwiftUI

/// Three tabs: practise, history, settings.
struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("练习", systemImage: "bubble.left.and.bubble.right.fill") }

            HistoryView()
                .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}