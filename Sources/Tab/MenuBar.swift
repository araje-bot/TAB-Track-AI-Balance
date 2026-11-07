import SwiftUI
import AppKit
import Combine
import Carbon.HIToolbox

/// Hosting view that lets clicks fall through to the status bar button.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct MenuBarLabel: View {
    @ObservedObject var store: Store

    /// Fills the whole menu bar slot and sits at its right edge, so the pill grows leftward
    /// smoothly while macOS widens the slot.
    var fill = false

    var body: some View {
        let u = store.pillState
        MorphMark(level: u?.level ?? .ok, pct: u?.pct,
                  glyph: u.flatMap { store.glyph($0.id) }, symbol: u.map { store.symbol($0.id) } ?? "sparkle")
            .fixedSize()
            #if DEBUG
            // TAB Dev wears a small orange dot, so it can't be mistaken for the real TAB (AK).
            .overlay(alignment: .topTrailing) {
                Circle().fill(Color.orange).frame(width: 5, height: 5).offset(x: 2, y: -1)
            }
            #endif
            .frame(maxWidth: fill ? .infinity : nil, maxHeight: fill ? .infinity : nil, alignment: .trailing)
    }
}

@MainActor
final class StatusItemController: NSObject {
    private(set) var item: NSStatusItem
    let popover = NSPopover()

    /// macOS remembers each menu bar item's spot under this name. Position 0 is the
    /// far right, next to Control Center, where a full menu bar can't hide it.
    private static let autosaveName = "TAB"
    private static let positionKey = "NSStatusItem Preferred Position TAB"

    private static func makeItem() -> NSStatusItem {
        let d = UserDefaults.standard
        if d.object(forKey: positionKey) == nil { d.set(0, forKey: positionKey) }
        let i = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        i.autosaveName = autosaveName
        i.behavior = []   // can't be removed from the menu bar by dragging
        return i
    }
    private var host: PassthroughHostingView<MenuBarLabel>!
    private var bag = Set<AnyCancellable>()
    let store: Store
    private var floating: FloatingPanel?
    private var introPopover: NSPopover?

    private let openSettings: () -> Void
    private let showWelcome: () -> Void
    #if DEBUG
    /// Developer menu actions that live in AppDelegate (see Developer.swift).
    var dev: DevHooks?
    #endif

    init(store: Store, openSettings: @escaping () -> Void, openAddMore: @escaping () -> Void, showWelcome: @escaping () -> Void) {
        self.store = store
        self.openSettings = openSettings
        self.showWelcome = showWelcome
        self.item = Self.makeItem()
        super.init()
        host = PassthroughHostingView(rootView: MenuBarLabel(store: store, fill: true))
        // The label always fills the button (minus its margins), so the icon or pill can never sit
        // in a slot that's wider than it, even for a moment.
        host.autoresizingMask = [.width, .height]
        configureButton()
        popover.behavior = .transient
        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.anchorPanel.orderOut(nil) }
        }
        popover.animates = true
        let hosting = NSHostingController(rootView: PopoverView(
            store: store,
            openSettings: { [weak self] in self?.popover.performClose(nil); openSettings() },
            openAddMore: { [weak self] in self?.popover.performClose(nil); openAddMore() }))
        hosting.sizingOptions = .preferredContentSize   // the popover follows the content's height
        popover.contentViewController = hosting
        layout()
        store.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.layout() }
            .store(in: &bag)
        // Pill turns (AK): when several apps want the pill, it moves on every minute. Never while
        // the popover or hover tip is open, so nothing changes under the person's eyes.
        let turns = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.store.holdPill = self.popover.isShown || self.tip.isShown
                self.store.rotatePill()
            }
        }
        RunLoop.main.add(turns, forMode: .common)
        turnTimer = turns
    }

    private var turnTimer: Timer?

    private func configureButton() {
        guard let b = item.button else { return }
        host.removeFromSuperview()
        b.addSubview(host)
        b.target = self
        b.action = #selector(toggle(_:))
        b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        b.setAccessibilityLabel("Track AI Balance")
        // Quick look on hover, in a glass tip (the system tooltip is slow and not Liquid Glass).
        b.toolTip = nil
        hover.onEnter = { [weak self] in self?.hoverEntered() }
        hover.onExit = { [weak self] in self?.hoverExited() }
        b.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                         owner: hover, userInfo: nil))
    }

    private let hover = HoverTracker()
    private lazy var tip = HoverTipController(store: store)
    private var hoverWork: DispatchWorkItem?

    private func hoverEntered() {
        hoverWork?.cancel()
        guard !popover.isShown else { return }
        let w = DispatchWorkItem { [weak self] in
            guard let self = self, !self.popover.isShown, let f = self.iconFrame else { return }
            self.tip.show(below: f)
        }
        hoverWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
    }

    private func hoverExited() {
        hoverWork?.cancel()
        tip.hide()
    }

    /// Puts the icon back at the far right, for example after macOS hid it behind the notch.
    func moveToFarRight() {
        if popover.isShown { popover.performClose(nil) }
        NSStatusBar.system.removeStatusItem(item)
        UserDefaults.standard.set(0, forKey: Self.positionKey)
        item = Self.makeItem()
        configureButton()
        layout()
        Diagnostics.log("menu bar icon moved to the far right")
    }

    private var widthTimer: Timer?
    #if DEBUG
    private var lastLoggedLength: CGFloat = -1
    #endif

    /// Resizes the menu bar slot when the icon turns into a pill or back. The width glides on the
    /// same quick 0.35s curve as the icon's morph, so the menu bar icons next to TAB slide smoothly
    /// instead of jumping (AK). Reduce Motion changes it in one step.
    func layout() {
        guard item.button != nil else { return }
        // Width from the state itself, not from a view that may not have redrawn yet,
        // so the pill is never clipped.
        let target = Self.slotWidth(urgentPct: store.pillState?.pct)
        animateLength(to: target, duration: Motion.morphDuration)
    }

    private func animateLength(to target: CGFloat, duration: TimeInterval) {
        widthTimer?.invalidate()
        let start = item.length
        if abs(start - target) < 0.5 || start <= 0 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            item.length = target
            placeHost()
            return
        }
        let began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            // The timer runs on the main run loop, so this is on the main thread.
            MainActor.assumeIsolated {
                guard let self = self else { t.invalidate(); return }
                let p = min(1, (CACurrentMediaTime() - began) / duration)
                // Ease in and out: starts gently, moves quickly, settles gently, so the icons
                // next to TAB glide instead of jumping either way.
                let eased = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
                self.item.length = (start + (target - start) * CGFloat(eased)).rounded()
                self.placeHost()
                if p >= 1 { self.item.length = target; self.placeHost(); t.invalidate() }
            }
        }
        // Common modes, so it keeps running while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        widthTimer = timer
    }

    /// Pill: 2 + dot 16 + gap 4 + number + 8, plus 10 for the slot's margins and 2 to spare.
    static func slotWidth(urgentPct: Double?) -> CGFloat {
        guard let p = urgentPct else { return 26 }
        let text = "\(Int(p.rounded()))%" as NSString
        let w = text.size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)]).width
        return ceil(2 + 16 + 4 + w + 8) + 12
    }

    /// Where the popover points: the icon's spot at the right end of the slot (AK). TAB sits at the
    /// far right and the pill grows leftward, so this spot never moves on screen. The popover
    /// stays put when the icon turns into a pill or back, for example when switching tabs.
    func anchor(in b: NSView) -> NSRect {
        let w = StatusItemController.slotWidth(urgentPct: nil)
        return NSRect(x: max(b.bounds.maxX - w, 0), y: 0, width: min(w, b.bounds.width), height: b.bounds.height)
    }

    /// Popovers point at a tiny invisible window placed over the icon's spot, not at the menu bar
    /// button. A popover attached to the button follows it while the slot resizes (it moved when
    /// the icon turned into a pill, AK); this window never moves while the popover is open.
    private lazy var anchorPanel: NSPanel = {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView = NSView()
        return p
    }()
    var anchorView: NSView { anchorPanel.contentView! }

    /// Moves the anchor window over the icon's spot (the slot's right end) and shows it.
    private func placeAnchor(in b: NSView) {
        guard let w = b.window else { return }
        let r = w.convertToScreen(b.convert(anchor(in: b), to: nil))
        anchorPanel.setFrame(r, display: false)
        anchorPanel.orderFront(nil)
    }

    private func placeHost() {
        guard let b = item.button else { return }
        let h = b.bounds.height > 0 ? b.bounds.height : 22
        host.frame = NSRect(x: 5, y: 0, width: max(item.length - 10, 12), height: h)
        #if DEBUG
        if item.length != lastLoggedLength {
            lastLoggedLength = item.length
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, let b = self.item.button, self.item.length == self.lastLoggedLength else { return }
                Diagnostics.log("menu bar slot \(Int(self.item.length)) pt, button \(Int(b.frame.width)) pt, label \(Int(self.host.frame.width)) pt, window \(Int(b.window?.frame.width ?? 0)) pt")
            }
        }
        #endif
    }

    /// False when macOS hid the icon, for example behind the camera notch on a full menu bar.
    var isVisibleOnScreen: Bool {
        guard item.isVisible, let w = item.button?.window, let screen = w.screen ?? NSScreen.main else { return false }
        let f = w.frame
        guard f.width > 0, screen.frame.intersects(f) else { return false }
        if let right = screen.auxiliaryTopRightArea {
            // On notched screens, items left of the notch's right edge are hidden.
            if f.minX < screen.frame.maxX - right.width - 1 { return false }
        }
        return true
    }

    /// Opens TAB. Anchored to the menu bar icon when it can be seen; otherwise a floating
    /// panel at the top right, so it never opens off screen.
    func open() {
        store.showTipTab()
        if isVisibleOnScreen {
            if !popover.isShown { toggle(nil) }
            return
        }
        if floating == nil {
            floating = FloatingPanel(root: PopoverView(store: store,
                                                       openSettings: { [weak self] in self?.floating?.close(); self?.openSettings() },
                                                       openAddMore: { [weak self] in self?.floating?.close(); self?.openSettings() })
                .glassPanel())
        }
        floating?.showTopRight()
    }

    /// The icon's place on screen, for pointing at it.
    var iconFrame: NSRect? {
        guard isVisibleOnScreen, let b = item.button, let w = b.window else { return nil }
        return w.convertToScreen(b.convert(b.bounds, to: nil))
    }

    /// After onboarding: a short note pointing at the menu bar icon (as in the prototype).
    /// It's a native popover on the icon, so the arrow and the glass come from macOS itself.
    func showIntro() {
        guard isVisibleOnScreen, let b = item.button else { open(); return }
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        let hosting = NSHostingController(rootView: IntroCallout(dismiss: { [weak p] in p?.performClose(nil) }))
        hosting.sizingOptions = .preferredContentSize
        p.contentViewController = hosting
        introPopover = p
        placeAnchor(in: b)
        p.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
    }

    /// Right-click (or Control-click) menu on the menu bar icon.
    private func showMenu() {
        guard let b = item.button else { return }
        let m = NSMenu()
        #if DEBUG
        // Quick previews of the three pills, to check the transitions with real apps (AK).
        // They swap in sample numbers and pause updates until "Back to real data".
        addPillPreviews(to: m)
        m.addItem(.separator())
        #endif
        m.addItem(menuItem("Open TAB", #selector(menuOpen)))
        m.addItem(menuItem("Settings…", #selector(menuSettings), key: ","))
        m.addItem(menuItem("Show welcome screens", #selector(menuWelcome)))
        #if DEBUG
        m.addItem(.separator())
        m.addItem(developerMenuItem())
        #endif
        m.addItem(.separator())
        m.addItem(menuItem("Quit TAB", #selector(menuQuit), key: "q"))
        m.autoenablesItems = false
        let y: CGFloat = b.isFlipped ? b.bounds.height + 5 : -5
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: b)
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func menuOpen() { open() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuWelcome() { showWelcome() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    @objc func toggle(_ sender: Any?) {
        hoverWork?.cancel()
        tip.hide()
        if let e = NSApp.currentEvent, e.type == .rightMouseUp || e.modifierFlags.contains(.control) {
            if popover.isShown { popover.performClose(nil) }
            showMenu()
            return
        }
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let b = item.button else { return }
        Task { await store.refreshIfOld() }
        // Tabs always start on the default view from "Usage monitoring" (AK); a pill can still
        // open the tab it is about.
        store.mode = store.watch
        store.holdPill = true
        store.showTipTab()
        placeAnchor(in: b)
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}

/// Quick view shown at the top of the screen with the shortcut.
struct QuickView: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 12) {
            if store.connected.isEmpty {
                Text("No apps connected in TAB yet").font(.headline).padding(20)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(store.displayOrder, id: \.self) { id in
                        let pct = store.percent(id)
                        let stale = store.isStale(id)
                        VStack(spacing: 6) {
                            LiquidTile(pct: pct, level: stale ? .ok : store.level(pct), glyph: store.glyph(id), symbol: store.symbol(id), size: 64, stale: stale && store.snapshots[id] != nil)
                            Text(store.name(id)).font(.callout.weight(.medium)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                            ForEach(store.visibleLimits(id)) { l in
                                LimitValue(limit: l, level: stale ? .ok : store.level(l.percentLeft), size: 15)
                            }
                        }
                        .frame(width: 96)
                    }
                }
                let s = store.summary
                if s.isAlert {
                HStack(spacing: 6) {
                    Image(systemName: s.symbol).foregroundStyle(s.color)
                    Text(s.text).font(.body.weight(.medium))
                }
                .padding(.horizontal, 14).padding(.vertical, 7)
                .innerCard()
                }
            }
        }
        .padding(18)
        .glassPanel()
        .fixedSize()
    }
}

@MainActor
final class QuickPanelController {
    private let panel: NSPanel
    private let host: NSHostingView<QuickView>

    init(store: Store) {
        host = NSHostingView(rootView: QuickView(store: store))
        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = host
    }

    /// Shows the panel in the middle of the screen you're on, both ways, like the ⌘TAB switcher (AK).
    func show() {
        guard let screen = NSScreen.main else { return }
        let size = host.fittingSize
        let f = screen.frame
        panel.setFrame(NSRect(x: (f.midX - size.width / 2).rounded(), y: (f.midY - size.height / 2).rounded(),
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil) }
    var isVisible: Bool { panel.isVisible }
}

/// The shortcut (⌘ T, ⌥ T or the person's own) shows the quick view from any app. It is a registered shortcut, so macOS
/// asks for no permission and TAB never sees any other key you press.
final class GlanceShortcut {
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private var installed = false

    /// Registers the picked shortcut. If another app already owns it, tries the others in order
    /// and returns the one that worked.
    @discardableResult
    func start(preferred: ShortcutChoice) -> ShortcutChoice? {
        install()
        if let h = hotKey { UnregisterEventHotKey(h); hotKey = nil }
        let order = [preferred] + ShortcutChoice.fallbacks.filter { $0 != preferred }
        for c in order {
            let (code, mods) = (Int(c.keyCode), c.modifier.carbon)
            let id = EventHotKeyID(signature: OSType(0x54414231), id: 1)   // "TAB1"
            let status = RegisterEventHotKey(UInt32(code), UInt32(mods), id, GetApplicationEventTarget(),
                                             OptionBits(kEventHotKeyExclusive), &hotKey)
            if status == noErr { return c }
            hotKey = nil
            Diagnostics.log("shortcut \(c.spoken) is taken by another app (\(status))")
        }
        return nil
    }

    /// Lets go of the shortcut while a new one is being recorded.
    func pause() {
        if let h = hotKey { UnregisterEventHotKey(h); hotKey = nil }
    }

    private func install() {
        guard !installed else { return }
        installed = true
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event = event, let userData = userData else { return noErr }
            let me = Unmanaged<GlanceShortcut>.fromOpaque(userData).takeUnretainedValue()
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { me.onPress() } else { me.onRelease() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 2, &types,
                            Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
}

/// A borderless floating panel that can take clicks and closes when you click elsewhere.
@MainActor
final class FloatingPanel: NSObject, NSWindowDelegate {
    private final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }
    private let panel: KeyPanel
    private let host: NSView

    init<V: View>(root: V) {
        let h = NSHostingView(rootView: root)
        host = h
        panel = KeyPanel(contentRect: NSRect(origin: .zero, size: h.fittingSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = h
        panel.delegate = self
    }

    func showTopRight() {
        guard let screen = NSScreen.main else { return }
        let size = host.fittingSize
        let vis = screen.visibleFrame
        present(NSRect(x: vis.maxX - size.width - 10, y: vis.maxY - size.height - 6, width: size.width, height: size.height))
    }

    /// Just below a menu bar item, centered on it, kept on screen.
    func show(below anchor: NSRect) {
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        var x = anchor.midX - size.width / 2
        if let vis = screen?.visibleFrame { x = min(max(x, vis.minX + 8), vis.maxX - size.width - 8) }
        present(NSRect(x: x, y: anchor.minY - size.height - 4, width: size.width, height: size.height))
    }

    private func present(_ frame: NSRect) {
        panel.setFrame(frame, display: true)
        if #available(macOS 14.0, *) { NSApp.activate() } else { NSApp.activate(ignoringOtherApps: true) }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel.orderOut(nil) }

    func windowDidResignKey(_ notification: Notification) { close() }
}

/// "TAB lives here": shown in a popover on the menu bar icon after onboarding.
struct IntroCallout: View {
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TankMark(size: 18, color: .primary)
                Text("TAB lives here").font(.title3.weight(.semibold)).foregroundStyle(.primary)
            }
            Text("Click it to see your usage. It turns yellow or red when an app runs low.")
                .font(TextStyle.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ShortcutHint(after: "to see it anytime")
                Spacer(minLength: 12)
                Button(action: dismiss) { ButtonText("Got it") }
                    .primaryButton()
            }
        }
        .padding(16)
        .frame(width: 340)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("TAB lives in your menu bar")
    }
}


/// Receives mouse enter/exit for the menu bar icon.
final class HoverTracker: NSResponder {
    var onEnter: () -> Void = {}
    var onExit: () -> Void = {}
    override func mouseEntered(with event: NSEvent) { onEnter() }
    override func mouseExited(with event: NSEvent) { onExit() }
}

/// Which limit a % is about: the limit's icon and name ("Session", "Weekly"), kept simple,
/// with no background (AK).
struct LimitTag: View {
    let kind: LimitKind?
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            if let k = kind { LimitIcon(kind: k, size: 11) }
            Text(text).lineLimit(1)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize()
    }
}

/// Small Liquid Glass tip under the menu bar icon: which limit each app's % is about.
struct HoverTip: View {
    @ObservedObject var store: Store
    private static let edge: CGFloat = 14
    private static let iconSize: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.connected.isEmpty {
                Text("Connect an AI app to start").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            } else {
                // A grid, so every column lines up from row to row: logo and name on the left,
                // then the limit tag and the % together on the right (AK). Tags start at one left
                // edge in their column; percentages line up on the right edge.
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    ForEach(store.tipRows) { r in
                        GridRow {
                            // The app's own logo, big enough to recognize (AK).
                            AppTile(icon: store.icon(r.id), symbol: store.symbol(r.id), size: Self.iconSize)
                            // Long names end in "…" after a point; the first word is enough (AK).
                            Text(r.name).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                                .lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: 104, alignment: .leading)
                            Spacer(minLength: 8)
                            LimitTag(kind: r.limitKind, text: r.kind)
                            Text(r.pct.map { "\(Int($0.rounded()))%" } ?? "–")
                                .font(.callout.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(Palette.text(r.level))
                                .lineLimit(1).fixedSize()   // never two lines; the tip widens instead (AK)
                                .frame(minWidth: 40, alignment: .trailing)
                                .gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        // Equal space on both sides (AK). App icons carry a built-in margin (about 10% of their
        // size), so the leading edge is trimmed by that much; the visible logo then sits as far
        // from the left edge as the % sits from the right edge.
        .padding(.leading, Self.edge - Self.iconSize * 0.1)
        // Text reads lighter than a logo, so the % gets a little extra room on the right to look
        // balanced against the icon on the left (AK).
        .padding(.trailing, Self.edge + 4)
        .padding(.vertical, 10)
        .frame(minWidth: 210, alignment: .leading)
        .glassPanel(cornerRadius: Radius.tip)
        .padding(10)   // room for the glass edge and shadow
    }
}

@MainActor
final class HoverTipController {
    private let panel: NSPanel
    private let host: NSHostingView<HoverTip>

    init(store: Store) {
        host = NSHostingView(rootView: HoverTip(store: store))
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
        panel.alphaValue = 0
    }

    func show(below icon: NSRect) {
        let size = host.fittingSize
        let screen = NSScreen.screens.first { $0.frame.intersects(icon) } ?? NSScreen.main
        let vis = screen?.visibleFrame ?? icon
        var x = icon.midX - size.width / 2
        x = min(max(x, vis.minX + 4), vis.maxX - size.width - 4)
        let y = icon.minY - size.height + 4
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.15; panel.animator().alphaValue = 1 }
    }

    var isShown: Bool { panel.isVisible && panel.alphaValue > 0 }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { c in c.duration = 0.12; panel.animator().alphaValue = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
        }
    }
}
