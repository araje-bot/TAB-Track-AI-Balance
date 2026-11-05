import SwiftUI
import AppKit

public enum TUMMain {
    @MainActor public static func main() {
        // Used by make_dmg.sh to produce the app icon file.
        let args = CommandLine.arguments
        // Build-tool flags write files, so they only work when the build scripts set TUM_BUILD_TOOLS=1
        // (security review L12). `--self-test` writes nothing and always works.
        let buildTools = ProcessInfo.processInfo.environment["TUM_BUILD_TOOLS"] == "1"
        if buildTools, let i = args.firstIndex(of: "--export-icon"), i + 1 < args.count {
            if let img = AppLogo.iconImage(),
               let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                do { try png.write(to: URL(fileURLWithPath: args[i + 1])); exit(0) } catch { exit(1) }
            }
            exit(1)
        }
        if args.contains("--self-test") { exit(SelfTest.run() ? 0 : 1) }
        if buildTools, let i = args.firstIndex(of: "--snapshots"), i + 1 < args.count { SelfTest.snapshots(to: args[i + 1]); exit(0) }

        // TUM's windows never use tabs. This also stops macOS from trying to index window tabs,
        // which logs "missing main bundle identifier" when Xcode runs the bare debug executable.
        NSWindow.allowsAutomaticWindowTabbing = false

        // Only one TUM at a time. If one is already running, ask it to show itself.
        // (Debug builds do the opposite below: the newest copy wins.)
        #if !DEBUG
        if let bid = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                Diagnostics.logNow("another TUM is already running: asking it to show itself, this copy quits")
                DistributedNotificationCenter.default().postNotificationName(AppDelegate.showNotice, object: nil, userInfo: nil, deliverImmediately: true)
                exit(0)
            }
        }
        #endif

        #if DEBUG
        // Debug builds (Xcode ⌘R or dev.sh): quit every other debug copy, so only one TUM Dev
        // icon is in the menu bar.
        // Only other debug copies: "TUM Dev" from dev.sh, or a bare Xcode build (LaunchServices
        // doesn't know its bundle id). The real TUM from the DMG is never touched (AK).
        let me = ProcessInfo.processInfo.processIdentifier
        NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != me && $0.executableURL?.lastPathComponent == "TUM"
                      && $0.bundleIdentifier != "edu.umd.inst474.tum" }
            .forEach { kill($0.processIdentifier, SIGKILL) }
        #endif

        // Record crashes so they show up in Copy diagnostics. The reason is cut short, since it
        // can hold names or paths (security review).
        NSSetUncaughtExceptionHandler { e in
            Diagnostics.logNow("crash: \(e.name.rawValue) \((e.reason ?? "").prefix(200))")
        }
        LaunchGuard.begin()

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // NSApplication holds its delegate weakly. Keep it alive for the whole run,
        // otherwise release builds free it before launch and nothing appears.
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class WindowHost: NSObject, NSWindowDelegate {
    let window: NSWindow
    var onClose: (() -> Void)?

    /// `title` shows in the window's title bar, as in standard macOS windows. Without one
    /// the title bar stays clear and the content runs under it (onboarding).
    init<V: View>(size: NSSize, title: String? = nil, subtitle: String? = nil, root: V) {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        // Follows the person's Light or Dark Mode setting, as the HIG asks.
        if let title = title {
            window.title = title
            window.subtitle = subtitle ?? ""
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
        } else {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        if #available(macOS 26.0, *) {
            // An empty toolbar gives the window the larger, rounder Liquid Glass corners.
            window.toolbar = NSToolbar(identifier: "tum.window")
            window.toolbarStyle = .unified
        }
        window.contentView = NSHostingView(rootView: root)
        // Adding a toolbar can grow the window. Put it back to the intended size so the
        // content (and its bottom buttons) fills the window exactly.
        window.setContentSize(size)
        window.contentMinSize = size
        window.contentMaxSize = size
        window.center()
        window.delegate = self
    }

    /// Brings the window in front of other apps. Menu bar apps aren't active by
    /// default, so newer macOS can otherwise open the window behind everything.
    func show() {
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let showNotice = Notification.Name("edu.umd.inst474.tum.show")
    let store = Store.shared
    private var status: StatusItemController!
    private var quick: QuickPanelController!
    private let shortcut = GlanceShortcut()      // ⌥ T by default, opens the quick view
    private var pressedAt = Date.distantPast
    private var autoHide: DispatchWorkItem?
    private let activity = ActivityWatcher()
    private var onboarding: WindowHost?
    private var settings: WindowHost?
    private var timers: [Timer] = []
    private var lastFrontURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let logo = AppLogo.image() { NSApp.applicationIconImage = logo }
        SQLiteRead.sweepLeftovers()
        store.scan()

        status = StatusItemController(store: store,
                                      openSettings: { [weak self] in self?.showSettings() },
                                      openAddMore: { [weak self] in self?.showSettings() },
                                      showWelcome: { [weak self] in self?.showOnboarding() })
        #if DEBUG
        status.dev = DevHooks(onboarding: { [weak self] in self?.showOnboarding(step: $0) },
                              connect: { [weak self] in self?.showOnboarding(connecting: $0) },
                              quickView: { [weak self] in self?.showQuick(for: 5) })
        #endif
        setUpMainMenu()
        store.onDockSettingChange = { [weak self] in self?.updateDock() }
        updateDock()
        // When a TUM window closes, leave the Dock unless the person wants TUM there.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.updateDock() }
        }
        quick = QuickPanelController(store: store)
        shortcut.onPress = { [weak self] in Task { @MainActor in self?.shortcutPressed() } }
        shortcut.onRelease = { [weak self] in Task { @MainActor in self?.shortcutReleased() } }
        let applyShortcut = { [weak self] in
            guard let self = self else { return }
            if let c = self.shortcut.start(preferred: self.store.shortcutChoice) { self.store.activeShortcut = c }
        }
        store.onShortcutChange = { DispatchQueue.main.async { applyShortcut() } }
        applyShortcut()

        // Check an app right after it is used: its files change, or you switch away from it.
        activity.onActivity = { [weak self] id, file in
            Task { @MainActor in self?.store.activity(id, file: file) }
        }
        if !LaunchGuard.safeMode { activity.start() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.store.activity(bundleURL: self.lastFrontURL)
                self.lastFrontURL = NSWorkspace.shared.frontmostApplication?.bundleURL
                let ownWindowOpen = [self.onboarding, self.settings].contains { $0?.window.isVisible == true }
                if !ownWindowOpen, let id = self.store.connectedID(for: self.lastFrontURL), self.store.shouldHeadsUp(id) {
                    self.showQuick(for: 3.5)
                }
            }
        }
        lastFrontURL = NSWorkspace.shared.frontmostApplication?.bundleURL

        // Fallback: refresh every 5 minutes, and nudge views every minute so "updated" times and staleness stay honest.
        timers.append(Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if !LaunchGuard.safeMode { self?.activity.start() }   // picks up tools installed since launch
                await self?.store.refreshAll()
            }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let s = self?.store else { return }
                s.tick = Date()
                // A reset time passed: fetch right away instead of showing old numbers.
                for id in s.connected where (s.snapshots[id]?.limits.contains { $0.isReset } ?? false) {
                    await s.refresh(id)
                }
            }
        })
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.store.refreshAll() }
        }

        // Opening TUM again (Finder, Spotlight, a second copy) always shows something.
        DistributedNotificationCenter.default().addObserver(forName: Self.showNotice, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showSomething() }
        }

        if store.onboardingDone {
            Task { await store.refreshAll() }
            // If macOS hid the menu bar icon, say so instead of looking like nothing opened.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.ensureMenuBarIcon(openSettingsIfHidden: true) }
        } else {
            showOnboarding()
        }
        // Still running after a few seconds: this launch worked.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { LaunchGuard.succeeded() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSomething()
        return true
    }

    /// A normal quit, however quick, is not a failed launch.
    func applicationWillTerminate(_ notification: Notification) { LaunchGuard.succeeded() }

    /// Shows the most useful thing: onboarding, the popover, or Settings when the icon is hidden.
    func showSomething() {
        if !store.onboardingDone { showOnboarding(); return }
        ensureMenuBarIcon(openSettingsIfHidden: false) { [weak self] _ in self?.status.open() }
    }

    /// Makes sure the menu bar icon can be seen. If macOS hid it, moves it to the far
    /// right and checks again. Calls back with true when it's visible.
    private func ensureMenuBarIcon(openSettingsIfHidden: Bool, then: ((Bool) -> Void)? = nil) {
        if status.isVisibleOnScreen {
            store.menuBarHidden = false
            then?(true)
            return
        }
        status.moveToFarRight()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let visible = self.status.isVisibleOnScreen
            self.store.menuBarHidden = !visible
            if !visible {
                Diagnostics.log("menu bar icon is hidden even at the far right")
                if openSettingsIfHidden { self.showSettings() }
            }
            then?(visible)
        }
    }

    // MARK: Quick view

    /// Tap the shortcut (⌥ T by default) to show it for a few seconds, or hold it to peek and let go to hide.
    private func shortcutPressed() {
        if quick.isVisible { hideQuick(); return }
        pressedAt = Date()
        showQuick(for: nil)
    }

    private func shortcutReleased() {
        if -pressedAt.timeIntervalSinceNow > 0.5 { hideQuick() } else { showQuick(for: 5) }
    }

    private func showQuick(for seconds: Double?) {
        autoHide?.cancel()
        quick.show()
        guard let s = seconds else { return }
        let w = DispatchWorkItem { [weak self] in self?.hideQuick() }
        autoHide = w
        DispatchQueue.main.asyncAfter(deadline: .now() + s, execute: w)
    }

    private func hideQuick() {
        autoHide?.cancel()
        quick.hide()
    }

    // MARK: Dock and menus

    /// In the Dock (with a TUM menu and ⌘Q) while a TUM window is open, or always if chosen in Settings.
    func updateDock() {
        let windowOpen = [onboarding, settings].contains { $0?.window.isVisible == true }
        let want: NSApplication.ActivationPolicy = (store.alwaysInDock || windowOpen) ? .regular : .accessory
        if NSApp.activationPolicy() != want { NSApp.setActivationPolicy(want) }
    }

    private func setUpMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "TUM")
        appMenu.addItem(withTitle: "About TUM", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let s = appMenu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        s.target = self
        let w = appMenu.addItem(withTitle: "Show welcome screens", action: #selector(menuWelcome), keyEquivalent: "")
        w.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide TUM", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit TUM", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let winItem = NSMenuItem()
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        winItem.submenu = win
        main.addItem(winItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }

    @objc private func menuSettings() { showSettings() }
    @objc private func menuWelcome() { showOnboarding() }

    /// Clicking the Dock icon shows TUM, like any other app.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        let s = m.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: "")
        s.target = self
        return m
    }

    /// `step` or `connecting` (Developer menu) rebuilds the window at that step.
    func showOnboarding(step: Int? = nil, connecting: AIApp? = nil) {
        Diagnostics.log("showing onboarding")
        if (step != nil || connecting != nil), let old = onboarding {
            old.onClose = nil
            old.window.close()
            onboarding = nil
        }
        if onboarding == nil {
            let host = WindowHost(size: NSSize(width: 800, height: OnboardingView.height),
                                  root: OnboardingView(store: store, finish: { [weak self] in
                                      self?.onboarding?.window.close()
                                      Task { @MainActor in await self?.store.refreshAll() }
                                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                          self?.ensureMenuBarIcon(openSettingsIfHidden: false) { visible in
                                              if visible { self?.status.showIntro() } else { self?.status.open() }
                                          }
                                      }
                                  }, startStep: step ?? 1, connecting: connecting))
            host.onClose = { [weak self] in
                self?.store.onboardingDone = true
            }
            onboarding = host
        }
        updateDockBeforeShowing()
        onboarding?.show()
    }

    private func updateDockBeforeShowing() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    func showSettings() {
        if settings == nil {
            settings = WindowHost(size: NSSize(width: 580, height: 660), title: "Advanced settings", subtitle: "Manage your apps, alerts and shortcut",
                                  root: SettingsView(store: store, showWelcome: { [weak self] in
                                      self?.settings?.window.close()
                                      self?.showOnboarding()
                                  }))
        }
        updateDockBeforeShowing()
        settings?.show()
    }
}

/// Notices when the previous launch didn't get going (crashed early), so TUM
/// starts in a safe mode next time instead of failing again.
enum LaunchGuard {
    private static let key = "launchInProgress"
    private(set) static var safeMode = false

    static func begin() {
        let d = UserDefaults.standard
        if d.bool(forKey: key) {
            safeMode = true
            Diagnostics.logNow("previous launch did not finish; starting in safe mode")
        }
        d.set(true, forKey: key)
    }

    static func succeeded() {
        UserDefaults.standard.set(false, forKey: key)
    }
}
