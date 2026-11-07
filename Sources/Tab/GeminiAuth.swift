import Foundation
import AppKit
import WebKit
import Security

/// TAB's own Google sign-in for the Gemini app's limits (AK, 2026-11-06): the 5-hour and weekly
/// limits that gemini.google.com/usage shows. Google stopped the Gemini CLI sign-in for personal,
/// AI Pro and Ultra accounts on 2026-06-18, so this is the way most people's numbers can be read.
///
/// The person signs in to Google in a small TAB window. That window keeps nothing on disk
/// (non-persistent web data). TAB keeps only the google.com session cookies, in its own Keychain
/// item, and sends them only to gemini.google.com, for the same usage call the page makes.
/// Nothing from another app or browser is read. Removing Gemini deletes the item.
/// Path from CodexBar's Gemini app source (docs/SYNC-PLAN.md).
enum GeminiAuth {
    static let service = "TAB Gemini sign-in"
    private static let account = "google"
    static let host = "gemini.google.com"

    /// The page's own usage query (UsagePageQuery), read-only.
    static var usageURL: URL {
        let signature = "2/dWbCvkVB0X16r9NPnxifeOAAqdCqMf0xeWvau9yPy7g="
        let variables = #"{"g1Request":{"entrypoints":["GEMINI_USAGE_SETTINGS_UPGRADE_BANNER"]},"workspaceRequest":{"recommendationsForSurfaceRequests":[]}}"#
        var c = URLComponents(string: "https://\(host)/_/BardChatUi/graphql/schemas/GEMINI_WEB_GRAPHQL/executeQuery")!
        c.queryItems = [URLQueryItem(name: "query_signature", value: signature), URLQueryItem(name: "variables", value: variables)]
        c.percentEncodedQuery = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return c.url!
    }

    static var signedIn: Bool { Keychain.ownExists(service: service) }

    // MARK: Cookies

    /// One saved cookie. Only what's needed to send it again.
    struct Saved: Codable, Equatable {
        var name: String
        var value: String
        var domain: String
        var path: String
        var expires: Date?
    }

    /// Only google.com cookies that gemini.google.com receives, never another site's.
    static func keep(_ cookies: [HTTPCookie]) -> [Saved] {
        cookies.compactMap { c in
            let d = c.domain.lowercased()
            let bare = d.hasPrefix(".") ? String(d.dropFirst()) : d
            guard bare == "google.com" || bare == host else { return nil }
            // Expired ones are kept here on purpose: in a reply, that's how Google deletes a
            // cookie, and `merge` then drops it. `header` never sends an expired one.
            guard safe(c.name), c.value.isEmpty || safe(c.value) else { return nil }
            return Saved(name: c.name, value: c.value, domain: d, path: c.path.isEmpty ? "/" : c.path, expires: c.expiresDate)
        }
    }

    /// A cookie name or value that can't break the header (no spaces, ";" or control characters).
    static func safe(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 4096 && s.unicodeScalars.allSatisfy { $0.value > 0x20 && $0.value < 0x7F && $0 != ";" && $0 != "," }
    }

    /// The Cookie header for gemini.google.com's usage call, or nil if nothing usable is left.
    /// Only cookies for that host and path, never expired ones.
    static func header(_ saved: [Saved], now: Date = Date()) -> String? {
        let path = usageURL.path
        let live = saved.filter { s in
            let bare = s.domain.hasPrefix(".") ? String(s.domain.dropFirst()) : s.domain
            return (bare == "google.com" || bare == host) && s.path.hasPrefix("/") && path.hasPrefix(s.path)
                && (s.expires.map { $0 > now } ?? true) && safe(s.name) && safe(s.value)
        }
        guard !live.isEmpty else { return nil }
        return live.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    /// Cookies Google refreshed in a reply replace the saved ones with the same name, domain and
    /// path. An expired one in a reply is Google deleting it. Expired ones never stay.
    static func merge(_ saved: [Saved], _ fresh: [Saved], now: Date = Date()) -> [Saved] {
        var out = saved.filter { s in !fresh.contains { $0.name == s.name && $0.domain == s.domain && $0.path == s.path } }
        out.append(contentsOf: fresh)
        return out.filter { ($0.expires.map { $0 > now } ?? true) && safe($0.value) }
    }

    static func load(interactive: Bool) throws -> [Saved] {
        let r = Keychain.readOwn(service: service, account: account, interactive: interactive)
        if Keychain.isPermissionProblem(r.status) {
            throw interactive ? ProviderError.denied("macOS didn't let TAB check Gemini. Try again and choose Always Allow.") : ProviderError.needsApproval
        }
        guard r.status == errSecSuccess, let d = r.data, let s = try? JSONDecoder().decode([Saved].self, from: d) else {
            if r.status == errSecSuccess { signOut() }   // unreadable: start clean next time
            throw ProviderError.notSignedIn("Sign in to Google in TAB to see Gemini's limits.")
        }
        return s
    }

    /// Saves the sign-in. Only the sign-in window creates the item (`create`); a background
    /// refresh only updates it, so a refresh racing Remove can never bring it back.
    @discardableResult
    static func save(_ cookies: [Saved], interactive: Bool, create: Bool = false) -> Bool {
        guard let data = try? JSONEncoder().encode(cookies) else { return false }
        if Keychain.update(service: service, account: account, data: data, interactive: interactive) == errSecSuccess { return true }
        guard create, !Keychain.exists(service: service) else { return false }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecAttrLabel as String: service,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                  kSecValueData as String: data]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func signOut() {
        let status = Keychain.deleteOwn(service: service)
        Diagnostics.log(status == errSecSuccess || status == errSecItemNotFound
                        ? "gemini sign-in: removed" : "gemini sign-in: remove failed (\(status))")
    }

    // MARK: Usage

    /// The two limits from the page's reply, or nil when the reply isn't what TAB expects.
    /// `signedOut` is true when Google answered but no one is signed in.
    static func parse(_ body: String) -> (limits: [UsageLimit], signedOut: Bool)? {
        var text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<") { return ([], true) }
        if text.hasPrefix(")]}'") { text = String(text.dropFirst(4)) }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return nil }
        let results = (obj as? [Any]) ?? [obj]
        guard let data = results.compactMap({ ($0 as? [String: Any])?["data"] as? [String: Any] })
                .first(where: { $0.keys.contains("viewer") }) else { return nil }
        if data["viewer"] is NSNull { return ([], true) }
        guard let pools = J.dig(data, "viewer", "rpcs", "getUsageInfo", "pools") as? [[String: Any]] else { return nil }
        func limit(_ type: String, _ kind: LimitKind, _ label: String) -> UsageLimit? {
            guard let p = pools.first(where: { $0["poolType"] as? String == type }),
                  let used = J.num(p["percentageUsed"]), used.isFinite, used >= 0 else { return nil }
            let reset = J.date(J.dig(p, "gxu", "windowRefreshesAt"))
            return UsageLimit(kind: kind, label: label, percentLeft: max(0, min(100, 100 - used * 100)), resetsAt: reset)
        }
        let out = [limit("GXU_FIVE_HOURLY", .short, "5 hours"), limit("GXU_WEEKLY", .long, "Week")].compactMap { $0 }
        return out.isEmpty ? nil : (out, false)
    }

    /// Asks gemini.google.com for the limits with the saved sign-in. Saves any cookie Google refreshed.
    static func fetch(interactive: Bool) async throws -> [UsageLimit] {
        let saved = try load(interactive: interactive)
        do {
            let (limits, fresh) = try await query(saved)
            if !fresh.isEmpty { save(merge(saved, fresh), interactive: false) }
            return limits
        } catch ProviderError.expired {
            // Google ended the session: drop it, so the card shows Connect and opens the window again.
            signOut()
            throw ProviderError.notSignedIn("Your Google sign-in in TAB ended. Click Connect to sign in again.")
        }
    }

    /// One usage call with these cookies. Returns the limits and any cookies Google refreshed.
    /// `log` is false while the sign-in window waits, so its checks don't fill the log.
    static func query(_ saved: [Saved], log: Bool = true) async throws -> ([UsageLimit], [Saved]) {
        guard let cookie = header(saved) else { throw ProviderError.notSignedIn("Sign in to Google in TAB to see Gemini's limits.") }
        var r = URLRequest(url: usageURL)
        r.setValue(cookie, forHTTPHeaderField: "Cookie")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        r.setValue("https://\(host)/usage", forHTTPHeaderField: "Referer")
        let (data, resp) = try await HTTP.raw(r, provider: "gemini", host: host, log: log)
        let fresh = keep(HTTPCookie.cookies(withResponseHeaderFields: resp.allHeaderFields as? [String: String] ?? [:], for: usageURL))
        // A redirect means Google sent TAB to its sign-in page: the session ended.
        if (300..<400).contains(resp.statusCode) || resp.statusCode == 401 || resp.statusCode == 403 {
            throw ProviderError.expired("Your Google sign-in in TAB ended. Click Connect to sign in again.")
        }
        guard resp.statusCode == 200 else { throw ProviderError.http(resp.statusCode) }
        guard let p = parse(String(decoding: data, as: UTF8.self)) else { throw ProviderError.format("Gemini") }
        if p.signedOut { throw ProviderError.expired("Your Google sign-in in TAB ended. Click Connect to sign in again.") }
        return (p.limits, fresh)
    }

    // MARK: Sign-in window

    /// Opens TAB's Google sign-in window and waits until Gemini's limits can be read with it.
    /// Throws CancellationError if the person closes the window or clicks Cancel.
    @MainActor
    static func signIn() async throws {
        let window = SignInWindow()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                window.start(done: { result in c.resume(with: result) })
            }
        } onCancel: {
            Task { @MainActor in window.cancel() }
        }
    }
}

/// The sign-in window: Google's own page in a plain web view, with nothing saved on disk.
@MainActor
private final class SignInWindow: NSObject, WKNavigationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var web: WKWebView?
    private var done: ((Result<Void, Error>) -> Void)?
    private var checking = false
    private var timer: Timer?

    /// Google's sign-in, returning to Gemini's usage page.
    private static let start = URL(string: "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fgemini.google.com%2Fusage")!

    func start(done: @escaping (Result<Void, Error>) -> Void) {
        self.done = done
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 480, height: 640), configuration: config)
        web.navigationDelegate = self
        let w = NSWindow(contentRect: web.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Sign in to Google"
        w.subtitle = "For Gemini's limits in TAB"
        w.contentView = web
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        self.web = web
        self.window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        web.load(URLRequest(url: Self.start))
        Diagnostics.log("gemini sign-in: opened")
        // Also check every few seconds, since Google's pages don't always finish a navigation.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        // Give up after 10 minutes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) { [weak self] in
            self?.finish(.failure(ProviderError.notSignedIn("That took too long. Click Try again to sign in.")))
        }
    }

    func cancel() { finish(.failure(CancellationError())) }

    func windowWillClose(_ notification: Notification) {
        if done != nil { finish(.failure(CancellationError())) }
    }

    /// Only Google's own pages load here. Anything else opens in the person's browser.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = action.request.url else { return .cancel }
        if url.scheme == "about" || url.scheme == "blob" || url.scheme == "data" { return .allow }
        let h = url.host?.lowercased() ?? ""
        let google = ["google.com", "gstatic.com", "youtube.com", "googleusercontent.com"]
            .contains { h == $0 || h.hasSuffix("." + $0) }
        if url.scheme == "https" && google { return .allow }
        if action.targetFrame?.isMainFrame == true, url.scheme == "https" { NSWorkspace.shared.open(url) }
        return .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView.url?.host == GeminiAuth.host { check() }
    }

    /// Tries the usage call with the window's cookies. Once it works, saves them and closes.
    private func check() {
        guard !checking, done != nil, let store = web?.configuration.websiteDataStore.httpCookieStore else { return }
        checking = true
        Task { @MainActor [weak self] in
            let cookies = await store.allCookies()
            defer { self?.checking = false }
            let saved = GeminiAuth.keep(cookies).filter { $0.expires.map { $0 > Date() } ?? true }
            // Not signed in yet: Google sets these session cookies only after a sign-in.
            guard saved.contains(where: { $0.name.hasSuffix("SID") }) else { return }
            guard let (_, fresh) = try? await GeminiAuth.query(saved, log: false) else { return }
            // Cancelled, closed or timed out while the check ran: keep nothing.
            guard let self, self.done != nil else { return }
            guard GeminiAuth.save(GeminiAuth.merge(saved, fresh), interactive: true, create: true) else {
                self.finish(.failure(ProviderError.denied("TAB couldn't finish signing in. Try again.")))
                return
            }
            Diagnostics.log("gemini sign-in: done")
            self.finish(.success(()))
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let d = done else { return }
        done = nil
        timer?.invalidate()
        timer = nil
        web?.stopLoading()
        web?.navigationDelegate = nil
        window?.delegate = nil
        window?.close()
        // Nothing from the sign-in stays in the window's memory either.
        web?.configuration.websiteDataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                                                       modifiedSince: .distantPast) {}
        web = nil
        window = nil
        if case .failure(let e) = result, e is CancellationError { Diagnostics.log("gemini sign-in: cancelled") }
        d(result)
    }
}
