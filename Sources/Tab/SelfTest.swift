import SwiftUI
import AppKit
import MachO
import Carbon.HIToolbox
import Security

/// `TAB --self-test` checks the parts most likely to break, without the network
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
        print("TAB self-test")
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
        // Gemini app limits through TAB's own Google sign-in (AK, 2026-11-06).
        let gemReply = #")]}' [{"data":{"viewer":{"rpcs":{"getUsageInfo":{"pools":[{"poolType":"GXU_FIVE_HOURLY","percentageUsed":0.25,"gxu":{"windowRefreshesAt":"2026-11-07T01:00:00Z"}},{"poolType":"GXU_WEEKLY","percentageUsed":0.6}]}}}}}]"#
        let gem = GeminiAuth.parse(gemReply)
        check("Gemini app shows 75% of its 5 hours and 40% of its week left",
              gem?.signedOut == false && gem?.limits.count == 2
              && gem?.limits.first.map { $0.kind == .short && abs($0.percentLeft - 75) < 0.01 && $0.resetsAt != nil } == true
              && gem?.limits.last.map { $0.kind == .long && abs($0.percentLeft - 40) < 0.01 } == true)
        check("Gemini notices a signed-out reply and rejects odd ones",
              GeminiAuth.parse(#")]}'[{"data":{"viewer":null}}]"#)?.signedOut == true
              && GeminiAuth.parse("<html>sign in</html>")?.signedOut == true
              && GeminiAuth.parse(#"[{"data":{"viewer":{"rpcs":{}}}}]"#) == nil && GeminiAuth.parse("x") == nil)
        let gemCookies = [HTTPCookie(properties: [.name: "SID", .value: "abc", .domain: ".google.com", .path: "/"])!,
                          HTTPCookie(properties: [.name: "OTHER", .value: "x", .domain: ".example.com", .path: "/"])!,
                          HTTPCookie(properties: [.name: "BAD", .value: "a b", .domain: ".google.com", .path: "/"])!]
        let kept = GeminiAuth.keep(gemCookies)
        let merged = GeminiAuth.merge(kept, [.init(name: "SID", value: "new", domain: ".google.com", path: "/", expires: nil)])
        check("Gemini keeps only google.com cookies, safe for a header, and takes Google's refreshed ones",
              kept.map(\.name) == ["SID"] && GeminiAuth.header(kept) == "SID=abc" && GeminiAuth.header(merged) == "SID=new"
              && GeminiAuth.header([]) == nil && GeminiAuth.usageURL.host == "gemini.google.com"
              && GeminiAuth.merge(kept, [.init(name: "SID", value: "x", domain: ".google.com", path: "/", expires: Date().addingTimeInterval(-1))]).isEmpty
              && GeminiAuth.header([.init(name: "SID", value: "old", domain: ".google.com", path: "/", expires: Date().addingTimeInterval(-60))]) == nil)
        check("Unknown reply is rejected, not shown as 0%", CursorProvider.parse(["something": 1] as [String: Any]) == nil && GrokProvider.parse([String: Any]()) == nil && GrokBotProvider.parse("x") == nil)

        // Codex's local session file.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("tab-selftest-\(UUID().uuidString).jsonl")
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
        let noNumbers = Store.preview(apps: ["claude": 60])
        noNumbers.connected.append("copilot")
        let byTab = WatchMode.allCases.map { m -> [String] in noNumbers.mode = m; return noNumbers.tabApps }
        check("An app with no numbers yet shows only on the tabs its kind of limit belongs to",
              byTab[0] == ["claude"] && byTab[1] == ["claude"] && byTab[2] == ["copilot"]
              && Catalog.kinds("cursor") == [.monthly] && Catalog.kinds("claude") == [.session, .weekly])
        check("Tabs match their period", WatchMode.session.matches(se) && WatchMode.weekly.matches(wk) && WatchMode.monthly.matches(mo)
              && !WatchMode.session.matches(wk) && !WatchMode.monthly.matches(se))

        // Levels.
        let store = Store.shared
        check("8% is almost out", store.level(8) == .out)
        check("At the threshold is low", store.level(store.threshold) == .low)
        // v4 two levels: red from 0 to R, yellow from R to Y, fine above Y. Every R and Y the slider
        // allows, every half percent: exactly one level, no gap and no overlap.
        var zonesOK = true
        for r in stride(from: Store.redRange.lowerBound, through: Store.redRange.upperBound, by: 1) {
            for y in stride(from: r + Store.levelGap, through: Store.yellowMax, by: 1) {
                for p in stride(from: 0.0, through: 100, by: 0.5) {
                    let want: Level = p <= r ? .out : (p <= y ? .low : .ok)
                    if Store.level(p, red: r, yellow: y) != want { zonesOK = false }
                }
            }
        }
        check("Alert levels have no gap and no overlap for every Almost out and Getting low", zonesOK)
        let slider = Store.preview(apps: ["claude": 50])
        slider.setLevels(red: 25, yellow: 40)
        // Red can go right up to yellow, and pushes it along instead of stopping (AK, 2026-11-09).
        slider.setRedAt(50); let pushedUp = (slider.redAt, slider.yellowAt)
        slider.setYellowAt(20); let pushedDown = (slider.redAt, slider.yellowAt)
        slider.setYellowAt(90); let yellowCapped = slider.yellowAt
        slider.setRedAt(-5); let redFloored = slider.redAt
        slider.setRedAt(99); let redCapped = (slider.redAt, slider.yellowAt)
        check("The two levels push each other and never cross or leave their range",
              pushedUp == (50, 55) && pushedDown == (15, 20) && yellowCapped == 60 && redFloored == 5
              && redCapped == (55, 60)
              && slider.level(slider.yellowAt) == .low && slider.level(slider.redAt) == .out)
        func migrated(_ old: Double?) -> (Double, Double) {
            let suite = "tab-selftest-levels"
            let d = UserDefaults(suiteName: suite)!
            d.removePersistentDomain(forName: suite)
            if let old { d.set(old, forKey: "threshold") }
            let st = Store(defaults: d)
            d.removePersistentDomain(forName: suite)
            return (st.redAt, st.yellowAt)
        }
        let m20 = migrated(20), m40 = migrated(40), m0 = migrated(nil)
        check("Old \"Turn yellow at\" becomes Getting low, and new installs start at 25 and 40",
              m20 == (15, 20) && m40 == (25, 40) && m0 == (25, 40))
        check("Plenty left is fine", store.level(90) == .ok)

        check("Onboarding version is set", Store.onboardingVersion >= 4)

        // Several accounts (v4): the top one is used, the pill follows it, and a low one suggests
        // the other when it has room.
        let multi = Store.preview(apps: ["codex": 88])
        multi.addSampleAccounts("claude", first: 24, second: 81)
        let inUse = multi.accountInUse("claude")?.email
        let firstPct = multi.percent("claude")
        let suggestion = multi.switchSuggestion("claude")
        let switchLine = multi.summary.text
        multi.moveAccount("claude", from: 1, to: 0)
        let afterMove = (multi.accountInUse("claude")?.email, multi.percent("claude"), multi.switchSuggestion("claude") == nil)
        check("The top account is used first, and dragging another to the top switches to it",
              inUse == "maya@brightpixel.co" && firstPct.map { abs($0 - 24) < 0.01 } == true
              && afterMove.0 == "maya.chen@gmail.com" && afterMove.1.map { abs($0 - 81) < 0.01 } == true
              && multi.accountList("claude").map(\.order) == [0, 1])
        check("A low account suggests switching to one with room",
              suggestion?.email == "maya.chen@gmail.com" && suggestion.map { abs($0.pct - 81) < 0.01 } == true
              && switchLine == "Claude is low. Switch to maya.chen@gmail.com\u{00A0}(81%)." && afterMove.2)
        let migrateSuite = "tab-selftest-accounts"
        let md = UserDefaults(suiteName: migrateSuite)!
        md.removePersistentDomain(forName: migrateSuite)
        md.set(["claude", "codex"], forKey: "connected")
        let migratedStore = Store(defaults: md)
        md.removePersistentDomain(forName: migrateSuite)
        check("Apps connected before v4 get one account each",
              migratedStore.accounts["claude"]?.count == 1 && migratedStore.accounts["codex"]?.first?.source == "auto")
        check("Emails never reach the log",
              Diagnostics.clean("claude: maya.chen@gmail.com signed in, 200") == "claude: <email> signed in, 200"
              && !Diagnostics.clean("x maya@brightpixel.co").contains("@"))
        check("Update check compares versions",
              Updates.isNewer("v0.2.0", than: "0.1.1") && !Updates.isNewer("v0.1.1", than: "0.1.1")
              && Updates.isNewer("0.10.0", than: "0.9.9") && !Updates.isNewer("v0.1.0", than: "0.2.0")
              && Updates.newest(["v0.1.0", "v0.2.1", "nightly", "v0.10.0", "v0.2.0"]) == "v0.10.0" && Updates.newest(["test"]) == nil)

        // Logo marks from app icons.
        check("Logo mark found on a plain icon", GlyphMaker.whiteGlyph(from: testIcon(withMark: true)) != nil)
        check("Plain tile gives no logo mark", GlyphMaker.whiteGlyph(from: testIcon(withMark: false)) == nil)

        // Every screen can be built and laid out without crashing.
        check("Popover lays out", fits(PopoverView(store: store, openSettings: {}, openConnect: { _, _ in })))
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
            check("No Keychain reads before onboarding", Keychain.read(service: "tab-self-test", interactive: false).status == errSecInteractionNotAllowed)
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
        let bar = StatusItemController(store: barStore, openSettings: {}, openConnect: { _, _ in }, showWelcome: {})
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
        print("        popover before \(popBefore.map { NSStringFromRect($0) } ?? "none"), after \(popAfter.map { NSStringFromRect($0) } ?? "none")")
        // The popover hugs its content (v4), and the status line goes away with the pill, so its
        // height may change. It must keep its side and the edge next to the icon. Offscreen
        // runs can place it above the item, so either edge counts.
        let samePlace = popBefore.flatMap { b in popAfter.map { a in
            abs(b.minX - a.minX) < 1 && (abs(b.maxY - a.maxY) < 1 || abs(b.minY - a.minY) < 1)
        } } ?? false
        check("The open popover stays put when the pill turns into the icon (AK)", samePlace)
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
        set("claude", 30); let first = flow.urgent?.id
        set("codex", 35); let second = flow.urgent?.id          // news takes the pill at once
        let turn = Store.pillTurnLength + 1
        flow.rotatePill(now: Date().addingTimeInterval(turn)); let third = flow.urgent?.id        // then Claude's turn
        flow.rotatePill(now: Date().addingTimeInterval(turn * 2)); let fourth = flow.urgent?.id   // and Codex again
        flow.holdPill = true
        flow.rotatePill(now: Date().addingTimeInterval(turn * 3)); let held = flow.urgent?.id      // not while TAB is open
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
        // Use it before it resets: green pill until TAB is opened, never over a warning.
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
        let ack = Store.preview(apps: ["claude": 32], threshold: 40)
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
        check("App notes fit on one line", (Catalog.all + Catalog.webEntries).allSatisfy { $0.hint.count <= 24 }
              && Catalog.all.filter { ["cursor", "grokbot", "gemini"].contains($0.id) }.allSatisfy { $0.hint.count <= 18 })
        // Apps TAB can't read are never connected (AK: no data, no point). They wait in Coming soon,
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
        let oldSuite = "tab-selftest-noreader"
        let oldDefaults = UserDefaults(suiteName: oldSuite)!
        oldDefaults.removePersistentDomain(forName: oldSuite)
        oldDefaults.set(["claude", "perplexity", "lovable", "kiro"], forKey: "connected")
        let reloaded = Store(defaults: oldDefaults).connected
        oldDefaults.removePersistentDomain(forName: oldSuite)
        check("Apps TAB can't read are never connected or offered",
              !perplexity.canConnect && !noReader.connected.contains("perplexity") && (refusal ?? nil) != nil
              && !noReader.readyToConnect.contains { $0.id == "perplexity" } && !noReader.addable(web: false).contains { $0.id == "perplexity" }
              && reloaded == ["claude"])
        // The rename from TUM: settings come over once, sign-ins keep working under the new name.
        let oldName = "tab-selftest-old", newName = "tab-selftest-new"
        let oldPrefs = UserDefaults(suiteName: oldName)!, newPrefs = UserDefaults(suiteName: newName)!
        oldPrefs.removePersistentDomain(forName: oldName); newPrefs.removePersistentDomain(forName: newName)
        newPrefs.set(0, forKey: "launchInProgress")   // a stray key from a self-test run doesn't stop the move
        oldPrefs.set(["claude", "codex"], forKey: "connected")
        oldPrefs.set(-1, forKey: "NSStatusItem Preferred Position TUM")
        Rename.moveSettings(from: oldName, into: newPrefs, id: newName)
        let movedOnce = newPrefs.stringArray(forKey: "connected") == ["claude", "codex"]
            && newPrefs.object(forKey: "NSStatusItem Preferred Position TAB") != nil
        oldPrefs.set(["zed"], forKey: "connected")
        Rename.moveSettings(from: oldName, into: newPrefs, id: newName)
        let notAgain = newPrefs.stringArray(forKey: "connected") == ["claude", "codex"]
        oldPrefs.removePersistentDomain(forName: oldName); newPrefs.removePersistentDomain(forName: newName)
        check("TAB brings TUM's settings over once, and its own sign-ins keep their old names as a fallback",
              movedOnce && notAgain
              && Rename.oldID(for: "edu.umd.inst474.tab") == "edu.umd.inst474.tum"
              && Rename.oldID(for: "edu.umd.inst474.tab.dev") == "edu.umd.inst474.tum.dev"
              && Rename.oldID(for: "com.example.other") == nil
              && Keychain.oldName(CursorAuth.service) == "TUM Cursor sign-in"
              && Keychain.oldName(GitHubAuth.service) == "TUM GitHub sign-in"
              && Keychain.oldName(GeminiAuth.service) == "TUM Gemini sign-in")
        check("Only installed apps count for apps TAB can't read, never a leftover folder",
              Catalog.all.filter { $0.providerID == nil }.allSatisfy { $0.markers.isEmpty }
              && !Catalog.all.contains { ["lovable", "canva", "capcut"].contains($0.id) })
        // On the web (v4): each app once, with a real logo and its domain, never also a Mac app.
        // Only ChatGPT has a reader, and only while web sign-in is on.
        let webIDs = Catalog.webApps.map(\.id)
        check("Web apps are listed once, with a logo and domain, and only ChatGPT can connect",
              Set(webIDs).count == webIDs.count && Array(webIDs.prefix(4)) == WebSite.featured
              && Catalog.webApps.allSatisfy { BrandLogos.logo($0.id) != nil && $0.domain != nil }
              && Catalog.all.allSatisfy { !webIDs.contains($0.id) }
              && Catalog.webApps.filter(\.canConnect).map(\.id) == (WebAuth.enabled ? ["chatgpt"] : [])
              && !webIDs.contains("sora") && !webIDs.contains("midjourney"))
        let fb = Feedback.issueURL("  Pill stays yellow + won't clear\nafter reset  ")?.absoluteString ?? ""
        check("Feedback opens a filled-in GitHub issue on TAB's repo, never an empty one",
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
        check("ChatGPT is never detected as a Mac app", !Detector.scan().contains { $0.name.localizedCaseInsensitiveContains("ChatGPT") })
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
        let saysWhy = rec.shortcutProblem == .oneModifier && rec.recordingShortcut && rec.pendingShortcut == nil
        rec.recorded(.success(ctrlK))
        let showsFirst = rec.recordingShortcut && rec.pendingShortcut == ctrlK && rec.shortcutChoice != ctrlK
        rec.saveRecordedShortcut()
        check("The shortcut box says why a press won't work, shows the good one, and saves it on Save",
              saysWhy && showsFirst && !rec.recordingShortcut && rec.shortcutChoice == ctrlK && rec.customShortcut == ctrlK
              && rec.pendingShortcut == nil)
        rec.shortcutChoice = .commandT
        rec.startRecordingShortcut()
        let reopens = rec.recordingShortcut && rec.pendingShortcut == ctrlK
        rec.stopRecordingShortcut()
        let cancelKeeps = rec.shortcutChoice == .commandT && rec.customShortcut == ctrlK
        rec.shortcutChoice = ctrlK
        rec.activeShortcut = ctrlK
        let syncLine = Store.preview(apps: ["claude": 62])
        let fresh = syncLine.snapshots["claude"]
        syncLine.snapshots["claude"] = fresh.map { ProviderSnapshot(limits: $0.limits, fetchedAt: Date()) }
        let hidesWhenFresh = !syncLine.showsSyncLine("claude")
        syncLine.snapshots["claude"] = fresh.map { ProviderSnapshot(limits: $0.limits, fetchedAt: Date(timeIntervalSinceNow: -20 * 60)) }
        let showsWhenOld = syncLine.showsSyncLine("claude")
        syncLine.snapshots["claude"] = fresh.map { ProviderSnapshot(limits: $0.limits, fetchedAt: Date()) }
        syncLine.errors["claude"] = "Can't reach Claude right now."
        check("The sync time shows only when numbers are old or a check failed",
              hidesWhenFresh && showsWhenOld && syncLine.showsSyncLine("claude"))
        check("Custom always opens the box with the saved keys in it, and Cancel keeps the old pick",
              reopens && cancelKeeps && rec.shortcutSubtitle("x") == "Your own keys, \(ctrlK.glyphs)")
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
        let rowTabs = NSHostingView(rootView: SettingRow("Usage monitoring", subtitle: "Which limit TAB watches for you") { SegmentedChoice(selection: .constant(WatchMode.session), options: WatchMode.segments) }).fittingSize
        let rowSwitch = NSHostingView(rootView: SettingRow("Open at login", subtitle: "Start TAB when you turn on your Mac") { Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).controlSize(.regular) }).fittingSize
        let rowButton = NSHostingView(rootView: SettingRow("Welcome screens", subtitle: "See the welcome tour again") { Button("Show welcome screens again", systemImage: "play.fill") {}.iconButton() }).fittingSize
        check("Every settings row has the same height", Set([rowTabs.height, rowSwitch.height, rowButton.height].map { Int($0.rounded()) }).count == 1)
        check("All buttons share one height", Set([plug.height, back.height, text.height, main.height].map { Int($0.rounded()) }).count == 1)
        NSStatusBar.system.removeStatusItem(item)
        check("App detection runs", { _ = Detector.scan(); return true }())

        print(failures.isEmpty ? "All \(passed) checks passed." : "\(failures.count) of \(passed + failures.count) checks failed: \(failures.joined(separator: "; "))")
        return failures.isEmpty
    }

    /// `TAB --snapshots <folder>` saves pictures of the main screens so the design can be
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
        // Shots use the real window background in the given appearance (TAB follows Light and Dark Mode).
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
        for step in 1...5 { shot(OnboardingView(store: store, finish: {}, startStep: step), NSSize(width: 800, height: OnboardingView.height), "onboarding-\(step)") }
        if let app = store.detected.first(where: { $0.supported && $0.canConnect }) ?? store.detected.first {
            shot(ConnectSheet(store: store, app: app, done: {}), NSSize(width: 480, height: 600), "connect")
        }
        shot(PopoverView(store: store, openSettings: {}, openConnect: { _, _ in }), NSSize(width: 340, height: 470), "popover")
        shot(IntroCallout(dismiss: {}), NSSize(width: 340, height: 150), "intro")
        render(HStack(spacing: 12) { LimitIcon(kind: .short, size: 14); LimitIcon(kind: .long, size: 14) }.foregroundColor(.white), "limit-icons")

        #if DEBUG
        // Debug builds (dev.sh) also save the sample-data states from Previews.swift.
        let yellow = Store.preview(apps: ["claude": 32, "codex": 88, "cursor": 70])
        let red = Store.preview(apps: ["claude": 62, "codex": 8])
        shot(PopoverView(store: yellow, openSettings: {}, openConnect: { _, _ in }), NSSize(width: 340, height: 470), "dev-popover-yellow")
        shot(PopoverView(store: red, openSettings: {}, openConnect: { _, _ in }), NSSize(width: 340, height: 470), "dev-popover-red")
        shot(DetailView(store: yellow, id: "claude", back: {}), NSSize(width: 340, height: 440), "dev-detail")
        shot(DetailView(store: yellow, id: "cursor", back: {}), NSSize(width: 340, height: 440), "dev-detail-monthly")
        let greenShot = Store.preview(apps: ["claude": 62, "codex": 80, "cursor": 70])
        greenShot.snapshots["codex"] = ProviderSnapshot(limits: Store.useItLimits("codex"), fetchedAt: Date())
        shot(PopoverView(store: greenShot, openSettings: {}, openConnect: { _, _ in }), NSSize(width: 340, height: 490), "dev-popover-green")
        // Every official logo as TAB draws it, to check sizes side by side.
        let logoIDs = BrandLogos.all.keys.sorted()
        shot(LazyVGrid(columns: Array(repeating: GridItem(.fixed(70)), count: 6), spacing: 12) {
            ForEach(logoIDs, id: \.self) { id in
                VStack(spacing: 4) {
                    AppTile(icon: BrandLogos.tile(id), symbol: "questionmark", size: 48)
                    Text(id).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding(14), NSSize(width: 470, height: 260), "dev-logos")
        // The white marks TAB draws in usage circles and pills, for the supported apps.
        let marks = Store.preview(apps: ["claude": 62, "codex": 80, "cursor": 70, "grokbot": 55, "copilot": 90, "gemini": 75])
        shot(HStack(spacing: 14) {
            ForEach(["claude", "codex", "cursor", "grokbot", "copilot", "gemini"], id: \.self) { id in
                VStack(spacing: 4) {
                    LiquidTile(pct: 60, level: .ok, glyph: marks.glyph(id), symbol: marks.symbol(id), size: 56)
                    Text(id).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }.padding(14), NSSize(width: 470, height: 110), "dev-marks")
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
        shot(ShortcutEditor(store: recording), NSSize(width: 320, height: 230), "dev-shortcut-box")
        recording.recorded(.failure(.usedByMac("⌘ + Q")))
        shot(ShortcutEditor(store: recording), NSSize(width: 320, height: 230), "dev-shortcut-box-problem")
        recording.recorded(.success(ShortcutChoice(modifier: .control, key: "K", keyCode: UInt16(kVK_ANSI_K))))
        shot(ShortcutEditor(store: recording), NSSize(width: 320, height: 230), "light-shortcut-box-keys", light: true)
        // The real button styles (not the capture look-alike), in both modes.
        let wasCapture = ControlMetrics.capture
        ControlMetrics.capture = false
        let buttons = HStack(spacing: 10) {
            Button("All apps", systemImage: "chevron.left") {}.iconButton()
            ConnectButton(name: "Test", action: {})
            Button {} label: { ButtonText("Copy diagnostics") }.secondaryButton()
            Button {} label: { ButtonText("Next") }.primaryButton()
        }.padding(16)
        shot(buttons, NSSize(width: 420, height: 64), "dev-buttons")
        shot(buttons, NSSize(width: 420, height: 64), "light-buttons", light: true)
        ControlMetrics.capture = wasCapture
        let wide = Store.preview(apps: ["claude": 100, "codex": 100, "copilot": 100, "cursor": 100])
        shot(HoverTip(store: wide), NSSize(width: 360, height: 200), "dev-hover-tip-wide")
        shot(HoverTip(store: yellow), NSSize(width: 380, height: 160), "dev-hover-tip")
        shot(QuickView(store: yellow), NSSize(width: 360, height: 220), "dev-quick-view")
        // Settings rows outside the scrolling form (offscreen captures can't draw forms).
        shot(VStack(spacing: 0) {
            SettingRow("Usage monitoring", subtitle: "Which limit TAB watches for you") { SegmentedChoice(selection: .constant(WatchMode.monthly), options: WatchMode.segments) }
            Divider()
            SettingRow(LevelSlider.yellowTitle, subtitle: LevelSlider.yellowSubtitle) { LevelSlider(store: yellow, red: false) }
            Divider()
            SettingRow(LevelSlider.redTitle, subtitle: LevelSlider.redSubtitle) { LevelSlider(store: yellow, red: true) }
            Divider()
            SettingRow("Show usage when I open a low app", subtitle: "A quick look when you open an app that's running low") { Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).controlSize(.regular) }
            Divider()
            SettingRow("Welcome screens", subtitle: "See the welcome tour again") { Button("Show welcome screens again", systemImage: "play.fill") {}.iconButton() }
        }.padding(.horizontal, 14).padding(.vertical, 6).frame(width: 520).contentCard().padding(16), NSSize(width: 560, height: 290), "dev-setting-rows")
        shot(OnboardingView(store: Store.preview(apps: ["claude": 62], onboardingDone: false), finish: {}, startStep: 4),
             NSSize(width: 800, height: OnboardingView.height), "dev-onboarding-4-connected")
        shot(VStack(alignment: .trailing, spacing: 12) {
            MorphMark(level: .ok, pct: nil, glyph: nil, symbol: "asterisk")
            MorphMark(level: .low, pct: 32, glyph: yellow.glyph("claude"), symbol: "asterisk")
            MorphMark(level: .out, pct: 8, glyph: yellow.glyph("claude"), symbol: "asterisk")
            MorphMark(level: .use, pct: 85, glyph: yellow.glyph("claude"), symbol: "asterisk")
        }.padding(12), NSSize(width: 140, height: 140), "dev-menubar-states")
        // App cards outside the scroll view, so the Connect button and the check can be compared.
        let cards = Store.preview(apps: ["claude": 62], onboardingDone: false)
        let other = AIApp(id: "perplexity", name: "Perplexity", category: "Search", appURL: nil, supported: false,
                          credentialFound: false, hint: "Usage view planned", source: "")
        shot(VStack(spacing: 10) {
            ForEach(Array(cards.detected.prefix(3))) { app in AppCard(store: cards, app: app, connect: {}) }
            AppCard(store: cards, app: Catalog.webApps[0], connect: {})
            AppCard(store: cards, app: other, connect: {})
        }.padding(12).frame(width: 280), NSSize(width: 280, height: 470), "dev-app-cards")
        // Every web app card, outside a scroll view.
        let soon = Catalog.webApps
        shot(LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            ForEach(soon) { app in AppCard(store: cards, app: app, connect: {}) }
        }.padding(12).frame(width: 776), NSSize(width: 776, height: CGFloat((soon.count + 2) / 3) * 78 + 24), "dev-web-apps")
        // The same key screens in Light Mode.
        shot(OnboardingView(store: Store.preview(apps: ["claude": 62], onboardingDone: false), finish: {}, startStep: 5),
             NSSize(width: 800, height: OnboardingView.height), "light-onboarding-5", light: true)
        shot(PopoverView(store: yellow, openSettings: {}, openConnect: { _, _ in }), NSSize(width: 340, height: 470), "light-popover-yellow", light: true)
        shot(VStack(spacing: 10) {
            ForEach(cards.detected.prefix(3)) { app in AppCard(store: cards, app: app, connect: {}) }
        }.padding(12).frame(width: 280), NSSize(width: 280, height: 240), "light-app-cards", light: true)
        // Pictures for the README, all in Dark Mode (AK).
        let tour = Store.preview(apps: ["claude": 62, "codex": 80, "cursor": 70, "grokbot": 55], onboardingDone: false)
        shot(OnboardingView(store: tour, finish: {}, startStep: 1), NSSize(width: 800, height: OnboardingView.height), "readme-welcome")
        shot(OnboardingView(store: tour, finish: {}, startStep: 4), NSSize(width: 800, height: OnboardingView.height), "readme-apps")
        shot(OnboardingView(store: yellow, finish: {}, startStep: 5), NSSize(width: 800, height: OnboardingView.height), "readme-nudge")
        shot(PopoverView(store: yellow, openSettings: {}, openConnect: { _, _ in }), NSSize(width: 340, height: 360), "readme-popover")
        shot(DetailView(store: yellow, id: "claude", back: {}), NSSize(width: 340, height: 400), "readme-detail")
        shot(HStack(alignment: .top, spacing: 36) {
            ForEach([("All good", MorphMark(level: .ok, pct: nil, glyph: nil, symbol: "asterisk")),
                     ("Getting low", MorphMark(level: .low, pct: 32, glyph: yellow.glyph("claude"), symbol: "asterisk")),
                     ("Almost out", MorphMark(level: .out, pct: 8, glyph: yellow.glyph("claude"), symbol: "asterisk")),
                     ("Not utilized enough", MorphMark(level: .use, pct: 85, glyph: yellow.glyph("claude"), symbol: "asterisk"))], id: \.0) { item in
                VStack(spacing: 12) {
                    item.1
                    Text(item.0).font(.callout).foregroundStyle(.secondary)
                }
            }
        }.padding(24), NSSize(width: 640, height: 110), "readme-pills")

        // v4 screens 01 to 13 (Figma "Prototype · TAB flow v4"), named to match.
        let v4tour = Store.preview(apps: ["claude": 62, "codex": 80, "cursor": 70, "grokbot": 55], onboardingDone: false)
        let v4fresh = Store.preview(apps: [:], onboardingDone: false)
        shot(OnboardingView(store: v4tour, finish: {}, startStep: 3), NSSize(width: 800, height: OnboardingView.height), "v4-01-counts")
        shot(OnboardingView(store: v4fresh, finish: {}, startStep: 4), NSSize(width: 800, height: OnboardingView.height), "v4-02-apps")
        shot(OnboardingView(store: v4fresh, finish: {}, startStep: 5), NSSize(width: 800, height: OnboardingView.height), "v4-03-alerts")
        for n in 1...4 {
            let tipStore = Store.preview(apps: ["claude": 32, "codex": 88])
            shot(PopoverView(store: tipStore, openSettings: {}, openConnect: { _, _ in }, startTip: n),
                 NSSize(width: 340, height: 420), "v4-0\(n + 3)-tip-\(n)")
        }
        let v4add = Store.preview(apps: ["claude": 32, "codex": 88])
        shot(PopoverView(store: v4add, openSettings: {}, openConnect: { _, _ in }, startAdding: true), NSSize(width: 340, height: 440), "v4-08-add-app")
        if let gpt = Catalog.webApp("chatgpt") {
            shot(ConnectSheet(store: v4add, app: gpt, done: {}), NSSize(width: 480, height: 600), "v4-09-web-sign-in")
        }
        let v4multi = Store.preview(apps: [:])
        v4multi.addSampleAccounts("claude", first: 32, second: 81)
        v4multi.addSampleAccounts("chatgpt", first: 88, second: 64)
        shot(PopoverView(store: v4multi, openSettings: {}, openConnect: { _, _ in }), NSSize(width: 340, height: 360), "v4-10-accounts")
        shot(DetailView(store: v4multi, id: "claude", back: {}), NSSize(width: 340, height: 340), "v4-11-account-detail")
        let v4settings = Store.preview(apps: ["codex": 80])
        v4settings.addSampleAccounts("claude", first: 32, second: 81)
        shot(SettingsView(store: v4settings), NSSize(width: 580, height: 660), "v4-12-settings")
        shot(VStack(alignment: .leading, spacing: 0) {
            SettingRow("Usage monitoring", subtitle: "Which limit TAB watches for you") { SegmentedChoice(selection: .constant(WatchMode.session), options: WatchMode.segments) }
            Divider()
            SettingRow(LevelSlider.yellowTitle, subtitle: LevelSlider.yellowSubtitle) { LevelSlider(store: v4settings, red: false) }
            Divider()
            SettingRow(LevelSlider.redTitle, subtitle: LevelSlider.redSubtitle) { LevelSlider(store: v4settings, red: true) }
            Divider()
            SettingRow("TAB \(Updates.current)", subtitle: UpdateChecker.shared.line) { Button {} label: { ButtonText("Check for updates") }.secondaryButton() }
        }.padding(.horizontal, 14).padding(.vertical, 6).frame(width: 540).contentCard().padding(16), NSSize(width: 580, height: 330), "v4-13-settings-rows")
        shot(OnboardingView(store: v4fresh, finish: {}, startStep: 5), NSSize(width: 800, height: OnboardingView.height), "light-v4-03-alerts", light: true)
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
