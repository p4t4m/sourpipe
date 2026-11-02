import Foundation
#if canImport(SQLite3)
import SQLite3
#endif

public struct FeedGroup: Codable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var channelURLs: [String]

    public init(id: UUID = UUID(), name: String, channelURLs: [String]) {
        self.id = id
        self.name = name
        self.channelURLs = channelURLs
    }
}

/// What a NewPipe, Tubular or PipePipe backup holds, in SourPipe's own types.
public struct NewPipeBackup: Equatable {
    public var subscriptions: [Subscription] = []
    public var searches: [String] = []
    public var history: [HistoryEntry] = []
    public var playlists: [LocalPlaylist] = []
    public var savedPlaylists: [InfoItem] = []
    public var feedGroups: [FeedGroup] = []
    public var sponsorBlockWhitelist: [String] = []
    /// Rows from services this app lacks, such as PipePipe's BiliBili and NicoNico.
    public var skippedOtherServices = 0

    public init() {}

    /// YouTube, SoundCloud, media.ccc.de, PeerTube and Bandcamp.
    static func isKnownService(_ id: Int) -> Bool { (0...4).contains(id) }
}

public struct ImportSummary: Equatable {
    public var subscriptions = 0
    public var history = 0
    public var playlists = 0
    public var playlistItems = 0
    public var savedPlaylists = 0
    public var feedGroups = 0
    public var searches = 0
    public var droppedHistory = 0
    public var skippedOtherServices = 0

    public var description: String {
        var lines = [
            "Subscriptions added: \(subscriptions)",
            "History entries added or updated: \(history)",
            "Playlists added or extended: \(playlists) (\(playlistItems) videos)",
            "Bookmarked playlists added: \(savedPlaylists)",
            "Feed groups added: \(feedGroups)",
            "Searches added: \(searches)",
        ]
        if droppedHistory > 0 {
            lines.append("Oldest history entries dropped over the limit: \(droppedHistory)")
        }
        if skippedOtherServices > 0 {
            lines.append("Skipped, from services this app lacks: \(skippedOtherServices)")
        }
        return lines.joined(separator: "\n")
    }
}

extension LibraryData {
    /// Adds a backup to the library without deleting anything, so importing twice changes nothing.
    @discardableResult
    public mutating func merge(_ backup: NewPipeBackup) -> ImportSummary {
        var summary = ImportSummary()
        summary.skippedOtherServices = backup.skippedOtherServices
        summary.subscriptions = NewPipeImport.merge(backup.subscriptions, into: &self)

        var byURL = Dictionary(history.map { ($0.item.url, $0) }, uniquingKeysWith: { a, _ in a })
        for entry in backup.history {
            if let existing = byURL[entry.item.url], existing.watchedAt >= entry.watchedAt { continue }
            byURL[entry.item.url] = entry
            summary.history += 1
        }
        let merged = byURL.values.sorted { $0.watchedAt > $1.watchedAt }
        summary.droppedHistory = max(0, merged.count - Self.historyLimit)
        history = Array(merged.prefix(Self.historyLimit))

        for incoming in backup.playlists {
            if let index = playlists.firstIndex(where: { $0.name == incoming.name }) {
                let known = Set(playlists[index].items.map(\.url))
                let added = incoming.items.filter { !known.contains($0.url) }
                if !added.isEmpty {
                    playlists[index].items += added
                    summary.playlists += 1
                    summary.playlistItems += added.count
                }
            } else {
                playlists.append(incoming)
                summary.playlists += 1
                summary.playlistItems += incoming.items.count
            }
        }
        for saved in backup.savedPlaylists where !savedPlaylists.contains(where: { $0.url == saved.url }) {
            savedPlaylists.append(saved)
            summary.savedPlaylists += 1
        }
        for group in backup.feedGroups {
            if let index = feedGroups.firstIndex(where: { $0.name == group.name }) {
                let known = Set(feedGroups[index].channelURLs)
                feedGroups[index].channelURLs += group.channelURLs.filter { !known.contains($0) }
            } else {
                feedGroups.append(group)
                summary.feedGroups += 1
            }
        }
        let knownSearches = Set(searches)
        let newSearches = backup.searches.filter { !knownSearches.contains($0) }
        summary.searches = newSearches.count
        searches = Array((searches + newSearches).prefix(Self.searchLimit))
        for name in backup.sponsorBlockWhitelist
        where !settings.sponsorBlock.whitelist.contains(name) {
            settings.sponsorBlock.whitelist.append(name)
        }
        return summary
    }
}

public enum NewPipeBackupError: Error, LocalizedError, Equatable {
    case notABackup
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .notABackup: return "This is not a NewPipe backup."
        case .database(let message): return "The backup's database could not be read: \(message)"
        }
    }
}

#if canImport(SQLite3)
public enum NewPipeBackupReader {
    /// Accepts the exported .zip or a bare newpipe.db.
    public static func read(_ data: Data) throws -> NewPipeBackup {
        let database: Data
        if data.starts(with: [0x50, 0x4B]) {
            let archive = try ZipArchive(data)
            guard archive.names.contains("newpipe.db") else { throw NewPipeBackupError.notABackup }
            database = try archive.read("newpipe.db")
        } else if data.starts(with: Array("SQLite format 3".utf8)) {
            database = data
        } else {
            throw NewPipeBackupError.notABackup
        }
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".db")
        try database.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        return try readDatabase(at: file.path)
    }

    private final class Database {
        var handle: OpaquePointer?

        init(path: String) throws {
            // immutable: the copy has no WAL files, and nothing here may ever write to it.
            let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
            guard sqlite3_open_v2("file:\(path)?immutable=1", &handle, flags, nil) == SQLITE_OK else {
                let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
                sqlite3_close(handle)
                throw NewPipeBackupError.database(message)
            }
        }

        deinit { sqlite3_close(handle) }

        func columns(of table: String) throws -> Set<String> {
            var names = Set<String>()
            try query("PRAGMA table_info(`\(table)`)") { row in
                if let name = row.text(1) { names.insert(name) }
            }
            return names
        }

        /// Selects the wanted columns in order. Forks and older schemas may lack some, which then
        /// read as NULL; a missing table gives no rows.
        func rows(_ table: String, _ wanted: [String], suffix: String = "",
                  _ body: (Row) throws -> Void) throws {
            let present = try columns(of: table)
            guard !present.isEmpty else { return }
            let list = wanted.map { present.contains($0) ? "`\($0)`" : "NULL" }
                .joined(separator: ", ")
            try query("SELECT \(list) FROM `\(table)` \(suffix)", body)
        }

        func query(_ sql: String, _ body: (Row) throws -> Void) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(handle))
                sqlite3_finalize(statement)
                throw NewPipeBackupError.database(message)
            }
            defer { sqlite3_finalize(statement) }
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW: try body(Row(statement: statement))
                case SQLITE_DONE: return
                default: throw NewPipeBackupError.database(String(cString: sqlite3_errmsg(handle)))
                }
            }
        }
    }

    private struct Row {
        let statement: OpaquePointer?

        func int(_ i: Int32) -> Int64? {
            sqlite3_column_type(statement, i) == SQLITE_NULL
                ? nil : sqlite3_column_int64(statement, i)
        }

        func text(_ i: Int32) -> String? {
            sqlite3_column_text(statement, i).map { String(cString: $0) }
        }
    }

    private static func image(_ url: String?) -> [RemoteImage] {
        guard let url, !url.isEmpty else { return [] }
        return [RemoteImage(url: url, width: -1, height: -1)]
    }

    private static func readDatabase(at path: String) throws -> NewPipeBackup {
        let db = try Database(path: path)
        guard try !db.columns(of: "subscriptions").isEmpty || !db.columns(of: "streams").isEmpty else {
            throw NewPipeBackupError.notABackup
        }
        var backup = NewPipeBackup()

        var channelURLs: [Int64: String] = [:]
        try db.rows("subscriptions", ["uid", "service_id", "url", "name", "avatar_url"]) { row in
            guard let uid = row.int(0), let service = row.int(1), let url = row.text(2) else { return }
            guard NewPipeBackup.isKnownService(Int(service)) else {
                backup.skippedOtherServices += 1
                return
            }
            channelURLs[uid] = url
            backup.subscriptions.append(Subscription(
                serviceId: Int(service), url: url, name: row.text(3) ?? url, avatar: row.text(4)))
        }

        var streams: [Int64: InfoItem] = [:]
        try db.rows("streams", ["uid", "service_id", "url", "title", "stream_type", "duration",
                                "uploader", "uploader_url", "thumbnail_url", "view_count",
                                "textual_upload_date", "upload_date"]) { row in
            guard let uid = row.int(0), let service = row.int(1), let url = row.text(2) else { return }
            guard NewPipeBackup.isKnownService(Int(service)) else { return }
            var item = InfoItem(type: .stream, serviceId: Int(service), url: url,
                                name: row.text(3) ?? "", thumbnails: image(row.text(8)))
            item.streamType = row.text(4)
            item.duration = row.int(5)
            item.uploaderName = row.text(6)
            item.uploaderUrl = row.text(7)
            item.viewCount = row.int(9)
            item.textualUploadDate = row.text(10)
            item.uploadDate = row.int(11).map(Double.init)
            streams[uid] = item
        }

        // NewPipe keeps one row per stream in stream_state, with the position in milliseconds.
        var positions: [Int64: Double] = [:]
        try db.rows("stream_state", ["stream_id", "progress_time"]) { row in
            if let id = row.int(0), let ms = row.int(1) { positions[id] = Double(ms) / 1000 }
        }

        var watched: [Int64: HistoryEntry] = [:]
        try db.rows("stream_history", ["stream_id", "access_date", "repeat_count"]) { row in
            guard let id = row.int(0), let item = streams[id] else { return }
            let date = Date(timeIntervalSince1970: Double(row.int(1) ?? 0) / 1000)
            let count = Int(row.int(2) ?? 1)
            if let existing = watched[id] {
                // Older schemas log one row per access; keep the newest and add up the plays.
                watched[id]?.repeatCount = (existing.repeatCount ?? 1) + count
                if date > existing.watchedAt { watched[id]?.watchedAt = date }
            } else {
                watched[id] = HistoryEntry(item: item, watchedAt: date,
                                           position: positions[id] ?? 0, repeatCount: count)
            }
        }
        // A saved position with no history row still lets the video resume.
        for (id, position) in positions where watched[id] == nil && position > 0 {
            if let item = streams[id] {
                watched[id] = HistoryEntry(item: item, watchedAt: Date(timeIntervalSince1970: 0),
                                           position: position)
            }
        }
        backup.history = watched.values.sorted { $0.watchedAt > $1.watchedAt }

        var playlistItems: [Int64: [InfoItem]] = [:]
        try db.rows("playlist_stream_join", ["playlist_id", "stream_id"],
                    suffix: "ORDER BY playlist_id, join_index") { row in
            guard let playlist = row.int(0), let stream = row.int(1) else { return }
            if let item = streams[stream] {
                // A list here cannot hold the same video twice, unlike in NewPipe.
                if playlistItems[playlist]?.contains(where: { $0.url == item.url }) != true {
                    playlistItems[playlist, default: []].append(item)
                }
            } else if streams.isEmpty == false {
                backup.skippedOtherServices += 1
            }
        }
        try db.rows("playlists", ["uid", "name"], suffix: "ORDER BY display_index, uid") { row in
            guard let uid = row.int(0) else { return }
            backup.playlists.append(LocalPlaylist(name: row.text(1) ?? "Playlist",
                                                  items: playlistItems[uid] ?? []))
        }

        try db.rows("remote_playlists", ["service_id", "name", "url", "thumbnail_url", "uploader",
                                         "stream_count"],
                    suffix: "ORDER BY display_index, uid") { row in
            guard let service = row.int(0), let url = row.text(2) else { return }
            guard NewPipeBackup.isKnownService(Int(service)) else {
                backup.skippedOtherServices += 1
                return
            }
            var item = InfoItem(type: .playlist, serviceId: Int(service), url: url,
                                name: row.text(1) ?? url, thumbnails: image(row.text(3)))
            item.uploaderName = row.text(4)
            item.streamCount = row.int(5)
            backup.savedPlaylists.append(item)
        }

        var groupChannels: [Int64: [String]] = [:]
        try db.rows("feed_group_subscription_join", ["group_id", "subscription_id"]) { row in
            if let group = row.int(0), let id = row.int(1), let url = channelURLs[id] {
                groupChannels[group, default: []].append(url)
            }
        }
        try db.rows("feed_group", ["uid", "name"], suffix: "ORDER BY sort_order, uid") { row in
            guard let uid = row.int(0), let name = row.text(1) else { return }
            backup.feedGroups.append(FeedGroup(name: name, channelURLs: groupChannels[uid] ?? []))
        }

        var seenSearches = Set<String>()
        try db.rows("search_history", ["search", "service_id"],
                    suffix: "ORDER BY creation_date DESC") { row in
            if let search = row.text(0), seenSearches.insert(search).inserted {
                backup.searches.append(search)
            }
        }
        try db.rows("sponsorblock_whitelist", ["uploader"]) { row in
            if let name = row.text(0) { backup.sponsorBlockWhitelist.append(name) }
        }
        return backup
    }
}
#endif
