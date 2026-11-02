import Foundation

// These types decode the JSON produced by extractor/src/bridge/java/sourpipe/bridge/Json.java.

public struct RemoteImage: Codable, Hashable {
    public var url: String
    public var width: Int
    public var height: Int
}

extension Array where Element == RemoteImage {
    /// The smallest image at least `minWidth` wide, or else the largest one. Unknown sizes are -1.
    public func best(minWidth: Int = 320) -> URL? {
        let sorted = self.sorted { $0.width < $1.width }
        let image = sorted.first { $0.width >= minWidth } ?? sorted.last
        return image.flatMap { URL(string: $0.url) }
    }
}

public struct PageToken: Codable, Hashable {
    public var url: String?
    public var id: String?
    public var ids: [String]?
    public var cookies: [String: String]?
    public var body: String?
}

public struct InfoItem: Codable, Hashable, Identifiable {
    public enum Kind: String, Codable { case stream, playlist, channel, comment }

    public var type: Kind
    public var serviceId: Int
    public var url: String
    public var name: String
    public var thumbnails: [RemoteImage]

    // Streams
    public var streamType: String?
    public var uploaderName: String?
    public var uploaderUrl: String?
    public var uploaderAvatars: [RemoteImage]?
    public var uploaderVerified: Bool?
    public var viewCount: Int64?
    public var duration: Int64?
    public var textualUploadDate: String?
    public var uploadDate: Double?
    public var shortDescription: String?
    public var isShort: Bool?

    // Channels and playlists
    public var description: String?
    public var subscriberCount: Int64?
    public var streamCount: Int64?
    public var verified: Bool?

    public var id: String { type.rawValue + ":" + url }

    public var isLive: Bool {
        streamType == "LIVE_STREAM" || streamType == "AUDIO_LIVE_STREAM"
    }

    public init(type: Kind, serviceId: Int, url: String, name: String,
                thumbnails: [RemoteImage] = []) {
        self.type = type
        self.serviceId = serviceId
        self.url = url
        self.name = name
        self.thumbnails = thumbnails
    }
}

public struct CommentItem: Codable, Identifiable, Hashable {
    public var commentId: String?
    public var serviceId: Int
    public var url: String?
    public var text: String?
    public var textType: String?
    public var uploaderName: String?
    public var uploaderUrl: String?
    public var uploaderAvatars: [RemoteImage]?
    public var uploaderVerified: Bool?
    public var textualUploadDate: String?
    public var likeCount: Int?
    public var textualLikeCount: String?
    public var hearted: Bool?
    public var pinned: Bool?
    public var replyCount: Int?
    public var replies: PageToken?

    public var id: String { commentId ?? (uploaderName ?? "") + (text ?? "") }

    /// Plain text; the services may return HTML. Tags are stripped without an HTML engine so this
    /// stays cheap inside long comment lists.
    public var plainText: String { HTMLText.plain(text ?? "", isHTML: textType == "html") }
}

public enum HTMLText {
    public static func plain(_ text: String, isHTML: Bool) -> String {
        guard isHTML else { return text }
        var out = text
            .replacingOccurrences(of: "<br>", with: "\n")
            .replacingOccurrences(of: "<br/>", with: "\n")
            .replacingOccurrences(of: "<br />", with: "\n")
            .replacingOccurrences(of: "</p>", with: "\n\n")
        out = out.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
                                    ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: character)
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct ItemPage: Codable {
    public var items: [InfoItem]
    public var nextPage: PageToken?
    public var name: String?
    public var url: String?
    public var suggestion: String?
    public var corrected: Bool?
    public var errors: [String]?
}

public struct CommentPage: Codable {
    public var items: [CommentItem]
    public var nextPage: PageToken?
    public var disabled: Bool?
    public var count: Int?
}

public struct ChannelTab: Codable, Hashable, Identifiable {
    public var name: String
    public var token: String
    public var id: String { token }
}

public struct ChannelDetails: Codable {
    public var serviceId: Int
    public var url: String
    public var name: String
    public var description: String?
    public var avatars: [RemoteImage]
    public var banners: [RemoteImage]
    public var subscriberCount: Int64?
    public var verified: Bool?
    public var tabs: [ChannelTab]
}

public struct PlaylistDetails: Codable {
    public var serviceId: Int
    public var url: String
    public var name: String
    public var thumbnails: [RemoteImage]
    public var uploaderName: String?
    public var uploaderUrl: String?
    public var streamCount: Int64?
    public var description: String?
    public var items: [InfoItem]
    public var nextPage: PageToken?
}

public struct VideoStreamInfo: Codable, Hashable {
    public var url: String?
    public var delivery: String
    public var format: String?
    public var mime: String?
    public var suffix: String?
    public var resolution: String?
    public var videoOnly: Bool?
    public var itag: Int?
    public var bitrate: Int?
    public var width: Int?
    public var height: Int?
    public var fps: Int?
    public var codec: String?
    public var contentLength: Int64?
}

public struct AudioStreamInfo: Codable, Hashable {
    public var url: String?
    public var delivery: String
    public var format: String?
    public var mime: String?
    public var suffix: String?
    public var averageBitrate: Int?
    public var itag: Int?
    public var codec: String?
    public var trackId: String?
    public var trackName: String?
    public var trackType: String?
    public var contentLength: Int64?
}

public struct SubtitleInfo: Codable, Hashable {
    public var url: String?
    public var languageTag: String?
    public var name: String?
    public var autoGenerated: Bool?
}

public struct StreamSegmentInfo: Codable, Hashable {
    public var title: String?
    public var start: Int
}

public struct StreamDetails: Codable {
    public var serviceId: Int
    public var url: String
    public var id: String?
    public var name: String
    public var streamType: String?
    public var thumbnails: [RemoteImage]
    public var uploaderName: String?
    public var uploaderUrl: String?
    public var uploaderAvatars: [RemoteImage]
    public var uploaderSubscriberCount: Int64?
    public var uploadDate: Double?
    public var textualUploadDate: String?
    public var duration: Int64
    public var viewCount: Int64?
    public var likeCount: Int64?
    public var ageLimit: Int?
    public var description: String?
    public var descriptionType: String?
    public var category: String?
    public var licence: String?
    public var tags: [String]?
    public var hlsUrl: String?
    public var dashMpdUrl: String?
    public var startPosition: Int64?
    public var videoStreams: [VideoStreamInfo]
    public var videoOnlyStreams: [VideoStreamInfo]
    public var audioStreams: [AudioStreamInfo]
    public var subtitles: [SubtitleInfo]
    public var relatedItems: [InfoItem]
    public var segments: [StreamSegmentInfo]

    public var isLive: Bool {
        streamType == "LIVE_STREAM" || streamType == "AUDIO_LIVE_STREAM"
    }

    /// The stream as a list item, used by the queue, history and bookmarks.
    public var asItem: InfoItem {
        var item = InfoItem(type: .stream, serviceId: serviceId, url: url, name: name,
                            thumbnails: thumbnails)
        item.streamType = streamType
        item.uploaderName = uploaderName
        item.uploaderUrl = uploaderUrl
        item.uploaderAvatars = uploaderAvatars
        item.viewCount = viewCount
        item.duration = duration
        item.textualUploadDate = textualUploadDate
        item.uploadDate = uploadDate
        return item
    }
}

public struct ServiceInfo: Codable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var baseUrl: String?
    public var capabilities: [String]
    public var kiosks: [String]
    public var defaultKiosk: String?
    public var searchFilters: [String]
}

public struct ServiceList: Codable {
    public var services: [ServiceInfo]
}

public struct ResolvedLink: Codable {
    public var serviceId: Int
    public var linkType: String
}

public struct SuggestionList: Codable {
    public var suggestions: [String]
}

public struct ExtractorFailure: Error, Codable, LocalizedError {
    public var kind: String
    public var message: String
    /// For "recaptcha": the page to open so the user can solve the challenge.
    public var url: String?

    public init(kind: String, message: String, url: String? = nil) {
        self.kind = kind
        self.message = message
        self.url = url
    }

    public var errorDescription: String? {
        switch kind {
        case "recaptcha":
            return "The service wants a CAPTCHA solved before it answers this network. "
                + "Solve it, or try again later or on another network."
        case "botCheck":
            return "YouTube is refusing anonymous playback from this network. "
                + "Try again later or on another network."
        case "ageRestricted": return "This content is age restricted."
        case "geoRestricted": return "This content is not available in your country."
        case "paid": return "This content must be purchased."
        case "private": return "This content is private."
        case "unavailable": return "This content is not available."
        case "unsupported": return "This content is not supported."
        case "network": return "Network error: \(message)"
        default: return "Extraction failed: \(message)"
        }
    }
}
