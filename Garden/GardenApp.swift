import SwiftUI

@main
struct GardenApp: App {
    @StateObject private var store = BacklogStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .newItem) {
                // Handled by toolbar button + ⌘N
            }
        }
    }
}
