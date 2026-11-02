import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var player: PlayerController
    @State private var importing = false
    @State private var importMessage: String?
    @State private var isImporting = false
    @State private var captchaCookies = CaptchaCookieStore.shared.count

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
                LabeledContent("Country") {
                    TextField("Code, such as US", text: $store.library.settings.country)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Show comments", isOn: $store.library.settings.showComments)
                Toggle("Hide Shorts", isOn: $store.library.settings.hideShorts)
            }
            Section("Appearance") {
                ThemeColorPicker(selection: $store.library.settings.themeColor)
                Picker("Theme", selection: $store.library.settings.appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                }
                NavigationLink("Home sections") { HomePagesSettingsView() }
                NavigationLink("Long-press menu") { StreamMenuSettingsView() }
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
                Button(isImporting ? "Importing…" : "Import NewPipe backup") { importing = true }
                    .disabled(isImporting)
            }
            Section {
                Toggle("SponsorBlock", isOn: $store.library.settings.sponsorBlockEnabled)
                if store.library.settings.sponsorBlockEnabled {
                    ForEach(SponsorCategory.allCases) { category in
                        Picker(category.title, selection: Binding(
                            get: { store.library.settings.sponsorBlock.mode(for: category) },
                            set: { store.library.settings.sponsorBlock.modes[category.rawValue] = $0 }
                        )) {
                            Text("Off").tag(SkipMode.off)
                            Text(category == .highlight ? "Show" : "Ask").tag(SkipMode.offer)
                            if category != .highlight { Text("Skip").tag(SkipMode.automatic) }
                        }
                    }
                    Toggle("Skip \"Ask\" segments in Picture in Picture and background",
                           isOn: $store.library.settings.sponsorBlock.skipAskedWhenHidden)
                    TextField("Server", text: $store.library.settings.sponsorBlock.server)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote)
                }
            } header: {
                Text("Skip segments")
            } footer: {
                Text("YouTube only. Uses community-submitted segments from sponsor.ajay.app. The server receives the first characters of a hash of the video ID, and your IP address.")
            }
            Section {
                Toggle("Return YouTube Dislike", isOn: $store.library.settings.dislikesEnabled)
                if store.library.settings.dislikesEnabled {
                    TextField("Server", text: $store.library.settings.dislikesServer)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote)
                }
            } header: {
                Text("Dislike counts")
            } footer: {
                Text("YouTube only. The counts are estimates. The server receives the ID of each video you open, and your IP address.")
            }
            Section {
                Button("Forget CAPTCHA cookies (\(captchaCookies))", role: .destructive) {
                    CaptchaCookieStore.shared.clear()
                    captchaCookies = 0
                }
                .disabled(captchaCookies == 0)
            } header: {
                Text("CAPTCHA")
            } footer: {
                Text("When a service asks for a CAPTCHA, solving it in the app keeps the cookies it sets and sends them to that service only.")
            }
            Section("About") {
                LabeledContent("Extractor", value: ExtractorVersion.commit)
                Link("Licence: GPL v3 or later",
                     destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }
        }
        .navigationTitle("Settings")
        .onAppear { captchaCookies = CaptchaCookieStore.shared.count }
        .onChange(of: store.library.settings.language) { _ in store.applyLocalization() }
        .onChange(of: store.library.settings.country) { _ in store.applyLocalization() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.zip, .json, .data]) { result in
            isImporting = true
            Task {
                importMessage = await importBackup(result)
                isImporting = false
            }
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

    /// Reads a NewPipe, Tubular or PipePipe backup, or a NewPipe subscriptions export.
    private func importBackup(_ result: Result<URL, Error>) async -> String {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            if data.first == UInt8(ascii: "{") {
                let incoming = try NewPipeImport.subscriptions(from: data)
                let added = NewPipeImport.merge(incoming, into: &store.library)
                return "Added \(added) of \(incoming.count) subscriptions."
            }
            let backup = try await Task.detached(priority: .userInitiated) {
                try NewPipeBackupReader.read(data)
            }.value
            return store.library.merge(backup).description
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
