import SwiftUI

@main
struct GardenApp: App {
    @StateObject private var store = BacklogStore()
    @StateObject private var agent: AgentService

    init() {
        let store = BacklogStore()
        _store = StateObject(wrappedValue: store)
        _agent = StateObject(wrappedValue: AgentService(backlogStore: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(agent)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1000, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Handled by toolbar button + Cmd+N
            }
        }

        Settings {
            SettingsView()
                .environmentObject(agent)
        }
    }
}
