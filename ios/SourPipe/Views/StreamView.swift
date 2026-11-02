import SwiftUI

/// The video page: player, details, comments and related items.
struct StreamView: View {
    let item: InfoItem
    /// Starts playback when the page opens; the mini player's page passes false.
    var autoplay = true

    @EnvironmentObject private var player: PlayerController
    @State private var loaded: StreamDetails?
    @State private var error: String?
    @State private var started = false

    private var isCurrent: Bool { player.isCurrent(url: item.url) }

    /// The player area shows this failure, so the list below must not keep spinning.
    private var hasFailed: Bool {
        if isCurrent, case .failed = player.state { return true }
        return false
    }

    /// What is on screen: the player's copy while this stream is playing.
    private var details: StreamDetails? {
        if isCurrent, let playing = player.details { return playing }
        return loaded
    }

    var body: some View {
        VStack(spacing: 0) {
            playerArea
            List {
                if let details {
                    StreamDetailsSection(details: details)
                } else if let error, !isCurrent {
                    StatusView(title: "Could not load this stream", message: error) {
                        Task { await load() }
                    }
                } else if !hasFailed {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle(details?.name ?? item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !started else { return }
            started = true
            if isCurrent { return }
            if autoplay {
                player.play(item)
            } else {
                await load()
            }
        }
        // Coming back to a page after another stream took over: show its details, not a spinner.
        .task(id: isCurrent) {
            if !isCurrent, loaded == nil, started { await load() }
        }
    }

    private var artworkURL: URL? {
        (details?.thumbnails ?? item.thumbnails).best(minWidth: 640)
    }

    @ViewBuilder private var playerArea: some View {
        ZStack {
            Color.black
            if isCurrent {
                switch player.state {
                case .failed(let message):
                    VStack(spacing: 8) {
                        Text(message)
                            .font(.footnote)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Button("Try again") { player.play(item) }
                            .buttonStyle(.bordered)
                            .tint(.white)
                    }
                    .padding()
                case .idle:
                    EmptyView()
                case .loading, .ready:
                    if player.isAudioOnly {
                        Thumbnail(url: artworkURL).opacity(0.5)
                        audioControls
                    } else {
                        VideoPlayerView(player: player.player) { active in
                            player.isInPictureInPicture = active
                        }
                    }
                    if player.state == .loading {
                        ProgressView().tint(.white)
                    }
                }
            } else {
                Thumbnail(url: artworkURL)
                Button {
                    player.play(item)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.white)
                }
                .accessibilityLabel("Play")
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .topTrailing) {
            if isCurrent { SkipBanner() }
        }
    }

    /// Audio mode has no system player controls, so it brings its own.
    private var audioControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 32) {
                Button { player.previous() } label: { Image(systemName: "backward.end.fill") }
                    .accessibilityLabel("Previous")
                Button { player.skip(by: -10) } label: { Image(systemName: "gobackward.10") }
                    .accessibilityLabel("Back 10 seconds")
                Button { player.togglePlayPause() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                }
                .font(.largeTitle)
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                Button { player.skip(by: 10) } label: { Image(systemName: "goforward.10") }
                    .accessibilityLabel("Forward 10 seconds")
                Button { player.next() } label: { Image(systemName: "forward.end.fill") }
                    .disabled(!player.hasNext)
                    .accessibilityLabel("Next")
            }
            .font(.title2)
            .foregroundColor(.white)
            if player.duration > 0 {
                Slider(value: Binding(get: { player.position }, set: { player.seek(to: $0) }),
                       in: 0...max(player.duration, 1))
                    .tint(.white)
                    .padding(.horizontal)
                Text("\(Format.duration(Int64(player.position))) / \(Format.duration(Int64(player.duration)))")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        }
    }

    private func load() async {
        do {
            error = nil
            loaded = try await Extractor.stream(serviceId: item.serviceId, url: item.url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct StreamDetailsSection: View {
    let details: StreamDetails
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager
    @State private var pane = Pane.related
    @State private var showDescription = false
    @State private var dislikes: DislikeCounts?

    enum Pane: String, CaseIterable {
        case related = "Related", comments = "Comments", queue = "Queue"
    }

    private var isCurrent: Bool { player.isCurrent(url: details.url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(details.name).font(.headline)
            Text(statistics).font(.caption).foregroundColor(.secondary)
        }
        // On a row that really renders: a List never shows an EmptyView, whose task would not run.
        .task(id: "\(details.url)/\(store.library.settings.dislikesEnabled)") {
            await loadDislikes()
        }
        actionRow
        uploaderRow
        sponsorBlockRows
        if let description = details.description, !description.isEmpty {
            DisclosureGroup("Description", isExpanded: $showDescription) {
                Text(HTMLText.plain(description, isHTML: details.descriptionType == "html"))
                    .font(.footnote)
                    .textSelection(.enabled)
            }
        }
        if !details.segments.isEmpty {
            DisclosureGroup("Chapters") {
                ForEach(details.segments, id: \.start) { segment in
                    Button {
                        if isCurrent { player.seek(to: Double(segment.start)) }
                    } label: {
                        HStack {
                            Text(Format.duration(Int64(max(segment.start, 1))))
                                .font(.caption.monospacedDigit())
                            Text(segment.title ?? "")
                                .font(.footnote)
                        }
                    }
                }
            }
        }
        Picker("Section", selection: $pane) {
            ForEach(Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .listRowSeparator(.hidden)
        switch pane {
        case .related:
            ForEach(uniqueRelated) { LinkedItemRow(item: $0) }
        case .comments:
            CommentsSection(serviceId: details.serviceId, url: details.url)
        case .queue:
            QueueSection()
        }
    }

    private func loadDislikes() async {
        let settings = store.library.settings
        var videoID = settings.dislikesEnabled && details.serviceId == 0 ? details.id : nil
        #if DEBUG
        // CI cannot open YouTube videos, so it borrows a known ID on another service's page.
        videoID = UserDefaults.standard.string(forKey: "testDislikeVideoID") ?? videoID
        #endif
        guard let videoID else {
            dislikes = nil
            return
        }
        dislikes = await CommunityServices.dislikes(videoID: videoID, server: settings.dislikesServer)
    }

    @ViewBuilder private var sponsorBlockRows: some View {
        let settings = store.library.settings
        if settings.sponsorBlockEnabled, details.serviceId == 0, let uploader = details.uploaderName {
            if isCurrent, !player.segments.isEmpty {
                DisclosureGroup("SponsorBlock (\(player.segments.count))") {
                    ForEach(player.segments) { segment in
                        Button {
                            player.seek(to: segment.start)
                        } label: {
                            HStack {
                                Text(Format.duration(Int64(max(segment.start, 1))))
                                    .font(.caption.monospacedDigit())
                                Text(segment.category.title).font(.footnote)
                            }
                        }
                    }
                }
            }
            Toggle("Skip segments on this channel", isOn: Binding(
                get: { !settings.sponsorBlock.whitelist.contains(uploader) },
                set: { player.setWhitelisted(!$0, uploader: uploader) }
            ))
            .font(.footnote)
        }
    }

    private var uniqueRelated: [InfoItem] {
        var seen = Set<String>()
        return details.relatedItems.filter { seen.insert($0.id).inserted }
    }

    private var statistics: String {
        var parts: [String] = []
        if let views = Format.views(details.viewCount) { parts.append(views) }
        let likes = (details.likeCount ?? -1) >= 0 ? details.likeCount : dislikes?.likes
        if let likes = Format.compact(likes) { parts.append(likes + " likes") }
        if let count = Format.compact(dislikes?.dislikes) { parts.append(count + " dislikes") }
        if let date = details.textualUploadDate, !date.isEmpty { parts.append(Format.date(date)) }
        if isCurrent, !player.sourceLabel.isEmpty { parts.append(player.sourceLabel) }
        return parts.joined(separator: " • ")
    }

    private var actionRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                if isCurrent, let highlight = player.segments.first(where: \.isHighlight),
                   store.library.settings.sponsorBlock.mode(for: .highlight) != .off {
                    Button {
                        player.seek(to: highlight.start)
                    } label: {
                        Label("Highlight", systemImage: "star")
                    }
                }
                Button {
                    player.setAudioOnly(!player.isAudioOnly)
                } label: {
                    Label(player.isAudioOnly ? "Show video" : "Audio only",
                          systemImage: player.isAudioOnly ? "film" : "headphones")
                }
                Button {
                    if isCurrent {
                        player.setAudioOnly(false)
                        player.popupRequested = true
                    } else {
                        player.play(details.asItem, mode: .popup)
                    }
                } label: {
                    Label("Popup", systemImage: "pip.enter")
                }
                Menu {
                    Picker("Maximum quality", selection: Binding(
                        get: { store.library.settings.maxHeight },
                        set: { player.setMaxHeight($0) }
                    )) {
                        Text("Automatic").tag(0)
                        ForEach([1080, 720, 480, 360, 240], id: \.self) { Text("\($0)p").tag($0) }
                    }
                } label: {
                    Label("Quality", systemImage: "slider.horizontal.3")
                }
                Menu {
                    let options = PlaybackPlanner.downloadOptions(for: details)
                    if options.isEmpty { Text("Nothing downloadable") }
                    ForEach(options.indices, id: \.self) { index in
                        Button(options[index].label) {
                            downloads.start(options[index], details: details)
                        }
                    }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                Menu {
                    AddToPlaylistMenu(item: details.asItem)
                    Button { player.enqueue(details.asItem) } label: {
                        Label("Add to queue", systemImage: "text.append")
                    }
                } label: {
                    Label("Save", systemImage: "text.badge.plus")
                }
                ShareLink(item: details.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(.bordered)
            .font(.footnote)
        }
        .listRowSeparator(.hidden)
    }

    @ViewBuilder private var uploaderRow: some View {
        if let url = details.uploaderUrl, !url.isEmpty {
            NavigationLink(value: Route.channel(serviceId: details.serviceId, url: url,
                                                name: details.uploaderName ?? "")) {
                HStack {
                    Thumbnail(url: details.uploaderAvatars.best(minWidth: 88))
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    VStack(alignment: .leading) {
                        Text(details.uploaderName ?? "").font(.subheadline.weight(.medium))
                        if let subs = Format.compact(details.uploaderSubscriberCount) {
                            Text(subs + " subscribers").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

/// The skip button, or the notice after an automatic skip.
struct SkipBanner: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        Group {
            if let segment = player.recentSkip {
                Button("Skipped \(segment.category.title) • Undo") { player.undoRecentSkip() }
            } else if let segment = player.offeredSkip {
                Button("Skip \(segment.category.title)") { player.acceptOfferedSkip() }
            }
        }
        .buttonStyle(.borderedProminent)
        .font(.caption.weight(.semibold))
        .padding(8)
    }
}

struct QueueSection: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        if player.queue.isEmpty {
            Text("The queue is empty").foregroundColor(.secondary)
        }
        ForEach(player.queue) { entry in
            Button {
                player.jump(to: entry)
            } label: {
                HStack {
                    ItemRow(item: entry.item)
                    if player.current == entry {
                        Image(systemName: "speaker.wave.2.fill").foregroundColor(.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .onDelete { player.removeFromQueue(at: $0) }
    }
}

/// The page behind the mini player.
struct NowPlayingScreen: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        if let entry = player.current {
            StreamView(item: entry.item, autoplay: false)
                .id(entry.id)
        } else {
            Text("Nothing is playing").foregroundColor(.secondary)
        }
    }
}
