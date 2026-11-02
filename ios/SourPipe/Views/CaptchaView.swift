import SwiftUI
import WebKit

/// Shows a service's CAPTCHA page, as NewPipe's ReCaptchaActivity does, and keeps the cookies that
/// solving it sets. Closes by itself once the service lets the page through.
struct CaptchaSheet: View {
    var onFinish: (_ solved: Bool) -> Void
    @StateObject private var session: CaptchaSession

    init(url: URL, onFinish: @escaping (_ solved: Bool) -> Void) {
        self.onFinish = onFinish
        _session = StateObject(wrappedValue: CaptchaSession(url: url))
    }

    var body: some View {
        NavigationStack {
            WebViewHost(view: session.webView)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Solve the CAPTCHA")
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .top, spacing: 0) {
                    Text("\(session.challengeHost) asked for this. It closes by itself once solved; "
                         + "if it does not, tap Done.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(.bar)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onFinish(false) }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { session.finish() }
                    }
                }
        }
        .onAppear { session.onSolved = { onFinish(true) } }
    }
}

private struct WebViewHost: UIViewRepresentable {
    let view: WKWebView
    func makeUIView(context: Context) -> WKWebView { view }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

@MainActor
final class CaptchaSession: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    let challengeHost: String
    var onSolved: (() -> Void)?
    private var sawChallenge = false
    private var finished = false
    private var found: [StoredCookie] = []

    init(url: URL) {
        challengeHost = url.host ?? "The service"
        let configuration = WKWebViewConfiguration()
        // A fresh store, so only this challenge's cookies are collected.
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        // The exemption is tied to the client that earned it, so use the extractor's user agent.
        webView.customUserAgent = ExtractorEngine.userAgent
        super.init()
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
    }

    /// Google redirects back with the exemption in the URL, before any page has set the cookie.
    private func inspect(_ url: URL?) {
        guard let url else { return }
        if let cookie = CaptchaCookieJar.abuseExemption(fromRedirect: url) {
            found.append(cookie)
            finish()
        } else if CaptchaCookieJar.isChallengePage(url) {
            sawChallenge = true
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        inspect(webView.url)
    }

    func webView(_ webView: WKWebView,
                 didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        inspect(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        inspect(webView.url)
        guard let url = webView.url, !finished else { return }
        if CaptchaCookieJar.isChallengePage(url) {
            sawChallenge = true
        } else if sawChallenge {
            // The challenge was shown and the service has now let the page through.
            finish()
        }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        let host = challengeHost
        let found = found
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            let all = found + cookies.map {
                StoredCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path,
                             expires: $0.expiresDate)
            }
            CaptchaCookieStore.shared.store(CaptchaCookieJar.relevant(all, challengeHost: host))
            Task { @MainActor in self.onSolved?() }
        }
    }
}

/// Offers to solve a waiting CAPTCHA from anywhere in the app.
struct CaptchaBanner: View {
    @ObservedObject private var solver = CaptchaSolver.shared
    @State private var solving = false

    var body: some View {
        if let url = solver.pending {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield")
                    .foregroundColor(.orange)
                Text("\(url.host ?? "A service") wants a CAPTCHA solved")
                    .font(.footnote)
                    .lineLimit(2)
                Spacer()
                Button("Solve") { solving = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button {
                    solver.dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
            .sheet(isPresented: $solving) {
                CaptchaSheet(url: url) { solved in
                    solving = false
                    if solved { solver.solved() }
                }
            }
            #if DEBUG
            .task {
                // CI: `-testCaptcha <url> -testCaptchaOpen YES` opens the sheet without a tap.
                if UserDefaults.standard.bool(forKey: "testCaptchaOpen") { solving = true }
            }
            #endif
        }
    }
}

/// The "Solve" button an error screen shows while a CAPTCHA is waiting; reloads when solved.
struct CaptchaSolveButton: View {
    var retry: (() -> Void)?
    @ObservedObject private var solver = CaptchaSolver.shared
    @State private var solving = false

    var body: some View {
        if let url = solver.pending {
            Button("Solve CAPTCHA") { solving = true }
                .buttonStyle(.borderedProminent)
                .sheet(isPresented: $solving) {
                    CaptchaSheet(url: url) { solved in
                        solving = false
                        if solved {
                            solver.solved()
                            retry?()
                        }
                    }
                }
        }
    }
}
