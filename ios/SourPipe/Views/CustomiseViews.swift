import SwiftUI

/// Settings > Long-press menu: which actions a video's menu shows, and in what order.
struct StreamMenuSettingsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            Section {
                ForEach($store.library.settings.streamMenu) { $setting in
                    Toggle(isOn: $setting.shown) {
                        Label(setting.entry.title, systemImage: setting.entry.symbol)
                    }
                }
                .onMove { store.library.settings.streamMenu.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                Text("Tap Edit to change the order. \"Show channel details\" appears only when the video names its channel.")
            }
            Section {
                Button("Restore defaults") {
                    store.library.settings.streamMenu = MenuEntrySetting.defaults
                }
            }
        }
        .navigationTitle("Long-press menu")
        .toolbar { EditButton() }
    }
}

/// Settings > Home sections, after NewPipe's "Content of main page".
struct HomePagesSettingsView: View {
    @EnvironmentObject private var store: AppStore

    private var pages: [HomePage] { store.library.settings.homePages }

    var body: some View {
        List {
            Section {
                ForEach(pages) { page in
                    Text(store.title(of: page))
                }
                .onMove { store.library.settings.homePages.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { offsets in
                    var updated = pages
                    updated.remove(atOffsets: offsets)
                    store.library.settings.homePages = updated.isEmpty ? HomePage.defaults : updated
                }
            } footer: {
                Text("With more than one, Home shows them as tabs across the top. The first opens by default.")
            }
            Section("Add") {
                add(.serviceSections, "Sections of the selected service")
                add(.feed, "What's new (subscriptions feed)")
                add(.subscriptions, "Subscriptions")
                add(.bookmarks, "Bookmarked playlists")
                add(.history, "History")
                ForEach(store.services) { service in
                    if !service.kiosks.isEmpty {
                        Menu("\(service.name) section…") {
                            ForEach(service.kiosks, id: \.self) { kiosk in
                                add(.kiosk(serviceId: service.id, id: kiosk), Format.kioskTitle(kiosk))
                            }
                        }
                    }
                }
                if !store.library.subscriptions.isEmpty {
                    Menu("Channel…") {
                        ForEach(store.library.subscriptions) { channel in
                            add(.channel(serviceId: channel.serviceId, url: channel.url,
                                         name: channel.name), channel.name)
                        }
                    }
                }
                if !store.library.savedPlaylists.isEmpty {
                    Menu("Bookmarked playlist…") {
                        ForEach(store.library.savedPlaylists) { playlist in
                            add(.playlist(serviceId: playlist.serviceId, url: playlist.url,
                                          name: playlist.name), playlist.name)
                        }
                    }
                }
            }
            Section {
                Button("Restore defaults") { store.library.settings.homePages = HomePage.defaults }
            }
        }
        .navigationTitle("Home sections")
        .toolbar { EditButton() }
    }

    @ViewBuilder private func add(_ page: HomePage, _ title: String) -> some View {
        let added = pages.contains(page)
        Button {
            store.library.settings.homePages.append(page)
        } label: {
            HStack {
                Text(title)
                Spacer()
                if added { Image(systemName: "checkmark").foregroundColor(.secondary) }
            }
        }
        .disabled(added)
    }
}

/// The colour swatches for Settings > Appearance.
struct ThemeColorPicker: View {
    @Binding var selection: ThemeColor

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
            ForEach(ThemeColor.allCases) { theme in
                Button {
                    selection = theme
                } label: {
                    Circle()
                        .fill(theme.color)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if theme == selection {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundColor(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.title)
                .accessibilityAddTraits(theme == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
