#if DEBUG
import SwiftUI
import AppKit

// Debug builds only (Xcode ⌘R and dev.sh). Release builds and the DMG never include this file's code.
//
// 1. A Developer section in the menu bar icon's right-click menu.
// 2. Sample data for the Xcode previews in Previews.swift.

/// Developer menu actions that need AppDelegate's windows.
@MainActor
struct DevHooks {
    var onboarding: (Int) -> Void
    var connect: (AIApp) -> Void
    var quickView: () -> Void
}

/// Fake menu bar states.
enum DevFake {
    case allGood, low, almostOut, useIt

    /// % left for the app that drives the pill.
    var pct: Double {
        switch self {
        case .allGood: return 80
        case .low: return 24
        case .almostOut: return 8
        case .useIt: return 85
        }
    }
}

extension Store {
    /// Shows a fake state in the real app. The first connected app (or the demo app) drives the pill,
    /// the others stay healthy. Refreshing is paused until `devUseRealData()`.
    func devFake(_ fake: DevFake) {
        if connected.isEmpty {
            let id = demoID
            devAddedID = id
            connected = [id]
        }
        devFrozen = true
        guard let main = connected.first else { return }
        // Yellow must be under the person's own "Turn yellow at" (20% would not turn yellow at 24%),
        // and every limit of the main app gets the same value, so the pill shows whichever
        // tab (Session, Weekly, Both) is picked (AK: the yellow preview did nothing).
        let mainPct: Double = fake == .low ? max(redAt + 2, threshold - 4) : fake.pct
        for id in connected {
            let limits: [UsageLimit]
            if id == main && fake == .useIt {
                limits = Self.useItLimits(id)
            } else if id == main {
                limits = Self.sampleLimits(id, pct: mainPct).map { var l = $0; l.percentLeft = mainPct; return l }
            } else {
                limits = Self.sampleLimits(id, pct: 72)
            }
            snapshots[id] = ProviderSnapshot(limits: limits, fetchedAt: Date())
            errors[id] = nil
        }
        // Clear "Got it" and the "already alerted" memory, so the preview always takes the pill.
        clearAcknowledged()
        updateAlerts()
        if fake == .useIt { resetUseItSeen() }
        needsApproval = []
        Diagnostics.log("developer: fake state \(fake)")
    }

    /// Ends a fake state and reads real numbers again.
    func devUseRealData() {
        devFrozen = false
        if let id = devAddedID { connected.removeAll { $0 == id }; devAddedID = nil }
        snapshots = [:]
        errors = [:]
        Task { await refreshAll() }
    }

}

extension StatusItemController {
    /// Yellow, red and green pill previews, right at the top of the right-click menu.
    func addPillPreviews(to m: NSMenu) {
        m.addItem(sectionTitle("Preview the pill"))
        m.addItem(devItem("Yellow: getting low", #selector(devYellow)))
        m.addItem(devItem("Red: almost out (8%)", #selector(devRed)))
        m.addItem(devItem("Green: not utilized enough", #selector(devGreen)))
        let real = devItem("Back to real data", #selector(devReal))
        real.isEnabled = store.devFrozen
        m.addItem(real)
    }

    /// The Developer submenu in the right-click menu.
    func developerMenuItem() -> NSMenuItem {
        let root = NSMenuItem(title: "Developer", action: nil, keyEquivalent: "")
        let m = NSMenu(title: "Developer")

        m.addItem(sectionTitle("Screens"))
        let names = ["Welcome", "How TAB works", "Apps", "Nudges"]
        for (i, n) in names.enumerated() {
            let item = devItem("Onboarding \(i + 1): \(n)", #selector(devOnboarding(_:)))
            item.tag = i + 1
            m.addItem(item)
        }
        m.addItem(devItem("Connect sheet", #selector(devConnect)))
        m.addItem(devItem("Intro callout", #selector(devIntro)))
        m.addItem(devItem("Quick view", #selector(devQuick)))

        m.addItem(.separator())
        m.addItem(sectionTitle("Fake states"))
        m.addItem(devItem("White icon (all good)", #selector(devWhite)))
        m.addItem(devItem("Yellow pill (24%)", #selector(devYellow)))
        m.addItem(devItem("Red pill (8%)", #selector(devRed)))
        m.addItem(devItem("Green pill (not utilized enough)", #selector(devGreen)))
        let real = devItem("Use real data", #selector(devReal))
        real.isEnabled = store.devFrozen
        m.addItem(real)

        m.addItem(.separator())
        m.addItem(devItem("Start fresh…", #selector(devStartFresh)))

        m.autoenablesItems = false
        root.submenu = m
        return root
    }

    private func sectionTitle(_ t: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: t) }
        let i = NSMenuItem(title: t, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func devItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        return i
    }

    @objc private func devOnboarding(_ sender: NSMenuItem) { dev?.onboarding(sender.tag) }

    @objc private func devConnect() {
        let id = store.detected.first(where: { $0.supported && $0.canConnect })?.id ?? store.demoID
        dev?.connect(store.sampleApp(id))
    }

    @objc private func devIntro() { showIntro() }
    @objc private func devQuick() { dev?.quickView() }
    @objc private func devWhite() { store.devFake(.allGood) }
    @objc private func devYellow() { store.devFake(.low) }
    @objc private func devRed() { store.devFake(.almostOut) }
    @objc private func devGreen() { store.devFake(.useIt) }
    @objc private func devReal() { store.devUseRealData() }

    /// Same as `killall TAB; defaults delete edu.umd.inst474.tab`, then opens TAB again.
    /// Sign-ins in other apps and the Keychain are not touched.
    @objc private func devStartFresh() {
        let a = NSAlert()
        a.messageText = "Start fresh?"
        a.informativeText = "This clears all TAB settings and connected apps, then reopens TAB like a new install."
        a.addButton(withTitle: "Start fresh")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }

        let domain = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        // Keep the two rename markers, so a fresh start doesn't bring TUM Dev's settings back
        // or reuse an old TUM sign-in that was already moved or removed.
        let retired = UserDefaults.standard.stringArray(forKey: Keychain.retiredKey)
        UserDefaults.standard.removePersistentDomain(forName: domain)
        UserDefaults.standard.set(true, forKey: Rename.movedKey)
        if let r = retired { UserDefaults.standard.set(r, forKey: Keychain.retiredKey) }
        UserDefaults.standard.synchronize()
        Diagnostics.logNow("developer: start fresh")
        // Reopen after this copy has quit, so the single-copy check doesn't stop it.
        let path = Bundle.main.bundlePath
        let cmd = path.hasSuffix(".app")
            ? "sleep 0.6; /usr/bin/open -n \"\(path)\""
            : "sleep 0.6; \"\(Bundle.main.executablePath ?? "")\" >/dev/null 2>&1 &"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", cmd]
        try? p.run()
        exit(0)
    }
}
#endif
