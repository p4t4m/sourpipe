import Foundation
import SwiftUI

/// The persistent library, observed by the UI and saved as one JSON file.
@MainActor
final class AppStore: ObservableObject {
    @Published var library: LibraryData {
        didSet { scheduleSave() }
    }
    @Published var services: [ServiceInfo] = []
    @Published var startupError: String?

    private var saveTask: Task<Void, Never>?

    nonisolated static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// Library data is not a user document, so it stays out of the Files app.
    private nonisolated static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("library.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let loaded = try? JSONDecoder().decode(LibraryData.self, from: data) {
            library = loaded
        } else {
            var fresh = LibraryData()
            if let language = Locale.current.languageCode { fresh.settings.language = language }
            if let region = Locale.current.regionCode { fresh.settings.country = region }
            library = fresh
        }
    }

    func start() async {
        do {
            try await Extractor.configure(language: library.settings.language,
                                          country: library.settings.country)
            services = try await Extractor.services()
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }

    var currentService: ServiceInfo? {
        services.first { $0.id == library.settings.serviceId } ?? services.first
    }

    func applyLocalization() {
        let settings = library.settings
        Task { try? await Extractor.configure(language: settings.language, country: settings.country) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = library
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                if let data = try? JSONEncoder().encode(snapshot) {
                    try? data.write(to: Self.fileURL, options: .atomic)
                }
            }.value
        }
    }

    /// For when the app is about to be suspended and a delayed save might never run.
    func saveNow() {
        saveTask?.cancel()
        if let data = try? JSONEncoder().encode(library) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
