import SwiftUI

struct ChannelView: View {
    let serviceId: Int
    let url: String
    let name: String
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = ItemListModel()
    @State private var channel: ChannelDetails?
    @State private var tab: ChannelTab?
    @State private var error: String?

    var body: some View {
        List {
            if let channel {
                header(channel)
                if channel.tabs.count > 1 {
                    Picker("Tab", selection: $tab) {
                        ForEach(channel.tabs) { Text($0.name.capitalized).tag(Optional($0)) }
                    }
                }
            }
            if let error {
                StatusView(title: "Could not load this channel", message: error) {
                    Task { await load() }
                }
            }
            if model.items.contains(where: { $0.type == .stream }) {
                PlayAllButtons(items: model.items)
            }
            if let tabError = model.error {
                Text(tabError).font(.footnote).foregroundColor(.secondary)
            }
            ItemListSection(model: model)
        }
        .listStyle(.plain)
        .overlay {
            if channel == nil && error == nil { ProgressView() }
        }
        .navigationTitle(channel?.name ?? name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let channel {
                    Button(store.library.isSubscribed(channel.url) ? "Unsubscribe" : "Subscribe") {
                        store.library.toggleSubscription(Subscription(
                            serviceId: channel.serviceId, url: channel.url, name: channel.name,
                            avatar: channel.avatars.best(minWidth: 88)?.absoluteString))
                    }
                }
            }
        }
        .task { if channel == nil { await load() } }
        .task(id: tab) { await loadTab() }
    }

    private func header(_ channel: ChannelDetails) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Thumbnail(url: channel.avatars.best(minWidth: 120))
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
                VStack(alignment: .leading) {
                    Text(channel.name).font(.headline)
                    if let subs = Format.compact(channel.subscriberCount) {
                        Text(subs + " subscribers").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            if let description = channel.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private func load() async {
        do {
            error = nil
            let details = try await Extractor.channel(serviceId: serviceId, url: url)
            channel = details
            tab = details.tabs.first
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadTab() async {
        guard let tab else { return }
        let token = tab.token
        await model.load(serviceId: serviceId, source: .channelTab(token: token)) {
            try await Extractor.channelTab(serviceId: serviceId, token: token)
        }
    }
}
