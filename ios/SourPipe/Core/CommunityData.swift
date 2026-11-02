import Foundation

public enum SkipMode: String, Codable, CaseIterable {
    case off, offer, automatic
}

public enum SponsorCategory: String, Codable, CaseIterable, Identifiable {
    case sponsor, selfpromo, interaction, intro, outro, preview, filler
    case musicOfftopic = "music_offtopic"
    case highlight = "poi_highlight"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sponsor: return "Sponsor"
        case .selfpromo: return "Self-promotion"
        case .interaction: return "Interaction reminder"
        case .intro: return "Intro"
        case .outro: return "Outro"
        case .preview: return "Preview or recap"
        case .filler: return "Filler"
        case .musicOfftopic: return "Non-music section"
        case .highlight: return "Highlight"
        }
    }

    public var defaultMode: SkipMode {
        switch self {
        case .sponsor: return .automatic
        case .selfpromo, .interaction, .highlight: return .offer
        default: return .off
        }
    }
}

public struct SponsorSegment: Codable, Hashable, Identifiable {
    public var uuid: String
    public var category: SponsorCategory
    public var isHighlight: Bool
    public var start: Double
    public var end: Double
    public var id: String { uuid }

    public init(uuid: String, category: SponsorCategory, isHighlight: Bool = false,
                start: Double, end: Double) {
        self.uuid = uuid
        self.category = category
        self.isHighlight = isHighlight
        self.start = start
        self.end = end
    }
}

public struct SponsorBlockSettings: Codable, Equatable {
    public static let defaultServer = "https://sponsor.ajay.app/api/"

    public var server = SponsorBlockSettings.defaultServer
    public var modes: [String: SkipMode] = [:]
    /// Uploader names, matching the whitelist in a Tubular backup.
    public var whitelist: [String] = []
    /// A skip button cannot be tapped in Picture in Picture or from the lock screen, so "ask"
    /// segments are skipped there instead of playing through.
    public var skipAskedWhenHidden = true

    public init() {}

    public func mode(for category: SponsorCategory) -> SkipMode {
        modes[category.rawValue] ?? category.defaultMode
    }

    enum CodingKeys: CodingKey { case server, modes, whitelist, skipAskedWhenHidden }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        server = try c.decodeIfPresent(String.self, forKey: .server) ?? Self.defaultServer
        modes = try c.decodeIfPresent([String: SkipMode].self, forKey: .modes) ?? [:]
        whitelist = try c.decodeIfPresent([String].self, forKey: .whitelist) ?? []
        skipAskedWhenHidden = try c.decodeIfPresent(Bool.self, forKey: .skipAskedWhenHidden) ?? true
    }
}

public enum SponsorBlockAPI {
    /// The hash prefix means the server never learns which video is being watched.
    public static func url(videoID: String, settings: SponsorBlockSettings) -> URL? {
        let categories = SponsorCategory.allCases.filter { settings.mode(for: $0) != .off }
        guard !categories.isEmpty else { return nil }
        var base = settings.server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasSuffix("/") { base += "/" }
        guard var components = URLComponents(
            string: base + "skipSegments/" + SHA256Hash.hex(videoID).prefix(4)) else { return nil }
        let names = categories.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        components.queryItems = [
            URLQueryItem(name: "categories", value: "[\(names)]"),
            URLQueryItem(name: "actionTypes", value: "[\"skip\",\"poi\"]"),
        ]
        return components.url
    }

    private struct Video: Decodable {
        struct Segment: Decodable {
            var category: String
            var actionType: String?
            var segment: [Double]
            var UUID: String
        }
        var videoID: String
        var segments: [Segment]
    }

    /// The response lists every video sharing the prefix; only this video's segments are kept.
    public static func segments(from data: Data, videoID: String) throws -> [SponsorSegment] {
        let videos = try JSONDecoder().decode([Video].self, from: data)
        return videos.filter { $0.videoID == videoID }.flatMap(\.segments).compactMap { raw in
            guard raw.segment.count == 2,
                  let category = SponsorCategory(rawValue: raw.category) else { return nil }
            let isHighlight = raw.actionType == "poi" || category == .highlight
            guard isHighlight || raw.actionType == nil || raw.actionType == "skip" else { return nil }
            return SponsorSegment(uuid: raw.UUID, category: category, isHighlight: isHighlight,
                                  start: raw.segment[0], end: raw.segment[1])
        }.sorted { $0.start < $1.start }
    }
}

public enum SkipPlanner {
    public enum Decision: Equatable {
        case none
        case skip(SponsorSegment)
        case offer(SponsorSegment)
    }

    /// `handled` holds segments already skipped or dismissed, so that seeking back into one lets
    /// the user watch it.
    public static func decide(position: Double, segments: [SponsorSegment],
                              settings: SponsorBlockSettings, handled: Set<String>,
                              canShowButton: Bool = true) -> Decision {
        var offer: SponsorSegment?
        for segment in segments where !segment.isHighlight && !handled.contains(segment.uuid) {
            // The margin stops an imprecise seek from landing just before the end and repeating.
            guard position >= segment.start, position < segment.end - 0.3 else { continue }
            switch settings.mode(for: segment.category) {
            case .automatic: return .skip(segment)
            case .offer:
                if !canShowButton && settings.skipAskedWhenHidden { return .skip(segment) }
                if canShowButton { offer = offer ?? segment }
            case .off: break
            }
        }
        return offer.map(Decision.offer) ?? .none
    }
}

public struct DislikeCounts: Codable, Equatable {
    public var likes: Int64?
    public var dislikes: Int64?
}

public enum ReturnYouTubeDislikeAPI {
    public static let defaultServer = "https://returnyoutubedislikeapi.com/"

    public static func url(videoID: String, server: String) -> URL? {
        var base = server.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.hasSuffix("/") { base += "/" }
        guard var components = URLComponents(string: base + "votes") else { return nil }
        components.queryItems = [URLQueryItem(name: "videoId", value: videoID)]
        return components.url
    }

    public static func counts(from data: Data) throws -> DislikeCounts {
        try JSONDecoder().decode(DislikeCounts.self, from: data)
    }
}
