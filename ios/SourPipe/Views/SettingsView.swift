import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var player: PlayerController
    @State private var importing = false
    @State private var importMessage: String?

    private static let languages = [
        ("en", "English"), ("de", "Deutsch"), ("es", "Español"), ("fr", "Français"),
        ("it", "Italiano"), ("ja", "日本語"), ("ko", "한국어"), ("nl", "Nederlands"),
        ("pl", "Polski"), ("pt", "Português"), ("ru", "Русский"), ("tr", "Türkçe"),
        ("uk", "Українська"), ("zh", "中文"),
    ]

    var body: some View {
        Form {
            Section("Content") {
                Picker("Service", selection: $store.library.settings.serviceId) {
                    ForEach(store.services) { Text($0.name).tag($0.id) }
                }
                Picker("Language", selection: $store.library.settings.language) {
                    ForEach(languageOptions, id: \.0) { Text($0.1).tag($0.0) }
                }
                TextField("Country code", text: $store.library.settings.country)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Toggle("Show comments", isOn: $store.library.settings.showComments)
                Toggle("Hide Shorts", isOn: $store.library.settings.hideShorts)
            }
            Section("Playback") {
                Picker("Maximum quality", selection: Binding(
                    get: { store.library.settings.maxHeight },
                    set: { player.setMaxHeight($0) }
                )) {
                    Text("Automatic").tag(0)
                    ForEach([1080, 720, 480, 360, 240], id: \.self) { Text("\($0)p").tag($0) }
                }
                Toggle("Audio only by default", isOn: Binding(
                    get: { store.library.settings.audioOnly },
                    set: {
                        store.library.settings.audioOnly = $0
                        player.setAudioOnly($0)
                    }
                ))
                Toggle("Play related video next", isOn: $store.library.settings.autoplayRelated)
                Toggle("Resume where I left off", isOn: $store.library.settings.resumePlayback)
            }
            Section("Library") {
                Toggle("Keep watch history", isOn: $store.library.settings.recordHistory)
                Button("Import NewPipe subscriptions") { importing = true }
            }
            Section("About") {
                LabeledContent("Extractor", value: ExtractorVersion.commit)
                Link("Licence: GPL v3 or later",
                     destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }
        }
        .navigationTitle("Settings")
        .onChange(of: store.library.settings.language) { _ in store.applyLocalization() }
        .onChange(of: store.library.settings.country) { _ in store.applyLocalization() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            importMessage = importSubscriptions(result)
        }
        .alert("Import", isPresented: Binding(
            get: { importMessage != nil }, set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    /// Keeps the active language selectable even if it is not in the short list.
    private var languageOptions: [(String, String)] {
        let current = store.library.settings.language
        return Self.languages.contains { $0.0 == current }
            ? Self.languages : Self.languages + [(current, current)]
    }

    private func importSubscriptions(_ result: Result<URL, Error>) -> String {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let incoming = try NewPipeImport.subscriptions(from: Data(contentsOf: url))
            let added = NewPipeImport.merge(incoming, into: &store.library)
            return "Added \(added) of \(incoming.count) subscriptions."
        } catch {
            return "That file could not be read: \(error.localizedDescription)"
        }
    }
}

enum ExtractorVersion {
    /// The pinned NewPipeExtractor commit, copied here by scripts/build-extractor.sh.
    static var commit: String {
        guard let url = Bundle.main.url(forResource: "extractor-version", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "unknown" }
        return String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(9))
    }
}
