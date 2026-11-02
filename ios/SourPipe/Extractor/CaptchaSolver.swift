import Foundation

/// Cookies from solved CAPTCHAs, read by every extractor engine thread for each request.
final class CaptchaCookieStore {
    static let shared = CaptchaCookieStore()
    private static let key = "captchaCookies"

    private let lock = NSLock()
    private var jar: CaptchaCookieJar

    private init() {
        jar = UserDefaults.standard.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode(CaptchaCookieJar.self, from: $0) }
            ?? CaptchaCookieJar()
        jar.store([])
    }

    func header(for url: URL) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return jar.header(for: url)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return jar.cookies.count
    }

    func store(_ cookies: [StoredCookie]) {
        lock.lock()
        jar.store(cookies)
        let data = try? JSONEncoder().encode(jar)
        lock.unlock()
        UserDefaults.standard.set(data, forKey: Self.key)
        NSLog("[captcha] kept %d cookies: %@", cookies.count,
              cookies.map { "\($0.name)@\($0.domain)" }.joined(separator: ", "))
    }

    func clear() {
        lock.lock()
        jar = CaptchaCookieJar()
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

/// Remembers the latest CAPTCHA a service asked for, so the UI can offer to solve it.
@MainActor
final class CaptchaSolver: ObservableObject {
    static let shared = CaptchaSolver()

    /// The page to open, or nil when nothing is waiting.
    @Published private(set) var pending: URL?
    /// Bumped after each solve, so screens can reload.
    @Published private(set) var solvedCount = 0

    nonisolated static func report(_ failure: ExtractorFailure) {
        guard failure.kind == "recaptcha" else { return }
        let url = failure.url.flatMap(URL.init(string:)) ?? URL(string: "https://www.youtube.com/")!
        Task { @MainActor in shared.pending = url }
    }

    func request(_ url: URL) {
        pending = url
    }

    func dismiss() {
        pending = nil
    }

    func solved() {
        pending = nil
        solvedCount += 1
    }
}
