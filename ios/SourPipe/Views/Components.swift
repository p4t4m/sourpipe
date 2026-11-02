import SwiftUI

struct Thumbnail: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Rectangle().fill(Color.secondary.opacity(0.2))
            }
        }
        .clipped()
    }
}

struct ItemRow: View {
    let item: InfoItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Text(Format.subtitle(for: item))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var artwork: some View {
        if item.type == .channel {
            Thumbnail(url: item.thumbnails.best(minWidth: 120))
                .frame(width: 64, height: 64)
                .clipShape(Circle())
                .frame(width: 128)
        } else {
            ZStack(alignment: .bottomTrailing) {
                Thumbnail(url: item.thumbnails.best(minWidth: 240))
                    .frame(width: 128, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(item.isLive ? Color.red : Color.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
            }
        }
    }

    private var badge: String? {
        if item.isLive { return "LIVE" }
        if item.type == .playlist { return Format.compact(item.streamCount) }
        guard let duration = item.duration, duration > 0 else { return nil }
        return Format.duration(duration)
    }
}

/// A row that opens the item, with queue and playlist actions in its context menu.
struct LinkedItemRow: View {
    let item: InfoItem
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        if let route = Route(item) {
            NavigationLink(value: route) {
                ItemRow(item: item)
            }
            .contextMenu {
                if item.type == .stream {
                    Button { player.play(item) } label: {
                        Label("Play", systemImage: "play")
                    }
                    Button { player.enqueueNext(item) } label: {
                        Label("Play next", systemImage: "text.insert")
                    }
                    Button { player.enqueue(item) } label: {
                        Label("Add to queue", systemImage: "text.append")
                    }
                    AddToPlaylistMenu(item: item)
                }
                ShareLink(item: item.url)
            }
        }
    }
}

struct AddToPlaylistMenu: View {
    let item: InfoItem
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Menu {
            ForEach(store.library.playlists) { playlist in
                Button(playlist.name) {
                    store.library.add(item, toPlaylist: playlist.id)
                }
            }
            Button {
                store.library.playlists.append(LocalPlaylist(
                    name: "Playlist \(store.library.playlists.count + 1)", items: [item]))
            } label: {
                Label("New playlist", systemImage: "plus")
            }
        } label: {
            Label("Add to playlist", systemImage: "text.badge.plus")
        }
    }
}

struct StatusView: View {
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(title).font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            CaptchaSolveButton(retry: retry)
            if let retry {
                Button("Try again") { retry() }
                    .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Paged item list state shared by the search, kiosk, playlist and channel screens.
@MainActor
final class ItemListModel: ObservableObject {
    @Published var items: [InfoItem] = []
    @Published var error: String?
    @Published var isLoading = false
    @Published var nextPage: PageToken?

    private var moreSource: Extractor.MoreSource?
    private var serviceId = 0
    private var generation = 0

    /// With no `source`, paging continues as a kiosk from the URL the first page reports.
    func load(serviceId: Int, source: Extractor.MoreSource?,
              _ fetch: @escaping () async throws -> ItemPage) async {
        generation += 1
        let current = generation
        self.serviceId = serviceId
        moreSource = source
        isLoading = true
        error = nil
        items = []
        nextPage = nil
        do {
            let page = try await fetch()
            guard current == generation else { return }
            items = Self.deduplicated(page.items)
            nextPage = page.nextPage
            if moreSource == nil, let url = page.url { moreSource = .kiosk(url: url) }
            if items.isEmpty, let first = page.errors?.first { error = first }
        } catch {
            guard current == generation else { return }
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func set(items: [InfoItem], next: PageToken?, serviceId: Int, source: Extractor.MoreSource) {
        generation += 1
        self.items = Self.deduplicated(items)
        nextPage = next
        self.serviceId = serviceId
        moreSource = source
        isLoading = false
        error = nil
    }

    func loadMore() async {
        guard let page = nextPage, let source = moreSource, !isLoading else { return }
        let current = generation
        isLoading = true
        defer { if current == generation { isLoading = false } }
        do {
            let result = try await Extractor.more(serviceId: serviceId, source: source, page: page)
            guard current == generation else { return }
            let known = Set(items.map(\.id))
            items += Self.deduplicated(result.items).filter { !known.contains($0.id) }
            nextPage = result.nextPage
        } catch {
            guard current == generation else { return }
            // The loaded items are still useful; just stop paging.
            nextPage = nil
        }
    }

    /// SwiftUI lists misbehave on duplicate ids, and services do repeat items across a page.
    private static func deduplicated(_ items: [InfoItem]) -> [InfoItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}

struct ItemListSection: View {
    @ObservedObject var model: ItemListModel
    @EnvironmentObject private var store: AppStore

    private var visibleItems: [InfoItem] {
        store.library.settings.hideShorts ? model.items.filter { $0.isShort != true } : model.items
    }

    var body: some View {
        ForEach(visibleItems) { item in
            LinkedItemRow(item: item)
        }
        if model.nextPage != nil {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .task(id: model.items.count) { await model.loadMore() }
        }
    }
}
