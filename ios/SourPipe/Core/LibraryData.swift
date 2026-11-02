import Foundation

public struct Subscription: Codable, Hashable, Identifiable {
    public var serviceId: Int
    public var url: String
    public var name: String
    public var avatar: String?
    public var id: String { url }

    public init(serviceId: Int, url: String, name: String, avatar: String? = nil) {
        self.serviceId = serviceId
        self.url = url
        self.name = name
        self.avatar = avatar
    }
}

public struct HistoryEntry: Codable, Hashable, Identifiable {
    public var item: InfoItem
    public var watchedAt: Date
    /// Seconds watched, used to resume.
    public var position: Double
    public var id: String { item.url }
}

public struct LocalPlaylist: Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var items: [InfoItem]

    public init(id: UUID = UUID(), name: String, items: [InfoItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

public struct DownloadRecord: Codable, Hashable, Identifiable {
    public var id: UUID
    public var item: InfoItem
    public var label: String
    /// Relative to the Documents directory, because the container path changes between installs.
    public var fileName: String
    public var isAudio: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), item: InfoItem, label: String, fileName: String, isAudio: Bool,
                createdAt: Date = Date()) {
        self.id = id
        self.item = item
        self.label = label
        self.fileName = fileName
        self.isAudio = isAudio
        self.createdAt = createdAt
    }
}

public struct AppSettings: Codable, Equatable {
    public var serviceId = 0
    public var language = "en"
    public var country = "US"
    public var maxHeight = 0
    public var audioOnly = false
    public var autoplayRelated = false
    public var resumePlayback = true
    public var recordHistory = true
    public var showComments = true
    public var hideShorts = false

    public init() {}
}

/// Everything the app persists. Plain data: AppStore wraps it for SwiftUI and writes it to disk.
public struct LibraryData: Codable, Equatable {
    public static let historyLimit = 1000

    public var settings = AppSettings()
    public var subscriptions: [Subscription] = []
    public var history: [HistoryEntry] = []
    public var playlists: [LocalPlaylist] = []
    public var downloads: [DownloadRecord] = []
    public var searches: [String] = []

    public init() {}

    enum CodingKeys: CodingKey {
        case settings, subscriptions, history, playlists, downloads, searches
    }

    /// Fields missing from an older file keep their defaults instead of failing the whole load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        subscriptions = try c.decodeIfPresent([Subscription].self, forKey: .subscriptions) ?? []
        history = try c.decodeIfPresent([HistoryEntry].self, forKey: .history) ?? []
        playlists = try c.decodeIfPresent([LocalPlaylist].self, forKey: .playlists) ?? []
        downloads = try c.decodeIfPresent([DownloadRecord].self, forKey: .downloads) ?? []
        searches = try c.decodeIfPresent([String].self, forKey: .searches) ?? []
    }

    public func isSubscribed(_ url: String) -> Bool {
        subscriptions.contains { $0.url == url }
    }

    public mutating func toggleSubscription(_ subscription: Subscription) {
        if let index = subscriptions.firstIndex(where: { $0.url == subscription.url }) {
            subscriptions.remove(at: index)
        } else {
            subscriptions.append(subscription)
            subscriptions.sort { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    public mutating func recordWatch(_ item: InfoItem, position: Double, at date: Date = Date()) {
        history.removeAll { $0.item.url == item.url }
        history.insert(HistoryEntry(item: item, watchedAt: date, position: position), at: 0)
        if history.count > Self.historyLimit {
            history.removeLast(history.count - Self.historyLimit)
        }
    }

    public mutating func updatePosition(url: String, position: Double) {
        guard let index = history.firstIndex(where: { $0.item.url == url }) else { return }
        history[index].position = position
    }

    /// Where to resume, or nil when nearly finished or barely started.
    public func resumePosition(url: String, duration: Double) -> Double? {
        guard let entry = history.first(where: { $0.item.url == url }),
              entry.position > 5, duration <= 0 || entry.position < duration - 10 else {
            return nil
        }
        return entry.position
    }

    public mutating func recordSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searches.removeAll { $0 == trimmed }
        searches.insert(trimmed, at: 0)
        if searches.count > 50 { searches.removeLast(searches.count - 50) }
    }

    public mutating func add(_ item: InfoItem, toPlaylist id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }),
              !playlists[index].items.contains(where: { $0.url == item.url }) else { return }
        playlists[index].items.append(item)
    }
}

/// Reads the subscriptions.json that NewPipe on Android exports.
public enum NewPipeImport {
    private struct Export: Decodable {
        struct Entry: Decodable {
            var service_id: Int
            var url: String
            var name: String
        }
        var subscriptions: [Entry]
    }

    public static func subscriptions(from data: Data) throws -> [Subscription] {
        try JSONDecoder().decode(Export.self, from: data).subscriptions.map {
            Subscription(serviceId: $0.service_id, url: $0.url, name: $0.name)
        }
    }

    /// Merges without duplicates; returns how many were new.
    @discardableResult
    public static func merge(_ incoming: [Subscription], into library: inout LibraryData) -> Int {
        var added = 0
        for subscription in incoming where !library.isSubscribed(subscription.url) {
            library.subscriptions.append(subscription)
            added += 1
        }
        library.subscriptions.sort { $0.name.lowercased() < $1.name.lowercased() }
        return added
    }
}
