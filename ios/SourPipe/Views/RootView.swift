import SwiftUI

enum Route: Hashable, Identifiable {
    case stream(InfoItem)
    case channel(serviceId: Int, url: String, name: String)
    case playlist(serviceId: Int, url: String, name: String)
    case localPlaylist(UUID)
    case history
    case downloads
    case subscriptions

    var id: Route { self }

    init?(_ item: InfoItem) {
        switch item.type {
        case .stream: self = .stream(item)
        case .channel: self = .channel(serviceId: item.serviceId, url: item.url, name: item.name)
        case .playlist: self = .playlist(serviceId: item.serviceId, url: item.url, name: item.name)
        case .comment: return nil
        }
    }
}

struct RouteScreen: View {
    let route: Route

    var body: some View {
        switch route {
        case .stream(let item):
            StreamView(item: item)
        case .channel(let serviceId, let url, let name):
            ChannelView(serviceId: serviceId, url: url, name: name)
        case .playlist(let serviceId, let url, let name):
            PlaylistView(serviceId: serviceId, url: url, name: name)
        case .localPlaylist(let id):
            LocalPlaylistView(id: id)
        case .history:
            HistoryView()
        case .downloads:
            DownloadsView()
        case .subscriptions:
            SubscriptionsView()
        }
    }
}

extension View {
    /// Every navigation stack in the app handles the same routes.
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { RouteScreen(route: $0) }
    }

    func miniPlayerInset(showing: Binding<Bool>) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                CaptchaBanner()
                MiniPlayerBar(showing: showing)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager
    @State private var showingPlayer = false
    @State private var linkTarget: Route?
    @State private var linkError: String?

    var body: some View {
        Group {
            if let error = store.startupError {
                StatusView(title: "The extractor failed to start", message: error) {
                    Task { await store.start() }
                }
            } else if store.services.isEmpty {
                ProgressView("Starting…")
            } else {
                tabs
            }
        }
        .sheet(isPresented: $showingPlayer) {
            RoutedStack {
                NowPlayingScreen()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingPlayer = false }
                        }
                    }
            }
        }
        .sheet(item: $linkTarget) { route in
            RoutedStack {
                RouteScreen(route: route)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { linkTarget = nil }
                        }
                    }
            }
        }
        .alert("Could not open the link", isPresented: Binding(
            get: { linkError != nil }, set: { if !$0 { linkError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(linkError ?? "")
        }
        .background(alignment: .topLeading) {
            // Must be in the window for Picture in Picture to start from it; covered by the app.
            PopupHost(player: player) { showingPlayer = true }
                .frame(width: 2, height: 2)
        }
        .tint(store.library.settings.themeColor.color)
        .onAppear { applyWindowTheme() }
        .onChange(of: store.library.settings.themeColor) { _ in applyWindowTheme() }
        .onChange(of: store.library.settings.appearance) { _ in applyWindowTheme() }
        .onOpenURL { open($0) }
        #if DEBUG
        // CI launches with `-openLink <url>`: a sourpipe:// link would stop at a system prompt.
        .task {
            if let page = UserDefaults.standard.string(forKey: "testCaptcha"),
               let url = URL(string: page) {
                CaptchaSolver.shared.request(url)
            }
            // `-testPopup <url>` plays in the popup; `-testDownload <url>` saves an audio track.
            if let link = UserDefaults.standard.string(forKey: "testPopup"),
               case .stream(let item)? = try? await LinkResolver.route(for: link) {
                player.play(item, mode: .popup)
            }
            if let link = UserDefaults.standard.string(forKey: "testDownload"),
               case .stream(let item)? = try? await LinkResolver.route(for: link),
               let details = try? await Extractor.stream(serviceId: item.serviceId, url: link) {
                let options = PlaybackPlanner.downloadOptions(for: details)
                if let option = options.first(where: { $0.label.hasPrefix("Audio") }) ?? options.last {
                    NSLog("[download] test: %@", option.label)
                    downloads.start(option, details: details)
                }
            }
            if let link = UserDefaults.standard.string(forKey: "openLink") {
                linkTarget = try? await LinkResolver.route(for: link)
            }
        }
        #endif
    }

    /// UIKit parts (alerts, sheets, the system player) take colour and style from the window.
    private func applyWindowTheme() {
        let settings = store.library.settings
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.tintColor = UIColor(settings.themeColor.color)
                window.overrideUserInterfaceStyle = settings.appearance.style
            }
        }
    }

    /// Handles sourpipe://open?url=<link>, and links rewritten as sourpipe://host/path.
    private func open(_ url: URL) {
        var link: String?
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            link = components.queryItems?.first { $0.name == "url" }?.value
            if link == nil, components.host != "open" {
                var rewritten = components
                rewritten.scheme = "https"
                link = rewritten.url?.absoluteString
            }
        }
        guard let link else { return }
        Task {
            do {
                linkTarget = try await LinkResolver.route(for: link)
            } catch {
                linkError = error.localizedDescription
            }
        }
    }

    private var tabs: some View {
        TabView {
            RoutedStack { HomeView() }
                .miniPlayerInset(showing: $showingPlayer)
                .tabItem { Label("Home", systemImage: "flame") }
            RoutedStack { SearchView() }
                .miniPlayerInset(showing: $showingPlayer)
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            RoutedStack { FeedView() }
                .miniPlayerInset(showing: $showingPlayer)
                .tabItem { Label("Feed", systemImage: "rectangle.stack") }
            RoutedStack { LibraryView() }
                .miniPlayerInset(showing: $showingPlayer)
                .tabItem { Label("Library", systemImage: "books.vertical") }
            RoutedStack { SettingsView() }
                .miniPlayerInset(showing: $showingPlayer)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

enum LinkResolver {
    static func route(for link: String) async throws -> Route {
        let resolved = try await Extractor.resolve(url: link)
        switch resolved.linkType {
        case "stream":
            return .stream(InfoItem(type: .stream, serviceId: resolved.serviceId, url: link, name: ""))
        case "channel":
            return .channel(serviceId: resolved.serviceId, url: link, name: "")
        case "playlist":
            return .playlist(serviceId: resolved.serviceId, url: link, name: "")
        default:
            throw ExtractorFailure(kind: "unsupported", message: "Unsupported link")
        }
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerController
    @Binding var showing: Bool

    var body: some View {
        if let entry = player.current {
            HStack(spacing: 10) {
                Thumbnail(url: entry.item.thumbnails.best(minWidth: 120))
                    .frame(width: 64, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.details?.name ?? entry.item.name)
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                    Text(status(entry))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if player.state == .loading {
                    ProgressView()
                } else {
                    Button { player.togglePlayPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                }
                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill")
                }
                .disabled(!player.hasNext)
                .accessibilityLabel("Next")
                Button { player.stop() } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Stop")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
            .contentShape(Rectangle())
            .onTapGesture { showing = true }
        }
    }

    private func status(_ entry: PlayerController.QueueEntry) -> String {
        if case .failed(let message) = player.state { return message }
        return player.details?.uploaderName ?? entry.item.uploaderName ?? ""
    }
}
