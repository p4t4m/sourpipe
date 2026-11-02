import SwiftUI

@main
struct SourPipeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: AppStore
    @StateObject private var player: PlayerController
    @StateObject private var downloads: DownloadManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Thumbnails load through the shared cache, which is tiny by default, so scrolling back
        // fetched and decoded them again.
        URLCache.shared = URLCache(memoryCapacity: 64 << 20, diskCapacity: 256 << 20)
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        _player = StateObject(wrappedValue: PlayerController(store: store))
        _downloads = StateObject(wrappedValue: DownloadManager(store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView(player: player, downloads: downloads)
                .environmentObject(store)
                .environmentObject(player)
                .environmentObject(downloads)
                .environment(\.controllers, Controllers(player: player, downloads: downloads))
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
