import SwiftUI
import UIKit

/// One per navigation stack, so menus can open pages and sheets where the user is.
@MainActor
final class Router: ObservableObject {
    @Published var path = NavigationPath()
    @Published var downloadItem: InfoItem?

    func open(_ route: Route) {
        path.append(route)
    }
}

/// A navigation stack with the app's routes and its own router.
struct RoutedStack<Content: View>: View {
    @StateObject private var router = Router()
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack(path: $router.path) {
            content().withRoutes()
        }
        .environmentObject(router)
        .sheet(item: $router.downloadItem) { item in
            DownloadSheet(item: item)
        }
    }
}

/// A video's long-press menu: NewPipe's entries, in the order and selection set in Settings.
struct StreamItemMenu: View {
    let item: InfoItem
    @EnvironmentObject private var store: AppStore
    @Environment(\.controllers) private var controllers
    @EnvironmentObject private var router: Router

    private var player: PlayerController? { controllers?.player }
    @Environment(\.openURL) private var openURL

    var body: some View {
        ForEach(store.library.settings.streamMenu.filter(\.shown)) { setting in
            entry(setting.entry)
        }
    }

    @ViewBuilder private func entry(_ entry: StreamMenuEntry) -> some View {
        switch entry {
        case .background: button(entry) { player?.play(item, mode: .background) }
        case .popup: button(entry) { player?.play(item, mode: .popup) }
        case .play: button(entry) { player?.play(item) }
        case .enqueue: button(entry) { player?.enqueue(item) }
        case .enqueueNext: button(entry) { player?.enqueueNext(item) }
        case .download: button(entry) { router.downloadItem = item }
        case .addToPlaylist: AddToPlaylistMenu(item: item)
        case .share:
            ShareLink(item: item.url) { Label(entry.title, systemImage: entry.symbol) }
        case .openInBrowser:
            if let url = URL(string: item.url) { button(entry) { openURL(url) } }
        case .copyLink: button(entry) { UIPasteboard.general.string = item.url }
        case .markWatched: button(entry) { store.library.markWatched(item) }
        case .showChannel:
            if let channel = item.uploaderUrl, !channel.isEmpty {
                button(entry) {
                    router.open(.channel(serviceId: item.serviceId, url: channel,
                                         name: item.uploaderName ?? ""))
                }
            }
        }
    }

    private func button(_ entry: StreamMenuEntry, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(entry.title, systemImage: entry.symbol) }
    }
}

/// Picks a quality for a video chosen from a list, which has no stream details loaded yet.
struct DownloadSheet: View {
    let item: InfoItem
    @EnvironmentObject private var downloads: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var details: StreamDetails?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let details {
                    let options = PlaybackPlanner.downloadOptions(for: details)
                    if options.isEmpty {
                        Text("Nothing downloadable").foregroundColor(.secondary)
                    }
                    ForEach(options.indices, id: \.self) { index in
                        Button(options[index].label) {
                            downloads.start(options[index], details: details)
                            dismiss()
                        }
                    }
                } else if let error {
                    StatusView(title: "Could not load this video", message: error) {
                        Task { await load() }
                    }
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
            .navigationTitle(item.name.isEmpty ? "Download" : item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { if details == nil { await load() } }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        do {
            error = nil
            details = try await Extractor.stream(serviceId: item.serviceId, url: item.url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// NewPipe's buttons above a list of videos: play it all in the player, the background or a popup.
struct PlayAllButtons: View {
    let items: [InfoItem]
    @Environment(\.controllers) private var controllers

    var body: some View {
        HStack(spacing: 8) {
            Button { controllers?.player.play(items, startingAt: 0) } label: {
                Label("Play all", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            Button { controllers?.player.play(items, startingAt: 0, mode: .background) } label: {
                Label("Background", systemImage: "headphones")
                    .frame(maxWidth: .infinity)
            }
            Button { controllers?.player.play(items, startingAt: 0, mode: .popup) } label: {
                Label("Popup", systemImage: "pip.enter")
                    .frame(maxWidth: .infinity)
            }
            Button { controllers?.player.play(items.shuffled(), startingAt: 0) } label: {
                Image(systemName: "shuffle")
            }
            .accessibilityLabel("Shuffle")
        }
        .labelStyle(CompactLabelStyle())
        .buttonStyle(.bordered)
        .font(.footnote)
        .disabled(!items.contains { $0.type == .stream })
        .listRowSeparator(.hidden)
    }
}

/// Icon over a short title, so three buttons fit across a phone.
private struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 2) {
            configuration.icon
            configuration.title.font(.caption2)
        }
    }
}

/// The same choices for a toolbar, where buttons do not fit.
struct PlayAllMenu: View {
    let items: [InfoItem]
    @Environment(\.controllers) private var controllers

    var body: some View {
        Menu {
            Button { controllers?.player.play(items, startingAt: 0) } label: {
                Label("Play all", systemImage: "play.fill")
            }
            Button { controllers?.player.play(items, startingAt: 0, mode: .background) } label: {
                Label("Play all in background", systemImage: "headphones")
            }
            Button { controllers?.player.play(items, startingAt: 0, mode: .popup) } label: {
                Label("Play all in popup", systemImage: "pip.enter")
            }
            Button { controllers?.player.play(items.shuffled(), startingAt: 0) } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
        } label: {
            Label("Play all", systemImage: "play")
        }
        .disabled(!items.contains { $0.type == .stream })
    }
}

/// References to the player and downloads for views that only act on them. Unlike
/// @EnvironmentObject this does not observe, so long lists do not redraw when playback changes.
struct Controllers {
    let player: PlayerController
    let downloads: DownloadManager
}

private struct ControllersKey: EnvironmentKey {
    static let defaultValue: Controllers? = nil
}

extension EnvironmentValues {
    var controllers: Controllers? {
        get { self[ControllersKey.self] }
        set { self[ControllersKey.self] = newValue }
    }
}
