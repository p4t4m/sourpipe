import SwiftUI

struct PlaylistView: View {
    let serviceId: Int
    let url: String
    let name: String
    @EnvironmentObject private var player: PlayerController
    @StateObject private var model = ItemListModel()
    @State private var playlist: PlaylistDetails?
    @State private var error: String?

    var body: some View {
        List {
            if let playlist {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name).font(.headline)
                    Text([playlist.uploaderName, Format.compact(playlist.streamCount).map { $0 + " videos" }]
                        .compactMap { $0 }.joined(separator: " • "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack {
                    Button {
                        player.play(model.items, startingAt: 0)
                    } label: {
                        Label("Play all", systemImage: "play.fill")
                    }
                    Button {
                        player.play(model.items.shuffled(), startingAt: 0)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                    }
                }
                .buttonStyle(.bordered)
                .listRowSeparator(.hidden)
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
        .task { if playlist == nil { await load() } }
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
