#if DEBUG
import SwiftUI
import AppKit

// Xcode canvas for every TAB screen and state, with sample data.
// Open TABApp/Package.swift in Xcode, open this file, then press ⌥⌘↩ to show the canvas
// (⌥⌘P refreshes it). Pick a preview from the tabs at the top of the canvas.
// Previews never read sign-ins or call any service (see Store.isPreview).

// MARK: Helpers

private extension View {
    /// Looks like a TAB window: dark, with the window background.
    func previewWindow(_ w: CGFloat, _ h: CGFloat) -> some View {
        frame(width: w, height: h)
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
    }

    /// Glass layers (popover, hover tip, quick view) over a desktop-like backdrop, so the glass shows.
    func previewDesk(padding: CGFloat = 24) -> some View {
        self.padding(padding)
            .background(LinearGradient(colors: [Color(hex: 0x2C3E66), Color(hex: 0x6B4A7A), Color(hex: 0x1E2A3A)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
    }

    /// A strip of dark menu bar behind the icon.
    func previewMenuBar() -> some View {
        frame(height: 24)
            .padding(.horizontal, 10)
            .background(Color(hex: 0x1C1C1E).opacity(0.92))
            .environment(\.colorScheme, .dark)
    }
}

@MainActor private func sampleStore(_ apps: [String: Double] = ["claude": 62, "codex": 88], done: Bool = true) -> Store {
    Store.preview(apps: apps, onboardingDone: done)
}

// MARK: Onboarding

#Preview("Onboarding 1 Welcome") {
    OnboardingView(store: sampleStore([:], done: false), finish: {}, startStep: 1).previewWindow(800, 560)
}

#Preview("Onboarding 2 How it works") {
    OnboardingView(store: sampleStore([:], done: false), finish: {}, startStep: 2).previewWindow(800, 560)
}

#Preview("Onboarding 3 Apps, none yet") {
    OnboardingView(store: sampleStore([:], done: false), finish: {}, startStep: 3).previewWindow(800, 560)
}

#Preview("Onboarding 3 Apps, connected") {
    OnboardingView(store: sampleStore(["claude": 62], done: false), finish: {}, startStep: 3).previewWindow(800, 560)
}

#Preview("Onboarding 4 Nudges") {
    OnboardingView(store: sampleStore(done: false), finish: {}, startStep: 4).previewWindow(800, 560)
}

#Preview("Connect sheet") {
    let s = sampleStore([:], done: false)
    return ConnectSheet(store: s, app: s.sampleApp("claude"), done: {}).previewWindow(480, 600)
}

// MARK: Menu bar popover

#Preview("Popover all good") {
    PopoverView(store: sampleStore(["claude": 62, "codex": 88, "cursor": 70]), openSettings: {}, openAddMore: {})
        .glassPanel()
        .previewDesk()
}

#Preview("Popover yellow") {
    PopoverView(store: sampleStore(["claude": 24, "codex": 88]), openSettings: {}, openAddMore: {})
        .glassPanel()
        .previewDesk()
}

#Preview("Popover red") {
    PopoverView(store: sampleStore(["claude": 62, "codex": 8]), openSettings: {}, openAddMore: {})
        .glassPanel()
        .previewDesk()
}

#Preview("Popover empty") {
    PopoverView(store: sampleStore([:]), openSettings: {}, openAddMore: {})
        .glassPanel()
        .previewDesk()
}

#Preview("Detail view") {
    DetailView(store: sampleStore(["claude": 24, "codex": 88]), id: "claude", back: {})
        .frame(width: 340, height: 440)
        .environment(\.colorScheme, .dark)
        .glassPanel()
        .previewDesk()
}

// MARK: Settings

#Preview("Settings") {
    SettingsView(store: sampleStore(["claude": 62, "codex": 88])).previewWindow(580, 660)
}

// MARK: Floating layers

#Preview("Intro callout") {
    IntroCallout(dismiss: {}).glassPanel().previewDesk()
}

#Preview("Hover tip") {
    HoverTip(store: sampleStore(["claude": 24, "codex": 88, "cursor": 8])).previewDesk()
}

#Preview("Quick view") {
    QuickView(store: sampleStore(["claude": 24, "codex": 88, "cursor": 70])).previewDesk()
}

// MARK: Menu bar icon

#Preview("Icon white, yellow, red") {
    VStack(alignment: .trailing, spacing: 14) {
        MorphMark(level: .ok, pct: nil, glyph: nil, symbol: "asterisk").previewMenuBar()
        MorphMark(level: .low, pct: 24, glyph: Store.shared.glyph("claude"), symbol: "asterisk").previewMenuBar()
        MorphMark(level: .out, pct: 8, glyph: Store.shared.glyph("claude"), symbol: "asterisk").previewMenuBar()
    }
    .padding(20)
    .preferredColorScheme(.dark)
}

#Preview("Pill yellow, large") {
    PillView(glyph: nil, symbol: "asterisk", pct: 24, level: .low, scale: 4).frame(width: 340, height: 120)
}

#Preview("Pill red, large") {
    PillView(glyph: nil, symbol: "asterisk", pct: 8, level: .out, scale: 4).frame(width: 340, height: 120)
}

/// Click to step through white, yellow and red and watch the morph.
private struct MorphPlayground: View {
    @State private var i = 0
    private let states: [(Level, Double?)] = [(.ok, nil), (.low, 24), (.out, 8), (.low, 41)]

    var body: some View {
        VStack(spacing: 16) {
            MorphMark(level: states[i].0, pct: states[i].1, glyph: nil, symbol: "asterisk")
                .previewMenuBar()
                .frame(width: 120, alignment: .trailing)
            Button("Next state") { withAnimation(Motion.standard) { i = (i + 1) % states.count } }
                .secondaryButton()
        }
        .padding(24)
        .preferredColorScheme(.dark)
    }
}

#Preview("Icon morph (click Next state)") {
    MorphPlayground()
}
#endif
