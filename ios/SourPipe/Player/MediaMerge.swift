import AVFoundation
import Foundation

/// Builds playable assets from separate or fragmented files, at their real length.
///
/// YouTube's DASH files are fragmented MP4s whose header already states the full length;
/// AVFoundation adds the fragments on top, so they load at twice their length with nothing in the
/// second half. The segment index (`sidx`) near the start of the file gives the real length.
enum MediaMerge {
    /// Video from `video` (if given) and audio from `audio`, cut to the indexed length.
    /// With `expected` (the service's duration in whole seconds) as a fallback cap.
    static func composition(video: URL?, audio: URL?, expected: Double? = nil) async throws
        -> AVMutableComposition {
        let composition = AVMutableComposition()
        var limit: CMTime?
        if let video {
            let (track, length) = try await track(of: .video, in: video, expected: expected)
            limit = length
            try composition.addMutableTrack(withMediaType: .video,
                                            preferredTrackID: kCMPersistentTrackID_Invalid)?
                .insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: .zero)
        }
        if let audio {
            let (track, ownLength) = try await track(of: .audio, in: audio, expected: expected)
            let length = limit.map { min($0, ownLength) } ?? ownLength
            try composition.addMutableTrack(withMediaType: .audio,
                                            preferredTrackID: kCMPersistentTrackID_Invalid)?
                .insertTimeRange(CMTimeRange(start: .zero, duration: length), of: track, at: .zero)
        }
        return composition
    }

    /// One file as an asset: unchanged if ordinary, cut to its real length if fragmented.
    static func asset(for url: URL, expected: Double? = nil) async -> AVAsset {
        let plain = AVURLAsset(url: url)
        if await indexedLength(of: url) == nil {
            // No index read (a failed request, say): still cap a length that is clearly doubled.
            guard let expected, expected > 0,
                  let declared = try? await plain.load(.duration).seconds,
                  declared > expected * 1.5 else { return plain }
        }
        let hasVideo = !((try? await plain.loadTracks(withMediaType: .video)) ?? []).isEmpty
        let hasAudio = !((try? await plain.loadTracks(withMediaType: .audio)) ?? []).isEmpty
        return (try? await composition(video: hasVideo ? url : nil, audio: hasAudio ? url : nil,
                                       expected: expected)) ?? plain
    }

    /// The indexed length if the file is fragmented, or nil for an ordinary file.
    static func indexedLength(of url: URL) async -> Double? {
        let head: Data?
        if url.isFileURL {
            let handle = try? FileHandle(forReadingFrom: url)
            head = try? handle?.read(upToCount: 256 << 10)
            try? handle?.close()
        } else {
            var request = URLRequest(url: url)
            request.setValue("bytes=0-\((256 << 10) - 1)", forHTTPHeaderField: "Range")
            request.setValue(ExtractorEngine.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            head = try? await URLSession.shared.data(for: request).0
        }
        return head.flatMap(MP4Index.duration(of:))
    }

    private static func track(of type: AVMediaType, in url: URL, expected: Double?) async throws
        -> (AVAssetTrack, CMTime) {
        let asset = AVURLAsset(url: url)
        async let indexed = indexedLength(of: url)
        guard let track = try await asset.loadTracks(withMediaType: type).first else {
            throw ExtractorFailure(kind: "unsupported", message: "No \(type.rawValue) track")
        }
        let declared = try await asset.load(.duration)
        var length = declared
        if let seconds = await indexed {
            length = min(length, CMTime(seconds: seconds, preferredTimescale: 600))
        } else if let expected, expected > 0 {
            length = min(length, CMTime(seconds: expected + 1, preferredTimescale: 600))
        }
        NSLog("[player] %@ track: declared %.1fs, using %.1fs", type.rawValue,
              declared.seconds, length.seconds)
        return (track, length)
    }
}
