import Foundation
import JavaScriptCore

/// Hosts extractor.js (NewPipeExtractor compiled by TeaVM) in a JSContext.
///
/// All JavaScript runs on one thread with a large stack, because JavaScriptCore has no JIT in
/// third-party iOS apps and interpreted frames are big; secondary threads default to 512 KB.
final class ExtractorEngine: NSObject {
    static let shared = ExtractorEngine()

    /// NewPipe's own downloader uses this as its default, so services see the same client.
    private static let userAgent =
        "Mozilla/5.0 (Windows NT 10.0; rv:128.0) Gecko/20100101 Firefox/128.0"

    private var thread: Thread!
    private var context: JSContext!
    private var timers: [Int: Timer] = [:]
    private var nextTimerId = 1
    private let session: URLSession

    private final class Block: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
    }

    override private init() {
        let configuration = URLSessionConfiguration.ephemeral
        // The extractor manages its own Cookie headers; URLSession's handling would replace them.
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        super.init()
        let started = DispatchSemaphore(value: 0)
        thread = Thread { [unowned self] in self.threadMain(started) }
        thread.name = "SourPipe.Extractor"
        thread.stackSize = 16 << 20
        thread.qualityOfService = .userInitiated
        thread.start()
        // Scheduling work on a thread is only reliable once its run loop exists.
        started.wait()
        onThread { self.loadBundle() }
    }

    private func threadMain(_ started: DispatchSemaphore) {
        // A port keeps the run loop alive while no timers are pending.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        started.signal()
        while true {
            autoreleasepool { _ = RunLoop.current.run(mode: .default, before: .distantFuture) }
        }
    }

    private func onThread(_ block: @escaping () -> Void) {
        perform(#selector(runBlock(_:)), on: thread, with: Block(block), waitUntilDone: false)
    }

    @objc private func runBlock(_ block: Block) {
        block.run()
    }

    private func loadBundle() {
        guard let context = JSContext(),
              let url = Bundle.main.url(forResource: "extractor", withExtension: "jsbundle"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("extractor.jsbundle is missing from the app bundle; see README")
        }
        self.context = context
        context.name = "SourPipe Extractor"
        context.exceptionHandler = { _, exception in
            NSLog("[extractor] uncaught: %@", exception?.toString() ?? "unknown")
        }
        installHost(in: context)
        context.evaluateScript(source + "\n;main([]);", withSourceURL: url)
    }

    private func installHost(in context: JSContext) {
        let setTimeout: @convention(block) (JSValue, Double) -> Int = { [unowned self] callback, ms in
            let id = self.nextTimerId
            self.nextTimerId += 1
            let timer = Timer(timeInterval: ms.isNaN ? 0 : max(ms, 0) / 1000, repeats: false) { [unowned self] _ in
                self.timers[id] = nil
                callback.call(withArguments: [])
            }
            self.timers[id] = timer
            RunLoop.current.add(timer, forMode: .default)
            return id
        }
        let clearTimeout: @convention(block) (Int) -> Void = { [unowned self] id in
            self.timers.removeValue(forKey: id)?.invalidate()
        }
        context.setObject(unsafeBitCast(setTimeout, to: AnyObject.self), forKeyedSubscript: "setTimeout" as NSString)
        context.setObject(unsafeBitCast(clearTimeout, to: AnyObject.self), forKeyedSubscript: "clearTimeout" as NSString)

        let host = JSValue(newObjectIn: context)!
        let log: @convention(block) (String) -> Void = { NSLog("[extractor] %@", $0) }
        let http: @convention(block) (String, String, String, JSValue, JSValue) -> Void = {
            [unowned self] method, url, headers, body, callback in
            self.http(method: method, url: url, headersJson: headers,
                      bodyBase64: body.isNull || body.isUndefined ? nil : body.toString(),
                      callback: callback)
        }
        host.setObject(unsafeBitCast(log, to: AnyObject.self), forKeyedSubscript: "log" as NSString)
        host.setObject(unsafeBitCast(http, to: AnyObject.self), forKeyedSubscript: "http" as NSString)
        context.setObject(host, forKeyedSubscript: "__sourpipeHost" as NSString)
    }

    private func http(method: String, url: String, headersJson: String, bodyBase64: String?,
                      callback: JSValue) {
        guard let target = URL(string: url) else {
            callback.call(withArguments: [NSNull(), "Invalid URL: \(url)"])
            return
        }
        var request = URLRequest(url: target)
        request.httpMethod = method
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        if let data = headersJson.data(using: .utf8),
           let headers = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] {
            for (name, values) in headers {
                request.setValue(values.joined(separator: ", "), forHTTPHeaderField: name)
            }
        }
        if let bodyBase64 {
            request.httpBody = Data(base64Encoded: bodyBase64)
        }
        session.dataTask(with: request) { [unowned self] data, response, error in
            var result: String?
            var failure = error?.localizedDescription
            if let response = response as? HTTPURLResponse {
                result = Self.encode(response, data: data ?? Data())
                if result == nil { failure = "Could not encode the response" }
            } else if failure == nil {
                failure = "No HTTP response"
            }
            self.onThread {
                callback.call(withArguments: [
                    result.map { $0 as Any } ?? NSNull(),
                    failure.map { $0 as Any } ?? NSNull(),
                ])
            }
        }.resume()
    }

    private static func encode(_ response: HTTPURLResponse, data: Data) -> String? {
        var headers: [String: [String]] = [:]
        for (name, value) in response.allHeaderFields {
            headers["\(name)".lowercased(), default: []].append("\(value)")
        }
        let encoding = response.textEncodingName.map {
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringConvertIANACharSetNameToEncoding($0 as CFString)))
        } ?? .utf8
        let body = String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        let object: [String: Any] = [
            "status": response.statusCode,
            "url": response.url?.absoluteString ?? "",
            "headers": headers,
            "body": body,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: json, encoding: .utf8)
    }

    /// Calls a bridge method (see Main.java) and returns its JSON result.
    func call(_ method: String, args: [String: Any]) async throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: args)
        let argsJson = String(decoding: json, as: UTF8.self)
        return try await withCheckedThrowingContinuation { continuation in
            onThread { self.invoke(method, argsJson, attempt: 0, continuation) }
        }
    }

    /// TeaVM runs main() on a green thread, so the entry point can appear slightly after load.
    private func invoke(_ method: String, _ argsJson: String, attempt: Int,
                        _ continuation: CheckedContinuation<Data, Error>) {
        guard let entry = context.objectForKeyedSubscript("__sourpipeCall"), !entry.isUndefined else {
            guard attempt < 1000 else {
                continuation.resume(throwing: ExtractorFailure(
                    kind: "extraction", message: "The extractor did not start"))
                return
            }
            let timer = Timer(timeInterval: 0.01, repeats: false) { [unowned self] _ in
                self.invoke(method, argsJson, attempt: attempt + 1, continuation)
            }
            RunLoop.current.add(timer, forMode: .default)
            return
        }
        let done: @convention(block) (JSValue, JSValue) -> Void = { result, error in
            if !error.isNull, !error.isUndefined, let text = error.toString() {
                let failure = (try? JSONDecoder().decode(ExtractorFailure.self,
                                                         from: Data(text.utf8)))
                    ?? ExtractorFailure(kind: "extraction", message: text)
                continuation.resume(throwing: failure)
            } else {
                continuation.resume(returning: Data((result.toString() ?? "{}").utf8))
            }
        }
        entry.call(withArguments: [method, argsJson, unsafeBitCast(done, to: AnyObject.self)])
    }
}

/// Typed access to the bridge. Any thread; results are plain values.
enum Extractor {
    private static func call<T: Decodable>(_ method: String, _ args: [String: Any] = [:]) async throws -> T {
        let data = try await ExtractorEngine.shared.call(method, args: args)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct Empty: Decodable {}

    private static func encode(_ page: PageToken) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(page))
    }

    static func configure(language: String, country: String) async throws {
        let _: Empty = try await call("configure", ["language": language, "country": country])
    }

    static func services() async throws -> [ServiceInfo] {
        let list: ServiceList = try await call("services")
        return list.services
    }

    static func resolve(url: String) async throws -> ResolvedLink {
        try await call("resolve", ["url": url])
    }

    static func suggestions(serviceId: Int, query: String) async throws -> [String] {
        let list: SuggestionList = try await call("suggestions",
                                                  ["serviceId": serviceId, "query": query])
        return list.suggestions
    }

    static func search(serviceId: Int, query: String, filter: String?) async throws -> ItemPage {
        var args: [String: Any] = ["serviceId": serviceId, "query": query]
        if let filter { args["filter"] = filter }
        return try await call("search", args)
    }

    static func kiosk(serviceId: Int, id: String) async throws -> ItemPage {
        try await call("kiosk", ["serviceId": serviceId, "id": id])
    }

    static func channel(serviceId: Int, url: String) async throws -> ChannelDetails {
        try await call("channel", ["serviceId": serviceId, "url": url])
    }

    static func channelTab(serviceId: Int, token: String) async throws -> ItemPage {
        try await call("channelTab", ["serviceId": serviceId, "token": token])
    }

    static func playlist(serviceId: Int, url: String) async throws -> PlaylistDetails {
        try await call("playlist", ["serviceId": serviceId, "url": url])
    }

    static func stream(serviceId: Int, url: String) async throws -> StreamDetails {
        try await call("stream", ["serviceId": serviceId, "url": url])
    }

    static func comments(serviceId: Int, url: String) async throws -> CommentPage {
        try await call("comments", ["serviceId": serviceId, "url": url])
    }

    enum MoreSource {
        case search(query: String, filter: String?)
        case kiosk(url: String)
        case playlist(url: String)
        case channelTab(token: String)
    }

    static func more(serviceId: Int, source: MoreSource, page: PageToken) async throws -> ItemPage {
        var args: [String: Any] = ["serviceId": serviceId, "page": try encode(page)]
        switch source {
        case .search(let query, let filter):
            args["kind"] = "search"
            args["query"] = query
            if let filter { args["filter"] = filter }
        case .kiosk(let url):
            args["kind"] = "kiosk"
            args["url"] = url
        case .playlist(let url):
            args["kind"] = "playlist"
            args["url"] = url
        case .channelTab(let token):
            args["kind"] = "channelTab"
            args["token"] = token
        }
        return try await call("more", args)
    }

    static func moreComments(serviceId: Int, url: String, page: PageToken) async throws -> CommentPage {
        try await call("more", ["serviceId": serviceId, "kind": "comments", "url": url,
                                "page": try encode(page)])
    }
}
