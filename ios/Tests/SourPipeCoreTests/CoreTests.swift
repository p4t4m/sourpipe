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

    func testTimestampsShowOnlyTheDate() {
        XCTAssertEqual(Format.date("2026-10-28T19:28:59.546Z"), "2026-10-28")
        XCTAssertEqual(Format.date("3 days ago"), "3 days ago")
    }

    // MARK: Library file compatibility

    func testLibraryFromTheFirstReleaseKeepsItsDataAndGainsDefaults() throws {
        let old = #"""
        {"settings":{"serviceId":3,"language":"de","country":"DE","maxHeight":720,"audioOnly":true,
         "autoplayRelated":false,"resumePlayback":true,"recordHistory":true,"showComments":true,
         "hideShorts":false},
         "subscriptions":[{"serviceId":0,"url":"u","name":"N"}],
         "history":[{"item":{"type":"stream","serviceId":0,"url":"h","name":"H","thumbnails":[]},
                     "watchedAt":0,"position":12}]}
        """#.data(using: .utf8)!
        let library = try JSONDecoder().decode(LibraryData.self, from: old)
        XCTAssertEqual(library.settings.serviceId, 3)
        XCTAssertEqual(library.settings.maxHeight, 720)
        XCTAssertFalse(library.settings.sponsorBlockEnabled)
        XCTAssertEqual(library.subscriptions.count, 1)
        XCTAssertEqual(library.history.first?.position, 12)
    }

    // MARK: Zip

    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "newpipe-backup", withExtension: "zip",
                                                  subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testZipReadsStoredAndDeflatedEntries() throws {
        let zip = try ZipArchive(fixture())
        XCTAssertEqual(zip.names, ["newpipe.db", "newpipe.settings", "preferences.json", "stored.txt"])
        XCTAssertEqual(String(decoding: try zip.read("stored.txt"), as: UTF8.self), "stored entry")
        XCTAssertEqual(try zip.read("newpipe.db").prefix(15), Data("SQLite format 3".utf8))
        XCTAssertThrowsError(try zip.read("absent"))
    }

    func testZipRejectsDamage() throws {
        XCTAssertThrowsError(try ZipArchive(Data("not a zip at all, but long enough".utf8)))
        var damaged = try fixture()
        let archive = try ZipArchive(damaged)
        XCTAssertNoThrow(try archive.read("newpipe.db"))
        // Flip a byte in the payload of stored.txt, the first entry: 30-byte header, 10-byte name.
        damaged[42] ^= 0xFF
        let broken = try ZipArchive(damaged)
        XCTAssertThrowsError(try broken.names.forEach { _ = try broken.read($0) })
    }

    // MARK: SponsorBlock

    func testSha256MatchesKnownValues() {
        XCTAssertEqual(SHA256Hash.hex("abc"),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256Hash.hex(String(repeating: "a", count: 119)).count, 64)
    }

    func testSponsorBlockUrlUsesOnlyTheHashPrefix() throws {
        var settings = SponsorBlockSettings()
        let url = try XCTUnwrap(SponsorBlockAPI.url(videoID: "abc", settings: settings))
        XCTAssertTrue(url.path.hasSuffix("/api/skipSegments/ba78"))
        XCTAssertFalse(url.absoluteString.contains("abc&"))
        XCTAssertTrue(url.query?.contains("sponsor") == true)
        XCTAssertFalse(url.query?.contains("filler") == true, "off by default")
        for category in SponsorCategory.allCases { settings.modes[category.rawValue] = .off }
        XCTAssertNil(SponsorBlockAPI.url(videoID: "abc", settings: settings))
    }

    func testSponsorBlockKeepsOnlyThisVideo() throws {
        let json = #"""
        [{"videoID":"other","segments":[{"category":"sponsor","actionType":"skip","segment":[1,2],"UUID":"x"}]},
         {"videoID":"mine","segments":[
           {"category":"intro","actionType":"skip","segment":[50,60],"UUID":"b","votes":1},
           {"category":"sponsor","actionType":"skip","segment":[10,20],"UUID":"a"},
           {"category":"poi_highlight","actionType":"poi","segment":[30,30],"UUID":"c"},
           {"category":"sponsor","actionType":"mute","segment":[70,80],"UUID":"m"},
           {"category":"future_kind","actionType":"skip","segment":[90,95],"UUID":"f"}]}]
        """#.data(using: .utf8)!
        let segments = try SponsorBlockAPI.segments(from: json, videoID: "mine")
        XCTAssertEqual(segments.map(\.uuid), ["a", "c", "b"])
        XCTAssertEqual(segments[1].isHighlight, true)
    }

    func testSkipPlanner() {
        var settings = SponsorBlockSettings()
        let sponsor = SponsorSegment(uuid: "s", category: .sponsor, start: 10, end: 20)
        let promo = SponsorSegment(uuid: "p", category: .selfpromo, start: 30, end: 40)
        let intro = SponsorSegment(uuid: "i", category: .intro, start: 0, end: 5)
        let spot = SponsorSegment(uuid: "h", category: .highlight, isHighlight: true, start: 50, end: 50)
        let all = [intro, sponsor, promo, spot]
        func decide(_ at: Double, _ handled: Set<String> = []) -> SkipPlanner.Decision {
            SkipPlanner.decide(position: at, segments: all, settings: settings, handled: handled)
        }
        XCTAssertEqual(decide(2), .none, "category switched off")
        XCTAssertEqual(decide(15), .skip(sponsor))
        XCTAssertEqual(decide(19.9), .none, "a seek that lands just short must not repeat")
        XCTAssertEqual(decide(15, ["s"]), .none, "seeking back lets the user watch it")
        XCTAssertEqual(decide(35), .offer(promo))
        XCTAssertEqual(decide(50), .none, "highlights are jumped to, never skipped")

        func hidden(_ at: Double) -> SkipPlanner.Decision {
            SkipPlanner.decide(position: at, segments: all, settings: settings, handled: [],
                               canShowButton: false)
        }
        XCTAssertEqual(hidden(35), .skip(promo), "no button can be tapped in Picture in Picture")
        XCTAssertEqual(hidden(15), .skip(sponsor))
        XCTAssertEqual(hidden(2), .none, "categories switched off stay off")
        settings.skipAskedWhenHidden = false
        XCTAssertEqual(hidden(35), .none, "plays through, with no button to offer")
    }

    func testDislikeResponse() throws {
        let json = #"{"id":"x","likes":110304,"dislikes":18652,"rating":4.4,"deleted":false}"#
        let counts = try ReturnYouTubeDislikeAPI.counts(from: Data(json.utf8))
        XCTAssertEqual(counts.dislikes, 18652)
        XCTAssertEqual(ReturnYouTubeDislikeAPI.url(videoID: "a b", server: "https://e.com")?.absoluteString,
                       "https://e.com/votes?videoId=a%20b")
    }

    // MARK: Backup import

    private func entry(_ url: String, at seconds: Double, position: Double = 0) -> HistoryEntry {
        HistoryEntry(item: InfoItem(type: .stream, serviceId: 0, url: url, name: url),
                     watchedAt: Date(timeIntervalSince1970: seconds), position: position)
    }

    func testMergeKeepsNewestAndIsRepeatable() {
        var library = LibraryData()
        library.history = [entry("kept", at: 100), entry("updated", at: 50, position: 1)]
        library.playlists = [LocalPlaylist(name: "Mine", items: [
            InfoItem(type: .stream, serviceId: 0, url: "a", name: "a"),
        ])]
        library.searches = ["local"]
        var backup = NewPipeBackup()
        backup.history = [entry("kept", at: 10), entry("updated", at: 90, position: 7), entry("new", at: 70)]
        backup.playlists = [LocalPlaylist(name: "Mine", items: [
            InfoItem(type: .stream, serviceId: 0, url: "a", name: "a"),
            InfoItem(type: .stream, serviceId: 0, url: "b", name: "b"),
        ]), LocalPlaylist(name: "Theirs")]
        backup.searches = ["local", "remote"]
        backup.savedPlaylists = [InfoItem(type: .playlist, serviceId: 0, url: "r", name: "R")]
        backup.feedGroups = [FeedGroup(name: "G", channelURLs: ["c"])]
        backup.sponsorBlockWhitelist = ["Someone"]

        let first = library.merge(backup)
        XCTAssertEqual(library.history.map(\.item.url), ["kept", "updated", "new"])
        XCTAssertEqual(library.history[1].position, 7)
        XCTAssertEqual(library.playlists.first?.items.map(\.url), ["a", "b"])
        XCTAssertEqual(library.playlists.count, 2)
        XCTAssertEqual(library.searches, ["local", "remote"])
        XCTAssertEqual(first.history, 2)
        XCTAssertEqual(library.settings.sponsorBlock.whitelist, ["Someone"])

        let snapshot = library
        let second = library.merge(backup)
        XCTAssertEqual(library, snapshot, "importing twice changes nothing")
        XCTAssertEqual(second.history, 0)
        XCTAssertEqual(second.playlistItems, 0)
    }

    #if canImport(SQLite3)
    func testRealSchemaBackupImports() throws {
        let backup = try NewPipeBackupReader.read(fixture())
        XCTAssertEqual(backup.subscriptions.map(\.name), ["Blender", "Ambient Label"])
        XCTAssertEqual(backup.subscriptions[0].avatar, "https://img/blender.jpg")
        XCTAssertEqual(backup.history.map(\.item.name), ["Sprite Fright", "Agent 327", "Resume only"])
        let first = backup.history[0]
        XCTAssertEqual(first.position, 95.5, "progress_time is in milliseconds")
        XCTAssertEqual(first.repeatCount, 3)
        XCTAssertEqual(first.watchedAt.timeIntervalSince1970, 1_700_000_000)
        XCTAssertEqual(first.item.duration, 629)
        XCTAssertEqual(first.item.streamType, "VIDEO_STREAM")
        XCTAssertEqual(first.item.thumbnails.first?.url, "https://img/sprite.jpg")
        XCTAssertEqual(first.item.uploadDate, 1_600_000_000_000)
        XCTAssertEqual(backup.playlists.map(\.name), ["Favourites", "Empty list"])
        XCTAssertEqual(backup.playlists[0].items.map(\.name), ["Agent 327", "Sprite Fright"],
                       "join_index order, without the duplicate")
        XCTAssertEqual(backup.savedPlaylists.map(\.name), ["Open Movies"])
        XCTAssertEqual(backup.savedPlaylists[0].streamCount, 14)
        XCTAssertEqual(backup.feedGroups.map(\.name), ["Art"])
        XCTAssertEqual(backup.feedGroups[0].channelURLs, ["https://www.youtube.com/channel/blender"])
        XCTAssertEqual(backup.searches, ["newest search", "older search"])
        XCTAssertEqual(backup.sponsorBlockWhitelist, ["Blender"])
        XCTAssertEqual(backup.skippedOtherServices, 3, "BiliBili subscription, list row and remote list")

        var library = LibraryData()
        let summary = library.merge(backup)
        XCTAssertEqual(summary.subscriptions, 2)
        XCTAssertEqual(library.resumePosition(url: first.item.url, duration: 629), 95.5)
    }

    func testBareDatabaseAndWrongFiles() throws {
        let database = try ZipArchive(fixture()).read("newpipe.db")
        XCTAssertEqual(try NewPipeBackupReader.read(database).subscriptions.count, 2)
        XCTAssertThrowsError(try NewPipeBackupReader.read(Data("{}".utf8))) {
            XCTAssertEqual($0 as? NewPipeBackupError, .notABackup)
        }
    }
    #endif

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
