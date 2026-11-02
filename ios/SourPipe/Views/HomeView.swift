import SwiftUI

struct ServiceMenu: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Menu {
            Picker("Service", selection: $store.library.settings.serviceId) {
                ForEach(store.services) { service in
                    Text(service.name).tag(service.id)
                }
            }
        } label: {
            Label(store.currentService?.name ?? "Service", systemImage: "globe")
        }
    }
}

/// The sections chosen in Settings > Home sections, as tabs across the top, like NewPipe's main page.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selection: HomePage?

    private var pages: [HomePage] {
        let pages = store.library.settings.homePages
        return pages.isEmpty ? HomePage.defaults : pages
    }

    private var current: HomePage {
        if let selection, pages.contains(selection) { return selection }
        return pages[0]
    }

    var body: some View {
        page(current)
            .id(current)
            .safeAreaInset(edge: .top, spacing: 0) {
                if pages.count > 1 { tabs }
            }
    }

    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(pages) { page in
                        let selected = page == current
                        Button {
                            selection = page
                        } label: {
                            Text(store.title(of: page))
                                .font(.footnote.weight(selected ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(selected ? Color.accentColor.opacity(0.2)
                                                     : Color.secondary.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(page)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .background(.bar)
            .onChange(of: current) { page in withAnimation { proxy.scrollTo(page) } }
        }
    }

    @ViewBuilder private func page(_ page: HomePage) -> some View {
        switch page {
        case .serviceSections:
            KioskPage(fixed: nil)
        case .kiosk(let serviceId, let id):
            KioskPage(fixed: (serviceId, id))
        case .feed:
            FeedView()
        case .subscriptions:
            SubscriptionsView()
        case .bookmarks:
            BookmarksView()
        case .history:
            HistoryView()
        case .channel(let serviceId, let url, let name):
            ChannelView(serviceId: serviceId, url: url, name: name)
        case .playlist(let serviceId, let url, let name):
            PlaylistView(serviceId: serviceId, url: url, name: name)
        }
    }
}

extension AppStore {
    func title(of page: HomePage) -> String {
        switch page {
        case .serviceSections: return currentService?.name ?? "Sections"
        case .kiosk(let serviceId, let id):
            let service = services.first { $0.id == serviceId }?.name
            let kiosk = Format.kioskTitle(id)
            return service.map { serviceId == library.settings.serviceId ? kiosk : "\($0): \(kiosk)" }
                ?? kiosk
        case .feed: return "What's new"
        case .subscriptions: return "Subscriptions"
        case .bookmarks: return "Bookmarks"
        case .history: return "History"
        case .channel(_, _, let name): return name.isEmpty ? "Channel" : name
        case .playlist(_, _, let name): return name.isEmpty ? "Playlist" : name
        }
    }
}

/// A service's sections. With `fixed`, one section of one service; otherwise the selected
/// service's sections with a picker.
struct KioskPage: View {
    let fixed: (serviceId: Int, id: String)?
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = ItemListModel()
    @State private var kiosk: String?

    private var service: ServiceInfo? {
        if let fixed { return store.services.first { $0.id == fixed.serviceId } }
        return store.currentService
    }

    private var selectedKiosk: String? { fixed?.id ?? kiosk ?? service?.defaultKiosk }

    var body: some View {
        List {
            if fixed == nil, let kiosks = service?.kiosks, kiosks.count > 1 {
                Picker("Section", selection: Binding(
                    get: { selectedKiosk ?? "" },
                    set: { kiosk = $0 }
                )) {
                    ForEach(kiosks, id: \.self) { Text(Format.kioskTitle($0)).tag($0) }
                }
            }
            if let error = model.error {
                StatusView(title: "Could not load this section", message: error) {
                    Task { await load() }
                }
            }
            ItemListSection(model: model)
        }
        .listStyle(.plain)
        .overlay {
            if model.isLoading && model.items.isEmpty { ProgressView() }
        }
        .navigationTitle(selectedKiosk.map(Format.kioskTitle) ?? "Home")
        .toolbar {
            if fixed == nil {
                ToolbarItem(placement: .primaryAction) { ServiceMenu() }
            }
        }
        .refreshable { await load() }
        .task(id: "\(service?.id ?? -1)/\(selectedKiosk ?? "")") { await load() }
        .onChange(of: store.library.settings.serviceId) { _ in kiosk = nil }
    }

    private func load() async {
        guard let service, let id = selectedKiosk, service.kiosks.contains(id) else { return }
        await model.load(serviceId: service.id, source: nil) {
            try await Extractor.kiosk(serviceId: service.id, id: id)
        }
    }
}

struct BookmarksView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            ForEach(store.library.savedPlaylists) { LinkedItemRow(item: $0) }
                .onDelete { store.library.savedPlaylists.remove(atOffsets: $0) }
        }
        .listStyle(.plain)
        .navigationTitle("Bookmarks")
        .overlay {
            if store.library.savedPlaylists.isEmpty {
                Text("No bookmarked playlists").foregroundColor(.secondary)
            }
        }
    }
}
