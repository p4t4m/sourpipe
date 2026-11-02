import SwiftUI

struct PlaylistView: View {
    let serviceId: Int
    let url: String
    let name: String
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = ItemListModel()
    @State private var playlist: PlaylistDetails?
    @State private var error: String?

    var body: some View {
        List {
            HomeTabsSlot()
            if let playlist {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name).font(.headline)
                    Text([playlist.uploaderName, Format.compact(playlist.streamCount).map { $0 + " videos" }]
                        .compactMap { $0 }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                PlayAllButtons(items: model.items)
            }
            if let error {
                StatusView(title: "Could not load this playlist", message: error) {
                    Task { await load() }
                }
            }
            ItemListSection(model: model)
        }
        .listStyle(.plain)
        .overlay {
            if playlist == nil && error == nil { ProgressView() }
        }
        .navigationTitle(playlist?.name ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let playlist {
                    let saved = store.library.savedPlaylists.contains { $0.url == playlist.url }
                    Button {
                        toggleSaved(playlist, saved: saved)
                    } label: {
                        Label(saved ? "Remove bookmark" : "Bookmark",
                              systemImage: saved ? "bookmark.fill" : "bookmark")
                    }
                }
            }
        }
        .task { if playlist == nil { await load() } }
    }

    private func toggleSaved(_ playlist: PlaylistDetails, saved: Bool) {
        if saved {
            store.library.savedPlaylists.removeAll { $0.url == playlist.url }
        } else {
            var item = InfoItem(type: .playlist, serviceId: playlist.serviceId, url: playlist.url,
                                name: playlist.name, thumbnails: playlist.thumbnails)
            item.uploaderName = playlist.uploaderName
            item.streamCount = playlist.streamCount
            store.library.savedPlaylists.append(item)
        }
    }

    @MainActor private func load() async {
        do {
            error = nil
            let details = try await Extractor.playlist(serviceId: serviceId, url: url)
            playlist = details
            model.set(items: details.items, next: details.nextPage, serviceId: serviceId,
                      source: .playlist(url: url))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
