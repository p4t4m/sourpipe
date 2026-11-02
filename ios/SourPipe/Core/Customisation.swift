import Foundation

/// The actions of a video's long-press menu, after NewPipe's StreamDialogDefaultEntry.
public enum StreamMenuEntry: String, Codable, CaseIterable, Identifiable {
    case background, popup, play, enqueue, enqueueNext, download, addToPlaylist, share
    case openInBrowser, copyLink, markWatched, showChannel

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .background: return "Play in background"
        case .popup: return "Play in popup"
        case .play: return "Play"
        case .enqueue: return "Add to queue"
        case .enqueueNext: return "Play next"
        case .download: return "Download"
        case .addToPlaylist: return "Add to playlist"
        case .share: return "Share"
        case .openInBrowser: return "Open in browser"
        case .copyLink: return "Copy link"
        case .markWatched: return "Mark as watched"
        case .showChannel: return "Show channel details"
        }
    }

    public var symbol: String {
        switch self {
        case .background: return "headphones"
        case .popup: return "pip.enter"
        case .play: return "play"
        case .enqueue: return "text.append"
        case .enqueueNext: return "text.insert"
        case .download: return "arrow.down.circle"
        case .addToPlaylist: return "text.badge.plus"
        case .share: return "square.and.arrow.up"
        case .openInBrowser: return "safari"
        case .copyLink: return "link"
        case .markWatched: return "checkmark.circle"
        case .showChannel: return "person.crop.circle"
        }
    }
}

public struct MenuEntrySetting: Codable, Equatable, Identifiable {
    public var entry: StreamMenuEntry
    public var shown: Bool
    public var id: String { entry.rawValue }

    public init(entry: StreamMenuEntry, shown: Bool = true) {
        self.entry = entry
        self.shown = shown
    }

    /// NewPipe's order. Copy link is off by default, as Share covers it.
    public static let defaults: [MenuEntrySetting] = StreamMenuEntry.allCases.map {
        MenuEntrySetting(entry: $0, shown: $0 != .copyLink)
    }

    /// Keeps the user's order and choices, drops duplicates, and appends entries added since.
    public static func normalised(_ stored: [MenuEntrySetting]) -> [MenuEntrySetting] {
        var seen = Set<StreamMenuEntry>()
        var result = stored.filter { seen.insert($0.entry).inserted }
        result += defaults.filter { !seen.contains($0.entry) }
        return result
    }
}

/// A section of the Home tab, after NewPipe's "Content of main page".
public enum HomePage: Codable, Hashable, Identifiable {
    /// The selected service's sections, with a picker: the original Home tab.
    case serviceSections
    case kiosk(serviceId: Int, id: String)
    case feed
    case subscriptions
    case bookmarks
    case history
    case channel(serviceId: Int, url: String, name: String)
    case playlist(serviceId: Int, url: String, name: String)

    public var id: Self { self }

    public static let defaults: [HomePage] = [.serviceSections]
}

/// Accent colours offered in Settings; the app maps each to a colour.
public enum ThemeColor: String, Codable, CaseIterable, Identifiable {
    case green, red, orange, yellow, mint, teal, blue, indigo, purple, pink

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}
