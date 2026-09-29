import SwiftUI

@main
struct TapeDelayApp: App {
    @UIApplicationDelegateAdaptor(Push.self) private var push
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    enum TabId: Hashable { case scores, standings, teams, settings }

    @Environment(AppModel.self) private var model
    @State private var tab: TabId = .scores
    @AppStorage("askedPush") private var askedPush = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Scores", systemImage: "sportscourt.fill", value: .scores) { ScoresView(tab: $tab) }
            Tab("Standings", systemImage: "list.number", value: .standings) { StandingsView() }
            Tab("Teams", systemImage: "star.fill", value: .teams) { TeamsView() }
            Tab("Settings", systemImage: "timer", value: .settings) { SettingsView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Ask for notifications the first time a team is followed, not on a cold first launch.
        .onChange(of: model.follows.count) { _, n in
            guard n > 0, !askedPush else { return }
            askedPush = true
            Task { _ = await Push.shared?.requestPermission() }
        }
    }
}
