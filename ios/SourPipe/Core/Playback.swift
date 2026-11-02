import Foundation

/// One way to play a stream. A stream yields several, tried in order until one starts.
public enum PlaybackSource: Equatable {
    /// HLS: AVPlayer picks the quality and it carries its own audio.
    case hls(URL)
    /// A single file with audio and video, or an audio-only file.
    case file(URL, label: String)
    /// Separate video and audio files, combined with AVMutableComposition.
    case merged(video: URL, audio: URL, label: String)

    public var label: String {
        switch self {
        case .hls: return "Adaptive (HLS)"
        case .file(_, let label), .merged(_, _, let label): return label
        }
    }
}

public struct PlaybackPreferences: Equatable {
    public var audioOnly: Bool
    /// 0 means no limit.
    public var maxHeight: Int

    public init(audioOnly: Bool = false, maxHeight: Int = 0) {
        self.audioOnly = audioOnly
        self.maxHeight = maxHeight
    }
}

/// Picks what AVPlayer can decode. WebM, VP9, Opus and (for reliability) AV1 are never chosen.
public enum PlaybackPlanner {
    public static func sources(for stream: StreamDetails,
                               preferences: PlaybackPreferences) -> [PlaybackSource] {
        let audio = audioSources(for: stream)
        let video = videoSources(for: stream, maxHeight: preferences.maxHeight)
        // Audio-only mode still falls back to video when no audio file exists.
        return preferences.audioOnly ? audio + video : video + audio
    }

    public static func playableAudio(in stream: StreamDetails) -> [AudioStreamInfo] {
        // A dubbed track must not win over the original; streams without a type are the original.
        func isOriginal(_ a: AudioStreamInfo) -> Bool {
            a.trackType == nil || a.trackType == "ORIGINAL"
        }
        let candidates = stream.audioStreams.filter { isPlayable(audio: $0) && $0.url != nil }
        let originals = candidates.filter(isOriginal)
        return (originals.isEmpty ? candidates : originals)
            .sorted { ($0.averageBitrate ?? 0) > ($1.averageBitrate ?? 0) }
    }

    private static func isPlayable(audio: AudioStreamInfo) -> Bool {
        let format = (audio.format ?? "").lowercased()
        let codec = (audio.codec ?? "").lowercased()
        if format.contains("webm") || format.contains("opus") || codec.contains("opus")
            || codec.contains("vorbis") || format.contains("ogg") {
            return false
        }
        return true
    }

    private static func isPlayable(video: VideoStreamInfo) -> Bool {
        let format = (video.format ?? "").lowercased()
        let codec = (video.codec ?? "").lowercased()
        if format.contains("webm") || codec.hasPrefix("vp") || codec.hasPrefix("av01") {
            return false
        }
        return true
    }

    private static func height(of video: VideoStreamInfo) -> Int {
        if let h = video.height, h > 0 { return h }
        let digits = (video.resolution ?? "").prefix { $0.isNumber }
        return Int(digits) ?? 0
    }

    /// Highest first within the limit; anything above the limit goes after, lowest first.
    private static func ordered(_ videos: [VideoStreamInfo], maxHeight: Int) -> [VideoStreamInfo] {
        let sorted = videos.sorted { height(of: $0) > height(of: $1) }
        guard maxHeight > 0 else { return sorted }
        let within = sorted.filter { height(of: $0) <= maxHeight }
        let above = sorted.filter { height(of: $0) > maxHeight }.reversed()
        return within + above
    }

    private static func audioSources(for stream: StreamDetails) -> [PlaybackSource] {
        playableAudio(in: stream).compactMap { audio in
            guard let url = audio.url.flatMap(URL.init(string:)) else { return nil }
            if audio.delivery == "HLS" { return .hls(url) }
            let rate = audio.averageBitrate.map { "\($0) kbps " } ?? ""
            return .file(url, label: "Audio \(rate)\(audio.format ?? "")")
        }
    }

    private static func videoSources(for stream: StreamDetails, maxHeight: Int) -> [PlaybackSource] {
        var result: [PlaybackSource] = []
        if let hls = stream.hlsUrl.flatMap(URL.init(string:)) {
            result.append(.hls(hls))
        }
        let muxed = ordered(stream.videoStreams.filter { isPlayable(video: $0) && $0.url != nil },
                            maxHeight: maxHeight)
        for video in muxed {
            guard let url = video.url.flatMap(URL.init(string:)) else { continue }
            if video.delivery == "HLS" {
                result.append(.hls(url))
            } else {
                result.append(.file(url, label: video.resolution ?? "Video"))
            }
        }
        // Keep this list short: every failed attempt costs the user seconds.
        if let audio = playableAudio(in: stream).first(where: { $0.delivery != "HLS" })?.url
            .flatMap(URL.init(string:)) {
            let videoOnly = ordered(
                stream.videoOnlyStreams.filter {
                    isPlayable(video: $0) && $0.url != nil && $0.delivery != "HLS"
                }, maxHeight: maxHeight)
            for video in videoOnly.prefix(2) {
                guard let url = video.url.flatMap(URL.init(string:)) else { continue }
                result.append(.merged(video: url, audio: audio,
                                      label: video.resolution ?? "Video"))
            }
        }
        return result
    }

    /// Choices offered for downloading; the HLS URL expires and cannot be saved as a file.
    public static func downloadOptions(for stream: StreamDetails) -> [PlaybackSource] {
        let files = videoSources(for: stream, maxHeight: 0).filter {
            if case .hls = $0 { return false }
            return true
        }
        let audio = audioSources(for: stream).filter {
            if case .hls = $0 { return false }
            return true
        }
        // videoSources limits merged options for playback; offer every merged quality here.
        var merged: [PlaybackSource] = []
        if let audioURL = playableAudio(in: stream).first(where: { $0.delivery != "HLS" })?.url
            .flatMap(URL.init(string:)) {
            let videos = ordered(stream.videoOnlyStreams.filter {
                isPlayable(video: $0) && $0.url != nil && $0.delivery != "HLS"
            }, maxHeight: 0)
            merged = videos.compactMap { video in
                guard let url = video.url.flatMap(URL.init(string:)) else { return nil }
                return .merged(video: url, audio: audioURL, label: video.resolution ?? "Video")
            }
        }
        let direct = files.filter {
            if case .file = $0 { return true }
            return false
        }
        return direct + merged + audio.prefix(1)
    }
}
