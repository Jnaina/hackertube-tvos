import SwiftUI

@main
struct HackerTubeApp: App {
    @StateObject private var catalog = Catalog()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(catalog)
                .task { await catalog.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await catalog.refreshIfStale() } }
                }
        }
    }
}
