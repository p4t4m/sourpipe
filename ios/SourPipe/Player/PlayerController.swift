@preconcurrency import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// The single app-wide player: a queue, source fallback, background audio and lock-screen controls.
@MainActor
final class PlayerController: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    /// NewPipe's three players: the main one, audio only in the background, and the popup,
    /// which on iOS is Picture in Picture.
    enum PlayMode {
        case normal, background, popup
    }

    struct QueueEntry: Identifiable, Equatable {
        let id = UUID()
        let item: InfoItem
        /// Set for downloaded files, which need no extraction.
        var localFile: URL?

        static func == (a: QueueEntry, b: QueueEntry) -> Bool { a.id == b.id }
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var queue: [QueueEntry] = []
    @Published private(set) var index = 0
    @Published private(set) var details: StreamDetails?
    @Published private(set) var isPlaying = false
    @Published private(set) var sourceLabel = ""
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var isAudioOnly = false
    @Published private(set) var segments: [SponsorSegment] = []
    /// A segment the user can skip with a button.
    @Published private(set) var offeredSkip: SponsorSegment?
    /// The segment just skipped automatically, shown briefly with an undo.
    @Published private(set) var recentSkip: SponsorSegment?

    /// Set when playback should move into Picture in Picture; PopupHost starts it and clears it.
    @Published var popupRequested = false
    /// Set to ask PopupHost to end the popup, so that only one player shows the video.
    @Published var popupCloseRequested = false
    /// Playing in the popup now. The video page shows a placeholder instead of a second copy.
    @Published private(set) var isInPopup = false

    func popupDidChange(_ active: Bool) {
        isInPopup = active
        isInPictureInPicture = active
    }

    /// NewPipe moves a video back from the popup when the main player opens; so does this.
    func closePopup() {
        if isInPopup { popupCloseRequested = true }
    }

    var isPlayingDownload: Bool { current?.localFile != nil }

    let player = AVPlayer()
    var isInPictureInPicture = false {
        didSet { NSLog("[player] picture in picture: %d", isInPictureInPicture ? 1 : 0) }
    }

    private let store: AppStore
    private var sources: [PlaybackSource] = []
    private var sourceIndex = 0
    private var loadTask: Task<Void, Never>?
    private var itemObservers: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var rateObserver: NSKeyValueObservation?
    private var lastSavedPosition: Double = 0
    private var artwork: MPMediaItemArtwork?
    private var handledSegments = Set<String>()
    private var segmentTask: Task<Void, Never>?
    private var recentSkipTask: Task<Void, Never>?

    var current: QueueEntry? { queue.indices.contains(index) ? queue[index] : nil }
    var hasNext: Bool { index + 1 < queue.count }
    var hasPrevious: Bool { index > 0 }

    init(store: AppStore) {
        self.store = store
        isAudioOnly = store.library.settings.audioOnly
        player.allowsExternalPlayback = true
        configureAudioSession()
        configureRemoteCommands()
        rateObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                self?.isPlaying = playing
                self?.updateNowPlaying()
            }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time) }
        }
    }

    // MARK: Queue

    func play(_ item: InfoItem, mode: PlayMode = .normal) {
        play([item], startingAt: 0, mode: mode)
    }

    func play(_ items: [InfoItem], startingAt start: Int, mode: PlayMode = .normal) {
        let entries = items.filter { $0.type == .stream }.map { QueueEntry(item: $0) }
        guard !entries.isEmpty else { return }
        switch mode {
        case .normal: isAudioOnly = store.library.settings.audioOnly
        case .background: isAudioOnly = true
        case .popup: isAudioOnly = false
        }
        setQueue(entries, start: start)
        popupRequested = mode == .popup
    }

    func playDownload(_ record: DownloadRecord) {
        let file = AppStore.documents.appendingPathComponent(record.fileName)
        // An audio file gets the artwork and the app's own controls.
        isAudioOnly = record.isAudio
        setQueue([QueueEntry(item: record.item, localFile: file)], start: 0)
    }

    func enqueue(_ item: InfoItem) {
        if queue.isEmpty {
            play(item)
        } else {
            queue.append(QueueEntry(item: item))
        }
    }

    func enqueueNext(_ item: InfoItem) {
        if queue.isEmpty {
            play(item)
        } else {
            queue.insert(QueueEntry(item: item), at: index + 1)
        }
    }

    func removeFromQueue(at offsets: IndexSet) {
        let removingCurrent = offsets.contains(index)
        let before = offsets.filter { $0 < index }.count
        for offset in offsets.reversed() { queue.remove(at: offset) }
        index -= before
        if removingCurrent {
            if queue.isEmpty {
                stop()
            } else {
                index = min(index, queue.count - 1)
                loadCurrent()
            }
        }
    }

    func jump(to entry: QueueEntry) {
        guard let target = queue.firstIndex(of: entry) else { return }
        savePosition()
        index = target
        loadCurrent()
    }

    func next() {
        guard hasNext else { return }
        savePosition()
        index += 1
        loadCurrent()
    }

    func previous() {
        if position > 5 || !hasPrevious {
            seek(to: 0)
        } else {
            savePosition()
            index -= 1
            loadCurrent()
        }
    }

    func stop() {
        savePosition()
        loadTask?.cancel()
        player.replaceCurrentItem(with: nil)
        clearItemObservers()
        queue = []
        index = 0
        details = nil
        state = .idle
        position = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        artwork = nil
        clearSegments()
    }

    private func setQueue(_ entries: [QueueEntry], start: Int) {
        guard !entries.isEmpty else { return }
        savePosition()
        queue = entries
        index = min(max(start, 0), entries.count - 1)
        loadCurrent()
    }

    // MARK: Loading

    /// Same stream as the one the user is looking at? Then the page must not restart it.
    func isCurrent(url: String) -> Bool {
        current?.item.url == url
    }

    func setAudioOnly(_ audioOnly: Bool) {
        guard audioOnly != isAudioOnly else { return }
        isAudioOnly = audioOnly
        guard let details, current?.localFile == nil else { return }
        let resume = position
        sources = PlaybackPlanner.sources(for: details, preferences: preferences())
        sourceIndex = 0
        startSource(resumeAt: resume)
    }

    func setMaxHeight(_ height: Int) {
        var settings = store.library.settings
        settings.maxHeight = height
        store.library.settings = settings
        guard let details, current?.localFile == nil else { return }
        applyQualityLimit()
        // An HLS item changes quality live; file sources need another URL.
        if case .hls = currentSource { return }
        let resume = position
        sources = PlaybackPlanner.sources(for: details, preferences: preferences())
        sourceIndex = 0
        startSource(resumeAt: resume)
    }

    private var currentSource: PlaybackSource? {
        sources.indices.contains(sourceIndex) ? sources[sourceIndex] : nil
    }

    private func preferences() -> PlaybackPreferences {
        PlaybackPreferences(audioOnly: isAudioOnly, maxHeight: store.library.settings.maxHeight)
    }

    private func loadCurrent() {
        guard let entry = current else { return }
        loadTask?.cancel()
        player.replaceCurrentItem(with: nil)
        clearItemObservers()
        details = nil
        state = .loading
        sourceLabel = ""
        position = 0
        duration = Double(entry.item.duration ?? 0)
        artwork = nil
        clearSegments()
        activateAudioSession()
        updateNowPlaying()

        if let file = entry.localFile {
            sources = [.file(file, label: "Downloaded")]
            sourceIndex = 0
            record(entry.item)
            startSource(resumeAt: resumePosition(for: entry.item))
            loadArtwork(from: entry.item.thumbnails.best(minWidth: 480))
            return
        }

        loadTask = Task { [weak self] in
            do {
                let details = try await Extractor.stream(serviceId: entry.item.serviceId,
                                                         url: entry.item.url)
                guard let self, !Task.isCancelled, self.current?.id == entry.id else { return }
                self.details = details
                self.sources = PlaybackPlanner.sources(for: details, preferences: self.preferences())
                self.sourceIndex = 0
                self.loadArtwork(from: details.thumbnails.best(minWidth: 480))
                guard !self.sources.isEmpty else {
                    self.state = .failed("No stream that iOS can play was found.")
                    return
                }
                self.record(details.asItem)
                self.loadSegments(for: details, entry: entry)
                let start = details.startPosition.map(Double.init).flatMap { $0 > 0 ? $0 : nil }
                self.startSource(resumeAt: start ?? self.resumePosition(for: details.asItem))
            } catch {
                guard let self, !Task.isCancelled, self.current?.id == entry.id else { return }
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    private func resumePosition(for item: InfoItem) -> Double {
        guard store.library.settings.resumePlayback, !item.isLive else { return 0 }
        return store.library.resumePosition(url: item.url, duration: Double(item.duration ?? 0)) ?? 0
    }

    private func record(_ item: InfoItem) {
        guard store.library.settings.recordHistory else { return }
        let existing = store.library.history.first { $0.item.url == item.url }?.position ?? 0
        store.library.recordWatch(item, position: existing)
    }

    private func startSource(resumeAt seconds: Double) {
        guard let source = currentSource else {
            state = .failed("None of the available streams could be played.")
            return
        }
        sourceLabel = source.label
        clearItemObservers()
        switch source {
        case .hls(let url), .file(let url, _):
            attach(AVPlayerItem(asset: AVURLAsset(url: url)), resumeAt: seconds)
        case .merged(let video, let audio, _):
            let expected = current?.id
            loadTask = Task { [weak self] in
                do {
                    let asset = try await Self.mergedAsset(video: video, audio: audio)
                    guard let self, !Task.isCancelled, self.current?.id == expected else { return }
                    self.attach(AVPlayerItem(asset: asset), resumeAt: seconds)
                } catch {
                    guard let self, !Task.isCancelled, self.current?.id == expected else { return }
                    NSLog("[player] merge failed: %@", error.localizedDescription)
                    self.tryNextSource(resumeAt: seconds)
                }
            }
        }
    }

    nonisolated private static func mergedAsset(video: URL, audio: URL) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ExtractorFailure(kind: "unsupported", message: "Stream has no usable track")
        }
        let length = try await videoAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: length)
        let audioRange = CMTimeRange(start: .zero,
                                     duration: min(length, try await audioAsset.load(.duration)))
        try composition.addMutableTrack(withMediaType: .video,
                                        preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: videoTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio,
                                        preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(audioRange, of: audioTrack, at: .zero)
        return composition
    }

    private func attach(_ item: AVPlayerItem, resumeAt seconds: Double) {
        applyQualityLimit(to: item)
        itemObservers.append(item.observe(\.status, options: [.new]) { [weak self] item, _ in
            let status = item.status
            let error = item.error?.localizedDescription
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                switch status {
                case .readyToPlay:
                    self.state = .ready
                    NSLog("[player] ready: %@", self.sourceLabel)
                    self.updateDuration(from: item)
                    self.updateNowPlaying()
                case .failed:
                    NSLog("[player] %@ failed: %@", self.sourceLabel, error ?? "unknown")
                    self.tryNextSource(resumeAt: self.position > 0 ? self.position : seconds)
                default:
                    break
                }
            }
        })
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishedCurrent() }
        }
        player.replaceCurrentItem(with: item)
        if seconds > 0 {
            item.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                      completionHandler: nil)
        }
        player.play()
    }

    private func tryNextSource(resumeAt seconds: Double) {
        sourceIndex += 1
        startSource(resumeAt: seconds)
    }

    private func applyQualityLimit(to item: AVPlayerItem? = nil) {
        guard let item = item ?? player.currentItem else { return }
        let height = store.library.settings.maxHeight
        item.preferredMaximumResolution = height > 0
            ? CGSize(width: CGFloat(height) * 16 / 9, height: CGFloat(height)) : .zero
    }

    private func clearItemObservers() {
        itemObservers.removeAll()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    private func finishedCurrent() {
        if let url = current?.item.url {
            store.library.updatePosition(url: url, position: 0)
        }
        if hasNext {
            index += 1
            loadCurrent()
        } else if store.library.settings.autoplayRelated,
                  let next = details?.relatedItems.first(where: { $0.type == .stream }) {
            queue.append(QueueEntry(item: next))
            index += 1
            loadCurrent()
        }
    }

    // MARK: Transport

    func togglePlayPause() {
        if player.timeControlStatus == .paused {
            activateAudioSession()
            player.play()
        } else {
            player.pause()
            savePosition()
        }
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(seconds, 0), preferredTimescale: 600))
        position = max(seconds, 0)
        updateNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: position + seconds)
    }

    private func tick(_ time: CMTime) {
        guard time.isNumeric else { return }
        position = time.seconds
        applySkips()
        if let item = player.currentItem { updateDuration(from: item) }
        if abs(position - lastSavedPosition) >= 10 { savePosition() }
    }

    private func updateDuration(from item: AVPlayerItem) {
        let length = item.duration
        if length.isNumeric, length.seconds > 0 { duration = length.seconds }
    }

    func savePosition() {
        guard let item = current?.item, !item.isLive, store.library.settings.recordHistory,
              position > 0 else { return }
        lastSavedPosition = position
        store.library.updatePosition(url: item.url, position: position)
    }

    // MARK: SponsorBlock

    private func clearSegments() {
        segmentTask?.cancel()
        recentSkipTask?.cancel()
        segments = []
        handledSegments = []
        offeredSkip = nil
        recentSkip = nil
    }

    private func loadSegments(for details: StreamDetails, entry: QueueEntry) {
        let settings = store.library.settings
        guard settings.sponsorBlockEnabled, details.serviceId == 0, !details.isLive,
              let videoID = details.id,
              !settings.sponsorBlock.whitelist.contains(details.uploaderName ?? "") else { return }
        segmentTask = Task { [weak self] in
            let found = await CommunityServices.segments(videoID: videoID,
                                                         settings: settings.sponsorBlock)
            guard let self, !Task.isCancelled, self.current?.id == entry.id else { return }
            self.segments = found
        }
    }

    /// False in Picture in Picture and in the background, where the skip button is out of reach.
    private var canShowSkipButton: Bool {
        !isInPictureInPicture && UIApplication.shared.applicationState == .active
    }

    private func applySkips() {
        #if DEBUG
        injectTestSegments()
        #endif
        guard !segments.isEmpty else { return }
        switch SkipPlanner.decide(position: position, segments: segments,
                                  settings: store.library.settings.sponsorBlock,
                                  handled: handledSegments, canShowButton: canShowSkipButton) {
        case .skip(let segment):
            handledSegments.insert(segment.uuid)
            offeredSkip = nil
            NSLog("[player] skipping %@ %.1f to %.1f, at %.1f, app state %d, pip %d",
                  segment.category.rawValue, segment.start, segment.end, position,
                  UIApplication.shared.applicationState.rawValue, isInPictureInPicture ? 1 : 0)
            seek(to: segment.end)
            recentSkip = segment
            recentSkipTask?.cancel()
            recentSkipTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if !Task.isCancelled { self?.recentSkip = nil }
            }
        case .offer(let segment):
            offeredSkip = segment
        case .none:
            offeredSkip = nil
        }
    }

    #if DEBUG
    /// CI cannot play YouTube, so `-testSkipAfter <seconds>` adds segments to any stream.
    private func injectTestSegments() {
        let delay = UserDefaults.standard.double(forKey: "testSkipAfter")
        guard delay > 0, segments.isEmpty, handledSegments.isEmpty, position > 0 else { return }
        segments = [
            SponsorSegment(uuid: "test-sponsor", category: .sponsor,
                           start: position + delay, end: position + delay + 10),
            SponsorSegment(uuid: "test-ask", category: .selfpromo,
                           start: position + delay + 20, end: position + delay + 30),
        ]
        NSLog("[player] test segments added at %.1f", position)
    }
    #endif

    func acceptOfferedSkip() {
        guard let segment = offeredSkip else { return }
        handledSegments.insert(segment.uuid)
        offeredSkip = nil
        seek(to: segment.end)
    }

    func undoRecentSkip() {
        guard let segment = recentSkip else { return }
        recentSkipTask?.cancel()
        recentSkip = nil
        seek(to: segment.start)
    }

    /// Whether a channel's segments apply. Takes effect at once for the video playing now.
    func setWhitelisted(_ whitelisted: Bool, uploader: String) {
        store.library.settings.sponsorBlock.whitelist.removeAll { $0 == uploader }
        if whitelisted {
            store.library.settings.sponsorBlock.whitelist.append(uploader)
            clearSegments()
        } else if let details, let entry = current, details.uploaderName == uploader {
            loadSegments(for: details, entry: entry)
        }
    }

    // MARK: System integration

    private func configureAudioSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    private func activateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func handle(_ command: MPRemoteCommand, _ action: @escaping @MainActor () -> Void) {
            command.addTarget { _ in
                Task { @MainActor in action() }
                return .success
            }
        }
        handle(center.playCommand) { [weak self] in self?.player.play() }
        handle(center.pauseCommand) { [weak self] in self?.player.pause() }
        handle(center.togglePlayPauseCommand) { [weak self] in self?.togglePlayPause() }
        handle(center.nextTrackCommand) { [weak self] in self?.next() }
        handle(center.previousTrackCommand) { [weak self] in self?.previous() }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let target = event.positionTime
            Task { @MainActor in self?.seek(to: target) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let entry = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: details?.name ?? entry.item.name,
            MPMediaItemPropertyArtist: details?.uploaderName ?? entry.item.uploaderName ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: Double(player.rate),
            MPNowPlayingInfoPropertyIsLiveStream: entry.item.isLive || details?.isLive == true,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(from url: URL?) {
        guard let url else { return }
        let entryId = current?.id
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data),
                  let self, self.current?.id == entryId else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.updateNowPlaying()
        }
    }
}
