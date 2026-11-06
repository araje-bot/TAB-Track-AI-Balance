import Foundation
import AppKit
import SwiftUI

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var detected: [AIApp] = []
    @Published var snapshots: [String: ProviderSnapshot] = [:] { didSet { updateAlerts() } }
    @Published var errors: [String: String] = [:]
    @Published var loading: Set<String> = []
    /// Apps the person asked to update by hand. Their status reads "Syncing…" until it finishes.
    @Published var updating: Set<String> = []
    /// Apps that just finished a manual update. Their status shows when, for a few seconds only.
    @Published var justUpdated: Set<String> = []
    /// Apps waiting for the person to click Allow before macOS may ask about their sign-in.
    @Published var needsApproval: Set<String> = []
    @Published var tick = Date()

    /// "Usage monitoring" (AK): the default view, chosen in onboarding or Settings. It is the limit
    /// the pill watches, and every time TUM opens its tabs start here.
    @Published var watch: WatchMode { didSet { defaults.set(watch.rawValue, forKey: "mode"); mode = watch; updateAlerts() } }
    /// The tab the popover shows right now. Clicking a tab only changes this view, never the
    /// default or the pill; opening TUM again starts on `watch`.
    @Published var mode: WatchMode
    /// "Turn yellow at": an app at or under this % left turns the icon into the yellow pill.
    @Published var threshold: Double { didSet { defaults.set(threshold, forKey: "threshold"); updateAlerts() } }
    /// Red is automatic (AK): at or under 10% left the pill turns red. Not a setting.
    let redAt: Double = 10
    @Published var connected: [String] { didSet { defaults.set(connected, forKey: "connected"); updateAlerts() } }
    /// Bump when onboarding changes, so everyone sees the new version once.
    static let onboardingVersion = 3

    /// Identifies this installed copy of TUM: when its program file was built. Installing a
    /// new build from the DMG changes it, so the welcome screens show again on every install.
    static var buildStamp: Int {
        guard let exe = Bundle.main.executableURL,
              let d = (try? FileManager.default.attributesOfItem(atPath: exe.path))?[.modificationDate] as? Date else { return 1 }
        return Int(d.timeIntervalSince1970)
    }

    static func onboardingSeenForThisCopy() -> Bool {
        let d = UserDefaults.standard
        guard d.integer(forKey: "onboardingVersion") >= onboardingVersion else { return false }
        #if DEBUG
        // Debug builds change on every rebuild. Show the welcome screens only on a fresh start
        // (Developer > Start fresh), or jump to a step from the Developer menu.
        return true
        #else
        let done = d.integer(forKey: "onboardingBuild")
        let ok = done == buildStamp
        if !ok { Diagnostics.log("new install (build \(buildStamp), onboarding was done on \(done)): showing welcome screens") }
        return ok
        #endif
    }
    @Published var onboardingDone: Bool {
        didSet {
            defaults.set(onboardingDone ? Self.onboardingVersion : 0, forKey: "onboardingVersion")
            defaults.set(onboardingDone ? Self.buildStamp : 0, forKey: "onboardingBuild")
            // Only the real store may open background Keychain reads; sample stores never do.
            if defaults === UserDefaults.standard { Keychain.silentReadsAllowed = onboardingDone }
        }
    }
    /// Off by default: TUM changes its icon and does not pop things up unless asked.
    @Published var headsUpOnOpen: Bool { didSet { defaults.set(headsUpOnOpen, forKey: "headsUpOnOpen") } }
    /// The shortcut the person picked, and the one actually working (another app may own the pick).
    @Published var shortcutChoice: ShortcutChoice { didSet { defaults.set(shortcutChoice.stored, forKey: "shortcutChoice"); onShortcutChange?() } }
    @Published var activeShortcut: ShortcutChoice = .commandT
    var onShortcutChange: (() -> Void)?
    /// The person's own shortcut from Custom, kept even while a preset is picked.
    @Published var customShortcut: ShortcutChoice? { didSet { defaults.set(customShortcut?.stored, forKey: "customShortcut") } }
    /// True while Custom waits for keys. The working shortcut is paused meanwhile, so pressing it
    /// records it instead of opening the quick view.
    @Published private(set) var recordingShortcut = false
    /// Why the last key press can't be the shortcut, shown in the row while recording.
    @Published private(set) var shortcutProblem: ShortcutProblem?
    var onShortcutRecording: ((Bool) -> Void)?

    /// The keys pressed in the shortcut box, shown there until Save (AK: see it, then set it).
    @Published private(set) var pendingShortcut: ShortcutChoice?

    func startRecordingShortcut() {
        shortcutProblem = nil
        pendingShortcut = nil
        guard !recordingShortcut else { return }
        recordingShortcut = true
        onShortcutRecording?(true)
    }

    func stopRecordingShortcut() {
        shortcutProblem = nil
        pendingShortcut = nil
        guard recordingShortcut else { return }
        recordingShortcut = false
        onShortcutRecording?(false)
    }

    /// A key press in the shortcut box: a good one shows in the box until Save; a bad one says
    /// why and keeps listening.
    func recorded(_ result: Result<ShortcutChoice, ShortcutProblem>) {
        switch result {
        case .failure(let p): shortcutProblem = p; pendingShortcut = nil
        case .success(let c): shortcutProblem = nil; pendingShortcut = c
        }
    }

    /// Save in the shortcut box: the keys shown there become the shortcut.
    func saveRecordedShortcut() {
        guard recordingShortcut, let c = pendingShortcut else { return }
        recordingShortcut = false
        shortcutProblem = nil
        pendingShortcut = nil
        if !ShortcutChoice.presets.contains(c) { customShortcut = c }
        shortcutChoice = c
        onShortcutRecording?(false)
    }

    /// The "See all apps" subtitle: what to press while recording, a problem, or another app
    /// owning the pick. One line, so the row never changes height (AK).
    func shortcutSubtitle(_ normal: String) -> String {
        if recordingShortcut { return "Set your own keys in the box that opened" }
        if activeShortcut != shortcutChoice { return "Taken by another app, so \(activeShortcut.glyphs) works" }
        return normal
    }
    /// TUM is always in the Dock while one of its windows is open. This keeps it there all the time.
    @Published var alwaysInDock: Bool { didSet { defaults.set(alwaysInDock, forKey: "alwaysInDock"); onDockSettingChange?() } }
    var onDockSettingChange: (() -> Void)?
    private var lastHeadsUp: [String: Date] = [:]

    /// Where settings are saved. Previews and sample data use a scratch suite, never the real one.
    private let defaults: UserDefaults
    private var backoff: [String: Date] = [:]
    /// Failed checks in a row, per app. Each failure doubles the wait before the next automatic
    /// check (1, 2, 4 ... 60 minutes), so a broken sign-in never calls a service every minute
    /// (security review M3). A success or a manual "Sync" starts over.
    private var failures: [String: Int] = [:]

    private func noteFailure(_ id: String) {
        let n = (failures[id] ?? 0) + 1
        failures[id] = n
        let wait = min(60.0 * pow(2, Double(n - 1)), 3600)
        backoff[id] = max(backoff[id] ?? .distantPast, Date().addingTimeInterval(wait))
    }
    private var iconCache: [String: NSImage] = [:]
    private var glyphCache: [String: NSImage] = [:]
    private var noGlyph: Set<String> = []
    /// Set at launch when the menu bar icon can't be seen (for example, hidden by the notch).
    @Published var menuBarHidden = false
    private var pending: Set<String> = []
    private var lastAttempt: [String: Date] = [:]
    private var codexHint: URL?

    /// Minutes after which a reading is treated as old and never drives a warning.
    let staleAfter: TimeInterval = 15 * 60

    /// True inside the Xcode canvas. Release builds never look at the environment for this.
    #if DEBUG
    static let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    #else
    static let isPreview = false
    #endif

    /// Sample data is showing (Developer menu, previews, self-test), so refreshes are skipped.
    var devFrozen = false
    /// Developer menu: an app it connected only to show a fake state.
    var devAddedID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // "Both" was removed (AK); it and anything unknown start on Session.
        let saved = WatchMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .session
        watch = saved
        mode = saved
        let t = defaults.double(forKey: "threshold")
        // Yellow always sits above red's 10% (the old 10% option moves to 20%).
        threshold = Thresholds.yellow.map(\.0).contains(t) ? t : (t > 0 && t <= 15 ? 20 : 25)
        // Keep only apps TUM can read (AK: a connection with no numbers is no use).
        // Apps connected with no numbers by older versions, and unknown ones, go.
        connected = (defaults.stringArray(forKey: "connected") ?? []).filter { Providers.all[$0] != nil }
        let seen = Self.onboardingSeenForThisCopy()
        onboardingDone = seen
        if defaults === UserDefaults.standard { Keychain.silentReadsAllowed = seen }
        headsUpOnOpen = defaults.bool(forKey: "headsUpOnOpen")
        // ⌘T became the default on 2026-11-04. Move everyone to it once; after that the choice sticks.
        if !defaults.bool(forKey: "shortcutDefaultCommandT") {
            defaults.set(true, forKey: "shortcutDefaultCommandT")
            defaults.removeObject(forKey: "shortcutChoice")
        }
        let choice = ShortcutChoice(stored: defaults.string(forKey: "shortcutChoice") ?? "") ?? .commandT
        shortcutChoice = choice
        // ⌥ Space was a preset before Custom existed; it now lives in the Custom slot.
        customShortcut = defaults.string(forKey: "customShortcut").flatMap(ShortcutChoice.init(stored:))
            ?? (ShortcutChoice.presets.contains(choice) ? nil : choice)
        alwaysInDock = defaults.bool(forKey: "alwaysInDock")
    }

    // MARK: Apps

    func scan() {
        detected = Detector.scan()
        iconCache = [:]; glyphCache = [:]; noGlyph = []
    }

    func app(_ id: String) -> AIApp? { detected.first { $0.id == id } }
    func name(_ id: String) -> String {
        app(id)?.name ?? Catalog.entry(id)?.name ?? id
    }

    /// Ready to connect: apps on this Mac that TUM can read.
    var readyToConnect: [AIApp] { detected.filter(\.supported) }

    /// Coming soon: apps on this Mac that TUM can't read yet (first), then the planned apps.
    /// Nothing here can be connected until TUM can show real numbers for it (AK).
    var comingSoon: [AIApp] {
        let waiting = detected.filter { !$0.supported }
        let found = Set(detected.map(\.id))
        return waiting + Catalog.plannedApps.filter { !found.contains($0.id) }
    }

    /// True when TUM can read this app's usage. Only these can be connected.
    func readsUsage(_ id: String) -> Bool { Providers.all[id] != nil }
    func symbol(_ id: String) -> String { Catalog.entry(id)?.symbol ?? "sparkle" }
    func source(_ id: String) -> String { Catalog.entry(id)?.source ?? "" }

    /// The app's real icon when it's installed, otherwise its official logo (`BrandLogos`).
    func icon(_ id: String) -> NSImage? {
        if let c = iconCache[id] { return c }
        let img = app(id)?.appURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? BrandLogos.tile(id)
        if let img = img { iconCache[id] = img }
        return img
    }

    /// The app's logo as a white mark, made from its installed icon.
    func glyph(_ id: String) -> NSImage? {
        if LaunchGuard.safeMode { return nil }
        if let g = glyphCache[id] { return g }
        if noGlyph.contains(id) { return nil }
        // The official one-color mark is the cleanest white logo; otherwise derive it from the icon.
        if let mark = BrandLogos.glyph(id) { glyphCache[id] = mark; return mark }
        guard let ic = icon(id) else { return nil }
        guard let g = GlyphMaker.whiteGlyph(from: ic) else { noGlyph.insert(id); return nil }
        glyphCache[id] = g
        return g
    }

    /// App used in onboarding examples: Claude by default, otherwise an app found on this Mac.
    var demoID: String {
        if connected.contains("claude") || app("claude") != nil { return "claude" }
        return connected.first ?? detected.first(where: { $0.supported })?.id ?? "claude"
    }

    func connect(_ id: String) {
        guard readsUsage(id) else { return }
        if !connected.contains(id) { connected.append(id) }
        errors[id] = nil
        Task { await refresh(id) }
    }

    /// Connects and checks it really works. Returns nil on success or a short reason.
    /// The GitHub code to show while the person approves TUM on github.com (Copilot sign-in).
    @Published var githubCode: GitHubAuth.DeviceCode?

    func connectAndCheck(_ id: String) async -> String? {
        // TUM can't read it yet, so there is nothing to connect.
        guard Providers.all[id] != nil else { return "TUM can't show usage for this app yet." }
        var signedInNow = false
        // Cursor and Grok Bot need TUM's own Cursor sign-in first (opens the browser).
        if (id == "cursor" || id == "grokbot") && !CursorAuth.signedIn {
            do { try await CursorAuth.signIn(); signedInNow = true }
            catch is CancellationError { return "Cancelled." }
            catch { return error.localizedDescription }
        }
        // Copilot signs in with GitHub only when VS Code or the GitHub CLI haven't already.
        if id == "copilot" && !GitHubAuth.signedIn && !CopilotProvider().hasLocalSignIn() {
            defer { githubCode = nil }
            do { try await GitHubAuth.signIn(show: { [weak self] code in self?.githubCode = code }); signedInNow = true }
            catch is CancellationError { return "Cancelled." }
            catch { return error.localizedDescription }
        }
        // Gemini signs in with Google, unless a working Gemini CLI sign-in is already here.
        if id == "gemini" && !GeminiAuth.signedIn {
            var cliWorks = false
            if GeminiProvider().hasCLISignIn { cliWorks = (try? await GeminiProvider().fetchCLI()) != nil }
            if !cliWorks {
                do { try await GeminiAuth.signIn(); signedInNow = true }
                catch is CancellationError { return "Cancelled." }
                catch { return error.localizedDescription }
            }
        }
        if !connected.contains(id) { connected.append(id) }
        errors[id] = nil
        backoff[id] = nil
        while loading.contains(id) { try? await Task.sleep(nanoseconds: 200_000_000) }
        let started = Date()
        await refresh(id, interactive: true)
        // Keep the progress visible briefly, so Try again never looks like nothing happened.
        let wait = 0.7 + started.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        if snapshots[id] != nil { return nil }
        let reason = errors[id] ?? "Couldn't reach \(name(id)). Try again."
        connected.removeAll { $0 == id }
        errors[id] = nil
        // A sign-in made just now that didn't end in a working connection is dropped again, so no
        // token stays behind with nothing in TUM to remove it (security review).
        if signedInNow {
            if id == "copilot" { GitHubAuth.signOut() } else if id == "gemini" { GeminiAuth.signOut() } else { CursorAuth.signOut() }
        }
        return reason
    }

    /// Disconnecting also signs out of that service inside TUM.
    func disconnect(_ id: String) {
        connected.removeAll { $0 == id }
        snapshots[id] = nil
        errors[id] = nil
        needsApproval.remove(id)
        if id == "claude" { ClaudeDesktop.forget() }
        // TUM's own Cursor sign-in goes away once nothing uses it.
        if id == "copilot", self === Store.shared, !Store.isPreview, GitHubAuth.signedIn { GitHubAuth.signOut() }
        if id == "gemini", self === Store.shared, !Store.isPreview, GeminiAuth.signedIn { GeminiAuth.signOut() }
        // Only when the person removes Cursor or Grok Bot themselves, never as a side effect.
        if id == "cursor" || id == "grokbot",
           self === Store.shared, !Store.isPreview, !connected.contains("cursor"), !connected.contains("grokbot"), CursorAuth.signedIn {
            CursorAuth.signOut()
        }
    }

    // MARK: Scan

    @Published var scanning = false

    /// Looks for AI apps again, with a short visible scan so people see it happened.
    func scanAnimated() async {
        guard !scanning else { return }
        scanning = true
        let started = Date()
        let found = await Task.detached(priority: .userInitiated) { Detector.scan() }.value
        let wait = 0.9 + started.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            detected = found
            iconCache = [:]; glyphCache = [:]; noGlyph = []
        }
        scanning = false
    }

    func removeAll() {
        for id in connected { disconnect(id) }
    }

    // MARK: Refresh

    func refreshAll() async {
        for id in connected { await refresh(id) }
    }

    func refreshIfOld() async {
        for id in connected {
            let age = snapshots[id].map { -$0.fetchedAt.timeIntervalSinceNow } ?? .infinity
            if age > 60 { await refresh(id) }
        }
    }

    // MARK: Activity

    /// Shortest gap between checks that activity can trigger. Claude's usage
    /// address refuses frequent requests, and Codex is read on this Mac for free.
    static func minGap(_ id: String) -> TimeInterval {
        switch id {
        case "codex": return 3
        case "claude": return 60
        case "cursor": return 120
        default: return 60
        }
    }

    /// An app was just used. Check it soon, without asking its company too often.
    func activity(_ id: String, file: URL? = nil) {
        if id == "codex", let f = file, f.pathExtension == "jsonl" { codexHint = f }
        guard connected.contains(id), !pending.contains(id) else { return }
        pending.insert(id)
        let since = lastAttempt[id].map { -$0.timeIntervalSinceNow } ?? .infinity
        // Wait a few seconds so the reply finishes and the company's count catches up.
        let wait = max(id == "codex" ? 1.5 : 8, Self.minGap(id) - since)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            self.pending.remove(id)
            await self.refresh(id)
        }
    }

    func connectedID(for bundleURL: URL?) -> String? {
        guard let u = bundleURL?.standardizedFileURL,
              let a = detected.first(where: { $0.appURL?.standardizedFileURL == u }),
              connected.contains(a.id) else { return nil }
        return a.id
    }

    /// True when the person opened a connected app that is low, at most once every 30 minutes per app.
    func shouldHeadsUp(_ id: String) -> Bool {
        guard headsUpOnOpen, !isStale(id), level(watchPercent(id)) != .ok else { return false }
        // Every switch to a low app shows it, but not again within a minute (fast back-and-forth).
        if let t = lastHeadsUp[id], -t.timeIntervalSinceNow < 60 { return false }
        lastHeadsUp[id] = Date()
        return true
    }

    /// Maps an app the person just left back to a connected provider.
    func activity(bundleURL: URL?) {
        guard let u = bundleURL?.standardizedFileURL,
              let a = detected.first(where: { $0.appURL?.standardizedFileURL == u }) else { return }
        activity(a.id)
    }

    /// `interactive` is true only right after the person clicked Connect or Allow.
    /// Before onboarding is finished, nothing is read unless the person asked.
    func refresh(_ id: String, interactive: Bool = false, manual: Bool = false) async {
        guard let p = Providers.all[id] else { return }
        guard onboardingDone || interactive else { return }
        // Xcode previews never read sign-ins or call any service.
        if Self.isPreview { return }
        // Sample data (Developer menu, previews, self-test) stays put until "Use real data", or
        // until the person clicks Sync on that app, which always asks for real numbers.
        if devFrozen && !manual { return }
        if loading.contains(id) {
            // Sync while a check is already running waits for that answer instead of claiming a
            // sync that never happened.
            if manual { while loading.contains(id) { try? await Task.sleep(nanoseconds: 150_000_000) } }
            return
        }

        // Codex keeps its own usage in the session file. Use it when it is recent.
        if id == "codex", !manual, let local = CodexLocal.latest(hint: codexHint),
           -local.at.timeIntervalSinceNow < 600,
           local.at >= (snapshots[id]?.fetchedAt ?? .distantPast) {
            snapshots[id] = ProviderSnapshot(limits: local.limits, fetchedAt: local.at)
            errors[id] = nil
            lastAttempt[id] = Date()
            return
        }

        if let b = backoff[id], b > Date() { return }
        // Automatic checks keep each service's minimum gap, whichever timer asked (security review).
        if !manual, !interactive, let last = lastAttempt[id], -last.timeIntervalSinceNow < Self.minGap(id) { return }
        lastAttempt[id] = Date()
        loading.insert(id)
        defer { loading.remove(id) }
        do {
            let limits = try await p.fetch(interactive: interactive)
            snapshots[id] = ProviderSnapshot(limits: limits, fetchedAt: Date())
            errors[id] = nil
            needsApproval.remove(id)
            failures[id] = nil
            backoff[id] = nil
        } catch ProviderError.needsApproval {
            needsApproval.insert(id)
            errors[id] = ProviderError.needsApproval.errorDescription
        } catch ProviderError.rateLimited(let until) {
            backoff[id] = until
        } catch let e as ProviderError {
            noteFailure(id)
            if useCodexFileInstead(id) { return }
            errors[id] = e.errorDescription
            // Cursor ended TUM's sign-in: the card shows Connect again, which opens the browser.
            if case .notSignedIn = e, id == "cursor" || id == "grokbot", !CursorAuth.signedIn { needsApproval.insert(id) }
            // The same for Gemini when Google ended TUM's sign-in and no Gemini CLI sign-in is here.
            if case .notSignedIn = e, id == "gemini", !GeminiAuth.signedIn, !GeminiProvider().hasCLISignIn { needsApproval.insert(id) }
            Diagnostics.log("\(id) error: \(Diagnostics.describe(e))")
        } catch {
            noteFailure(id)
            if useCodexFileInstead(id) { return }
            errors[id] = "Can't reach \(name(id)) right now."
            Diagnostics.log("\(id) error: \(Diagnostics.describe(error))")
        }
    }

    /// Backup for Codex: its own session file on this Mac, even if older (shown with its time).
    private func useCodexFileInstead(_ id: String) -> Bool {
        guard id == "codex", let local = CodexLocal.latest(hint: codexHint) else { return false }
        snapshots[id] = ProviderSnapshot(limits: local.limits, fetchedAt: local.at)
        errors[id] = nil
        return true
    }

    // MARK: Derived values

    /// The limits shown for a tab (the popover's current one unless another is given).
    func visibleLimits(_ id: String, for m: WatchMode? = nil) -> [UsageLimit] {
        let all = snapshots[id]?.limits ?? []
        let tab = m ?? mode
        let match = all.filter { tab.matches($0) }
        // No limit of this period (Claude has no monthly one): show the app's own limits, so
        // nothing goes blank and warnings never get lost.
        return match.isEmpty ? all : match
    }

    /// The limit that drives the pill. When both are shown, the session limit comes first;
    /// otherwise the one with the least left. Limits whose reset already passed are skipped.
    func primaryLimit(_ id: String, for m: WatchMode? = nil) -> UsageLimit? {
        let live = visibleLimits(id, for: m).filter { !$0.isReset }
        return live.first { $0.kind == .short } ?? live.min { $0.percentLeft < $1.percentLeft }
    }

    /// What the popover's current tab shows.
    func percent(_ id: String) -> Double? { primaryLimit(id)?.percentLeft }

    /// The limit the pill, warnings and hover tip watch: always "Usage monitoring", whatever tab
    /// is open, so flipping tabs never changes the menu bar.
    func watchLimit(_ id: String) -> UsageLimit? { primaryLimit(id, for: watch) }
    func watchPercent(_ id: String) -> Double? { watchLimit(id)?.percentLeft }

    /// True for apps with one plan limit and no session or weekly split (Cursor: monthly).
    func hasOnlyOneLimit(_ id: String) -> Bool {
        guard let l = snapshots[id]?.limits, !l.isEmpty else { return false }
        return l.allSatisfy { $0.kind == .only }
    }

    /// The end of "70% left …": "this session", "this week", "this month", "today".
    func periodPhrase(_ l: UsageLimit) -> String {
        switch kindName(l) {
        case "Session": return "this session"
        case "Weekly": return "this week"
        case "Monthly": return "this month"
        case "Daily": return "today"
        default: return "· " + l.label
        }
    }

    /// Hover text for the menu bar pill: which limit the number is, and when it resets.
    /// Short name of a limit's window: Session, Weekly, Monthly.
    func kindName(_ l: UsageLimit) -> String {
        switch l.kind {
        case .short: return "Session"
        case .long: return "Weekly"
        case .only: return l.label == "Month" ? "Monthly" : (l.label == "Day" ? "Daily" : (l.label == "Week" ? "Weekly" : l.label))
        }
    }

    /// One line per connected app for the hover tip, most urgent first.
    struct TipRow: Identifiable { let id: String; let name: String; let kind: String; let limitKind: LimitKind?; let pct: Double?; let level: Level; let reset: Date? }
    var tipRows: [TipRow] {
        sortedConnected.prefix(4).map { id in
            let l = isStale(id) ? nil : watchLimit(id)
            return TipRow(id: id, name: name(id), kind: l.map { self.kindName($0) } ?? (readsUsage(id) ? "Syncing" : "No data yet"), limitKind: l?.kind,
                          pct: l?.percentLeft, level: level(l?.percentLeft), reset: l?.resetsAt)
        }
    }

    var pillHelp: String {
        guard let u = urgent, let l = watchLimit(u.id) else { return "TUM: all good" }
        let kind: String
        switch l.kind {
        case .short: kind = "Session"
        case .long: kind = "Weekly"
        case .only: kind = l.label == "Month" ? "Monthly" : (l.label == "Day" ? "Daily" : (l.label == "Week" ? "Weekly" : l.label))
        }
        var text = "\(name(u.id)) · \(kind): \(Int(l.percentLeft.rounded()))% left"
        if let r = l.resetsAt { text += ". Resets \(Format.when(r))" }
        return text
    }

    func isStale(_ id: String) -> Bool {
        guard let s = snapshots[id] else { return true }
        return -s.fetchedAt.timeIntervalSinceNow > staleAfter
    }

    func level(_ p: Double?) -> Level {
        guard let p = p else { return .ok }
        if p <= redAt { return .out }
        if p <= threshold { return .low }
        return .ok
    }

    /// How long a low reading keeps the pill showing when refreshes fail. A failed refresh must
    /// never quietly hide a real warning; only a reset or a very old reading clears it.
    let alertKeepsFor: TimeInterval = 3 * 3600

    /// True when the last reading can still drive the pill: not too old, and its limit hasn't reset.
    func canAlert(_ id: String) -> Bool {
        guard let s = snapshots[id], -s.fetchedAt.timeIntervalSinceNow <= alertKeepsFor else { return false }
        if let reset = watchLimit(id)?.resetsAt, reset < Date() { return false }
        return true
    }

    /// When each app crossed into yellow or red, and at which level. An app enters this list the
    /// moment it drops under "Turn yellow at", and again (as red) when it reaches 10%. It leaves
    /// when it's healthy again (for example after a reset).
    private(set) var alertSince: [String: (level: Level, at: Date)] = [:]
    /// Warnings the person cleared with "Got it", by app and level (AK). The pill and the line go
    /// back to normal for that app until it reaches a new level (yellow to red) or recovers.
    private(set) var acknowledged: [String: Level] = [:]

    /// Forgets every "Got it" on warnings (Developer menu previews, Start fresh).
    func clearAcknowledged() { objectWillChange.send(); acknowledged = [:] }

    /// "Got it" on the yellow or red line. The next app in line takes the pill right away.
    func acknowledgeAlert() {
        guard let u = urgent else { return }
        objectWillChange.send()
        acknowledged[u.id] = u.level
        rotatePill()
    }

    /// Records new crossings. Several apps that cross in the same update share one moment; then
    /// the lower one wins the tie.
    func updateAlerts() {
        let now = Date()
        for id in Array(alertSince.keys) where !connected.contains(id) { alertSince[id] = nil }
        for id in connected {
            let l: Level = canAlert(id) ? level(watchPercent(id)) : .ok
            if l == .ok { alertSince[id] = nil; acknowledged[id] = nil }
            else if alertSince[id]?.level != l { alertSince[id] = (l, now); lastTurn[id] = nil }
            if let a = acknowledged[id], a != l { acknowledged[id] = nil }
        }
        rotatePill(now: now)
    }

    /// The warning on the pill right now, if the pill is yellow or red.
    var urgent: (id: String, pct: Double, level: Level)? {
        guard let p = pillState, p.level != .use else { return nil }
        return p
    }

    // MARK: Pill turns (AK): several apps, one pill

    /// How long one app keeps the pill before the next one in its color gets a turn.
    static let pillTurnLength: TimeInterval = 60
    /// Whose turn it is, and since when. Kept in memory only.
    private(set) var pillTurn: String?
    private var turnStarted: Date?
    /// When each app last had the pill. Cleared when it crosses into a new level, so it counts as news.
    private var lastTurn: [String: Date] = [:]
    /// True while the person is looking at TUM (popover or hover tip): the pill never changes
    /// under their eyes, except for news.
    var holdPill = false

    /// Every app that wants the pill, in the one color that wins, in turn order. The rules:
    /// 1. Red beats yellow beats green. Colors never mix, so lower ones wait.
    /// 2. News first: an app that just crossed into its level (newest first) or a new green tip
    ///    (soonest reset first) goes to the front.
    /// 3. Then everyone takes turns, longest since their last turn first, so every app is seen.
    ///    Ties go to the app with less left.
    /// "Got it" takes an app out until it reaches a new level.
    var pillCandidates: [(id: String, pct: Double, level: Level)] {
        let live = alertSince.compactMap { id, a -> (id: String, pct: Double, level: Level, at: Date)? in
            guard connected.contains(id), canAlert(id), let p = watchPercent(id) else { return nil }
            return (id, p, level(p), a.at)
        }.filter { $0.level != .ok && acknowledged[$0.id] != $0.level }
        if !live.isEmpty {
            let tier = live.contains { $0.level == .out } ? live.filter { $0.level == .out } : live
            return tier.sorted { a, b in
                let ta = lastTurn[a.id], tb = lastTurn[b.id]
                if (ta == nil) != (tb == nil) { return ta == nil }
                if let ta, let tb, ta != tb { return ta < tb }
                if ta == nil && a.at != b.at { return a.at > b.at }
                return a.pct < b.pct
            }.map { ($0.id, $0.pct, $0.level) }
        }
        // Green tips come soonest reset first already.
        let tips = useItTips.filter(isNew).enumerated()
        return tips.sorted { a, b in
            let ta = lastTurn[a.element.id], tb = lastTurn[b.element.id]
            if (ta == nil) != (tb == nil) { return ta == nil }
            if let ta, let tb, ta != tb { return ta < tb }
            return a.offset < b.offset
        }.map { ($0.element.id, $0.element.pct, Level.use) }
    }

    /// What the menu bar shows: whoever's turn it is.
    var pillState: (id: String, pct: Double, level: Level)? {
        let c = pillCandidates
        if let t = pillTurn, let hit = c.first(where: { $0.id == t }) { return hit }
        return c.first
    }

    /// Moves the pill on when it's time. Called on every update and every few seconds by the menu bar.
    /// News takes the pill at once; otherwise the turn lasts `pillTurnLength`, and never ends while
    /// the person is looking at TUM.
    func rotatePill(now: Date = Date()) {
        let c = pillCandidates
        let ids = Set(c.map(\.id))
        for id in Array(lastTurn.keys) where !ids.contains(id) { lastTurn[id] = nil }
        guard let first = c.first else {
            if pillTurn != nil { pillTurn = nil; turnStarted = nil }
            return
        }
        let current = c.first { $0.id == pillTurn }
        let news = first.id != pillTurn && lastTurn[first.id] == nil
        let turnOver = !holdPill && c.count > 1 && now.timeIntervalSince(turnStarted ?? .distantPast) >= Self.pillTurnLength
        guard current == nil || news || turnOver else { return }
        let next = (current == nil || news) ? first : (c.first { $0.id != pillTurn } ?? first)
        objectWillChange.send()
        pillTurn = next.id
        turnStarted = now
        lastTurn[next.id] = now
    }

    // MARK: Use it before it resets (AK: TUM's differentiator)

    /// An app with a lot left on a weekly, monthly or daily limit that resets soon, so that
    /// usage would otherwise go to waste. Checked on every refresh: at launch, on wake, and
    /// when an app is used.
    struct UseItTip: Equatable { let id: String; let pct: Double; let resetsAt: Date; let mode: WatchMode }

    /// The rule, in two tiers:
    /// - resets within a day with at least half left, or
    /// - resets within three days and barely touched (80% or more left).
    /// The 5-hour session limit is left out: it resets all the time, so it would nag.
    static func worthUsing(_ l: UsageLimit, now: Date = Date()) -> Bool {
        guard l.kind != .short, !l.isEstimate, let r = l.resetsAt, r > now else { return false }
        let left = r.timeIntervalSince(now)
        return (left <= 24 * 3600 && l.percentLeft >= 50) || (left <= 72 * 3600 && l.percentLeft >= 80)
    }

    /// Every app worth using now, soonest reset first. Apps that are low never appear here.
    var useItTips: [UseItTip] {
        connected.compactMap { id -> UseItTip? in
            guard !isStale(id), alertSince[id] == nil, let limits = snapshots[id]?.limits else { return nil }
            let best = limits.filter { Self.worthUsing($0) }.max { $0.percentLeft < $1.percentLeft }
            return best.map { UseItTip(id: id, pct: $0.percentLeft, resetsAt: $0.resetsAt!, mode: WatchMode.period(of: $0)) }
        }
        .sorted { $0.resetsAt != $1.resetsAt ? $0.resetsAt < $1.resetsAt : $0.pct > $1.pct }
    }

    /// Recommendations the person has already seen, by app, with the reset they were about.
    /// Saved, so the green pill doesn't come back for the same reset after a relaunch.
    private var useItSeen: [String: Double] {
        get { defaults.dictionary(forKey: "useItSeen") as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: "useItSeen") }
    }

    private func isNew(_ t: UseItTip) -> Bool {
        guard let seen = useItSeen[t.id] else { return true }
        return abs(seen - t.resetsAt.timeIntervalSince1970) > 120
    }

    /// The first recommendation the person hasn't seen yet, for the green pill.
    var newUseItTip: UseItTip? { useItTips.first(where: isNew) }

    /// Forgets which recommendations were seen (Developer menu and Start fresh).
    func resetUseItSeen() {
        objectWillChange.send()
        useItSeen = [:]
    }

    /// Clicking the green pill opens TUM on the tab the tip is about (weekly, monthly), so the
    /// number in the pill is the one you see (AK).
    func showTipTab() {
        if let p = pillState, p.level == .use, let t = useItTips.first(where: { $0.id == p.id }) {
            if mode != t.mode { mode = t.mode }
        } else if let u = urgent, !tabApps.contains(u.id), let l = watchLimit(u.id) {
            // A warning for an app that isn't on this tab opens the tab where it is.
            mode = WatchMode.period(of: l)
        }
    }

    /// True when the app has a limit of the chosen tab's period.
    func hasLimit(_ id: String, for m: WatchMode) -> Bool {
        (snapshots[id]?.limits ?? []).contains { m.matches($0) }
    }

    /// The apps on the current tab (AK): only those with a limit of that period. Apps with no
    /// numbers yet stay, so a sign-in problem or "Connect" is never hidden.
    var tabApps: [String] {
        displayOrder.filter { snapshots[$0] == nil || hasLimit($0, for: mode) }
    }

    /// "Got it" on the recommendation (AK): the line goes away and the green pill turns back
    /// into the white icon, until a new reset comes up.
    func markUseItSeen() {
        let tips = useItTips.filter(isNew)
        guard !tips.isEmpty else { return }
        objectWillChange.send()
        var seen = useItSeen
        for t in tips { seen[t.id] = t.resetsAt.timeIntervalSince1970 }
        useItSeen = seen
        rotatePill()
    }

    /// What the menu bar shows. Yellow and red warnings always win. Otherwise a new "use it"
    /// recommendation shows as the green pill until TUM is opened.


    /// The positive status line: short, plain, a suggestion (AK). One app says what's left and
    /// when it resets; several are listed by name.
    var useItLine: String? {
        let tips = useItTips.filter(isNew)
        guard let first = tips.first else { return nil }
        if tips.count == 1 {
            // A no-break space keeps "5 AM" together when the line wraps.
            let when = Format.when(first.resetsAt).replacingOccurrences(of: " AM", with: "\u{00A0}AM")
                .replacingOccurrences(of: " PM", with: "\u{00A0}PM")
            return "\(name(first.id)) has \(Int(first.pct.rounded()))% left and resets \(when)."
        }
        let names = tips.prefix(3).map { name($0.id) }
        let list = names.count == 2 ? names.joined(separator: " and ")
                                    : names.dropLast().joined(separator: ", ") + " and " + names.last!
        let more = tips.count > 3 ? " and \(tips.count - 3) more" : ""
        return "\(list)\(more) reset soon with plenty left."
    }

    /// Lowest first. Only for the hover tip, which is about what needs attention.
    var sortedConnected: [String] {
        connected.sorted { (watchPercent($0) ?? 999) < (watchPercent($1) ?? 999) }
    }

    /// The order tiles appear in the popover and quick view: the order the person connected them.
    /// It never changes with Session, Weekly or Both, so icons stay in place (AK).
    var displayOrder: [String] { connected }

    func soonestReset(_ id: String) -> Date? { watchLimit(id)?.resetsAt }

    func updatedText(_ id: String) -> String {
        if updating.contains(id) { return "Syncing…" }
        guard let s = snapshots[id] else { return "Not synced yet" }
        // The time of the last real sync, never "just now" for a check you didn't start (AK).
        return "Synced " + Format.at(s.fetchedAt)
    }

    /// "Sync" from the More menu or the detail screen. A manual check skips the local Codex
    /// shortcut and any wait from an earlier busy reply, and "Syncing…" stays up for at least
    /// 0.8s so the person sees that something happened, even when the answer is instant.
    func syncNow(_ id: String) async {
        guard !updating.contains(id) else { return }
        updating.insert(id)
        let start = Date()
        // A manual update skips the wait, but at most once a minute, so clicking can't hammer a
        // service that asked TUM to slow down (security review M4).
        if (lastAttempt[id] ?? .distantPast).timeIntervalSinceNow < -60 { backoff[id] = nil; failures[id] = nil }
        await refresh(id, interactive: true, manual: true)
        let wait = 0.8 + start.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        updating.remove(id)
        // Only a real new answer says "Just now". A failed sync keeps its error showing instead.
        guard let fetched = snapshots[id]?.fetchedAt, fetched >= start.addingTimeInterval(-1), errors[id] == nil else { return }
        // "Connected · Just now" stays long enough to read, then the row goes back to just
        // "Connected" (AK: less clutter).
        justUpdated.insert(id)
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        if !updating.contains(id) { justUpdated.remove(id) }
    }

    /// A connected app's one-line status. Normally just "Connected" (AK: less clutter). Right
    /// after "Sync" it says "Connected · Syncing…", then "Connected · Just now" for a few
    /// seconds, then goes back to "Connected". Apps TUM can't read yet say so.
    func connectedText(_ id: String) -> String {
        if !readsUsage(id) { return "Connected · No data yet" }
        if updating.contains(id) { return "Connected · Syncing…" }
        if justUpdated.contains(id), let s = snapshots[id] {
            let ago = Format.ago(s.fetchedAt)
            return "Connected · " + (ago == "just now" ? "Just now" : "Synced " + ago)
        }
        return "Connected"
    }

    struct Summary {
        let symbol: String; let color: Color; let text: String
        /// What "Got it" clears: a yellow or red warning, or a "use it" tip. Nil: no button.
        enum Dismiss { case alert, tip }
        var dismiss: Dismiss? = nil
        var isTip: Bool { dismiss == .tip }
        /// The status line is only for alerts. "All good" needs no line at all.
        var isAlert: Bool { text != "All good" && text != "Connect an AI app to start" }
    }

    var summary: Summary {
        if connected.isEmpty { return Summary(symbol: "info.circle.fill", color: .secondary, text: "Connect an AI app to start") }
        if let u = urgent {
            let n = name(u.id)
            if u.level == .out {
                let t = soonestReset(u.id).map { "\(n) resets \(Format.when($0))" } ?? "\(n) is almost out"
                return Summary(symbol: "exclamationmark.circle.fill", color: Palette.redText, text: t, dismiss: .alert)
            }
            let t = soonestReset(u.id).map { "\(n) may run out before \(Format.short($0))" } ?? "\(n) is getting low"
            return Summary(symbol: "exclamationmark.triangle.fill", color: Palette.amberText, text: t, dismiss: .alert)
        }
        // The positive line (AK): apps that reset soon with lots unused. A suggestion, not a warning.
        if let line = useItLine {
            return Summary(symbol: "lightbulb.fill", color: Palette.green, text: line, dismiss: .tip)
        }
        // The status line is only for yellow and red warnings (AK). Apps that need a click
        // already show their Connect button.
        return Summary(symbol: "checkmark.circle.fill", color: Palette.green, text: "All good")
    }
}
