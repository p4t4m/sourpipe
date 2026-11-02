import SwiftUI

/// Newest videos across subscriptions, kept on disk so that the feed opens instantly.
@MainActor
final class FeedModel: ObservableObject {
    @Published var isLoading = false
    @Published var completed = 0
    @Published var failed: [String] = []
    @Published private(set) var updatedAt: Date?
    /// Per channel, so that a feed group can filter without fetching again.
    @Published private var byChannel: [String: [InfoItem]] = [:] {
        didSet { sortedLists = [:] }
    }
    private var sortedLists: [[String]?: [InfoItem]] = [:]
    private var total = 0
    private var pending: ArraySlice<Subscription> = []

    /// Below this, the cached feed is shown without checking again. Pull to refresh always checks.
    private static let freshFor: TimeInterval = 30 * 60
    /// Calls at once per engine. Above one, a second call parses while the first waits on the network.
    private static let callsPerEngine = 2

    private struct Cache: Codable {
        var updatedAt: Date
        var byChannel: [String: [InfoItem]]
    }

    private nonisolated static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("feed.json")
    }

    func loadIfNeeded(_ subscriptions: [Subscription], settings: AppSettings) async {
        if updatedAt == nil, !isLoading {
            let cache = await Task.detached(priority: .userInitiated) { () -> Cache? in
                guard let data = try? Data(contentsOf: Self.cacheURL) else { return nil }
                return try? JSONDecoder().decode(Cache.self, from: data)
            }.value
            if let cache {
                byChannel = cache.byChannel
                updatedAt = cache.updatedAt
            }
        }
        let known = Set(byChannel.keys)
        let isMissingChannels = subscriptions.contains { !known.contains($0.url) }
        let isStale = updatedAt.map { Date().timeIntervalSince($0) > Self.freshFor } ?? true
        if isStale || isMissingChannels { await load(subscriptions, settings: settings) }
    }

    func load(_ subscriptions: [Subscription], settings: AppSettings) async {
        guard !isLoading, !subscriptions.isEmpty else { return }
        isLoading = true
        completed = 0
        failed = []
        total = subscriptions.count
        pending = subscriptions[...]
        let engines = ExtractorEngine.workers(min(subscriptions.count, 3))
        await withTaskGroup(of: Void.self) { group in
            for engine in engines {
                group.addTask { await Self.prepare(engine, settings: settings) }
            }
            await group.waitForAll()
            for engine in engines {
                for _ in 0..<Self.callsPerEngine {
                    group.addTask { await self.work(on: engine) }
                }
            }
        }
        updatedAt = Date()
        isLoading = false
        save()
    }

    private nonisolated static func prepare(_ engine: ExtractorEngine, settings: AppSettings) async {
        try? await Extractor.configure(language: settings.language, country: settings.country,
                                       on: engine)
    }

    private func work(on engine: ExtractorEngine) async {
        while let subscription = pending.popFirst() {
            let videos = try? await Self.videos(of: subscription, on: engine)
            completed += 1
            if let videos {
                // A failed channel keeps its cached videos.
                byChannel[subscription.url] = videos
            } else {
                failed.append(subscription.name)
            }
        }
    }

    private nonisolated static func videos(of subscription: Subscription,
                                           on engine: ExtractorEngine) async throws -> [InfoItem] {
        let channel = try await Extractor.channel(serviceId: subscription.serviceId,
                                                  url: subscription.url, on: engine)
        guard let tab = channel.tabs.first(where: { $0.name == "videos" }) ?? channel.tabs.first else {
            return []
        }
        return try await Extractor.channelTab(serviceId: subscription.serviceId, token: tab.token,
                                              on: engine)
            .items.filter { $0.type == .stream }
    }

    private func save() {
        guard let updatedAt else { return }
        let cache = Cache(updatedAt: updatedAt, byChannel: byChannel)
        Task.detached(priority: .utility) {
            if let data = try? JSONEncoder().encode(cache) {
                try? data.write(to: Self.cacheURL, options: .atomic)
            }
        }
    }

    /// Newest first across the given channels. Unsubscribed channels drop out because the caller
    /// only passes current ones. Remembered, since the view asks repeatedly while rendering.
    func items(in channels: [String]) -> [InfoItem] {
        if let known = sortedLists[channels] { return known }
        var seen = Set<String>()
        let sorted = channels.compactMap { byChannel[$0] }.flatMap { $0 }
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.uploadDate ?? 0) > ($1.uploadDate ?? 0) }
        sortedLists[channels] = sorted
        return sorted
    }

    var progressText: String { "Checked \(completed) of \(total) channels" }
}

struct FeedView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = FeedModel()
    @State private var groupID: UUID?

    private var group: FeedGroup? {
        store.library.feedGroups.first { $0.id == groupID }
    }

    private var visibleItems: [InfoItem] {
        let items = model.items(in: group?.channelURLs ?? store.library.subscriptions.map(\.url))
        return store.library.settings.hideShorts ? items.filter { $0.isShort != true } : items
    }

    var body: some View {
        List {
            HomeTabsSlot()
            if store.library.subscriptions.isEmpty {
                VStack(spacing: 8) {
                    Text("No subscriptions yet").font(.headline)
                    Text("Subscribe from a channel page, or import a NewPipe export in Settings.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }
            if model.isLoading {
                Label {
                    Text(model.progressText).font(.footnote)
                } icon: {
                    ProgressView()
                }
            }
            if !model.failed.isEmpty {
                Text("Could not check: " + model.failed.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            ForEach(visibleItems) { LinkedItemRow(item: $0) }
        }
        .listStyle(.plain)
        .navigationTitle(group?.name ?? "Feed")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !store.library.feedGroups.isEmpty {
                    Menu {
                        Picker("Feed group", selection: $groupID) {
                            Text("All").tag(UUID?.none)
                            ForEach(store.library.feedGroups) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    } label: {
                        Label("Feed group", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                PlayAllMenu(items: visibleItems)
            }
        }
        .refreshable {
            await model.load(store.library.subscriptions, settings: store.library.settings)
        }
        .task {
            await model.loadIfNeeded(store.library.subscriptions, settings: store.library.settings)
        }
    }
}

struct SubscriptionsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            HomeTabsSlot()
            ForEach(store.library.subscriptions) { subscription in
                NavigationLink(value: Route.channel(serviceId: subscription.serviceId,
                                                    url: subscription.url,
                                                    name: subscription.name)) {
                    HStack {
                        Thumbnail(url: subscription.avatar.flatMap(URL.init(string:)))
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        Text(subscription.name)
                    }
                }
            }
            .onDelete { store.library.subscriptions.remove(atOffsets: $0) }
        }
        .navigationTitle("Subscriptions")
        .overlay {
            if store.library.subscriptions.isEmpty {
                Text("No subscriptions yet").foregroundColor(.secondary)
            }
        }
    }
}
