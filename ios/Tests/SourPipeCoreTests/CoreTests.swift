import Foundation
import XCTest
@testable import SourPipeCore

final class CoreTests: XCTestCase {
    private func stream(hls: String? = nil, video: [VideoStreamInfo] = [],
                        videoOnly: [VideoStreamInfo] = [],
                        audio: [AudioStreamInfo] = []) -> StreamDetails {
        StreamDetails(serviceId: 0, url: "https://x/v", id: "v", name: "n", streamType: "VIDEO_STREAM",
                      thumbnails: [], uploaderName: nil, uploaderUrl: nil, uploaderAvatars: [],
                      uploaderSubscriberCount: nil, uploadDate: nil, textualUploadDate: nil,
                      duration: 10, viewCount: nil, likeCount: nil, ageLimit: nil, description: nil,
                      descriptionType: nil, category: nil, licence: nil, tags: nil, hlsUrl: hls,
                      dashMpdUrl: nil, startPosition: nil, videoStreams: video,
                      videoOnlyStreams: videoOnly, audioStreams: audio, subtitles: [],
                      relatedItems: [], segments: [])
    }

    private func video(_ height: Int, format: String = "MPEG-4", codec: String = "avc1.4D401F",
                       only: Bool = false) -> VideoStreamInfo {
        VideoStreamInfo(url: "https://x/\(format)\(height)", delivery: "PROGRESSIVE_HTTP",
                        format: format, resolution: "\(height)p", videoOnly: only, height: height,
                        codec: codec)
    }

    private func audio(_ rate: Int, format: String = "m4a", codec: String = "mp4a.40.2",
                       type: String? = nil) -> AudioStreamInfo {
        AudioStreamInfo(url: "https://x/a\(rate)\(format)", delivery: "PROGRESSIVE_HTTP",
                        format: format, averageBitrate: rate, codec: codec, trackType: type)
    }

    func testHlsIsPreferredForVideo() {
        let s = stream(hls: "https://x/master.m3u8", video: [video(360)], audio: [audio(128)])
        let sources = PlaybackPlanner.sources(for: s, preferences: .init())
        XCTAssertEqual(sources.first, .hls(URL(string: "https://x/master.m3u8")!))
        XCTAssertEqual(sources[1].label, "360p")
    }

    func testAudioOnlyPutsBestAacFirstAndNeverOpus() {
        let s = stream(hls: "https://x/m.m3u8", audio: [
            audio(160, format: "WebM Opus", codec: "opus"), audio(48), audio(128),
        ])
        let sources = PlaybackPlanner.sources(for: s, preferences: .init(audioOnly: true))
        XCTAssertEqual(sources.first, .file(URL(string: "https://x/a128m4a")!,
                                            label: "Audio 128 kbps m4a"))
        XCTAssertFalse(sources.contains { $0.label.contains("Opus") })
    }

    func testVideoOnlyIsMergedWithoutUndecodableCodecs() {
        let s = stream(videoOnly: [
            video(2160, format: "WebM", codec: "vp9", only: true),
            video(1440, codec: "av01.0.12M.08", only: true),
            video(1080, only: true), video(720, only: true), video(480, only: true),
        ], audio: [audio(128)])
        let sources = PlaybackPlanner.sources(for: s, preferences: .init())
        XCTAssertEqual(sources.first, .merged(video: URL(string: "https://x/MPEG-41080")!,
                                              audio: URL(string: "https://x/a128m4a")!,
                                              label: "1080p"))
        XCTAssertEqual(sources.filter {
            if case .merged = $0 { return true }
            return false
        }.count, 2)
    }

    func testMaxHeightOrdersWithinLimitFirst() {
        let s = stream(video: [video(1080), video(720), video(360)])
        let labels = PlaybackPlanner.sources(for: s, preferences: .init(maxHeight: 720))
            .map(\.label)
        XCTAssertEqual(labels, ["720p", "360p", "1080p"])
    }

    func testDubbedAudioDoesNotBeatOriginal() {
        let s = stream(audio: [audio(256, type: "DUBBED"), audio(128, type: "ORIGINAL")])
        XCTAssertEqual(PlaybackPlanner.playableAudio(in: s).map(\.averageBitrate), [128])
    }

    func testDownloadOptionsExcludeHls() {
        let s = stream(hls: "https://x/m.m3u8", videoOnly: [video(1080, only: true)],
                       audio: [audio(128)])
        XCTAssertEqual(PlaybackPlanner.downloadOptions(for: s).map(\.label),
                       ["1080p", "Audio 128 kbps m4a"])
    }

    func testBestImage() {
        let images = [RemoteImage(url: "https://x/1", width: 120, height: 90),
                      RemoteImage(url: "https://x/2", width: 480, height: 360),
                      RemoteImage(url: "https://x/3", width: 1280, height: 720)]
        XCTAssertEqual(images.best()?.absoluteString, "https://x/2")
        XCTAssertEqual(images.best(minWidth: 4000)?.absoluteString, "https://x/3")
        XCTAssertNil([RemoteImage]().best())
    }

    func testFormatting() {
        XCTAssertEqual(Format.duration(59), "0:59")
        XCTAssertEqual(Format.duration(3725), "1:02:05")
        XCTAssertEqual(Format.compact(999), "999")
        XCTAssertEqual(Format.compact(1234), "1.2K")
        XCTAssertEqual(Format.compact(1_000_000), "1M")
        XCTAssertEqual(Format.compact(250_400), "250K")
        XCTAssertNil(Format.compact(-1))
        XCTAssertEqual(Format.kioskTitle("trending_movies_and_shows"), "Movies And Shows")
    }

    func testHtmlIsStripped() {
        XCTAssertEqual(HTMLText.plain("a<br>b &amp; <a href=\"x\">c</a>", isHTML: true), "a\nb & c")
        XCTAssertEqual(HTMLText.plain("a<b", isHTML: false), "a<b")
    }

    func testHistoryMovesToFrontAndResumeRules() {
        var library = LibraryData()
        let a = InfoItem(type: .stream, serviceId: 0, url: "a", name: "A")
        let b = InfoItem(type: .stream, serviceId: 0, url: "b", name: "B")
        library.recordWatch(a, position: 50)
        library.recordWatch(b, position: 3)
        library.recordWatch(a, position: 95)
        XCTAssertEqual(library.history.map(\.item.url), ["a", "b"])
        XCTAssertEqual(library.resumePosition(url: "a", duration: 200), 95)
        XCTAssertNil(library.resumePosition(url: "a", duration: 100), "nearly finished")
        XCTAssertNil(library.resumePosition(url: "b", duration: 100), "barely started")
        XCTAssertNil(library.resumePosition(url: "c", duration: 100))
    }

    func testOlderLibraryFileLoadsWithDefaults() throws {
        let data = #"{"subscriptions":[{"serviceId":0,"url":"u","name":"N"}]}"#.data(using: .utf8)!
        let library = try JSONDecoder().decode(LibraryData.self, from: data)
        XCTAssertEqual(library.subscriptions.count, 1)
        XCTAssertEqual(library.settings, AppSettings())
    }

    func testLibraryRoundTrips() throws {
        var library = LibraryData()
        library.settings.maxHeight = 720
        library.recordSearch(" cats ")
        library.recordWatch(InfoItem(type: .stream, serviceId: 1, url: "u", name: "n"), position: 12)
        let encoded = try JSONEncoder().encode(library)
        let decoded = try JSONDecoder().decode(LibraryData.self, from: encoded)
        XCTAssertEqual(decoded.settings.maxHeight, 720)
        XCTAssertEqual(decoded.searches, ["cats"])
        XCTAssertEqual(decoded.history.first?.position, 12)
    }

    func testNewPipeSubscriptionImportMergesWithoutDuplicates() throws {
        let export = #"""
        {"app_version":"0.27.0","app_version_int":1000,"subscriptions":[
          {"service_id":0,"url":"https://www.youtube.com/channel/A","name":"Zed"},
          {"service_id":1,"url":"https://soundcloud.com/b","name":"Abe"}]}
        """#.data(using: .utf8)!
        var library = LibraryData()
        library.subscriptions = [Subscription(serviceId: 0,
                                              url: "https://www.youtube.com/channel/A", name: "Z")]
        let added = NewPipeImport.merge(try NewPipeImport.subscriptions(from: export), into: &library)
        XCTAssertEqual(added, 1)
        XCTAssertEqual(library.subscriptions.map(\.name), ["Abe", "Z"])
    }

    /// Live bridge output, written by `bun extractor/test/dump-fixtures.mjs <dir>`. Not committed,
    /// because it contains stream URLs tied to the IP address that requested them.
    func testBridgeJsonDecodes() throws {
        guard let dir = ProcessInfo.processInfo.environment["FIXTURE_DIR"] else {
            throw XCTSkip("FIXTURE_DIR not set")
        }
        func load<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name + ".json")
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
        }
        XCTAssertGreaterThanOrEqual(try load("services", as: ServiceList.self).services.count, 5)
        XCTAssertFalse(try load("search", as: ItemPage.self).items.isEmpty)
        XCTAssertFalse(try load("kiosk", as: ItemPage.self).items.isEmpty)
        XCTAssertFalse(try load("channel", as: ChannelDetails.self).tabs.isEmpty)
        XCTAssertFalse(try load("channelTab", as: ItemPage.self).items.isEmpty)
        XCTAssertFalse(try load("playlist", as: PlaylistDetails.self).items.isEmpty)
        XCTAssertFalse(try load("comments", as: CommentPage.self).items.isEmpty)
        let yt = try load("streamYoutube", as: StreamDetails.self)
        let plan = PlaybackPlanner.sources(for: yt, preferences: .init())
        XCTAssertFalse(plan.isEmpty)
        if case .hls = plan[0] {} else { XCTFail("YouTube should start with HLS: \(plan[0])") }
        XCTAssertFalse(PlaybackPlanner.sources(for: yt, preferences: .init(audioOnly: true)).isEmpty)
        for name in ["streamSoundcloud", "streamPeertube", "streamBandcamp", "streamMediaccc"] {
            let details = try load(name, as: StreamDetails.self)
            XCTAssertFalse(PlaybackPlanner.sources(for: details, preferences: .init()).isEmpty, name)
        }
    }
}
