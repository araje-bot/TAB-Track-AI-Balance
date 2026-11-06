import SwiftUI
import Combine
import AppKit

/// Text styles for the whole app: the system text styles, in label colors.
enum TextStyle {
    static let title = Font.largeTitle.bold()        // primary
    static let subtitle = Font.title3                // secondary
    static let body = Font.body                      // primary
    static let caption = Font.callout                // secondary
    static let tertiary = Color(nsColor: .tertiaryLabelColor)
}

/// First-run setup: 4 short steps. Every step's title sits in the same place.
/// Nothing is read and no prompt can appear until the person chooses to connect an app.
struct OnboardingView: View {
    @ObservedObject var store: Store
    var finish: () -> Void
    @State private var step: Int
    @State private var connectTarget: AIApp? = nil
    private let total = 4

    /// `connecting` opens the connect sheet for that app right away (Developer menu and previews).
    init(store: Store, finish: @escaping () -> Void, startStep: Int = 1, connecting: AIApp? = nil) {
        self.store = store
        self.finish = finish
        _step = State(initialValue: connecting == nil ? startStep : 3)
        _connectTarget = State(initialValue: connecting)
    }

    private func header(_ step: Int) -> (String, String) {
        switch step {
        case 1: return ("Welcome to TUM", "Know how much AI you have left, in every app you use.")
        case 2: return ("How TUM works", "Three steps, then it stays quietly in your menu bar.")
        case 3: return ("Which AI apps do you use?", store.connected.isEmpty ? "Connect at least one to continue." : "Connect the ones you want TUM to watch.")
        default: return ("When should TUM nudge you?", "The icon turns yellow when an app runs low. Nothing pops up.")
        }
    }

    /// The onboarding window's height (App.swift uses it too).
    static let height: CGFloat = 600

    /// Next stays off on the apps step until at least one app is connected. Back always works.
    private var canGoNext: Bool { step != 3 || !store.connected.isEmpty }

    /// Pages crossfade in place, the system's standard for swapping a window's content (System
    /// Settings panes do the same). No sliding; AK found both slide versions odd. The pages share
    /// one ZStack, so old and new overlap exactly and never stack. The fade uses `Motion.page`.
    private var pageTransition: AnyTransition { .opacity }

    private func go(to next: Int) {
        withAnimation(Motion.page) { step = next }
    }

    /// One whole page: title, subtitle and the step's content.
    private func page(_ step: Int) -> some View {
        let header = header(step)
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                // The scan button sits on the title's line, centered on it (AK: it looked misaligned
                // when pinned to the top edge).
                HStack(alignment: .center) {
                    Text(header.0).font(TextStyle.title).foregroundStyle(.primary)
                    Spacer()
                    if step == 3 { FindAppsButton(store: store) }
                }
                Text(header.1).font(TextStyle.subtitle).foregroundStyle(.secondary)
            }
            .frame(height: 64, alignment: .top)
            .padding(.top, 60)

            Group {
                switch step {
                case 1: WelcomeStep()
                case 2: HowStep(store: store)
                case 3: AppsStep(store: store, connectTarget: $connectTarget)
                default: NudgesStep(store: store)
                }
            }
            // Each step's content sits in the middle of the space between the title and the
            // buttons, so nothing looks pushed down (AK).
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 40)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                page(step)
                    .id(step)
                    .transition(pageTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, -40)   // pages carry their own side padding

            HStack(spacing: 10) {
                // Page dots in label colors (macOS has no page control in SwiftUI).
                HStack(spacing: 7) {
                    ForEach(1...total, id: \.self) { i in
                        Circle().fill(i == step ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                            .frame(width: 7, height: 7)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: step)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step) of \(total)")
                Spacer()
                if step > 1 {
                    Button { go(to: step - 1) } label: { ButtonText("Back") }
                        .secondaryButton()
                }
                Button {
                    if step < total { go(to: step + 1) } else { store.onboardingDone = true; finish() }
                } label: { ButtonText(step == 1 ? "Get started" : (step == total ? "Done" : "Next")) }
                    .keyboardShortcut(.defaultAction)
                    .primaryButton()
                    .disabled(!canGoNext)
            }
            .padding(.bottom, 24)
            .padding(.top, 12)
        }
        .padding(.horizontal, 40)
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: Self.height, maxHeight: .infinity)
        .ignoresSafeArea()
        .sheet(item: $connectTarget) { app in
            ConnectSheet(store: store, app: app, done: { connectTarget = nil })
        }
        .onAppear { Task { await store.scanAnimated() } }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        HStack(alignment: .center, spacing: 40) {
            VStack(spacing: 14) {
                AppLogo(size: 120, flowing: true)
                Text("Token Utilization Monitor").font(.headline).foregroundStyle(.secondary)
            }
            .frame(width: 280)
            // Three separate cards, like the steps on "How TUM works" (AK), each with a hairline border.
            VStack(spacing: 18) {
                benefit("gauge.with.needle.fill", "See what's left at a glance",
                        "For AI apps on your Mac, not websites")
                benefit("bell.badge.fill", "Quiet until it matters",
                        "Turns yellow, then red, when an app runs low")
                benefit("lock.shield.fill", "Your info stays secure",
                        "No TUM server. Sign-ins go only to their app")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A short title with one plain line underneath (AK: a bit more descriptive).
    private func benefit(_ symbol: String, _ title: String, _ detail: String) -> some View {
        Card(padding: 20, bordered: true) {
            HStack(spacing: 12) {
                // Large filled symbols, like Apple's own welcome screens (AK: better, bigger icons).
                Image(systemName: symbol).symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
                    .font(.largeTitle).frame(width: 48)
                // Same sizes as the step text on "How TUM works": body text for the line (AK).
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// An SF Symbol in the accent color next to a line of text. Used for info rows.
struct InfoRow: View {
    let symbol: String
    let text: String
    var body: some View {
        Label {
            Text(text).foregroundStyle(.primary)
        } icon: {
            Image(systemName: symbol).symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
                .frame(width: 24)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

@MainActor
private struct HowStep: View {
    @ObservedObject var store: Store

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            card(1, "Connect the AI apps you pay for") { appsVisual }
            card(2, "TUM checks how much each app has left") {
                HStack(spacing: 10) {
                    LiquidTile(pct: 46, level: .ok, glyph: store.glyph(store.demoID), symbol: store.symbol(store.demoID), size: 48)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary)
                    Text("46%").font(.title2.bold()).foregroundStyle(.primary)
                }
            }
            card(3, "The icon notifies you when an app runs low") { IconStoryDemo(store: store) }
        }
    }

    private var appsVisual: some View {
        let ids = Array(store.detected.prefix(4).map { $0.id })
        return LazyVGrid(columns: [GridItem(.fixed(48)), GridItem(.fixed(48))], spacing: 12) {
            if ids.isEmpty {
                ForEach(["asterisk", "chevron.left.forwardslash.chevron.right", "cursorarrow.rays", "bolt.fill"], id: \.self) { s in
                    AppTile(icon: nil, symbol: s, size: 48)
                }
            } else {
                ForEach(ids, id: \.self) { id in
                    AppTile(icon: store.icon(id), symbol: store.symbol(id), size: 48)
                }
            }
        }
    }

    private func card<V: View>(_ n: Int, _ text: String, @ViewBuilder visual: () -> V) -> some View {
        // Concentric corners: the card's radius is the inner square's radius plus the padding.
        Card(padding: 10, cornerRadius: Radius.card + 10) {
            VStack(spacing: 0) {
                // The illustration sits on its own rounded square, a shade lighter than the card,
                // with the same corner as every other section (AK: one roundness everywhere).
                ZStack { visual() }
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .modifier(StepWell(cornerRadius: Radius.card))
                // The number sits beside its text, vertically centered on it, and the pair is
                // centered in the card (AK). Same 44pt slot in every card, so they all match.
                HStack(alignment: .center, spacing: 10) {
                    StepNumber(n)
                    Text(text).font(.body).foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .padding(.top, 12)
                .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// A step number: a white circle with a dark number in Dark Mode (dark with light in Light Mode),
/// so it reads as a label, not a button (AK).
private struct StepNumber: View {
    static let size: CGFloat = 22
    let n: Int
    init(_ n: Int) { self.n = n }
    var body: some View {
        Text("\(n)")
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .frame(width: Self.size, height: Self.size)
            .background(Circle().fill(Color.primary))
            .accessibilityLabel("Step \(n)")
    }
}

/// The lighter rounded square behind each step's illustration.
private struct StepWell: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 14.0, *) {
            // One step down from the secondary fill: still lighter than the card, a bit darker (AK).
            content.background(.fill.tertiary, in: shape)
        } else {
            content.background(Color.primary.opacity(0.05), in: shape)
        }
    }
}

/// An installed app's own icon, which already has the macOS icon shape.
/// Without an icon, a symbol on the system fill in the same shape.
struct AppTile: View {
    let icon: NSImage?
    let symbol: String
    var size: CGFloat = 36
    var body: some View {
        if let icon = icon {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            // On the macOS app icon grid (artwork about 80% of the box), like real icons and logos.
            let inner = size * 0.8
            AppIconView(icon: nil, symbol: symbol, size: inner * 0.62)
                .frame(width: inner, height: inner)
                .background(Color(nsColor: .quaternaryLabelColor),
                            in: RoundedRectangle(cornerRadius: inner * Radius.tile, style: .continuous))
                .frame(width: size, height: size)
        }
    }
}

/// A looping carousel: All good -> Getting low -> Almost out -> All good, always sliding
/// the same way. A copy of the first slide sits at the end so the loop has no jump back.
struct IconStoryDemo: View {
    @ObservedObject var store: Store
    @State private var index = 0
    private let width: CGFloat = 170
    private let tick = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { i in slide(i % 3).frame(width: width) }
        }
        .offset(x: -CGFloat(index) * width)
        .frame(width: width, alignment: .leading)
        .clipped()
        .onReceive(tick) { _ in advance() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("The menu bar icon turns yellow when an app gets low, and red when it's almost out")
    }

    private func advance() {
        let next = index + 1
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { index = next }
        if next == 3 {
            // After sliding onto the copy of the first slide, snap back to the real one unseen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { index = 0 }
            }
        }
    }

    private func slide(_ k: Int) -> some View {
        VStack(spacing: 14) {
            ZStack {
                if k == 0 { TankMark(size: 31, color: .primary) }
                if k == 1 { PillView(glyph: store.glyph(store.demoID), symbol: store.symbol(store.demoID), pct: 24, level: .low, scale: 1.4) }
                if k == 2 { PillView(glyph: store.glyph(store.demoID), symbol: store.symbol(store.demoID), pct: 8, level: .out, scale: 1.4) }
            }
            .frame(height: 30)
            Text(["All good", "Getting low", "Almost out"][k]).font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct AppsStep: View {
    @ObservedObject var store: Store
    @Binding var connectTarget: AIApp?

    var body: some View {
        // Centered when the apps fit; scrolls only when there are more than fit. Snapshots can't
        // draw a scroll view, so pictures show the top of the list instead.
        if ControlMetrics.capture {
            // The overlay takes only the space offered, so the long list never pushes the title up.
            Color.clear.overlay(alignment: .top) { grid }.clipped()
        } else {
            ViewThatFits(in: .vertical) {
                grid
                ScrollView { grid }
            }
        }
    }

    /// Two groups (AK): every AI app found on this Mac, ready to connect (apps TUM can't read yet
    /// come last and connect without numbers, so the person decides), and "Coming soon", the image,
    /// video and music apps TUM plans to support.
    private var grid: some View {
        let ready = store.detected.filter(\.supported) + store.detected.filter { !$0.supported }
        let later = store.comingSoon
        // 28pt between the two groups, so they read as separate sections (AK).
        return VStack(alignment: .leading, spacing: 28) {
            if !ready.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    GroupTitle("Ready to connect")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(ready) { app in
                            AppCard(store: store, app: app, connect: { connectTarget = app })
                                .transition(.scale(scale: 0.92).combined(with: .opacity))
                        }
                    }
                }
            }
            if !later.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    GroupTitle("Coming soon")
                    // The same grid, card and size as above; only the Connect button is missing (AK).
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        ForEach(later) { app in ComingSoonCard(store: store, app: app) }
                    }
                }
            }
        }
        .padding(.bottom, 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.detected.map(\.id))
    }
}

/// A small group heading in the secondary label color.
struct GroupTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// An app TUM can't show yet: the same card as a supported app (same shape, size, icon and
/// text), with no Connect button. Dimmed, with a grayed-out icon, and not clickable (AK).
struct ComingSoonCard: View {
    @ObservedObject var store: Store
    let app: AIApp

    var body: some View {
        Card {
            HStack(spacing: 10) {
                AppTile(icon: store.icon(app.id), symbol: store.symbol(app.id), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline).lineLimit(1)
                    // How TUM plans to support it, in one short line (never "Coming soon" again).
                    Text(app.hint).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .frame(minHeight: 44)
        }
        // Normal colors (AK): there's no button, so nothing needs to look disabled.
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(app.name), coming soon. \(app.hint)")
    }
}

@MainActor
struct AppCard: View {
    @ObservedObject var store: Store
    let app: AIApp
    var connect: () -> Void

    private var isConnected: Bool { store.connected.contains(app.id) }

    var body: some View {
        Card {
            HStack(spacing: 10) {
                AppTile(icon: store.icon(app.id), symbol: store.symbol(app.id), size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline).lineLimit(1)
                    statusText(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                .layoutPriority(1)   // the name and status keep their room; the button never squeezes them
                Spacer(minLength: 4)
                trailing
            }
            .frame(minHeight: 44)
        }
        .help(app.hint)
        .contextMenu {
            if isConnected {
                AppMenuItems(name: app.name, refresh: syncAction, remove: remove)
            } else if app.canConnect {
                Button("Connect \(app.name)", action: connect)
            }
        }
    }

    /// One line. Cursor and Grok Bot say up front that they need a quick browser sign-in.
    private var subtitle: String {
        if isConnected { return store.errors[app.id] ?? store.connectedText(app.id) }
        if app.usesCursorSignIn && !CursorAuth.signedIn { return app.hint }
        if app.usesGitHubSignIn && !GitHubAuth.signedIn && !CopilotProvider().hasLocalSignIn() { return app.hint }
        // Apps TUM can't read yet say so up front, so connecting one is an informed choice.
        if !app.supported { return app.hint }
        return app.canConnect ? app.category : app.hint
    }

    private func refresh() { Task { await store.syncNow(app.id) } }
    private func remove() { withAnimation { store.disconnect(app.id) } }
    /// Nil for apps TUM can't read yet, so their menu has no Sync.
    private var syncAction: (() -> Void)? {
        guard store.readsUsage(app.id) else { return nil }
        return refresh
    }

    @ViewBuilder private var trailing: some View {
        if isConnected {
            AppMenu(name: app.name, refresh: syncAction, remove: remove)
        } else if app.canConnect {
            ConnectButton(name: app.name, action: connect)
        }
    }
}

/// Explains what connecting means before anything happens, then connects using the
/// sign-in the app already keeps on this Mac. Stays open and shows the result.
struct ConnectSheet: View {
    @ObservedObject var store: Store
    let app: AIApp
    var done: () -> Void

    private enum Phase { case ready, connecting, connected, failed }
    @State private var phase: Phase = .ready
    @State private var reason = ""
    @State private var work: Task<Void, Never>?

    /// Apps whose saved sign-in is protected by the macOS Keychain, so macOS asks once: Claude,
    /// Codex when its sign-in is there instead of in a file, Copilot through the GitHub CLI, and Zed.
    private var macMayAsk: Bool {
        switch app.id {
        case "claude": return true
        case "codex": return !FileManager.default.fileExists(atPath: homeURL(".codex/auth.json").path)
        case "copilot": return Keychain.exists(service: "gh:github.com")
        case "zed": return true
        default: return false
        }
    }
    /// Cursor and Grok Bot need a one-time sign-in in the browser (TUM's own, in the Keychain).
    private var needsCursor: Bool { app.usesCursorSignIn && !CursorAuth.signedIn }
    private var needsGitHub: Bool { app.usesGitHubSignIn && !GitHubAuth.signedIn && !CopilotProvider().hasLocalSignIn() }
    private var needsBrowser: Bool { needsCursor || needsGitHub }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                AppLogo(size: 52)
                Image(systemName: "plus").font(.headline).foregroundStyle(.secondary)
                AppTile(icon: store.icon(app.id), symbol: store.symbol(app.id), size: 52)
            }
            Text("Connect \(app.name)").font(.title.bold()).foregroundStyle(.primary)
            Card {
                VStack(spacing: 0) {
                    if app.supported {
                        InfoRow(symbol: "gauge.with.dots.needle.50percent", text: "See how much you have left")
                        Divider()
                        InfoRow(symbol: "calendar", text: "See when it resets")
                    } else {
                        // Nothing to read yet, so the sheet says plainly what connecting does (AK).
                        InfoRow(symbol: "square.grid.2x2", text: "Keep it in your list with your other apps")
                        Divider()
                        InfoRow(symbol: "clock.badge.checkmark", text: "Its numbers show up once TUM supports it")
                    }
                    Divider()
                    InfoRow(symbol: "eye.slash", text: "TUM never saves or sends your prompts or work")
                    Divider()
                    InfoRow(symbol: "lock", text: "It can't change anything. Remove it anytime")
                }
            }

            status.frame(maxWidth: .infinity, minHeight: 64)

            HStack(spacing: 10) {
                Spacer()
                if phase != .connected {
                    // Cancel stays available while waiting for the browser, and stops waiting.
                    Button { work?.cancel(); done() } label: { ButtonText("Cancel") }
                        .keyboardShortcut(.cancelAction).secondaryButton()
                        .disabled(phase == .connecting && !needsBrowser)
                }
                Button(action: primary) { ButtonText(primaryTitle) }
                    .keyboardShortcut(.defaultAction).primaryButton()
                    .disabled(phase == .connecting)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var primaryTitle: String {
        switch phase {
        case .ready: return needsCursor ? "Sign in" : needsGitHub ? "Sign in" : (macMayAsk ? "Continue" : "Connect")
        case .connecting: return "Connecting"
        case .connected: return "Done"
        case .failed: return "Try again"
        }
    }

    @ViewBuilder private var status: some View {
        switch phase {
        case .ready:
            if needsGitHub {
                note("safari", .secondary, "Sign in once with GitHub",
                     "TUM shows a short code and opens github.com. Paste it there and approve.")
            } else if needsCursor {
                note("safari", .secondary, "Sign in once in your browser",
                     "TUM opens cursor.com. Click Approve, then come back here.")
            } else if macMayAsk {
                note("key.fill", .secondary, "macOS will ask once",
                     "Choose Always Allow so TUM can check \(app.name) without asking again.")
            } else if !app.supported {
                Text("Nothing to sign in to. TUM can't read \(app.name)'s usage yet.").font(TextStyle.caption).foregroundStyle(.secondary)
            } else {
                Text("Uses the \(app.name) account you're already signed in to").font(TextStyle.caption).foregroundStyle(.secondary)
            }
        case .connecting where needsGitHub && store.githubCode != nil:
            githubCodeCard(store.githubCode!)
        case .connecting:
            Card {
                HStack(spacing: 12) {
                    ActivityRing()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(needsCursor ? "Waiting for you on cursor.com" : needsGitHub ? "Getting a code from GitHub" : "Connecting").font(.headline)
                        if needsCursor {
                            Text("Click Approve there. This updates on its own.").font(TextStyle.caption).foregroundStyle(.secondary)
                        } else if macMayAsk {
                            Text("If macOS asks, choose Always Allow.").font(TextStyle.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
            }
        case .connected:
            note("checkmark.circle.fill", Palette.green, "You're all set", app.supported
                 ? "\(app.name) now shows in your menu bar."
                 : "\(app.name) is in your list. Its numbers come once TUM supports it.")
        case .failed:
            note("exclamationmark.circle.fill", Palette.redText, "Couldn't connect", reason)
        }
    }

    private func primary() {
        if phase == .connected { done(); return }
        phase = .connecting
        work = Task { @MainActor in
            if let r = await store.connectAndCheck(app.id) {
                if Task.isCancelled { return }
                reason = r
                phase = .failed
            } else {
                phase = .connected
                try? await Task.sleep(nanoseconds: 900_000_000)
                if phase == .connected { done() }
            }
        }
    }

    /// The GitHub code, big and easy to copy, while the person approves TUM on github.com.
    private func githubCodeCard(_ code: GitHubAuth.DeviceCode) -> some View {
        Card {
            VStack(spacing: 10) {
                Text(code.code)
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .textSelection(.enabled)
                    .accessibilityLabel("Your code is \(code.code.map(String.init).joined(separator: " "))")
                HStack(spacing: 6) {
                    ActivityRing()
                    Text("Copied. Paste it on github.com and approve.").font(TextStyle.caption).foregroundStyle(.secondary)
                }
                Button { NSWorkspace.shared.open(code.url) } label: { ButtonText("Open GitHub") }
                    .secondaryButton()
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code.code, forType: .string)
        }
    }

    private func note(_ symbol: String, _ color: Color, _ title: String, _ text: String) -> some View {
        Card {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(text).font(TextStyle.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: symbol).font(.title3).foregroundStyle(color).frame(width: 24)
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct NudgesStep: View {
    @ObservedObject var store: Store
    @State private var bump = false

    /// Only the yellow pill is explained here (AK: the red one confused people, and the setting
    /// below only moves the yellow point). The first card shows the change itself, white icon to
    /// yellow pill, with "Turn yellow at" right under it in the same card, so the link is plain.
    /// The pill and its line preview the chosen value live (HIG: show the effect of a setting right
    /// away). The other settings sit in their own card below.
    var body: some View {
        let t = Int(store.threshold)
        VStack(spacing: 12) {
            Card(padding: 6) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        state("All good", Text("Above \(t)% left")) { TankMark(size: 34, color: .primary) }
                        Image(systemName: "arrow.right")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        state("Turns yellow", Text("At ") + Text("\(t)%").foregroundColor(Pill.amberText).bold() + Text(" or less")) {
                            PillView(glyph: store.glyph(store.demoID), symbol: store.symbol(store.demoID), pct: store.threshold, level: .low, scale: 1.6)
                                .scaleEffect(bump ? 1.08 : 1)
                        }
                    }
                    .padding(.vertical, 14)
                    Divider().padding(.horizontal, 6)
                    settingRow("Turn yellow at", subtitle: "How much is left when it turns yellow") {
                        SegmentedChoice(selection: $store.threshold, options: Thresholds.yellow, label: "Turn yellow at")
                    }
                }
            }
            // The rows bring their own 10pt form inset, so the card needs less padding of its own.
            Card(padding: 6) {
                VStack(spacing: 0) {
                    settingRow("Usage monitoring", subtitle: "Which limit TUM watches for you") {
                        SegmentedChoice(selection: $store.watch, options: WatchMode.segments, label: "Usage monitoring")
                    }
                    Divider().padding(.horizontal, 6)
                    settingRow("See all apps", subtitle: store.shortcutSubtitle("Keys that show every app at once")) {
                        ShortcutPicker(store: store)
                    }
                }
            }
        }
        // A short pulse on the pill whenever the threshold changes, so the link is felt.
        .onChange(of: store.threshold) { _ in
            withAnimation(Motion.standard) { bump = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { withAnimation(Motion.standard) { bump = false } }
        }
    }

    private func state<V: View>(_ label: String, _ detail: Text, @ViewBuilder _ v: () -> V) -> some View {
        VStack(spacing: 8) {
            v().frame(height: 40)
            Text(label).font(.title3.weight(.semibold))
            detail.font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func settingRow<V: View>(_ title: String, subtitle: String, @ViewBuilder _ control: () -> V) -> some View {
        // The same row as Advanced settings: centered, one height for every row. A grouped form
        // adds 10pt above and below each row, so the same inset here makes the rows match the
        // Settings window exactly (68pt each, AK).
        SettingRow(title, subtitle: subtitle, control: control)
            .padding(.vertical, SettingRow<EmptyView>.formInset)
            .padding(.horizontal, 6)
    }
}
