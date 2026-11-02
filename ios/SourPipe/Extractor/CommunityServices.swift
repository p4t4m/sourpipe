import Foundation

/// The community databases Tubular and PipePipe use. Failures only mean the extras are missing, so
/// they are logged and never interrupt playback.
enum CommunityServices {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        return URLSession(configuration: configuration)
    }()

    static func segments(videoID: String, settings: SponsorBlockSettings) async -> [SponsorSegment] {
        guard let url = SponsorBlockAPI.url(videoID: videoID, settings: settings) else { return [] }
        do {
            let (data, response) = try await session.data(from: url)
            // 404 is how the API says that no video with this prefix has segments.
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
            return try SponsorBlockAPI.segments(from: data, videoID: videoID)
        } catch {
            NSLog("[sponsorblock] %@", error.localizedDescription)
            return []
        }
    }

    static func dislikes(videoID: String, server: String) async -> DislikeCounts? {
        guard let url = ReturnYouTubeDislikeAPI.url(videoID: videoID, server: server) else { return nil }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return try ReturnYouTubeDislikeAPI.counts(from: data)
        } catch {
            NSLog("[dislikes] %@", error.localizedDescription)
            return nil
        }
    }
}
