import Foundation
import AppKit
import WebKit
import Security

/// AI apps people use in a browser (v4, usability round 1). TAB signs in on the app's own site in
/// a small window that keeps nothing on disk, then keeps only the one session cookie that app's
/// usage page needs, in TAB's own Keychain item. Nothing else is read and no other cookie is kept.
/// Behind a feature flag for now (`WebAuth.enabled`); apps with no usage endpoint say so.
struct WebSite {
    let id: String
    let name: String
    let domain: String
    let category: String
    /// The site's own sign-in page.
    let login: URL
    /// Hosts the sign-in window may show (the site and the sign-in services it sends people to).
    let hosts: [String]
    /// The cookie domain to keep, and which cookie names (a name, or a prefix ending in "*").
    let cookieDomain: String
    let cookies: [String]
    /// True when TAB has a usage reader for it.
    let readsUsage: Bool

    static let all: [WebSite] = [
        WebSite(id: "chatgpt", name: "ChatGPT", domain: "chatgpt.com", category: "Chat",
                login: URL(string: "https://chatgpt.com/auth/login")!,
                hosts: ["chatgpt.com", "openai.com", "oaistatic.com", "oaiusercontent.com", "google.com", "gstatic.com",
                        "apple.com", "microsoftonline.com", "live.com", "microsoft.com", "cloudflare.com"],
                cookieDomain: "chatgpt.com", cookies: ["__Secure-next-auth.session-token*"], readsUsage: true),
        WebSite(id: "perplexity", name: "Perplexity", domain: "perplexity.ai", category: "Search",
                login: URL(string: "https://www.perplexity.ai/")!, hosts: ["perplexity.ai"],
                cookieDomain: "perplexity.ai", cookies: [], readsUsage: false),
        WebSite(id: "higgsfield", name: "Higgsfield", domain: "higgsfield.ai", category: "Video",
                login: URL(string: "https://higgsfield.ai/")!, hosts: ["higgsfield.ai"],
                cookieDomain: "higgsfield.ai", cookies: [], readsUsage: false),
        WebSite(id: "elevenlabs", name: "ElevenLabs", domain: "elevenlabs.io", category: "Voice",
                login: URL(string: "https://elevenlabs.io/app/sign-in")!, hosts: ["elevenlabs.io"],
                cookieDomain: "elevenlabs.io", cookies: [], readsUsage: false),
        WebSite(id: "suno", name: "Suno", domain: "suno.com", category: "Music",
                login: URL(string: "https://suno.com/")!, hosts: ["suno.com"],
                cookieDomain: "suno.com", cookies: [], readsUsage: false),
        WebSite(id: "manus", name: "Manus", domain: "manus.im", category: "Agents",
                login: URL(string: "https://manus.im/")!, hosts: ["manus.im"],
                cookieDomain: "manus.im", cookies: [], readsUsage: false),
    ]

    /// The four shown first in onboarding (Figma screen 02).
    static let featured = ["chatgpt", "perplexity", "higgsfield", "elevenlabs"]

    static func site(_ id: String) -> WebSite? { all.first { $0.id == id } }

    func allows(_ host: String) -> Bool {
        let h = host.lowercased()
        return hosts.contains { h == $0 || h.hasSuffix("." + $0) }
    }

    func keeps(_ c: HTTPCookie) -> Bool {
        let d = c.domain.lowercased()
        let bare = d.hasPrefix(".") ? String(d.dropFirst()) : d
        guard bare == cookieDomain else { return false }
        return cookies.contains { p in p.hasSuffix("*") ? c.name.hasPrefix(String(p.dropLast())) : c.name == p }
    }
}

enum WebAuth {
    /// The feature flag. Off in the release build unless `defaults write <bundle id> webSignIn -bool true`.
    /// On in TAB Dev, so it can be tried.
    static var enabled: Bool {
        let d = UserDefaults.standard
        if d.object(forKey: "webSignIn") != nil { return d.bool(forKey: "webSignIn") }
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    static func service(_ id: String) -> String { "TAB \(WebSite.site(id)?.name ?? id) sign-in" }
    private static let account = "web"
    typealias Saved = GeminiAuth.Saved

    /// Every account's cookies for one web app, by account key. One Keychain item per app.
    static func loadAll(_ id: String, interactive: Bool) throws -> [String: [Saved]] {
        let r = Keychain.readOwn(service: service(id), account: account, interactive: interactive)
        if Keychain.isPermissionProblem(r.status) {
            throw interactive ? ProviderError.denied("macOS didn't let TAB check this app. Try again and choose Always Allow.") : ProviderError.needsApproval
        }
        guard r.status == errSecSuccess, let d = r.data else { return [:] }
        return (try? JSONDecoder().decode([String: [Saved]].self, from: d)) ?? [:]
    }

    static func load(_ id: String, account key: String, interactive: Bool) throws -> [Saved] {
        guard let s = try loadAll(id, interactive: interactive)[key], !s.isEmpty else {
            throw ProviderError.notSignedIn("Your sign-in in TAB ended. Click Add account to sign in again.")
        }
        return s
    }

    @discardableResult
    static func save(_ id: String, account key: String, cookies: [Saved], interactive: Bool) -> Bool {
        // A read that fails must never count as "no accounts", or saving one would drop the others.
        guard var all = try? loadAll(id, interactive: interactive) else { return false }
        all[key] = cookies
        guard let data = try? JSONEncoder().encode(all) else { return false }
        if Keychain.update(service: service(id), account: account, data: data, interactive: interactive) == errSecSuccess { return true }
        guard interactive, !Keychain.exists(service: service(id)) else { return false }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service(id),
                                  kSecAttrAccount as String: account, kSecAttrLabel as String: service(id),
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                  kSecValueData as String: data]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    /// Removes one account's cookies. The item goes away with the last one. Remove is a click, so
    /// macOS may ask. If the item can't be read, nothing is changed, so other accounts stay.
    @discardableResult
    static func remove(_ id: String, account key: String, interactive: Bool = true) -> Bool {
        guard var all = try? loadAll(id, interactive: interactive) else {
            Diagnostics.log("\(id) web sign-in: remove skipped (couldn't read it)")
            return false
        }
        all[key] = nil
        let status: OSStatus
        if all.isEmpty {
            status = Keychain.deleteOwn(service: service(id))
        } else if let data = try? JSONEncoder().encode(all) {
            status = Keychain.update(service: service(id), account: account, data: data, interactive: interactive)
        } else {
            status = errSecParam
        }
        let ok = status == errSecSuccess || status == errSecItemNotFound
        Diagnostics.log("\(id) web sign-in: \(ok ? "removed" : "remove failed (\(status))")")
        return ok
    }

    /// Removes every account of one web app at once (Remove app).
    static func removeAll(_ id: String) {
        let status = Keychain.deleteOwn(service: service(id))
        Diagnostics.log("\(id) web sign-in: \(status == errSecSuccess || status == errSecItemNotFound ? "removed" : "remove failed (\(status))")")
    }

    /// With web sign-in off, a sign-in saved while it was on (in TAB Dev) is deleted quietly, so
    /// nothing stays behind that no screen could remove (security review).
    static func cleanUpIfOff() {
        guard !enabled else { return }
        for s in WebSite.all where s.readsUsage && Keychain.exists(service: service(s.id)) {
            Keychain.quietDelete(service: service(s.id))
            Diagnostics.log("\(s.id) web sign-in: removed (web sign-in is off)")
        }
    }

    /// The Cookie header for the site, or nil when nothing usable is left.
    static func header(_ saved: [Saved], now: Date = Date()) -> String? {
        let live = saved.filter { ($0.expires.map { $0 > now } ?? true) && GeminiAuth.safe($0.name) && GeminiAuth.safe($0.value) }
        guard !live.isEmpty else { return nil }
        return live.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// Opens the site's sign-in window and waits until its usage can be read. Returns the new account's key.
    @MainActor
    static func signIn(_ site: WebSite) async throws -> String {
        let window = WebSignInWindow(site: site)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
                window.start(done: { c.resume(with: $0) })
            }
        } onCancel: {
            Task { @MainActor in window.cancel() }
        }
    }
}

// MARK: ChatGPT on the web

/// ChatGPT's own usage view, with the session cookie from TAB's sign-in window. The cookie goes only
/// to chatgpt.com, to get a short-lived access token for the same usage call Codex uses.
struct ChatGPTWebProvider: UsageProvider {
    let id = "chatgpt"
    static let host = "chatgpt.com"
    func credentialAvailable() -> Bool { true }
    func sources() -> [String] { [] }

    func fetch(interactive: Bool) async throws -> [UsageLimit] {
        throw ProviderError.notSignedIn("Click Add account to sign in to ChatGPT.")
    }

    func read(source: String, interactive: Bool) async throws -> Reading {
        let saved = try WebAuth.load(id, account: source, interactive: interactive)
        let s = try await Self.session(saved)
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer " + s.token, forHTTPHeaderField: "Authorization")
        let r = try await HTTP.json(req, provider: "chatgpt")
        let limits = CodexProvider.limits(from: J.find(r, keys: ["rate_limit", "rate_limits"]) ?? r, base: Date())
        if limits.isEmpty { throw ProviderError.format("ChatGPT") }
        return Reading(limits: limits, email: s.email)
    }

    /// The access token and email from ChatGPT's session page. Nothing from it is logged.
    static func session(_ saved: [WebAuth.Saved], log: Bool = true) async throws -> (token: String, email: String?) {
        guard let cookie = WebAuth.header(saved) else { throw ProviderError.notSignedIn("Click Add account to sign in to ChatGPT.") }
        var r = URLRequest(url: URL(string: "https://\(host)/api/auth/session")!)
        r.setValue(cookie, forHTTPHeaderField: "Cookie")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await HTTP.raw(r, provider: "chatgpt-session", host: host, log: log)
        if (300..<400).contains(resp.statusCode) || resp.statusCode == 401 || resp.statusCode == 403 {
            throw ProviderError.expired("Your ChatGPT sign-in in TAB ended. Sign in again with Add account.")
        }
        guard resp.statusCode == 200, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.http(resp.statusCode)
        }
        guard let tok = headerSafe(o["accessToken"] as? String) else {
            throw ProviderError.expired("Your ChatGPT sign-in in TAB ended. Sign in again with Add account.")
        }
        return (tok, cleanEmail(J.dig(o, "user", "email")))
    }
}

// MARK: Sign-in window

/// The site's own page in a plain web view, with nothing saved on disk. Only the site's hosts load
/// here; anything else opens in the person's browser.
@MainActor
private final class WebSignInWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private let site: WebSite
    private var window: NSWindow?
    private var web: WKWebView?
    private var done: ((Result<String, Error>) -> Void)?
    private var checking = false
    private var timer: Timer?

    init(site: WebSite) { self.site = site }

    func start(done: @escaping (Result<String, Error>) -> Void) {
        self.done = done
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 680), configuration: config)
        web.navigationDelegate = self
        let w = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Sign in to \(site.name)"
        w.subtitle = "TAB keeps only what it needs, on this Mac"
        w.contentView = web
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        self.web = web
        self.window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        web.load(URLRequest(url: site.login))
        Diagnostics.log("\(site.id) web sign-in: opened")
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in
            self?.finish(.failure(ProviderError.notSignedIn("That took too long. Click Try again to sign in.")))
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    func windowWillClose(_ notification: Notification) {
        if done != nil { finish(.failure(CancellationError())) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" { return .allow }
        if url.scheme == "https", let h = url.host, site.allows(h) { return .allow }
        // Other sites open in the browser only when the person clicks a link, never from a script.
        if action.navigationType == .linkActivated, url.scheme == "https" { NSWorkspace.shared.open(url) }
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { check() }

    /// The window shows no address bar, so its subtitle says which site the page is on.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let h = webView.url?.host { window?.subtitle = "On \(h)" }
    }

    /// Tries the usage sign-in with the window's cookies. Once it works, saves only the kept cookie.
    private func check() {
        guard !checking, done != nil, site.readsUsage, let store = web?.configuration.websiteDataStore.httpCookieStore else { return }
        checking = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let cookies = await store.allCookies()
            defer { self.checking = false }
            let kept = cookies.filter(self.site.keeps).compactMap { c -> WebAuth.Saved? in
                guard GeminiAuth.safe(c.name), GeminiAuth.safe(c.value) else { return nil }
                return WebAuth.Saved(name: c.name, value: c.value, domain: c.domain.lowercased(), path: c.path.isEmpty ? "/" : c.path, expires: c.expiresDate)
            }
            guard !kept.isEmpty, (try? await ChatGPTWebProvider.session(kept, log: false)) != nil else { return }
            guard self.done != nil else { return }
            let key = UUID().uuidString.prefix(8).lowercased()
            guard WebAuth.save(self.site.id, account: String(key), cookies: kept, interactive: true) else {
                self.finish(.failure(ProviderError.denied("TAB couldn't finish signing in. Try again.")))
                return
            }
            Diagnostics.log("\(self.site.id) web sign-in: done")
            self.finish(.success(String(key)))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        guard let d = done else { return }
        done = nil
        timer?.invalidate()
        timer = nil
        web?.stopLoading()
        web?.navigationDelegate = nil
        window?.delegate = nil
        window?.close()
        web?.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        web = nil
        window = nil
        if case .failure(let e) = result, e is CancellationError { Diagnostics.log("\(site.id) web sign-in: cancelled") }
        d(result)
    }
}
