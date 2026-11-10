import Foundation
import AppKit

// Several accounts per app (v4, usability round 1). One circle per app; the account in use is
// the top one with fresh numbers, and the pill follows it. The person drags to reorder.
// Emails are shown in TAB's own screens only and never logged.

extension Store {
    /// An app's accounts, top first. A connected app always has at least one.
    func accountList(_ id: String) -> [Account] {
        let list = (accounts[id] ?? []).sorted { $0.order < $1.order }
        if list.isEmpty && connected.contains(id) { return [Account(id: "auto", email: nil, source: "auto", order: 0)] }
        return list
    }

    /// Makes sure a connected app has its first account (its usual sign-in).
    func ensureAccount(_ id: String) {
        if (accounts[id] ?? []).isEmpty { accounts[id] = [Account(id: "auto", email: nil, source: "auto", order: 0)] }
    }

    /// The account TAB follows: the first in order with fresh numbers, else the first with any.
    func accountInUse(_ id: String) -> Account? {
        let list = accountList(id)
        let snaps = accountSnapshots[id] ?? [:]
        if let fresh = list.first(where: { a in snaps[a.id].map { -$0.fetchedAt.timeIntervalSinceNow <= staleAfter } ?? false }) { return fresh }
        return list.first { snaps[$0.id] != nil } ?? list.first
    }

    /// What's left on one account, for the tab shown (or `Usage monitoring`).
    func accountPercent(_ id: String, _ accountID: String, for m: WatchMode? = nil) -> Double? {
        guard let s = accountSnapshots[id]?[accountID] else {
            // A single account read before v4 (previews, the Codex file) lives in `snapshots`.
            return accountList(id).count == 1 ? Store.primary(snapshots[id]?.limits ?? [], for: m ?? mode)?.percentLeft : nil
        }
        return Store.primary(s.limits, for: m ?? mode)?.percentLeft
    }

    /// Saves one account's reading and points the app's numbers at the account in use.
    func setReading(_ id: String, account accountID: String, limits: [UsageLimit], at: Date, email: String?) {
        var snaps = accountSnapshots[id] ?? [:]
        snaps[accountID] = ProviderSnapshot(limits: limits, fetchedAt: at)
        accountSnapshots[id] = snaps
        accountErrors[id]?[accountID] = nil
        if let e = email, var list = accounts[id], let i = list.firstIndex(where: { $0.id == accountID }), list[i].email != e {
            list[i].email = e
            accounts[id] = list
        }
        useAccountInUse(id)
    }

    /// `snapshots[id]` always holds the account in use, so the pill, tiles and warnings follow it.
    func useAccountInUse(_ id: String) {
        guard let a = accountInUse(id), let s = accountSnapshots[id]?[a.id] else { return }
        snapshots[id] = s
    }

    /// Reads every account of an app at once. Throws the first problem only if none worked.
    func refreshAccounts(_ id: String, provider p: UsageProvider, accounts accs: [Account], interactive: Bool) async throws {
        var results: [(String, Result<Reading, Error>)] = []
        await withTaskGroup(of: (String, Result<Reading, Error>).self) { group in
            for a in accs {
                group.addTask {
                    do { return (a.id, .success(try await p.read(source: a.source, interactive: interactive))) }
                    catch { return (a.id, .failure(error)) }
                }
            }
            for await r in group { results.append(r) }
        }
        var firstError: Error?
        let now = Date()
        for (accountID, r) in results {
            switch r {
            case .success(let reading): setReading(id, account: accountID, limits: reading.limits, at: now, email: reading.email)
            case .failure(let e):
                if firstError == nil { firstError = e }
                var errs = accountErrors[id] ?? [:]
                errs[accountID] = (e as? ProviderError)?.errorDescription ?? "Can't reach \(name(id)) right now."
                accountErrors[id] = errs
            }
        }
        if !results.contains(where: { if case .success = $0.1 { return true } else { return false } }), let e = firstError { throw e }
    }

    /// Drag to reorder (v4): the top account is used first.
    func moveAccount(_ id: String, from: Int, to: Int) {
        var list = accountList(id)
        guard list.indices.contains(from), to >= 0, to <= list.count, from != to else { return }
        let a = list.remove(at: from)
        list.insert(a, at: to > from ? to - 1 : to)
        for i in list.indices { list[i].order = i }
        accounts[id] = list
        useAccountInUse(id)
        updateAlerts()
    }

    /// Puts one account on top, so TAB uses it first.
    func useFirst(_ id: String, account accountID: String) {
        guard let i = accountList(id).firstIndex(where: { $0.id == accountID }) else { return }
        moveAccount(id, from: i, to: 0)
    }

    /// Removes one account. Removing the last one removes the app.
    func removeAccount(_ id: String, account accountID: String) {
        let list = accountList(id)
        guard list.count > 1 else { disconnect(id); return }
        if WebSite.site(id) != nil, self === Store.shared, !Store.isPreview, let a = list.first(where: { $0.id == accountID }) {
            // If its sign-in can't be removed, the account stays, so nothing is left behind unseen.
            guard WebAuth.remove(id, account: a.source) else { return }
        }
        var rest = list.filter { $0.id != accountID }
        for i in rest.indices { rest[i].order = i }
        accounts[id] = rest
        accountSnapshots[id]?[accountID] = nil
        accountErrors[id]?[accountID] = nil
        useAccountInUse(id)
        updateAlerts()
    }

    /// Apps that can hold more than one account, and so show "Add account".
    func canAddAccount(_ id: String) -> Bool {
        id == "claude" || id == "codex" || WebSite.site(id) != nil
    }

    /// Looks for other sign-ins of this app on this Mac and adds each one with a new email.
    /// Returns how many were added. Runs right after Connect and on Add account.
    /// Right after Connect it never asks macOS for access (`interactive: false`); only a click on
    /// Add account may.
    @discardableResult
    func discoverAccounts(_ id: String, interactive: Bool = false) async -> Int {
        guard let p = Providers.all[id], id == "claude" || id == "codex", !Store.isPreview, !devFrozen else { return 0 }
        var list = accountList(id)
        let known = Set(list.compactMap(\.email).map { $0.lowercased() })
        var added = 0
        if id == "claude" {
            // The Claude app and Claude Code: two accounts only when they are signed in as two people.
            let sources = p.sources()
            guard sources.count > 1 else { return 0 }
            var found: [(source: String, reading: Reading)] = []
            for s in sources {
                if let r = try? await p.read(source: s, interactive: interactive), r.email != nil { found.append((s, r)) }
            }
            let emails = Set(found.compactMap { $0.reading.email?.lowercased() })
            guard emails.count > 1 else { return 0 }
            var next: [Account] = []
            for f in found {
                guard let e = f.reading.email, !next.contains(where: { $0.email?.lowercased() == e.lowercased() }) else { continue }
                next.append(Account(id: "claude-" + f.source, email: e, source: f.source, order: next.count))
            }
            // The account that was first stays first.
            if let firstEmail = list.first?.email?.lowercased(), let i = next.firstIndex(where: { $0.email?.lowercased() == firstEmail }), i > 0 {
                next.insert(next.remove(at: i), at: 0)
            }
            for i in next.indices { next[i].order = i }
            added = max(0, next.count - list.count)
            accounts[id] = next
            accountSnapshots[id] = [:]
            for f in found { if let a = next.first(where: { $0.source == f.source }) { setReading(id, account: a.id, limits: f.reading.limits, at: Date(), email: f.reading.email) } }
        } else {
            // Codex: other Codex sign-ins in the Keychain, one per Codex folder.
            for s in p.sources() where s != "auto" && !list.contains(where: { $0.source == s }) {
                guard let r = try? await p.read(source: s, interactive: interactive), let e = r.email,
                      !known.contains(e.lowercased()), !list.contains(where: { $0.email?.lowercased() == e.lowercased() }) else { continue }
                let a = Account(id: "codex-" + UUID().uuidString.prefix(8), email: e, source: s, order: list.count)
                list.append(a)
                accounts[id] = list
                setReading(id, account: a.id, limits: r.limits, at: Date(), email: e)
                added += 1
            }
        }
        if added > 0 { Diagnostics.log("\(id): found \(added) more account(s)") }
        updateAlerts()
        return added
    }

    /// Add account (v4). Finds another sign-in on this Mac, asks for a Codex folder, or signs in
    /// on the web. Returns nil when one was added, or a short reason.
    func addAccount(_ id: String) async -> String? {
        if WebSite.site(id) != nil { return await addWebAccount(id) }
        if await discoverAccounts(id, interactive: true) > 0 { return nil }
        if id == "codex" {
            guard let path = Self.chooseCodexFolder() else { return "Cancelled." }
            return await addCodexFolder(path)
        }
        if id == "claude" {
            return "No other Claude account on this Mac. Sign in to a different one in the Claude app or Claude Code, then try again."
        }
        return "\(name(id)) has one account in TAB."
    }

    /// Adds a Codex folder (CODEX_HOME) the person picked, if it holds a sign-in for a new account.
    func addCodexFolder(_ path: String) async -> String? {
        guard CodexProvider.isCodexFolder(path) else { return "That folder has no Codex sign-in. Pick the folder Codex uses, like .codex." }
        let source = "folder:" + path
        var list = accountList("codex")
        if list.contains(where: { $0.source == source }) { return "That Codex folder is already added." }
        do {
            let r = try await CodexProvider().read(source: source, interactive: true)
            if let e = r.email, list.contains(where: { $0.email?.lowercased() == e.lowercased() }) {
                return "That's the same account as one you already have."
            }
            let a = Account(id: "codex-" + UUID().uuidString.prefix(8), email: r.email, source: source, order: list.count)
            list.append(a)
            accounts["codex"] = list
            setReading("codex", account: a.id, limits: r.limits, at: Date(), email: r.email)
            updateAlerts()
            return nil
        } catch {
            return (error as? ProviderError)?.errorDescription ?? "Couldn't read that Codex folder."
        }
    }

    @MainActor static func chooseCodexFolder() -> String? {
        let panel = NSOpenPanel()
        panel.title = "Choose a Codex folder"
        panel.message = "Pick the folder another Codex account uses (it holds auth.json)."
        panel.prompt = "Add account"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = homeURL("")
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    /// Signs in on a web app's own site and adds that sign-in as an account (behind a feature flag).
    func addWebAccount(_ id: String) async -> String? {
        guard let site = WebSite.site(id) else { return "TAB can't show usage for this app yet." }
        guard WebAuth.enabled, site.readsUsage else { return "TAB can't show usage for \(site.name) yet. It's on the list." }
        let key: String
        do { key = try await WebAuth.signIn(site) }
        catch is CancellationError { return "Cancelled." }
        catch { return (error as? ProviderError)?.errorDescription ?? error.localizedDescription }
        var list = accounts[id] ?? []
        let a = Account(id: "web-" + key, email: nil, source: key, order: list.count)
        list.append(a)
        accounts[id] = list
        if !connected.contains(id) { connected.append(id) }
        errors[id] = nil
        while loading.contains(id) { try? await Task.sleep(nanoseconds: 200_000_000) }
        await refresh(id, interactive: true, manual: true)
        if accountSnapshots[id]?[a.id] != nil { return nil }
        let reason = accountErrors[id]?[a.id] ?? errors[id] ?? "Couldn't reach \(site.name). Try again."
        // A sign-in that didn't lead to numbers is dropped again, so nothing stays behind.
        if list.count == 1 { disconnect(id) } else { removeAccount(id, account: a.id) }
        return reason
    }

    /// v4: when the account in use is low and another has room, which one to switch to.
    func switchSuggestion(_ id: String) -> (email: String, pct: Double)? {
        let list = accountList(id)
        guard list.count > 1, let use = accountInUse(id), let p = accountPercent(id, use.id, for: watch), p <= yellowAt else { return nil }
        let others = list.filter { $0.id != use.id }.compactMap { a -> (String, Double)? in
            guard let e = a.email, let s = accountSnapshots[id]?[a.id], -s.fetchedAt.timeIntervalSinceNow <= staleAfter,
                  let q = Store.primary(s.limits, for: watch)?.percentLeft, q > yellowAt else { return nil }
            return (e, q)
        }
        return others.max { $0.1 < $1.1 }.map { (email: $0.0, pct: $0.1) }
    }

    /// The line under an app in Settings (v4): "2 accounts · updated 2 min ago", or "Connected · …".
    func accountsLine(_ id: String) -> String {
        let n = accountList(id).count
        let head = n > 1 ? "\(n) accounts" : "Connected"
        if updating.contains(id) || loading.contains(id) { return head + " · syncing…" }
        guard let s = snapshots[id] else { return head }
        return head + " · updated " + Format.ago(s.fetchedAt)
    }
}

// MARK: Updates (v4, F13)

/// TAB's version and the newest release on GitHub.
enum Updates {
    static let latestURL = URL(string: "https://api.github.com/repos/araje-bot/TAB-Track-AI-Balance/releases/latest")!
    static let releasesPage = URL(string: "https://github.com/araje-bot/TAB-Track-AI-Balance/releases/latest")!

    /// This copy's version, from its Info.plist.
    static var current: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "dev"
    }

    /// True when `latest` is a newer version than `current` ("v0.2.0" > "0.1.1").
    static func isNewer(_ latest: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// The newest release's tag, or nil if GitHub can't be reached. Sends nothing about the person.
    static func latestTag() async -> String? {
        var r = URLRequest(url: latestURL)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await HTTP.raw(r, provider: "updates", host: "api.github.com"), resp.statusCode == 200,
              let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = o["tag_name"] as? String, tag.count <= 32,
              tag.range(of: #"^v?[0-9]+(\.[0-9]+){0,3}$"#, options: .regularExpression) != nil else { return nil }
        return tag
    }
}

/// "Check for updates" in Settings (v4). Asks GitHub for the newest release only when clicked.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    enum State: Equatable { case idle, checking, upToDate(Date), available(String), failed }
    @Published var state: State = .idle

    var line: String {
        switch state {
        case .idle: return "Checks GitHub only when you click"
        case .upToDate: return "You're up to date. " + checkedText
        case .checking: return "Checking…"
        case .available(let tag): return "TAB \(tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))) is out"
        case .failed: return "Couldn't check. Try again later."
        }
    }

    private var checkedText: String {
        guard case .upToDate(let d) = state else { return "" }
        return Calendar.current.isDateInToday(d) ? "Checked today." : "Checked \(Format.at(d))."
    }

    func check() {
        guard state != .checking else { return }
        if case .available = state { NSWorkspace.shared.open(Updates.releasesPage); return }
        state = .checking
        Task {
            let started = Date()
            let tag = await Updates.latestTag()
            // Long enough to read "Checking…".
            let wait = 0.6 - Date().timeIntervalSince(started)
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            guard let tag else { state = .failed; return }
            state = Updates.isNewer(tag, than: Updates.current) ? .available(tag) : .upToDate(Date())
        }
    }
}
