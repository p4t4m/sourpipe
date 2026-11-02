import SwiftUI

/// Newest videos across subscriptions.
@MainActor
final class FeedModel: ObservableObject {
    @Published var items: [InfoItem] = []
    @Published var isLoading = false
    @Published var completed = 0
    @Published var failed: [String] = []
    private var total = 0

    /// Requests to run at once. The services rate limit, and JS runs on one thread anyway.
    private static let concurrency = 4

    func load(_ subscriptions: [Subscription]) async {
        guard !isLoading else { return }
        isLoading = true
        completed = 0
        failed = []
        total = subscriptions.count
        var collected: [InfoItem] = []
        var pending = subscriptions[...]
        await withTaskGroup(of: (Subscription, [InfoItem]?).self) { group in
            for _ in 0..<Self.concurrency {
                guard let subscription = pending.popFirst() else { break }
                group.addTask { (subscription, try? await Self.videos(of: subscription)) }
            }
            for await (subscription, videos) in group {
                completed += 1
                if let videos {
                    collected += videos
                } else {
                    failed.append(subscription.name)
                }
                items = Self.sorted(collected)
                if let next = pending.popFirst() {
                    group.addTask { (next, try? await Self.videos(of: next)) }
                }
            }
        }
        isLoading = false
    }

    private nonisolated static func videos(of subscription: Subscription) async throws -> [InfoItem] {
        let channel = try await Extractor.channel(serviceId: subscription.serviceId,
                                                  url: subscription.url)
        guard let tab = channel.tabs.first(where: { $0.name == "videos" }) ?? channel.tabs.first else {
            return []
        }
        return try await Extractor.channelTab(serviceId: subscription.serviceId, token: tab.token)
            .items.filter { $0.type == .stream }
    }

    private static func sorted(_ items: [InfoItem]) -> [InfoItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
            .sorted { ($0.uploadDate ?? 0) > ($1.uploadDate ?? 0) }
    }

    var progressText: String { "Checked \(completed) of \(total) channels" }
}

struct FeedView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var player: PlayerController
    @StateObject private var model = FeedModel()

    private var visibleItems: [InfoItem] {
        store.library.settings.hideShorts ? model.items.filter { $0.isShort != true } : model.items
    }

    var body: some View {
        List {
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
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    player.play(visibleItems, startingAt: 0)
                } label: {
                    Label("Play all", systemImage: "play")
                }
                .disabled(visibleItems.isEmpty)
            }
        }
        .refreshable { await model.load(store.library.subscriptions) }
        .task {
            if model.items.isEmpty && !store.library.subscriptions.isEmpty {
                await model.load(store.library.subscriptions)
            }
        }
    }
}

struct SubscriptionsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
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
