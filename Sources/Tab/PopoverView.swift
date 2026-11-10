import SwiftUI
import AppKit

/// The menu bar popover. No background of its own, so the system popover
/// material shows through (Liquid Glass on macOS 26 and later). It hugs its content (v4).
@MainActor
struct PopoverView: View {
    @ObservedObject var store: Store
    var openSettings: () -> Void
    /// Opens the connect window for an app (`true` adds another account).
    var openConnect: (AIApp, Bool) -> Void
    /// Snapshots and previews: open on this tip (1 to 4) or on Add app.
    var startTip = 0
    var startAdding = false
    @State private var detailID: String? = nil
    @State private var adding = false
    /// Every page's own height, measured, so the popover can glide between them.
    @State private var pageHeight: CGFloat = 300
    @State private var feedback = false
    /// First-open tips (v4): 1 to 3 point at the tabs, 4 at Add app. 0 when not showing.
    @State private var tip = 0
    @State private var tabsFrame: CGRect = .zero
    @State private var addFrame: CGRect = .zero

    /// Opening an app pushes its detail in from the right and Back slides it out again, the
    /// standard macOS navigation motion, on the same quick smooth curve as the rest of TAB (AK).
    private func open(_ id: String?) {
        withAnimation(Motion.morph) { detailID = id }
    }

    private var pushed: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity))
    }

    var body: some View {
        ZStack(alignment: .top) {
            if feedback {
                FeedbackPage(back: { withAnimation(Motion.morph) { feedback = false } })
                    .modifier(MeasureHeight())
                    .transition(pushed)
            } else if adding {
                AddAppPage(store: store, back: { withAnimation(Motion.morph) { adding = false } },
                           connect: { app in openConnect(app, false) })
                    .modifier(MeasureHeight())
                    .transition(pushed)
            } else if let id = detailID, store.connected.contains(id) {
                DetailView(store: store, id: id, back: { open(nil) },
                           addAccount: { if let a = store.app(id) { openConnect(a, true) } })
                    .modifier(MeasureHeight())
                    .transition(pushed)
            } else {
                main
                    .modifier(MeasureHeight())
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .onPreferenceChange(DetailHeightKey.self) { h in if h > 0 { pageHeight = h } }
        .frame(width: 340, height: pageHeight, alignment: .top)
        .clipped()
        .animation(Motion.morph, value: pageHeight)
        // While the popover window and the content resize at slightly different moments, keep
        // everything pinned to the top (AK).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if startAdding { adding = true }
            if startTip > 0 { tip = startTip; if startTip <= 3 { store.mode = [WatchMode.session, .weekly, .monthly][startTip - 1] } }
            startTipsIfNeeded()
        }
    }

    private func startTipsIfNeeded() {
        guard !store.tipsSeen, store.onboardingDone, !store.connected.isEmpty, tip == 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showTip(1) }
    }

    private func showTip(_ n: Int) {
        withAnimation(Motion.standard) {
            tip = n
            if n <= 3 { store.mode = [WatchMode.session, .weekly, .monthly][n - 1] }
        }
    }

    private func finishTips() {
        withAnimation(Motion.standard) { tip = 0 }
        store.tipsSeen = true
        store.mode = store.watch
    }

    /// Rows of tiles shown. Sized for the fullest tab, so switching tabs never resizes the popover
    /// (AK: a resize mid-switch made the title and tabs flicker). Past three rows, it scrolls.
    private var gridRows: Int { min(3, (max(store.mostTabApps, 1) + 2) / 3) }
    static let rowHeight: CGFloat = 104

    private var main: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Track AI Balance").font(.title3.weight(.semibold))
                Spacer()
                Button("Settings", systemImage: "gearshape", action: openSettings)
                    .iconButton()
                    .help("Settings")
                    .accessibilityLabel("Settings")
            }

            SegmentedChoice(selection: $store.mode, options: WatchMode.segments, label: "Usage monitoring", switchesView: true)
                .overlay(alignment: .leading) { tabOutline }
                .background(GeometryReader { g in Color.clear.onAppear { tabsFrame = g.frame(in: .named("popover")) }
                    .onChange(of: g.frame(in: .named("popover"))) { tabsFrame = $0 } })

            if store.summary.isAlert {
                StatusLine(store: store)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if store.connected.isEmpty {
                VStack(spacing: 10) {
                    TankMark(size: 40, color: .secondary)
                    Text("No apps connected yet").font(.headline)
                    Button { withAnimation(Motion.morph) { adding = true } } label: { ButtonText("Connect an app") }
                        .primaryButton()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if store.tabApps.isEmpty {
                // No connected app has a limit of this period.
                VStack(spacing: 6) {
                    Text("No \(store.mode.rawValue.lowercased()) limits").font(.headline)
                    Text("None of your apps has a \(store.mode.rawValue.lowercased()) limit.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: CGFloat(gridRows) * Self.rowHeight)
            } else {
                Group {
                    if store.tabApps.count > 9 {
                        ScrollView(showsIndicators: false) { grid }
                    } else {
                        grid
                    }
                }
                .frame(height: CGFloat(gridRows) * Self.rowHeight, alignment: .top)
                // A tab that lists other apps swaps the whole grid at once (AK).
                .id(store.tabApps)
                .transition(.identity)
            }

            HStack {
                Spacer()
                Button { withAnimation(Motion.morph) { adding = true } } label: { ButtonText("Add app", systemImage: "plus") }
                    .secondaryButton()
                    .overlay(tip == 4 ? Capsule(style: .circular).inset(by: -1).stroke(Color.accentColor, lineWidth: 2) : nil)
                    .background(GeometryReader { g in Color.clear.onAppear { addFrame = g.frame(in: .named("popover")) }
                        .onChange(of: g.frame(in: .named("popover"))) { addFrame = $0 } })
            }

            HStack {
                ShortcutHint(before: "", after: "for all apps")
                Spacer()
                Button("Feedback for us") { withAnimation(Motion.morph) { feedback = true } }
                    .buttonStyle(.link)
                    .font(.callout)
                    .help("Send feedback to the TAB team")
            }
        }
        .padding(16)
        .coordinateSpace(name: "popover")
        .overlay(alignment: .topLeading) { tipOverlay }
    }

    private var grid: some View {
        // Tiles sit at the top of their row, so the water icons always line up across a row (AK).
        // Only apps with a limit of this tab show; never a disabled tile (v4).
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: 3),
                  alignment: .center, spacing: 14) {
            ForEach(store.tabApps, id: \.self) { id in
                Button { open(id) } label: { TileCell(store: store, id: id) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .animation(Motion.standard, value: store.mode)
        .animation(Motion.standard, value: store.tabApps)
    }

    /// The blue outline on the tab a tip is about.
    @ViewBuilder private var tabOutline: some View {
        if (1...3).contains(tip) {
            GeometryReader { g in
                let w = g.size.width / 3
                Capsule(style: .circular).inset(by: 1).stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: w - 2, height: g.size.height - 2)
                    .offset(x: CGFloat(tip - 1) * w + 1, y: 1)
            }
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder private var tipOverlay: some View {
        if (1...3).contains(tip), tabsFrame != .zero {
            let w = tabsFrame.width / 3
            let center = tabsFrame.minX + w * (CGFloat(tip) - 0.5)
            let x = min(max(center - TipBubble.width / 2, 8), 340 - 8 - TipBubble.width)
            TipBubble(arrowX: center - x, arrowUp: true, step: tip, content: tabTip(tip),
                      next: { tip < 3 ? showTip(tip + 1) : showTip(4) })
                .offset(x: x, y: tabsFrame.maxY + 2)
                .transition(.opacity)
                .id(tip)
        } else if tip == 4, addFrame != .zero {
            let x = 340 - 8 - TipBubble.width
            TipBubble(arrowX: addFrame.midX - x, arrowUp: false, step: 4, content: .init(
                title: "Use AI in a browser?", resets: nil, body: "Add ChatGPT and other browser apps, or a second account.", cursor: false),
                      next: finishTips)
                // The bubble's bottom sits just above Add app.
                .frame(height: max(addFrame.minY - 4, 0), alignment: .bottom)
                .offset(x: x)
                .transition(.opacity)
        }
    }

    private func tabTip(_ n: Int) -> TipBubble.Content {
        switch n {
        case 1: return .init(title: "Session", resets: "Every 5 hours", body: "Your limit for a few hours of use.", cursor: false)
        case 2: return .init(title: "Weekly", resets: "Every 7 days", body: "Your limit for the whole week.", cursor: false)
        default: return .init(title: "Monthly", resets: "Every month", body: "Your plan's limit for the month.", cursor: true)
        }
    }
}

/// One first-open tip (v4): a compact card joined to a small arrow, the step count and Next.
struct TipBubble: View {
    struct Content {
        var title: String
        var resets: String?
        var body: String
        var cursor: Bool
    }
    static let width: CGFloat = 240
    let arrowX: CGFloat
    let arrowUp: Bool
    let step: Int
    let content: Content
    var next: () -> Void
    private let arrow: CGFloat = 7

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(content.title).font(.headline)
                Spacer(minLength: 8)
                if let r = content.resets {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Resets").font(.caption).foregroundStyle(.secondary)
                        Text(r).font(.callout.weight(.semibold))
                    }
                }
            }
            Text(content.body).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if content.cursor {
                HStack(spacing: 6) {
                    AppTile(icon: BrandLogos.tile("cursor"), symbol: "cursorarrow.rays", size: 20)
                    Text("Cursor only has this one.").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(step) of 4").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button(action: next) { Text(step == 4 ? "Got it" : "Next").frame(minWidth: 52) }
                    .primaryButton()
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: Self.width, alignment: .leading)
        .padding(arrowUp ? .top : .bottom, arrow)
        .background(BubbleShape(arrowX: arrowX, arrowUp: arrowUp, arrow: arrow)
            .fill(Palette.tipFill)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tip \(step) of 4")
    }
}

/// A rounded card with a small arrow joined to its top or bottom edge.
struct BubbleShape: Shape {
    let arrowX: CGFloat
    let arrowUp: Bool
    let arrow: CGFloat
    func path(in r: CGRect) -> Path {
        let body = arrowUp ? CGRect(x: r.minX, y: r.minY + arrow, width: r.width, height: r.height - arrow)
                           : CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height - arrow)
        var p = Path(roundedRect: body, cornerRadius: 12, style: .continuous)
        let x = min(max(arrowX, 18), r.width - 18)
        var t = Path()
        if arrowUp {
            t.move(to: CGPoint(x: x - arrow - 1, y: body.minY + 0.5))
            t.addLine(to: CGPoint(x: x, y: r.minY))
            t.addLine(to: CGPoint(x: x + arrow + 1, y: body.minY + 0.5))
        } else {
            t.move(to: CGPoint(x: x - arrow - 1, y: body.maxY - 0.5))
            t.addLine(to: CGPoint(x: x, y: r.maxY))
            t.addLine(to: CGPoint(x: x + arrow + 1, y: body.maxY - 0.5))
        }
        t.closeSubpath()
        p.addPath(t)
        return p
    }
}

/// Reports a page's own height so the popover sizes to it.
private struct MeasureHeight: ViewModifier {
    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { g in Color.clear.preference(key: DetailHeightKey.self, value: g.size.height) })
    }
}

struct StatusLine: View {
    @ObservedObject var store: Store

    var body: some View {
        let s = store.summary
        // Text only, no leading icon, so the message gets the whole width (AK). The pill and the
        // water circle below already carry the color.
        HStack(spacing: 12) {
            Text(s.text).font(.body.weight(.medium)).lineLimit(3).truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let d = s.dismiss {
                // A blue check clears the line and the pill goes back to the white icon (AK). A
                // warning comes back if the app gets lower (yellow to red); a tip at the next reset.
                Button("Got it", systemImage: "checkmark") {
                    withAnimation(Motion.morph) { d == .tip ? store.markUseItSeen() : store.acknowledgeAlert() }
                }
                .iconButton(prominent: true)
                .help("Got it")
            }
        }
        .contentCard()
    }
}

struct TileCell: View {
    @ObservedObject var store: Store
    let id: String

    var body: some View {
        let pct = store.percent(id)
        let stale = store.isStale(id)
        let lvl: Level = stale ? .ok : store.level(pct)
        VStack(spacing: 5) {
            LiquidTile(pct: pct, level: lvl, glyph: store.glyph(id), symbol: store.symbol(id), size: 56, stale: stale && store.snapshots[id] != nil)
                // One circle per app; a small count shows when it has several accounts (v4).
                .overlay(alignment: .topTrailing) {
                    let n = store.accountList(id).count
                    if n > 1 { CountBadge(n: n).offset(x: 6, y: -3) }
                }
            Text(store.name(id)).font(.callout.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            if !store.readsUsage(id) {
                Text("No data yet").font(.callout).foregroundStyle(.secondary)
                    .help("TAB can't read \(store.name(id))'s usage yet")
            } else if store.needsApproval.contains(id) {
                Text("Connect").font(.callout.weight(.semibold)).foregroundStyle(.tint)
                    .help("One more click to finish connecting")
            } else if store.snapshots[id] == nil {
                if let err = store.errors[id] {
                    Text("Needs attention").font(.callout.weight(.semibold)).foregroundStyle(.secondary).help(err)
                } else {
                    ActivityRing()
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(store.visibleLimits(id)) { l in
                        LimitValue(limit: l, level: stale ? .ok : store.level(l.percentLeft))
                    }
                }
                if stale {
                    Text(store.updatedText(id)).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details")
    }
}

private struct DetailHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The small account count on an app's circle. Its ring is the popover's own color, so it
/// looks cut out of the circle.
struct CountBadge: View {
    let n: Int
    var body: some View {
        Text("\(n)")
            .font(.system(size: 10, weight: .semibold)).monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 17, minHeight: 17)
            .background(Circle().fill(Color(hex: 0x48484A)))
            .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 2).padding(-1.5))
            .accessibilityLabel("\(n) accounts")
    }
}

struct DetailView: View {
    @ObservedObject var store: Store
    let id: String
    var back: () -> Void
    var addAccount: () -> Void = {}
    @State private var dragging: String?

    /// One app, in a simple fixed order (AK): header, the app's circle and the tabs, then one card
    /// (finish connecting, or the limits), then Refresh and Remove. It sizes to its content, so
    /// nothing is ever squeezed. TAB never offers to open the app itself.
    var body: some View {
        let pct = store.percent(id)
        let stale = store.isStale(id)
        let needsConnect = store.needsApproval.contains(id)
        let reads = store.readsUsage(id)
        let many = store.accountList(id).count > 1
        VStack(spacing: many ? 14 : 16) {
            HStack(spacing: 10) {
                // Icon-only, as Liquid Glass back buttons are. VoiceOver says "All apps".
                Button("All apps", systemImage: "chevron.left", action: back)
                    .iconButton()
                    .help("All apps")
                Text(store.name(id)).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }

            if many {
                accountsView(stale: stale)
            } else {
            LiquidTile(pct: pct, level: stale ? .ok : store.level(pct), glyph: store.glyph(id), symbol: store.symbol(id),
                       size: 88, stale: stale && store.snapshots[id] != nil)

            if !reads {
                // Connected by choice, with nothing TAB can read yet (AK).
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No usage data yet").font(.headline)
                        Text("TAB can't read \(store.name(id))'s usage yet. Its numbers show here once it does.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if needsConnect {
                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Finish connecting \(store.name(id))").font(.headline)
                        Text("If macOS asks, choose Always Allow so it won't ask again.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { Task { await store.refresh(id, interactive: true) } } label: {
                            ButtonText("Connect").frame(maxWidth: .infinity)
                        }
                        .primaryButton()
                        .disabled(store.loading.contains(id))
                    }
                }
            } else {
                if store.hasOnlyOneLimit(id), let only = store.snapshots[id]?.limits.first {
                    // Apps with a single plan limit (Cursor is monthly) have no Session or Weekly
                    // to pick, so the tabs make way for a plain label that says which period it is.
                    Label(store.kindName(only) + " limit", systemImage: "calendar")
                        .font(.headline).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: ControlMetrics.round)
                } else {
                    SegmentedChoice(selection: $store.mode, options: WatchMode.segments, label: "Usage monitoring", switchesView: true)
                }
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        if let err = store.errors[id], store.snapshots[id] == nil {
                            Label(err, systemImage: "exclamationmark.circle").font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            ForEach(store.hasOnlyOneLimit(id) ? (store.snapshots[id]?.limits ?? []) : store.visibleLimits(id)) { l in
                                limitRow(l, stale: stale)
                            }
                        }
                        // The sync line sits apart from the numbers, below a divider (AK), and only
                        // shows when the numbers are old or a check failed. TAB syncs by itself.
                        if store.showsSyncLine(id) {
                        Divider()
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary).frame(width: 16)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(store.updatedText(id)).font(.callout).foregroundStyle(.secondary)
                                // Why the last Sync didn't bring new numbers, so it never fails silently.
                                if let err = store.errors[id], store.snapshots[id] != nil {
                                    Text(err).font(.callout).foregroundStyle(Palette.amberText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if store.canAddAccount(id) && !needsConnect && reads { addAccountRow }
            }

            // Remove and Sync side by side at the right, the same size, with the usual 10pt between
            // buttons (AK). Remove's text is red: it's the danger action.
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(role: .destructive) { store.disconnect(id); back() } label: {
                    ButtonText("Remove").foregroundStyle(Palette.redText)
                }
                .secondaryButton()
                .help("Remove \(store.name(id))")
                if !needsConnect && reads {
                    Button { Task { await store.syncNow(id) } } label: {
                        ButtonText(store.updating.contains(id) ? "Syncing…" : "Sync")
                    }
                    .disabled(store.updating.contains(id))
                    .secondaryButton()
                    .help("Get the latest numbers from \(store.name(id))")
                }
            }
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
        // Opening an app's details checks it again if its numbers are over a minute old.
        .task(id: id) { await store.refreshIfOld(id) }
    }

    private var addAccountRow: some View {
        HStack {
            Spacer()
            Button(action: addAccount) { ButtonText("Add account", systemImage: "plus") }
                .secondaryButton()
                .help("Watch another \(store.name(id)) account")
        }
    }

    /// Several accounts (v4 screen 11): the tabs, then one row per account, top first. Drag a row
    /// to reorder; the top one is used first. Right-click for the same moves without dragging.
    @ViewBuilder private func accountsView(stale: Bool) -> some View {
        if store.hasOnlyOneLimit(id), let only = store.snapshots[id]?.limits.first {
            Label(store.kindName(only) + " limit", systemImage: "calendar")
                .font(.headline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: ControlMetrics.round)
        } else {
            SegmentedChoice(selection: $store.mode, options: WatchMode.segments, label: "Usage monitoring", switchesView: true)
        }
        let list = store.accountList(id)
        VStack(spacing: 8) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                AccountRow(store: store, appID: id, account: a, stale: stale)
                    .opacity(dragging == a.id ? 0.4 : 1)
                    .onDrag {
                        dragging = a.id
                        return NSItemProvider(object: a.id as NSString)
                    }
                    .onDrop(of: [.text], delegate: AccountDrop(store: store, appID: id, target: a.id, dragging: $dragging))
                    .contextMenu {
                        if i > 0 { Button("Use first") { withAnimation(Motion.standard) { store.useFirst(id, account: a.id) } } }
                        Button("Remove account") { withAnimation(Motion.standard) { store.removeAccount(id, account: a.id) } }
                    }
                    .accessibilityAction(named: "Move up") { if i > 0 { store.moveAccount(id, from: i, to: i - 1) } }
                    .accessibilityAction(named: "Move down") { if i < list.count - 1 { store.moveAccount(id, from: i, to: i + 2) } }
            }
        }
        .animation(Motion.standard, value: list.map(\.id))
        addAccountRow
    }

    /// One limit: what's left, in the same color as the water circle, and when it resets at the
    /// right end of the same line (AK). The tab (or the "Monthly
    /// limit" label) already says which period this is, so the line doesn't repeat it, unless
    /// the app has no limit of this tab's period and shows its own instead.
    private func limitRow(_ l: UsageLimit, stale: Bool) -> some View {
        let showPeriod = !store.hasOnlyOneLimit(id) && !store.mode.matches(l)
        let amount = "\(l.isEstimate ? "~" : "")\(Int(l.percentLeft.rounded()))% left" + (showPeriod ? " " + store.periodPhrase(l) : "")
        let level: Level = (stale || l.isReset) ? .ok : store.level(l.percentLeft)
        // What's left on the left, when it resets on the right, on one line (AK).
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            LimitIcon(kind: l.kind, size: 14).foregroundStyle(.secondary).frame(width: 16)
            Text(l.isReset ? "Reset, checking…" : amount)
                .font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(Palette.text(level))
                .fixedSize()
            Spacer(minLength: 8)
            if let r = l.resetsAt, !l.isReset {
                Text("Resets " + Format.when(r)).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One account in an app's detail: its water circle, email, what's left and a drag handle.
struct AccountRow: View {
    @ObservedObject var store: Store
    let appID: String
    let account: Account
    var stale = false

    var body: some View {
        let pct = store.accountPercent(appID, account.id)
        let lvl: Level = stale ? .ok : store.level(pct)
        HStack(spacing: 10) {
            LiquidTile(pct: pct, level: lvl, glyph: store.glyph(appID), symbol: store.symbol(appID), size: 32)
            Text(account.email ?? "\(store.name(appID)) account")
                .font(.body).lineLimit(1).truncationMode(.tail)
                .help(account.email ?? "")
            Spacer(minLength: 8)
            if let p = pct {
                Text("\(Int(p.rounded()))%").font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Palette.text(lvl))
            } else if let e = store.accountErrors[appID]?[account.id] {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.secondary).help(e)
            } else {
                ActivityRing()
            }
            Image(systemName: "line.3.horizontal").font(.callout).foregroundStyle(.secondary)
                .help("Drag to reorder. The top account is used first.")
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Moves the dragged account to where it's held, live, like the System Settings lists.
struct AccountDrop: DropDelegate {
    let store: Store
    let appID: String
    let target: String
    @Binding var dragging: String?

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != target else { return }
        let list = store.accountList(appID)
        guard let from = list.firstIndex(where: { $0.id == d }), let to = list.firstIndex(where: { $0.id == target }) else { return }
        withAnimation(Motion.standard) { store.moveAccount(appID, from: from, to: to > from ? to + 1 : to) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { dragging = nil; return true }
}
