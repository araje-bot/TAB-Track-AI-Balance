import SwiftUI
import AppKit
import MachO
import Carbon.HIToolbox
import Security

/// `TUM --self-test` checks the parts most likely to break, without the network
/// and without changing any saved settings. make_dmg.sh runs it on every build
/// and stops if anything fails, so a broken app never reaches the DMG.
@MainActor
enum SelfTest {
    private static var failures: [String] = []
    private static var passed = 0

    private static func check(_ name: String, _ ok: @autoclosure () -> Bool) {
        if ok() { passed += 1; print("  ok    \(name)") }
        else { failures.append(name); print("  FAIL  \(name)") }
    }

    static func run() -> Bool {
        print("TUM self-test")
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        // The current macOS design (Liquid Glass) only applies when the app records the SDK it was built with.
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)) {
            check("Built with the current macOS SDK (Liquid Glass on)", (linkedSDKMajor() ?? 0) >= 26)
        }

        // Reading usage from each service's reply.
        let claudeReply: [String: Any] = ["five_hour": ["utilization": 40, "resets_at": "2030-01-01T10:00:00Z"] as [String: Any],
                                          "seven_day": ["utilization": 75.5] as [String: Any]]
        let claude = ClaudeProvider.parse(claudeReply)
        check("Claude reply gives 2 limits", claude.count == 2)
        check("Claude 40% used = 60% left", abs((claude.first?.percentLeft ?? 0) - 60) < 0.01)
        check("Claude short limit first", claude.first?.kind == .short && claude.last?.kind == .long)

        let codexReply: [String: Any] = ["primary": ["used_percent": 20, "window_minutes": 300, "resets_in_seconds": 600] as [String: Any],
                                         "secondary": ["used_percent": 90, "window_minutes": 10080] as [String: Any]]
        let codex = CodexProvider.limits(from: codexReply, base: Date())
        check("Codex reply gives 5 hours and Week", codex.map(\.label) == ["5 hours", "Week"])
        check("Codex 90% used = 10% left", abs((codex.last?.percentLeft ?? 0) - 10) < 0.01)
        check("Codex reset time computed", codex.first?.resetsAt != nil)

        let cursorReply: [String: Any] = ["totalPercentUsed": 30, "billingCycleEnd": "1893456000000"]
        let cursor = CursorProvider.parse(cursorReply)
        check("Cursor reply gives 70% left", abs((cursor?.first?.percentLeft ?? 0) - 70) < 0.01)
        // Token "header.payload.sig" whose payload is {"sub":"auth0|user_123"}
        check("Cursor account id from sign-in", CursorProvider.userID(fromToken: "e30.eyJzdWIiOiJhdXRoMHx1c2VyXzEyMyJ9.x") == "user_123")
        check("Cursor website reply", abs((CursorProvider.parse(["individualUsage": ["plan": ["totalPercentUsed": 40] as [String: Any]] as [String: Any]] as [String: Any])?.first?.percentLeft ?? 0) - 60) < 0.01)
        check("Cursor spend/limit fallback", CursorProvider.parse(["totalSpend": 5, "limit": 20] as [String: Any])?.first.map { abs($0.percentLeft - 75) < 0.01 } ?? false)
        check("Gemini lowest bucket wins", abs((GeminiProvider.parse(["buckets": [["remainingFraction": 0.8], ["remainingFraction": 0.25]] as [[String: Any]]] as [String: Any])?.first?.percentLeft ?? 0) - 25) < 0.01)
        let grokCredits: [String: Any] = ["config": ["creditUsagePercent": 40.0,
            "currentPeriod": ["type": "USAGE_PERIOD_TYPE_WEEKLY", "end": "2030-01-08T04:01:09+00:00"] as [String: Any]] as [String: Any]]
        check("Grok weekly pool 60% left", abs((GrokProvider.parse(grokCredits)?.first?.percentLeft ?? 0) - 60) < 0.01)
        let grokZero: [String: Any] = ["config": ["currentPeriod": ["type": "USAGE_PERIOD_TYPE_WEEKLY"] as [String: Any]] as [String: Any]]
        check("Grok 0% used (number left out) = 100% left", GrokProvider.parse(grokZero)?.first?.percentLeft == 100)
        check("Grok Bot 30% used", abs((GrokBotProvider.parse(["usagePercent": 30, "nextResetTimestampUtc": "2030-01-08T00:00:00Z"] as [String: Any])?.first?.percentLeft ?? 0) - 70) < 0.01)
        check("Grok Bot 0% used (number left out)", GrokBotProvider.parse(["currentPeriodStart": "2030-01-01T00:00:00Z"] as [String: Any])?.first?.percentLeft == 100)
        check("Cursor 0% used (number left out) = 100% left", CursorProvider.parse(["planUsage": ["limit": 2000] as [String: Any]] as [String: Any])?.first?.percentLeft == 100)
        check("Codex 0% used (number left out)", CodexProvider.limits(from: ["primary": ["window_minutes": 300] as [String: Any]] as [String: Any], base: Date()).first?.percentLeft == 100)
        check("Sign-in token expiry read", JWT.expiresSoon("e30.eyJleHAiOjF9.x") && !JWT.expiresSoon("e30.eyJleHAiOjk5OTk5OTk5OTl9.x"))
        let copilotReply: [String: Any] = ["quota_reset_date": "2030-02-01",
            "quota_snapshots": ["premium_interactions": ["percent_remaining": 35.5, "entitlement": 300] as [String: Any]] as [String: Any]]
        check("Copilot premium requests 35.5% left", abs((CopilotProvider.parse(copilotReply)?.first?.percentLeft ?? 0) - 35.5) < 0.01)
        check("GitHub CLI token found in hosts.yml", CopilotProvider.ghToken(fromHostsYAML: "github.com:\n    user: me\n    oauth_token: fake-token-abc\nother.com:\n    oauth_token: no\n") == "fake-token-abc")
        let zedFree: [String: Any] = ["plan": ["plan_v3": "zed_free", "has_overdue_invoices": false,
            "subscription_period": ["started_at": "2030-01-01T00:00:00Z", "ended_at": "2030-02-01T00:00:00Z"] as [String: Any],
            "usage": ["edit_predictions": ["used": 1500, "limit": 2000] as [String: Any]] as [String: Any]] as [String: Any]]
        let zedPro: [String: Any] = ["plan": ["plan_v3": "zed_pro",
            "usage": ["edit_predictions": ["used": 90, "limit": "unlimited"] as [String: Any]] as [String: Any]] as [String: Any]]
        let zedFreeLeft = ZedProvider.parse(zedFree)?.first
        check("Zed edit predictions 25% left, resets with the billing period",
              abs((zedFreeLeft?.percentLeft ?? 0) - 25) < 0.01 && zedFreeLeft?.resetsAt == J.date("2030-02-01T00:00:00Z")
              && ZedProvider.parse(zedPro)?.first?.percentLeft == 100)
        check("Zed sign-in header is \"<user id> <token>\" and refuses odd values",
              ZedProvider.header(user: "12345", token: "fake-token") == "12345 fake-token"
              && ZedProvider.header(user: "me@x", token: "fake") == nil && ZedProvider.header(user: "1", token: "a b\nc") == nil)
        check("Zed reply without its usage is rejected", ZedProvider.parse(["plan": ["plan_v3": "zed_free"] as [String: Any]] as [String: Any]) == nil
              && ZedProvider.parse(["plan": ["usage": ["edit_predictions": ["used": 1, "limit": 0] as [String: Any]] as [String: Any]] as [String: Any]] as [String: Any]) == nil)
        check("Unknown reply is rejected, not shown as 0%", CursorProvider.parse(["something": 1] as [String: Any]) == nil && GrokProvider.parse([String: Any]()) == nil && GrokBotProvider.parse("x") == nil)

        // Codex's local session file.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tum-selftest-\(UUID().uuidString).jsonl")
        let line = #"{"timestamp":"2030-01-01T10:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_in_seconds":60},"secondary":{"used_percent":40,"window_minutes":10080}}}}"#
        try? ("{\"type\":\"other\"}\n" + line + "\n").write(to: tmp, atomically: true, encoding: .utf8)
        let local = CodexLocal.read(tmp)
        check("Codex session file is read", local?.limits.count == 2)
        check("Codex session value correct", abs((local?.limits.first?.percentLeft ?? 0) - 87.5) < 0.01)
        try? FileManager.default.removeItem(at: tmp)

        // Small helpers.
        check("Dates in seconds and ms", J.date(1893456000.0) == J.date(1893456000000.0))
        check("ISO dates", J.date("2030-01-01T10:00:00.123Z") != nil)
        let wk = UsageLimit(kind: .long, label: "Week", percentLeft: 50, resetsAt: nil)
        let mo = UsageLimit(kind: .only, label: "Month", percentLeft: 50, resetsAt: nil)
        let se = UsageLimit(kind: .short, label: "5 hours", percentLeft: 50, resetsAt: nil)
        let tabs = Store.preview(apps: ["claude": 20, "cursor": 70], threshold: 25, mode: .monthly)
        let monthlyApps = tabs.tabApps
        tabs.showTipTab()   // Claude is low on its session limit, which isn't on Monthly
        let jumped = tabs.mode
        check("Each tab lists only apps with that limit, and a warning opens its tab",
              monthlyApps == ["cursor"] && jumped == .session && tabs.tabApps == ["claude"])
        check("Tabs match their period", WatchMode.session.matches(se) && WatchMode.weekly.matches(wk) && WatchMode.monthly.matches(mo)
              && !WatchMode.session.matches(wk) && !WatchMode.monthly.matches(se))

        // Levels.
        let store = Store.shared
        check("8% is almost out", store.level(8) == .out)
        check("At the threshold is low", store.level(store.threshold) == .low)
        // The product's core: healthy stays the white icon, at or under "Turn yellow at" is yellow,
        // and 10% or less is always red, whatever yellow is set to.
        let levels = Store.preview(apps: ["claude": 50])
        check("Healthy is the white icon, low is yellow, 10% or less is red",
              levels.level(80) == .ok && levels.level(levels.threshold) == .low && levels.level(10) == .out && levels.level(3) == .out
              && Thresholds.yellow.allSatisfy { $0.0 > levels.redAt })
        check("Plenty left is fine", store.level(90) == .ok)

        check("Onboarding version is set", Store.onboardingVersion >= 2)

        // Logo marks from app icons.
        check("Logo mark found on a plain icon", GlyphMaker.whiteGlyph(from: testIcon(withMark: true)) != nil)
        check("Plain tile gives no logo mark", GlyphMaker.whiteGlyph(from: testIcon(withMark: false)) == nil)

        // Every screen can be built and laid out without crashing.
        check("Popover lays out", fits(PopoverView(store: store, openSettings: {}, openAddMore: {})))
        check("Onboarding lays out", fits(OnboardingView(store: store, finish: {})))
        check("Settings lays out", fits(SettingsView(store: store)))
        check("Quick view lays out", fits(QuickView(store: store)))
        check("Connect sheet lays out", fits(ConnectSheet(store: store, app: AIApp(id: "claude", name: "Claude", category: "Chat", appURL: nil, supported: true, credentialFound: true, hint: "", source: "test"), done: {})))
        check("Yellow pill renders", render(PillView(glyph: nil, symbol: "asterisk", pct: 24, level: .low)))
        check("Red pill renders", render(PillView(glyph: nil, symbol: "asterisk", pct: 8, level: .out)))
        check("App icon renders", AppLogo.iconImage() != nil)

        do {
            let was = Keychain.silentReadsAllowed
            Keychain.silentReadsAllowed = false
            check("No Keychain reads before onboarding", Keychain.read(service: "tum-self-test", interactive: false).status == errSecInteractionNotAllowed)
            Keychain.silentReadsAllowed = was
        }
        check("Cursor sign-in code is URL-safe", !CursorAuth.base64URL(Data([0xfb, 0xff, 0xfe, 0x01])).contains(where: { "+/=".contains($0) }))
        check("Pill slot fits the number", StatusItemController.slotWidth(urgentPct: 100) >= 62 && StatusItemController.slotWidth(urgentPct: nil) >= 22)
        check("Hover tip lays out", fits(HoverTip(store: store)))

        // Menu bar and shortcut.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        check("Menu bar item can be created", item.button != nil)
        // The real menu bar item turns into the pill when an app is low, and back when all is good.
        let barStore = Store.preview(apps: ["claude": 24])
        let bar = StatusItemController(store: barStore, openSettings: {}, openAddMore: {}, showWelcome: {})
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let pillWidth = bar.item.length
        // How far the popover's anchor sits from the slot's right edge. It must be 0 for both the
        // pill and the icon: the menu bar keeps an item's right edge fixed while it resizes, so
        // the popover then never moves. (Screen positions depend on other menu bar items.)
        func anchorX() -> CGFloat? {
            guard let b = bar.item.button else { return nil }
            return b.bounds.maxX - bar.anchor(in: b).maxX
        }
        let anchorAtPill = anchorX()
        // Open the real popover, then turn the pill into the icon: the popover must not move.
        bar.toggle(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let popBefore = bar.popover.contentViewController?.view.window?.frame
        let itemBefore = bar.item.button?.window?.frame
        barStore.snapshots["claude"] = ProviderSnapshot(limits: Store.sampleLimits("claude", pct: 80), fetchedAt: Date())
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let popAfter = bar.popover.contentViewController?.view.window?.frame
        let itemAfter = bar.item.button?.window?.frame
        _ = (itemBefore, itemAfter)
        check("The open popover stays put when the pill turns into the icon (AK)",
              popBefore != nil && popAfter != nil && abs(popBefore!.minX - popAfter!.minX) < 1 && abs(popBefore!.maxY - popAfter!.maxY) < 1)
        bar.popover.performClose(nil)
        let iconWidth = bar.item.length
        let anchorAtIcon = anchorX()
        check("The popover points at the slot's right end for the pill and the icon",
              anchorAtPill != nil && anchorAtIcon != nil && abs(anchorAtPill!) < 1 && abs(anchorAtIcon!) < 1)
        // A green "use it" pill, then Got it: the slot shrinks back to the icon and the
        // label still fills it (no empty space beside the icon).
        barStore.snapshots["claude"] = ProviderSnapshot(limits: Store.useItLimits("claude"), fetchedAt: Date())
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let greenWidth = bar.item.length
        barStore.markUseItSeen()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        let hostWidth = bar.item.button?.subviews.first?.frame.width ?? 0
        check("Green pill widens the slot, and it shrinks back after Got it",
              greenWidth > iconWidth + 20 && abs(bar.item.length - iconWidth) < 1 && abs(hostWidth - (iconWidth - 10)) < 1)
        print("        menu bar: urgent \(barStore.urgent.map { "\($0.id) \(Int($0.pct))%" } ?? "none"), pill slot \(Int(pillWidth)), icon slot \(Int(iconWidth))")
        check("Menu bar turns into the pill when an app is low", abs(pillWidth - StatusItemController.slotWidth(urgentPct: 24)) < 1)
        check("Menu bar goes back to the icon when all is good", abs(iconWidth - StatusItemController.slotWidth(urgentPct: nil)) < 1)
        NSStatusBar.system.removeStatusItem(bar.item)
        // Pill turns (AK): news first, then every app in the winning color takes a turn.
        let flow = Store.preview(apps: ["claude": 80, "codex": 80, "gemini": 80], threshold: 40)
        func set(_ id: String, _ pct: Double) {
            flow.snapshots[id] = ProviderSnapshot(limits: Store.sampleLimits(id, pct: pct), fetchedAt: Date())
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        let start = flow.urgent == nil
        set("claude", 20); let first = flow.urgent?.id
        set("codex", 35); let second = flow.urgent?.id          // news takes the pill at once
        let turn = Store.pillTurnLength + 1
        flow.rotatePill(now: Date().addingTimeInterval(turn)); let third = flow.urgent?.id        // then Claude's turn
        flow.rotatePill(now: Date().addingTimeInterval(turn * 2)); let fourth = flow.urgent?.id   // and Codex again
        flow.holdPill = true
        flow.rotatePill(now: Date().addingTimeInterval(turn * 3)); let held = flow.urgent?.id      // not while TUM is open
        flow.holdPill = false
        check("Several low apps take turns on the pill, news first",
              start && first == "claude" && second == "codex" && third == "claude" && fourth == "codex" && held == "codex")
        set("claude", 8); let red = flow.urgent                 // red beats yellow at once
        set("gemini", 30); let stillRed = flow.urgent?.id       // a new yellow waits behind red
        flow.rotatePill(now: Date().addingTimeInterval(turn * 5)); let onlyRed = flow.urgent?.id
        set("codex", 5); let newRed = flow.urgent?.id           // a second red is news
        flow.rotatePill(now: Date().addingTimeInterval(turn * 7)); let redTurn = flow.urgent?.id
        check("Red beats yellow, and red apps take turns too",
              red?.id == "claude" && red?.level == .out && stillRed == "claude" && onlyRed == "claude"
              && newRed == "codex" && redTurn == "claude")
        flow.acknowledgeAlert()
        check("Got it hands the pill to the next app", flow.urgent?.id == "codex")
        // Usage monitoring is the default view; flipping tabs never changes the pill (AK).
        let view = Store.preview(apps: ["claude": 20], threshold: 25, mode: .session)
        view.mode = .weekly
        let pillOnWeekly = view.pillState?.id
        view.watch = .weekly
        check("Tabs only change the view; Usage monitoring sets the default", pillOnWeekly == "claude"
              && view.mode == .weekly && view.watch == .weekly)
        let oldLow = Store.preview(apps: ["claude": 50])
        oldLow.snapshots["claude"] = ProviderSnapshot(limits: Store.sampleLimits("claude", pct: 20), fetchedAt: Date().addingTimeInterval(-30 * 60))
        check("A low reading keeps the pill when a refresh fails", oldLow.urgent?.id == "claude")
        // Use it before it resets: green pill until TUM is opened, never over a warning.
        let now = Date()
        let soonFull = UsageLimit(kind: .long, label: "Week", percentLeft: 85, resetsAt: now.addingTimeInterval(9 * 3600))
        let soonHalf = UsageLimit(kind: .long, label: "Week", percentLeft: 55, resetsAt: now.addingTimeInterval(20 * 3600))
        let farFull = UsageLimit(kind: .long, label: "Week", percentLeft: 95, resetsAt: now.addingTimeInterval(5 * 86400))
        let session = UsageLimit(kind: .short, label: "5 hours", percentLeft: 95, resetsAt: now.addingTimeInterval(3600))
        check("Use-it rule: soon and plenty left, never the session limit",
              Store.worthUsing(soonFull) && Store.worthUsing(soonHalf) && !Store.worthUsing(farFull) && !Store.worthUsing(session))
        let green = Store.preview(apps: ["claude": 80, "codex": 80])
        green.snapshots["codex"] = ProviderSnapshot(limits: Store.useItLimits("codex"), fetchedAt: now)
        let greenBefore = green.pillState
        let tipBefore = green.summary
        check("The tip reads as a suggestion with a Got it button", tipBefore.isTip && tipBefore.text.hasPrefix("Codex has 85% left") && tipBefore.symbol == "lightbulb.fill")
        green.showTipTab()
        check("Clicking the green pill opens its tab (weekly)", green.mode == .weekly)
        green.markUseItSeen()
        let greenAfter = green.pillState
        check("Green pill and its tip show until Got it", greenBefore?.id == "codex" && greenBefore?.level == .use
              && greenAfter == nil && !green.summary.isTip)
        green.mode = .session
        green.snapshots["claude"] = ProviderSnapshot(limits: Store.sampleLimits("claude", pct: 8), fetchedAt: now)
        check("A warning always wins over the green pill", green.pillState?.level == .out)
        // Got it on a warning: back to the icon until the app gets lower.
        let ack = Store.preview(apps: ["claude": 20], threshold: 25)
        let ackYellow = ack.pillState?.level
        ack.acknowledgeAlert()
        let ackCleared = ack.pillState == nil && ack.summary.dismiss == nil
        ack.snapshots["claude"] = ProviderSnapshot(limits: Store.sampleLimits("claude", pct: 8), fetchedAt: Date())
        check("Got it clears a warning until the app turns red", ackYellow == .low && ackCleared && ack.pillState?.level == .out)
        #if DEBUG
        // The right-click previews must work whatever "Turn yellow at" and the tab are (AK).
        let fake = Store.preview(apps: ["claude": 90, "codex": 90], threshold: 20, mode: .weekly)
        fake.devFake(.low); let y = fake.pillState?.level
        fake.devFake(.almostOut); let r = fake.pillState?.level
        fake.devFake(.low); let y2 = fake.pillState?.level
        check("Pill previews show yellow, red, then yellow again", y == .low && r == .out && y2 == .low)
        #endif
        // Security review L1: "nan" or "inf" from a file or a server must never reach Int() and crash.
        check("Numbers that aren't finite are ignored", J.num("nan") == nil && J.num("inf") == nil && J.num("-inf") == nil && J.num("42") == 42)
        check("Cursor and Grok Bot can always be connected", CursorAuth.available())
        check("GitHub Copilot can always be connected", Providers.all["copilot"]?.credentialAvailable() == true)
        // Tabs fill the popover's width with equal segments.
        let tabsSize = NSHostingView(rootView: SegmentedChoice(selection: .constant(WatchMode.monthly), options: WatchMode.segments,
                                                               label: "Usage monitoring", switchesView: true).frame(width: 300)).fittingSize
        check("Tabs fill their width", abs(tabsSize.width - 300) < 1 && tabsSize.height >= 28)
        // Card notes never wrap or cut off: 24 characters, 18 when the Connect button shares the row.
        check("App notes fit on one line", (Catalog.all + Catalog.planned).allSatisfy { $0.hint.count <= 24 }
              && Catalog.all.filter { $0.id == "cursor" || $0.id == "grokbot" }.allSatisfy { $0.hint.count <= 18 })
        // Apps TUM can't read are never connected (AK: no data, no point). They wait in Coming soon,
        // and ones connected by older versions are dropped on launch.
        let noReader = Store.preview(apps: [:])
        let perplexity = AIApp(id: "perplexity", name: "Perplexity", category: "Search", appURL: URL(fileURLWithPath: "/Applications/Perplexity.app"),
                               supported: false, credentialFound: false, hint: "Usage view planned", source: "")
        noReader.detected.append(perplexity)
        noReader.connect("perplexity")
        var refusal: String?? = .none
        Task { @MainActor in refusal = .some(await noReader.connectAndCheck("perplexity")) }
        let refusalDeadline = Date().addingTimeInterval(2)
        while refusal == nil && Date() < refusalDeadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        let oldSuite = "tum-selftest-noreader"
        let oldDefaults = UserDefaults(suiteName: oldSuite)!
        oldDefaults.removePersistentDomain(forName: oldSuite)
        oldDefaults.set(["claude", "perplexity", "lovable", "kiro"], forKey: "connected")
        let reloaded = Store(defaults: oldDefaults).connected
        oldDefaults.removePersistentDomain(forName: oldSuite)
        check("Apps TUM can't read are never connected; they wait in Coming soon",
              !perplexity.canConnect && !noReader.connected.contains("perplexity") && (refusal ?? nil) != nil
              && !noReader.readyToConnect.contains { $0.id == "perplexity" } && noReader.comingSoon.first?.id == "perplexity"
              && reloaded == ["claude"])
        check("Only installed apps count for apps TUM can't read, never a leftover folder",
              Catalog.all.filter { $0.providerID == nil }.allSatisfy { $0.markers.isEmpty }
              && !Catalog.all.contains { ["lovable", "canva", "capcut"].contains($0.id) })
        // Coming soon: each app once, with a real logo; one found on this Mac moves to
        // Ready to connect instead of showing twice.
        let plannedIDs = Catalog.planned.map(\.id)
        let soonStore = Store.preview(apps: [:])
        soonStore.detected.append(AIApp(id: "manus", name: "Manus", category: "Agents", appURL: nil, supported: false,
                                        credentialFound: false, hint: "Credits view planned", source: ""))
        check("Coming soon lists each app once, with its logo, and nothing shut down",
              !plannedIDs.isEmpty && Set(plannedIDs).count == plannedIDs.count
              && Catalog.planned.allSatisfy { BrandLogos.all[$0.id] != nil } && !plannedIDs.contains("sora")
              && Catalog.all.allSatisfy { !plannedIDs.contains($0.id) }
              && soonStore.comingSoon.filter { $0.id == "manus" }.count == 1 && soonStore.comingSoon.contains { $0.id == "suno" }
              && !soonStore.readyToConnect.contains { $0.id == "manus" }
              && !plannedIDs.contains("midjourney"))
        let fb = Feedback.issueURL("  Pill stays yellow + won't clear\nafter reset  ")?.absoluteString ?? ""
        check("Feedback opens a filled-in GitHub issue on TUM's repo, never an empty one",
              fb.hasPrefix(Feedback.repo + "/issues/new?title=Feedback") && fb.contains("%2B") && fb.contains("body=")
              && Feedback.issueURL("   \n ") == nil
              && (Feedback.issueURL(String(repeating: "🙂", count: 2000))?.absoluteString.utf8.count ?? .max) <= Feedback.maxURLLength)
        let savedForm = Feedback.config
        let realFormReady = savedForm.ready
        Feedback.config = .init(formID: "1FAIpQLSd_fakeFormIdForTheSelfTest0123", message: "entry.111", email: "entry.222", version: "entry.333")
        let pre = Feedback.formURL("Pill + stays", email: "a@b.co")?.absoluteString ?? ""
        let formOK = Feedback.config.ready && pre.hasPrefix("https://docs.google.com/forms/d/e/1FAIpQLSd_fakeFormIdForTheSelfTest0123/viewform?usp=pp_url")
            && pre.contains("entry.111=Pill%20%2B%20stays") && !pre.contains("a@b.co")
        Feedback.config = savedForm
        check("Feedback goes to the team's form with no account; reply email is optional and checked",
              realFormReady && formOK && Feedback.replyEmail(" a@b.co ") == "a@b.co" && Feedback.replyEmail("not an email") == nil
              && !Feedback.Config(formID: "x/../evil", message: "entry.1", email: "entry.2", version: "entry.3").ready)
        check("ChatGPT is never listed on its own", !Detector.scan().contains { $0.name.localizedCaseInsensitiveContains("ChatGPT") })
        // Custom shortcut rules (AK): one of ⌘, ⌥ or ⌃ plus one letter, number or Space.
        func try_(_ m: [ShortcutChoice.Modifier], _ k: String, _ c: Int) -> ShortcutProblem? {
            if case .failure(let p) = ShortcutChoice.check(modifiers: m, key: k, keyCode: UInt16(c)) { return p }
            return nil
        }
        check("Custom shortcut: two keys, a letter, number or Space, nothing macOS needs",
              try_([.control], "K", kVK_ANSI_K) == nil && try_([.option], "Space", kVK_Space) == nil && try_([.command], "5", kVK_ANSI_5) == nil
              && try_([], "K", kVK_ANSI_K) == .needsModifier && try_([.command, .option], "K", kVK_ANSI_K) == .oneModifier
              && try_([.option], "É", kVK_ANSI_E) == .plainKey && try_([.command], "Q", kVK_ANSI_Q) == .usedByMac("⌘ + Q")
              && try_([.command], "Space", kVK_Space) == .usedByMac("⌘ + Space"))
        let ctrlK = ShortcutChoice(modifier: .control, key: "K", keyCode: UInt16(kVK_ANSI_K))
        check("Shortcuts save and load, old names too, \u{2318}T first",
              ShortcutChoice(stored: ctrlK.stored) == ctrlK && ShortcutChoice(stored: "optionSpace") == .optionSpace
              && ShortcutChoice(stored: "option:T:53") == nil
              && ShortcutChoice(stored: "command:Q:12") == nil && ShortcutChoice.presets.first == .commandT
              && ShortcutChoice.presets.allSatisfy { $0.keys.count == 2 })
        let rec = Store.preview(apps: [:])
        rec.startRecordingShortcut()
        rec.recorded(.failure(.oneModifier))
        let saysWhy = rec.shortcutSubtitle("x") == ShortcutProblem.oneModifier.message && rec.recordingShortcut
        rec.recorded(.success(ctrlK))
        check("Recording says why a press won't work, then keeps the good one",
              saysWhy && !rec.recordingShortcut && rec.shortcutChoice == ctrlK && rec.customShortcut == ctrlK)
        // One button size everywhere: icon buttons (Connect, back) match text buttons in height.
        let plug = NSHostingView(rootView: ConnectButton(name: "Test", action: {})).fittingSize
        let back = NSHostingView(rootView: Button("All apps", systemImage: "chevron.left") {}.iconButton()).fittingSize
        let text = NSHostingView(rootView: Button("Add more", systemImage: "plus") {}.secondaryButton()).fittingSize
        let main = NSHostingView(rootView: Button("Next") {}.primaryButton()).fittingSize
        print("        buttons: connect \(Int(plug.width))x\(Int(plug.height)), back \(Int(back.width))x\(Int(back.height)), text h\(Int(text.height)), main h\(Int(main.height))")
        check("Connect button is a circle", abs(plug.width - plug.height) <= 1)
        // One width for every text button, with or without an icon (AK).
        let widths = [NSHostingView(rootView: Button {} label: { ButtonText("Back") }.secondaryButton()).fittingSize.width,
                      NSHostingView(rootView: Button {} label: { ButtonText("Add more", systemImage: "plus") }.secondaryButton()).fittingSize.width,
                      NSHostingView(rootView: Button {} label: { ButtonText("Copy diagnostics") }.secondaryButton()).fittingSize.width,
                      NSHostingView(rootView: Button {} label: { ButtonText("Get started") }.primaryButton()).fittingSize.width,
                      NSHostingView(rootView: Button {} label: { ButtonText("Open in browser") }.primaryButton()).fittingSize.width]
        print("        text button widths: \(widths.map { Int($0.rounded()) })")
        check("Every text button is the same width, icon or not", (widths.max() ?? 0) - (widths.min() ?? 0) <= 1)
        let more = NSHostingView(rootView: AppMenu(name: "Test", refresh: {}, remove: {})).fittingSize
        print("        more: \(Int(more.width))x\(Int(more.height))")
        check("More button matches the Connect circle", Int(more.height.rounded()) == Int(plug.height.rounded()) && abs(more.width - more.height) <= 1)
        let rowTabs = NSHostingView(rootView: SettingRow("Turn yellow at", subtitle: "When the icon turns yellow") { SegmentedChoice(selection: .constant(25.0), options: Thresholds.yellow) }).fittingSize
        let rowSwitch = NSHostingView(rootView: SettingRow("Open at login", subtitle: "Start TUM when you turn on your Mac") { Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).controlSize(.regular) }).fittingSize
        let rowButton = NSHostingView(rootView: SettingRow("Welcome screens", subtitle: "See the welcome tour again") { Button("Show welcome screens again", systemImage: "play.fill") {}.iconButton() }).fittingSize
        check("Every settings row has the same height", Set([rowTabs.height, rowSwitch.height, rowButton.height].map { Int($0.rounded()) }).count == 1)
        check("All buttons share one height", Set([plug.height, back.height, text.height, main.height].map { Int($0.rounded()) }).count == 1)
        NSStatusBar.system.removeStatusItem(item)
        check("App detection runs", { _ = Detector.scan(); return true }())

        print(failures.isEmpty ? "All \(passed) checks passed." : "\(failures.count) of \(passed + failures.count) checks failed: \(failures.joined(separator: "; "))")
        return failures.isEmpty
    }

    /// `TUM --snapshots <folder>` saves pictures of the main screens so the design can be
    /// checked against Figma without a person taking screenshots.
    static func snapshots(to dir: String) {
        // Glass buttons can't be drawn offscreen, so pictures use their plain look-alike.
        ControlMetrics.capture = true
        defer { ControlMetrics.capture = false }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let folder = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = Store.shared
        store.scan()

        func save(_ rep: NSBitmapImageRep?, _ name: String) {
            guard let png = rep?.representation(using: .png, properties: [:]) else { print("  no picture: \(name)"); return }
            try? png.write(to: folder.appendingPathComponent(name + ".png"))
            print("  saved \(name).png")
        }
        // Shots use the real window background in the given appearance (TUM follows Light and Dark Mode).
        func shot<V: View>(_ v: V, _ size: NSSize, _ name: String, light: Bool = false) {
            let look = NSAppearance(named: light ? .aqua : .darkAqua)!
            var bg = NSColor.windowBackgroundColor.cgColor
            look.performAsCurrentDrawingAppearance { bg = NSColor.windowBackgroundColor.cgColor }
            let host = NSHostingView(rootView: v.environment(\.colorScheme, light ? .light : .dark)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor)))
            host.frame = NSRect(origin: .zero, size: size)
            host.appearance = look
            host.wantsLayer = true
            host.layer?.backgroundColor = bg
            let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            win.appearance = look
            win.backgroundColor = NSColor(cgColor: bg) ?? .windowBackgroundColor
            win.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            host.display()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)
            if let r = rep { host.cacheDisplay(in: host.bounds, to: r) }
            save(rep, name)
        }
        func render<V: View>(_ v: V, _ name: String) {
            let r = ImageRenderer(content: v.padding(6).background(Color(hex: 0x2A2D3A)))
            r.scale = 8
            guard let img = r.nsImage, let tiff = img.tiffRepresentation else { return }
            save(NSBitmapImageRep(data: tiff), name)
        }

        render(PillView(glyph: store.glyph(store.demoID), symbol: store.symbol(store.demoID), pct: 24, level: .low), "pill-yellow")
        render(PillView(glyph: store.glyph(store.demoID), symbol: store.symbol(store.demoID), pct: 8, level: .out), "pill-red")
        if let g = store.glyph(store.demoID) {
            render(Image(nsImage: g).resizable().frame(width: 64, height: 64).background(Color.black), "logo-mark")
        }
        for step in 1...4 { shot(OnboardingView(store: store, finish: {}, startStep: step), NSSize(width: 800, height: OnboardingView.height), "onboarding-\(step)") }
        if let app = store.detected.first(where: { $0.supported && $0.canConnect }) ?? store.detected.first {
            shot(ConnectSheet(store: store, app: app, done: {}), NSSize(width: 480, height: 600), "connect")
        }
        shot(PopoverView(store: store, openSettings: {}, openAddMore: {}), NSSize(width: 340, height: 470), "popover")
        shot(IntroCallout(dismiss: {}), NSSize(width: 340, height: 150), "intro")
        render(HStack(spacing: 12) { LimitIcon(kind: .short, size: 14); LimitIcon(kind: .long, size: 14) }.foregroundColor(.white), "limit-icons")

        #if DEBUG
        // Debug builds (dev.sh) also save the sample-data states from Previews.swift.
        let yellow = Store.preview(apps: ["claude": 24, "codex": 88, "cursor": 70])
        let red = Store.preview(apps: ["claude": 62, "codex": 8])
        shot(PopoverView(store: yellow, openSettings: {}, openAddMore: {}), NSSize(width: 340, height: 470), "dev-popover-yellow")
        shot(PopoverView(store: red, openSettings: {}, openAddMore: {}), NSSize(width: 340, height: 470), "dev-popover-red")
        shot(DetailView(store: yellow, id: "claude", back: {}), NSSize(width: 340, height: 440), "dev-detail")
        shot(DetailView(store: yellow, id: "cursor", back: {}), NSSize(width: 340, height: 440), "dev-detail-monthly")
        let greenShot = Store.preview(apps: ["claude": 62, "codex": 80, "cursor": 70])
        greenShot.snapshots["codex"] = ProviderSnapshot(limits: Store.useItLimits("codex"), fetchedAt: Date())
        shot(PopoverView(store: greenShot, openSettings: {}, openAddMore: {}), NSSize(width: 340, height: 490), "dev-popover-green")
        // Every official logo as TUM draws it, to check sizes side by side.
        let logoIDs = BrandLogos.all.keys.sorted()
        shot(LazyVGrid(columns: Array(repeating: GridItem(.fixed(70)), count: 6), spacing: 12) {
            ForEach(logoIDs, id: \.self) { id in
                VStack(spacing: 4) {
                    AppTile(icon: BrandLogos.tile(id), symbol: "questionmark", size: 48)
                    Text(id).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding(14), NSSize(width: 470, height: 260), "dev-logos")
        // The white marks TUM draws in usage circles and pills, for the supported apps.
        let marks = Store.preview(apps: ["claude": 62, "codex": 80, "cursor": 70, "grokbot": 55, "copilot": 90])
        shot(HStack(spacing: 14) {
            ForEach(["claude", "codex", "cursor", "grokbot", "copilot"], id: \.self) { id in
                VStack(spacing: 4) {
                    LiquidTile(pct: 60, level: .ok, glyph: marks.glyph(id), symbol: marks.symbol(id), size: 56)
                    Text(id).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding(14), NSSize(width: 400, height: 110), "dev-marks")
        let pending = Store.preview(apps: ["claude": 62])
        pending.snapshots["claude"] = nil
        pending.needsApproval = ["claude"]
        shot(DetailView(store: pending, id: "claude", back: {}), NSSize(width: 340, height: 440), "dev-detail-connect")
        shot(SettingsView(store: yellow), NSSize(width: 580, height: 660), "dev-settings")
        let formBefore = Feedback.config
        Feedback.config = .init(formID: "", message: "", email: "", version: "")
        shot(FeedbackPage(back: {}), NSSize(width: 340, height: 330), "dev-feedback-github")
        Feedback.config = formBefore
        shot(FeedbackPage(back: {}), NSSize(width: 340, height: 400), "dev-feedback")
        let recording = Store.preview(apps: ["claude": 62])
        recording.startRecordingShortcut()
        recording.recorded(.failure(.usedByMac("⌘ + Q")))
        shot(OnboardingView(store: recording, finish: {}, startStep: 4), NSSize(width: 800, height: OnboardingView.height), "dev-shortcut-recording")
        let wide = Store.preview(apps: ["claude": 100, "codex": 100, "copilot": 100, "cursor": 100])
        shot(HoverTip(store: wide), NSSize(width: 360, height: 200), "dev-hover-tip-wide")
        shot(HoverTip(store: yellow), NSSize(width: 380, height: 160), "dev-hover-tip")
        shot(QuickView(store: yellow), NSSize(width: 360, height: 220), "dev-quick-view")
        // Settings rows outside the scrolling form (offscreen captures can't draw forms).
        shot(VStack(spacing: 0) {
            SettingRow("Usage monitoring", subtitle: "Which limit TUM watches for you") { SegmentedChoice(selection: .constant(WatchMode.monthly), options: WatchMode.segments) }
            Divider()
            SettingRow("Turn yellow at", subtitle: "When the icon turns yellow") { SegmentedChoice(selection: .constant(25.0), options: Thresholds.yellow) }
            Divider()
            SettingRow("Show usage when I open a low app", subtitle: "A quick look when you open an app that's running low") { Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).controlSize(.regular) }
            Divider()
            SettingRow("Welcome screens", subtitle: "See the welcome tour again") { Button("Show welcome screens again", systemImage: "play.fill") {}.iconButton() }
        }.padding(.horizontal, 14).padding(.vertical, 6).frame(width: 520).contentCard().padding(16), NSSize(width: 560, height: 230), "dev-setting-rows")
        shot(OnboardingView(store: Store.preview(apps: ["claude": 62], onboardingDone: false), finish: {}, startStep: 3),
             NSSize(width: 800, height: OnboardingView.height), "dev-onboarding-3-connected")
        shot(VStack(alignment: .trailing, spacing: 12) {
            MorphMark(level: .ok, pct: nil, glyph: nil, symbol: "asterisk")
            MorphMark(level: .low, pct: 24, glyph: yellow.glyph("claude"), symbol: "asterisk")
            MorphMark(level: .out, pct: 8, glyph: yellow.glyph("claude"), symbol: "asterisk")
            MorphMark(level: .use, pct: 85, glyph: yellow.glyph("claude"), symbol: "asterisk")
        }.padding(12), NSSize(width: 140, height: 140), "dev-menubar-states")
        // App cards outside the scroll view, so the Connect button and the check can be compared.
        let cards = Store.preview(apps: ["claude": 62], onboardingDone: false)
        let other = AIApp(id: "perplexity", name: "Perplexity", category: "Search", appURL: nil, supported: false,
                          credentialFound: false, hint: "Usage view planned", source: "")
        shot(VStack(spacing: 10) {
            ForEach(Array(cards.detected.prefix(3))) { app in AppCard(store: cards, app: app, connect: {}) }
            ComingSoonCard(store: cards, app: other)
            ComingSoonCard(store: cards, app: Catalog.plannedApps[0])
        }.padding(12).frame(width: 280), NSSize(width: 280, height: 470), "dev-app-cards")
        // Every Coming soon card, outside a scroll view.
        let soon = Catalog.plannedApps
        shot(LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(soon) { app in ComingSoonCard(store: cards, app: app) }
        }.padding(12).frame(width: 776), NSSize(width: 776, height: CGFloat((soon.count + 2) / 3) * 78 + 24), "dev-coming-soon")
        // The same key screens in Light Mode.
        shot(OnboardingView(store: Store.preview(apps: ["claude": 62], onboardingDone: false), finish: {}, startStep: 4),
             NSSize(width: 800, height: OnboardingView.height), "light-onboarding-4", light: true)
        shot(PopoverView(store: yellow, openSettings: {}, openAddMore: {}), NSSize(width: 340, height: 470), "light-popover-yellow", light: true)
        shot(VStack(spacing: 10) {
            ForEach(cards.detected.prefix(3)) { app in AppCard(store: cards, app: app, connect: {}) }
        }.padding(12).frame(width: 280), NSSize(width: 280, height: 240), "light-app-cards", light: true)
        // Pictures for the README, all in Dark Mode (AK).
        let tour = Store.preview(apps: ["claude": 62, "codex": 80, "cursor": 70, "grokbot": 55], onboardingDone: false)
        shot(OnboardingView(store: tour, finish: {}, startStep: 1), NSSize(width: 800, height: OnboardingView.height), "readme-welcome")
        shot(OnboardingView(store: tour, finish: {}, startStep: 3), NSSize(width: 800, height: OnboardingView.height), "readme-apps")
        shot(OnboardingView(store: yellow, finish: {}, startStep: 4), NSSize(width: 800, height: OnboardingView.height), "readme-nudge")
        shot(PopoverView(store: yellow, openSettings: {}, openAddMore: {}), NSSize(width: 340, height: 360), "readme-popover")
        shot(DetailView(store: yellow, id: "claude", back: {}), NSSize(width: 340, height: 400), "readme-detail")
        shot(HStack(alignment: .top, spacing: 36) {
            ForEach([("All good", MorphMark(level: .ok, pct: nil, glyph: nil, symbol: "asterisk")),
                     ("Getting low", MorphMark(level: .low, pct: 24, glyph: yellow.glyph("claude"), symbol: "asterisk")),
                     ("Almost out", MorphMark(level: .out, pct: 8, glyph: yellow.glyph("claude"), symbol: "asterisk")),
                     ("Worth using", MorphMark(level: .use, pct: 85, glyph: yellow.glyph("claude"), symbol: "asterisk"))], id: \.0) { item in
                VStack(spacing: 12) {
                    item.1
                    Text(item.0).font(.callout).foregroundStyle(.secondary)
                }
            }
        }.padding(24), NSSize(width: 640, height: 110), "readme-pills")
        #endif
    }

    /// SDK version recorded in this app's own binary.
    static func linkedSDKMajor() -> Int? {
        guard let header = _dyld_get_image_header(0) else { return nil }
        var p = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
        for _ in 0..<Int(header.pointee.ncmds) {
            let lc = p.load(as: load_command.self)
            if lc.cmd == UInt32(LC_BUILD_VERSION) {
                return Int(p.load(as: build_version_command.self).sdk >> 16)
            }
            p = p.advanced(by: Int(lc.cmdsize))
        }
        return nil
    }

    private static func fits<V: View>(_ v: V) -> Bool {
        let host = NSHostingView(rootView: v)
        host.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        host.layoutSubtreeIfNeeded()
        let s = host.fittingSize
        return s.width > 10 && s.height > 10
    }

    private static func render<V: View>(_ v: V) -> Bool {
        let r = ImageRenderer(content: v)
        r.scale = 2
        guard let img = r.nsImage else { return false }
        return img.size.width > 10
    }

    private static func testIcon(withMark: Bool) -> NSImage {
        NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            NSColor(red: 0.95, green: 0.55, blue: 0.2, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), xRadius: 28, yRadius: 28).fill()
            if withMark {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 40, dy: 40)).fill()
            }
            return true
        }
    }
}
