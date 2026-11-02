import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var downloads: DownloadManager
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.history) {
                    Label("History", systemImage: "clock")
                }
                NavigationLink(value: Route.subscriptions) {
                    Label("Subscriptions", systemImage: "person.2")
                }
                NavigationLink(value: Route.downloads) {
                    HStack {
                        Label("Downloads", systemImage: "arrow.down.circle")
                        Spacer()
                        if !downloads.jobs.isEmpty {
                            Text("\(downloads.jobs.count)").foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section("Playlists") {
                ForEach(store.library.playlists) { playlist in
                    NavigationLink(value: Route.localPlaylist(playlist.id)) {
                        VStack(alignment: .leading) {
                            Text(playlist.name)
                            Text("\(playlist.items.count) videos")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { store.library.playlists.remove(atOffsets: $0) }
                Button {
                    newName = ""
                    creating = true
                } label: {
                    Label("New playlist", systemImage: "plus")
                }
            }
            if !store.library.savedPlaylists.isEmpty {
                Section("Bookmarked playlists") {
                    ForEach(store.library.savedPlaylists) { LinkedItemRow(item: $0) }
                        .onDelete { store.library.savedPlaylists.remove(atOffsets: $0) }
                }
            }
        }
        .navigationTitle("Library")
        .alert("New playlist", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Create") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.library.playlists.append(LocalPlaylist(name: name)) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct LocalPlaylistView: View {
    let id: UUID
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var player: PlayerController
    @State private var renaming = false
    @State private var newName = ""

    private var index: Int? { store.library.playlists.firstIndex { $0.id == id } }
    private var items: [InfoItem] { index.map { store.library.playlists[$0].items } ?? [] }

    var body: some View {
        List {
            if !items.isEmpty {
                PlayAllButtons(items: items)
            }
            ForEach(items) { LinkedItemRow(item: $0) }
                .onDelete { offsets in
                    if let index { store.library.playlists[index].items.remove(atOffsets: offsets) }
                }
                .onMove { source, destination in
                    if let index {
                        store.library.playlists[index].items.move(fromOffsets: source,
                                                                  toOffset: destination)
                    }
                }
        }
        .listStyle(.plain)
        .navigationTitle(index.map { store.library.playlists[$0].name } ?? "Playlist")
        .toolbar {
            ToolbarItem(placement: .primaryAction) { EditButton() }
            ToolbarItem(placement: .secondaryAction) {
                Button("Rename") {
                    newName = index.map { store.library.playlists[$0].name } ?? ""
                    renaming = true
                }
            }
        }
        .alert("Rename playlist", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let index, !newName.isEmpty { store.library.playlists[index].name = newName }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirming = false

    var body: some View {
        List {
            ForEach(store.library.history) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    LinkedItemRow(item: entry.item)
                    if let count = entry.repeatCount, count > 1 {
                        Text("Played \(count) times").font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
            .onDelete { store.library.history.remove(atOffsets: $0) }
        }
        .listStyle(.plain)
        .navigationTitle("History")
        .overlay {
            if store.library.history.isEmpty {
                Text("Nothing watched yet").foregroundColor(.secondary)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear", role: .destructive) { confirming = true }
                    .disabled(store.library.history.isEmpty)
            }
        }
        .confirmationDialog("Clear the watch history?", isPresented: $confirming) {
            Button("Clear history", role: .destructive) { store.library.history = [] }
        }
    }
}

struct DownloadsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        List {
            ForEach(downloads.jobs) { job in
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title).font(.footnote).lineLimit(2)
                    if let error = job.error {
                        Text(error).font(.caption).foregroundColor(.red)
                    } else {
                        ProgressView(job.phase, value: job.progress)
                            .font(.caption2)
                    }
                }
                .swipeActions {
                    Button(job.error == nil ? "Cancel" : "Remove", role: .destructive) {
                        downloads.cancel(job)
                    }
                }
            }
            ForEach(store.library.downloads) { record in
                Button {
                    player.playDownload(record)
                } label: {
                    VStack(alignment: .leading) {
                        ItemRow(item: record.item)
                        Text(record.label).font(.caption2).foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button("Delete", role: .destructive) { downloads.delete(record) }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Downloads")
        .overlay {
            if downloads.jobs.isEmpty && store.library.downloads.isEmpty {
                Text("Nothing downloaded yet").foregroundColor(.secondary)
            }
        }
    }
}
