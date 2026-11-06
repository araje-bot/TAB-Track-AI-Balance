import SwiftUI
import AppKit

/// The menu bar popover. No background of its own, so the system popover
/// material shows through (Liquid Glass on macOS 26 and later).
@MainActor
struct PopoverView: View {
    @ObservedObject var store: Store
    var openSettings: () -> Void
    var openAddMore: () -> Void
    @State private var detailID: String? = nil
    /// The detail screen's own height, measured, so the popover can glide to it.
    @State private var detailHeight: CGFloat = 420
    @State private var feedback = false

    /// Grows with the number of apps instead of always being tall.
    private var height: CGFloat {
        if store.connected.isEmpty { return 300 }
        let rows = CGFloat((max(store.tabApps.count, 1) + 2) / 3)
        // The status line's text shares its row with a small check button, so long lines wrap.
        let alertLine: CGFloat = store.summary.isAlert ? (store.summary.text.count > 36 ? 72 : 52) : 0
        return min(494, 190 + alertLine + rows * 118)
    }

    /// Opening an app pushes its detail in from the right and Back slides it out again, the
    /// standard macOS navigation motion, on the same quick smooth curve as the rest of TUM (AK).
    /// The popover resizes on that curve too.
    private func open(_ id: String?) {
        withAnimation(Motion.morph) { detailID = id }
    }

    var body: some View {
        ZStack {
            if feedback {
                FeedbackPage(back: { withAnimation(Motion.morph) { feedback = false } })
                    .background(GeometryReader { g in
                        Color.clear.preference(key: DetailHeightKey.self, value: g.size.height)
                    })
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            } else if let id = detailID, store.connected.contains(id) {
                DetailView(store: store, id: id, back: { open(nil) })
                    .background(GeometryReader { g in
                        Color.clear.preference(key: DetailHeightKey.self, value: g.size.height)
                    })
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                main
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        // The app list has a set height; one app's detail sizes to its own content.
        .onPreferenceChange(DetailHeightKey.self) { h in if h > 0 { detailHeight = h } }
        // Both screens have a real height, so the popover resizes smoothly between them.
        .frame(width: 340, height: detailID == nil && !feedback ? height : detailHeight, alignment: .top)
        .clipped()
        .animation(Motion.morph, value: height)
        .animation(Motion.morph, value: detailHeight)
        // While the popover window and the content resize at slightly different moments, keep
        // everything pinned to the top. Otherwise the content is centered in the window for a
        // moment, so the title, gear and tabs jump down and back on every tab switch (AK).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var main: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Token Utilization Monitor").font(.title3.weight(.semibold))
                Spacer()
                Button("Settings", systemImage: "gearshape", action: openSettings)
                    .iconButton()
                .help("Settings")
                .accessibilityLabel("Settings")
            }

            SegmentedChoice(selection: $store.mode, options: WatchMode.segments, label: "Usage monitoring", switchesView: true)

            if store.summary.isAlert {
                StatusLine(store: store)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if store.connected.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    TankMark(size: 40, color: .secondary)
                    Text("No apps connected yet").font(.headline)
                    Button(action: openAddMore) { ButtonText("Connect an app") }.primaryButton()
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.tabApps.isEmpty {
                // No connected app has a limit of this period.
                VStack(spacing: 6) {
                    Spacer()
                    Text("No \(store.mode.rawValue.lowercased()) limits").font(.headline)
                    Text("None of your apps has a \(store.mode.rawValue.lowercased()) limit.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    // Tiles sit at the top of their row, so the water icons always line up across a row,
                    // however many lines each one shows. More apps start a new row below (AK).
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4, alignment: .top), count: 3),
                              alignment: .center, spacing: 24) {   // roomy rows (AK)
                        ForEach(store.tabApps, id: \.self) { id in
                            Button { open(id) } label: { TileCell(store: store, id: id) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                    // Values inside the tiles change smoothly; the tiles themselves stay put.
                    .animation(Motion.standard, value: store.mode)
                    .animation(Motion.standard, value: store.tabApps)
                }
                .frame(maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                ShortcutHint()
                Spacer()
                Button(action: openAddMore) { ButtonText("Add more", systemImage: "plus") }
                    .secondaryButton()
            }

            // Feedback goes to TUM's GitHub Issues (AK).
            FeedbackLink { withAnimation(Motion.morph) { feedback = true } }
        }
        .padding(16)
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
            Text(store.name(id)).font(.callout.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            if !store.readsUsage(id) {
                Text("No data yet").font(.callout).foregroundStyle(.secondary)
                    .help("TUM can't read \(store.name(id))'s usage yet")
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

struct DetailView: View {
    @ObservedObject var store: Store
    let id: String
    var back: () -> Void

    /// One app, in a simple fixed order (AK): header, the app's circle and the tabs, then one card
    /// (finish connecting, or the limits), then Refresh and Remove. It sizes to its content, so
    /// nothing is ever squeezed. TUM never offers to open the app itself.
    var body: some View {
        let pct = store.percent(id)
        let stale = store.isStale(id)
        let needsConnect = store.needsApproval.contains(id)
        let reads = store.readsUsage(id)
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                // Icon-only, as Liquid Glass back buttons are. VoiceOver says "All apps".
                Button("All apps", systemImage: "chevron.left", action: back)
                    .iconButton()
                    .help("All apps")
                Text(store.name(id)).font(.title3.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }

            LiquidTile(pct: pct, level: stale ? .ok : store.level(pct), glyph: store.glyph(id), symbol: store.symbol(id),
                       size: 88, stale: stale && store.snapshots[id] != nil)

            if !reads {
                // Connected by choice, with nothing TUM can read yet (AK).
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No usage data yet").font(.headline)
                        Text("TUM can't read \(store.name(id))'s usage yet. Its numbers show here once it does.")
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
                        // The sync line sits apart from the numbers, below a divider (AK).
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Remove and Sync side by side at the right, the same size, with the usual 10pt between
            // buttons (AK). Remove's text is red: it's the danger action.
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button(role: .destructive) { store.disconnect(id); back() } label: {
                    ButtonText("Remove").frame(width: 96).foregroundStyle(Palette.redText)
                }
                .secondaryButton()
                .help("Remove \(store.name(id))")
                if !needsConnect && reads {
                    Button { Task { await store.syncNow(id) } } label: {
                        ButtonText(store.updating.contains(id) ? "Syncing…" : "Sync").frame(width: 96)
                    }
                    .disabled(store.updating.contains(id))
                    .secondaryButton()
                    .help("Get the latest numbers from \(store.name(id))")
                }
            }
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
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
