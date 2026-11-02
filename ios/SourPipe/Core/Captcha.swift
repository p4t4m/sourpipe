import Foundation

/// A cookie kept after a CAPTCHA was solved, sent with later extractor requests to its domain.
public struct StoredCookie: Codable, Equatable {
    public var name: String
    public var value: String
    /// Lowercased, without a leading dot; it also matches subdomains.
    public var domain: String
    public var path: String
    public var expires: Date?

    public init(name: String, value: String, domain: String, path: String = "/",
                expires: Date? = nil) {
        self.name = name
        self.value = value
        var domain = domain.lowercased()
        while domain.hasPrefix(".") { domain.removeFirst() }
        self.domain = domain
        self.path = path.isEmpty ? "/" : path
        self.expires = expires
    }

    public func matches(_ url: URL, now: Date = Date()) -> Bool {
        if let expires, expires <= now { return false }
        guard let host = url.host?.lowercased() else { return false }
        guard host == domain || host.hasSuffix("." + domain) else { return false }
        let requestPath = url.path.isEmpty ? "/" : url.path
        return path == "/" || requestPath == path || requestPath.hasPrefix(path.hasSuffix("/") ? path : path + "/")
    }
}

/// The cookies NewPipe keeps after a CAPTCHA, and the same rules for using them.
public struct CaptchaCookieJar: Codable, Equatable {
    public var cookies: [StoredCookie] = []

    public init(cookies: [StoredCookie] = []) {
        self.cookies = cookies
    }

    /// The Google cookies NewPipe's ReCaptchaActivity keeps; others would change the extractor's
    /// language, consent or account state.
    public static let googleCookieNames: Set<String> = [
        "GOOGLE_ABUSE_EXEMPTION", "s_gl", "goojf", "VISITOR_INFO1_LIVE",
    ]

    static func isGoogle(_ domain: String) -> Bool {
        ["google.com", "youtube.com", "youtube-nocookie.com", "googleapis.com"].contains {
            domain == $0 || domain.hasSuffix("." + $0)
        } || domain.hasPrefix("google.") || domain.contains(".google.")
    }

    /// Picks what to keep from a solved CAPTCHA page. For Google only the cookies above; for any
    /// other service, the cookies of the site that asked.
    public static func relevant(_ cookies: [StoredCookie], challengeHost: String) -> [StoredCookie] {
        let host = challengeHost.lowercased()
        return cookies.filter { cookie in
            if googleCookieNames.contains(cookie.name) { return true }
            if isGoogle(cookie.domain) { return false }
            return host == cookie.domain || host.hasSuffix("." + cookie.domain)
        }
    }

    /// Adds or replaces cookies with the same name, domain and path, and drops expired ones.
    public mutating func store(_ new: [StoredCookie], now: Date = Date()) {
        for cookie in new {
            cookies.removeAll {
                $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path
            }
            cookies.append(cookie)
        }
        cookies.removeAll { $0.expires.map { $0 <= now } ?? false }
    }

    /// The `Cookie` header value for a request, or nil when nothing applies.
    public func header(for url: URL, now: Date = Date()) -> String? {
        let parts = cookies.filter { $0.matches(url, now: now) }.map { "\($0.name)=\($0.value)" }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// Joins the extractor's own Cookie header with ours. The extractor's values win when a name
    /// appears in both.
    public static func merge(existing: String?, extra: String?) -> String? {
        guard let extra, !extra.isEmpty else { return existing }
        guard let existing, !existing.isEmpty else { return extra }
        let names = Set(existing.split(separator: ";").compactMap {
            $0.split(separator: "=", maxSplits: 1).first.map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        })
        let added = extra.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { part in
                let name = part.split(separator: "=", maxSplits: 1).first.map(String.init) ?? part
                return !names.contains(name)
            }
        return added.isEmpty ? existing : existing + "; " + added.joined(separator: "; ")
    }

    /// After a Google CAPTCHA, the page redirects back with the exemption cookie in a
    /// `google_abuse` query parameter, before any page has set it. NewPipe reads it from there too.
    public static func abuseExemption(fromRedirect url: URL) -> StoredCookie? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "google_abuse" })?.value else { return nil }
        let text = raw.replacingOccurrences(of: "+", with: " ")
        var parts = text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !parts.isEmpty else { return nil }
        let first = parts.removeFirst()
        guard let equals = first.firstIndex(of: "=") else { return nil }
        let name = String(first[..<equals])
        let value = String(first[first.index(after: equals)...])
        guard name == "GOOGLE_ABUSE_EXEMPTION", !value.isEmpty else { return nil }
        var domain = url.host ?? "youtube.com"
        var path = "/"
        var expires: Date?
        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            switch pair[0].lowercased() {
            case "domain": domain = pair[1]
            case "path": path = pair[1]
            case "expires": expires = parseExpiry(pair[1])
            default: break
            }
        }
        return StoredCookie(name: name, value: value, domain: domain, path: path, expires: expires)
    }

    static func parseExpiry(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        for format in ["EEE, dd-MMM-yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss zzz",
                       "EEE, dd-MMM-yy HH:mm:ss zzz"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    /// True for the page that shows the challenge, such as google.com/sorry/index.
    public static func isChallengePage(_ url: URL) -> Bool {
        url.path.hasPrefix("/sorry") || url.path.contains("/recaptcha/")
            || url.path.contains("captcha")
    }
}
