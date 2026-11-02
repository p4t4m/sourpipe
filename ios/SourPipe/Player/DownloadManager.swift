import AVFoundation
import Combine
import Foundation

/// Saves streams into Documents/Downloads (visible in the Files app).
@MainActor
final class DownloadManager: ObservableObject {
    struct Job: Identifiable {
        let id = UUID()
        let title: String
        var progress: Double = 0
        var phase = "Downloading"
        var error: String?
        var task: Task<Void, Never>?
    }

    @Published private(set) var jobs: [Job] = []
    private let store: AppStore

    init(store: AppStore) {
        self.store = store
    }

    private static var folder: URL {
        let dir = AppStore.documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start(_ source: PlaybackSource, details: StreamDetails) {
        var job = Job(title: "\(details.name) (\(source.label))")
        let id = job.id
        job.task = Task { [weak self] in
            await self?.run(id: id, source: source, details: details)
        }
        jobs.append(job)
    }

    func cancel(_ job: Job) {
        job.task?.cancel()
        jobs.removeAll { $0.id == job.id }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    private func run(id: UUID, source: PlaybackSource, details: StreamDetails) async {
        let safeName = String(details.name.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) || $0 == " " ? Character($0) : "_"
        }.prefix(80))
        let base = "\(safeName) \(id.uuidString.prefix(8))"
        let isAudio = source.label.hasPrefix("Audio")
        let fileName = base + (isAudio ? ".m4a" : ".mp4")
        let destination = Self.folder.appendingPathComponent(fileName)
        do {
            switch source {
            case .hls:
                throw ExtractorFailure(kind: "unsupported", message: "HLS cannot be saved")
            case .file(let url, _):
                let file = try await fetch(url, id: id, from: 0, to: 1)
                try FileManager.default.moveItem(at: file, to: destination)
            case .merged(let video, let audio, _):
                let videoFile = try await fetch(video, id: id, from: 0, to: 0.8)
                defer { try? FileManager.default.removeItem(at: videoFile) }
                let audioFile = try await fetch(audio, id: id, from: 0.8, to: 1)
                defer { try? FileManager.default.removeItem(at: audioFile) }
                update(id) { $0.phase = "Combining" }
                try await Self.mux(video: videoFile, audio: audioFile, to: destination)
            }
            let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            NSLog("[download] saved %@ (%ld bytes)", fileName, size)
            store.library.downloads.insert(
                DownloadRecord(item: details.asItem, label: source.label,
                               fileName: "Downloads/" + fileName, isAudio: isAudio), at: 0)
            jobs.removeAll { $0.id == id }
        } catch is CancellationError {
            jobs.removeAll { $0.id == id }
        } catch {
            NSLog("[download] failed: %@", error.localizedDescription)
            update(id) { $0.error = error.localizedDescription }
        }
    }

    private func fetch(_ url: URL, id: UUID, from: Double, to: Double) async throws -> URL {
        try await Self.fetchInChunks(url) { [weak self] fraction in
            Task { @MainActor in
                self?.update(id) { $0.progress = from + (to - from) * min(fraction, 1) }
            }
        }
    }

    /// YouTube sends a whole file at a trickle: an audio stream stalled after 290 KB, while ranged
    /// requests for the same URL ran at full speed. So fetch in ranges, as NewPipe does.
    nonisolated private static let chunkSize: Int64 = 8 << 20

    nonisolated private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.httpAdditionalHeaders = ["User-Agent": ExtractorEngine.userAgent]
        return URLSession(configuration: configuration)
    }()

    nonisolated private static func fetchInChunks(
        _ url: URL, report: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        let handle = try FileHandle(forWritingTo: output)
        var closed = false
        defer { if !closed { try? handle.close() } }
        var offset: Int64 = 0
        var total: Int64?
        do {
            while total.map({ offset < $0 }) ?? true {
                try Task.checkCancellation()
                var request = URLRequest(url: url)
                request.setValue("bytes=\(offset)-\(offset + chunkSize - 1)",
                                 forHTTPHeaderField: "Range")
                let start = offset
                let knownTotal = total
                let (file, response) = try await withRetries {
                    try await session.download(for: request, delegate: Progress { fraction in
                        guard let knownTotal, knownTotal > 0 else { return }
                        let size = min(chunkSize, knownTotal - start)
                        report((Double(start) + fraction * Double(size)) / Double(knownTotal))
                    })
                }
                defer { try? FileManager.default.removeItem(at: file) }
                guard let http = response as? HTTPURLResponse else {
                    throw ExtractorFailure(kind: "network", message: "No HTTP response")
                }
                if http.statusCode == 200 && offset == 0 {
                    // The server ignored the range and sent everything.
                    try handle.close()
                    closed = true
                    try FileManager.default.removeItem(at: output)
                    try FileManager.default.moveItem(at: file, to: output)
                    report(1)
                    return output
                }
                guard http.statusCode == 206 else {
                    throw ExtractorFailure(kind: "network", message: "HTTP \(http.statusCode)")
                }
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                guard !data.isEmpty else {
                    throw ExtractorFailure(kind: "network", message: "Empty response")
                }
                try handle.write(contentsOf: data)
                offset += Int64(data.count)
                if total == nil {
                    total = ByteRange.total(contentRange: http.value(forHTTPHeaderField: "Content-Range"))
                }
                // Without a total, a short chunk is the last one.
                if total == nil && Int64(data.count) < chunkSize { break }
                report(total.map { Double(offset) / Double($0) } ?? 0)
            }
        } catch {
            try? handle.close()
            closed = true
            try? FileManager.default.removeItem(at: output)
            throw error
        }
        return output
    }

    /// Mobile connections drop; retry a chunk a few times before failing the download.
    nonisolated private static func withRetries<T>(
        _ attempt: () async throws -> T
    ) async throws -> T {
        var tries = 0
        while true {
            do {
                return try await attempt()
            } catch let error as URLError where error.code != .cancelled && tries < 4 {
                tries += 1
                NSLog("[download] retrying after %@", error.localizedDescription)
                try await Task.sleep(nanoseconds: UInt64(tries) * 1_500_000_000)
            }
        }
    }

    /// URLSession calls this once, before any progress can be reported.
    private final class Progress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let report: @Sendable (Double) -> Void
        private var observation: NSKeyValueObservation?

        init(report: @escaping @Sendable (Double) -> Void) {
            self.report = report
        }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            observation = task.progress.observe(\.fractionCompleted) { [report] progress, _ in
                report(progress.fractionCompleted)
            }
        }
    }

    nonisolated private static func mux(video: URL, audio: URL, to destination: URL) async throws {
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: video)
        let audioAsset = AVURLAsset(url: audio)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ExtractorFailure(kind: "unsupported", message: "Downloaded file has no track")
        }
        let length = try await videoAsset.load(.duration)
        let audioLength = min(length, try await audioAsset.load(.duration))
        try composition.addMutableTrack(withMediaType: .video,
                                        preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: length), of: videoTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio,
                                        preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(CMTimeRange(start: .zero, duration: audioLength), of: audioTrack, at: .zero)
        guard let export = AVAssetExportSession(asset: composition,
                                                presetName: AVAssetExportPresetPassthrough) else {
            throw ExtractorFailure(kind: "unsupported", message: "Cannot export this format")
        }
        export.outputURL = destination
        export.outputFileType = .mp4
        await export.export()
        if let error = export.error { throw error }
    }

    func delete(_ record: DownloadRecord) {
        try? FileManager.default.removeItem(at: AppStore.documents.appendingPathComponent(record.fileName))
        store.library.downloads.removeAll { $0.id == record.id }
    }
}
