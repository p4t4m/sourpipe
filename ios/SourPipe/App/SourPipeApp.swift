import SwiftUI

@main
struct SourPipeApp: App {
    @StateObject private var store: AppStore
    @StateObject private var player: PlayerController
    @StateObject private var downloads: DownloadManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: PlayerController(store: store))
        _downloads = StateObject(wrappedValue: DownloadManager(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(player)
                .environmentObject(downloads)
                .task { await store.start() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .background {
                player.savePosition()
                store.saveNow()
            }
        }
    }
}
