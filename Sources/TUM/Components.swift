import SwiftUI
import AppKit

/// Water surface used by the tank mark and all usage tiles.
struct WaveShape: Shape {
    var level: Double          // 0...1, how full
    var phase: Double
    var amplitude: CGFloat = 1.5

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(level, phase) }
        set { level = newValue.first; phase = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let lv = max(0, min(1, level))
        let y = r.height * CGFloat(1 - lv)
        let amp: CGFloat = lv >= 0.995 ? 0 : amplitude
        p.move(to: CGPoint(x: 0, y: y))
        var x: CGFloat = 0
        while x <= r.width {
            let rel = Double(x / max(r.width, 1))
            let yy = y + amp * CGFloat(sin(rel * 2 * Double.pi + phase))
            p.addLine(to: CGPoint(x: x, y: yy))
            x += 1
        }
        p.addLine(to: CGPoint(x: r.width, y: r.height))
        p.addLine(to: CGPoint(x: 0, y: r.height))
        p.closeSubpath()
        return p
    }
}

/// TUM's "all good" mark: a round tank with a waterline.
struct TankMark: View {
    var size: CGFloat = 16
    var color: Color = .primary

    var body: some View {
        // The water runs right into the ring, with no gap, so no dark line shows under it.
        ZStack {
            WaveShape(level: 0.5, phase: 0.6, amplitude: size * 0.06)
                .fill(color)
            Circle().strokeBorder(color, lineWidth: max(1.4, size * 0.11))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .compositingGroup()
    }
}

/// The TUM app logo (Ocean option from the prototype).
struct AppLogo: View {
    var size: CGFloat = 88
    /// The water moves, like the usage circles (welcome screen, AK). The app icon export stays still.
    var flowing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !flowing || reduceMotion)) { ctx in
            logo(phase: flowing ? ctx.date.timeIntervalSinceReferenceDate : 0)
        }
        .frame(width: size, height: size)
    }

    private func logo(phase t: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x13406E), Color(hex: 0x0B2546), Color(hex: 0x06121F)],
                                     startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(RadialGradient(colors: [Color(hex: 0x4FD1FF).opacity(0.35), .clear],
                                     center: .topLeading, startRadius: 0, endRadius: size * 0.9))
            ZStack {
                Circle().fill(Color.white.opacity(0.1))
                // Two waves at different speeds, the same flow as the usage circles.
                WaveShape(level: 0.6, phase: 1.4 + t * 1.7, amplitude: size * 0.03)
                    .fill(Color(hex: 0x9FF4EA).opacity(0.8))
                WaveShape(level: 0.53, phase: t * 2.3, amplitude: size * 0.03)
                    .fill(LinearGradient(colors: [Color(hex: 0x2FE0D0), Color(hex: 0x1478E8)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(Circle())
            .frame(width: size * 0.63, height: size * 0.63)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: size * 0.046))
        }
        .frame(width: size, height: size)
    }

    /// 1024 px macOS app icon with standard margins.
    @MainActor
    static func iconImage() -> NSImage? {
        let content = AppLogo(size: 824)
            .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
            .frame(width: 1024, height: 1024)
        let r = ImageRenderer(content: content)
        r.scale = 1
        return r.nsImage
    }

    @MainActor
    static func image(size: CGFloat = 512) -> NSImage? {
        let r = ImageRenderer(content: AppLogo(size: size))
        r.scale = 1
        return r.nsImage
    }
}

/// The real app icon from the Mac when installed, otherwise a plain symbol.
struct AppIconView: View {
    let icon: NSImage?
    let symbol: String
    var size: CGFloat

    var body: some View {
        if let icon = icon {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.6, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

/// Rounded tile that fills with water to show what's left.
struct LiquidTile: View {
    let pct: Double?
    let level: Level
    let glyph: NSImage?
    let symbol: String
    var size: CGFloat = 56
    var stale = false

    /// Every usage tile is the same component as the menu bar pill's dot (Figma): a dark circle,
    /// the app's white logo in the middle, and water flowing up to what's left, in blue, yellow
    /// or red. Old numbers dim a little but keep flowing. Reduce Motion stops the flow.
    var body: some View {
        LiquidDot(glyph: glyph, symbol: symbol, pct: pct ?? 0, liquid: Palette.water(level),
                  size: size, flowing: pct != nil, glyphScale: 0.5, empty: pct == nil, tintedTank: true,
                  logoOnWater: level == .use ? Pill.ink : nil)
            .opacity(stale ? 0.6 : 1)
    }
}

/// Menu bar pill for an app that is low or almost out. Matches the Figma component:
/// a glossy amber or red capsule, a dark circle with the app's white logo,
/// and liquid in the circle filled to what's left.
struct PillView: View {
    let glyph: NSImage?
    let symbol: String
    let pct: Double
    let level: Level
    /// Draws the pill larger at its real size (onboarding). Never use `scaleEffect` on the pill:
    /// its logo is flattened first, so a scaled pill looks blurry (AK).
    var scale: CGFloat = 1

    var body: some View {
        let c = Pill.colors(level)
        let top = c.top, base = c.base, ink = c.ink
        HStack(spacing: 4 * scale) {
            LiquidDot(glyph: glyph, symbol: symbol, pct: pct,
                      liquid: c.liquid, size: 16 * scale, flowing: true,
                      logoOnWater: level == .use ? Pill.ink : nil, rim: level == .use ? Pill.ink : nil)
            Text("\(Int(pct.rounded()))%")
                .font(.system(size: 12 * scale, weight: .bold))
                .monospacedDigit()
                .foregroundColor(ink)
        }
        .padding(.leading, 2 * scale)
        .padding(.trailing, 8 * scale)
        .frame(height: 20 * scale)
        .background(Capsule().fill(LinearGradient(colors: [top, base, base], startPoint: .top, endPoint: .bottom)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MorphMark.spoken(level, pct))
    }
}

/// Dark circle with an app's white logo and liquid filled to the % left.
struct LiquidDot: View {
    let glyph: NSImage?
    let symbol: String
    let pct: Double
    let liquid: Color
    var size: CGFloat = 16
    var flowing = true
    /// The logo's size as a share of the circle (the pill uses a larger logo than the tiles).
    var glyphScale: CGFloat = 0.58
    /// No number yet: an empty circle with just the logo.
    var empty = false
    /// Tiles tint the empty part of the tank with its water color, so the whole circle shows
    /// on any background. The menu bar pill keeps the plain dark circle (Figma).
    var tintedTank = false
    /// The green pill (AK): green water around a white logo on a green pill was hard to read at
    /// any shade. With a color here, the logo turns this color where the water covers it (like
    /// the dark % text next to it) and stays white above the water line.
    var logoOnWater: Color? = nil
    /// A thin ring in this color, so the circle stands apart from a pill of the same hue.
    var rim: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !flowing || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle().fill(Pill.ink)
                if tintedTank { Circle().fill(liquid.opacity(empty ? 0.14 : 0.22)) }
                let surface = WaveShape(level: level, phase: t * 2.3, amplitude: size * 0.06)
                if !empty {
                    // Two waves moving at different speeds read as real flowing water:
                    // a lighter crest behind the main surface.
                    WaveShape(level: level + 0.04, phase: t * 1.7 + 1.2, amplitude: size * 0.055).fill(liquid.opacity(0.45))
                    surface.fill(liquid)
                }
                GlyphView(glyph: glyph, symbol: symbol, size: size * glyphScale, color: .white)
                    .shadow(color: .black.opacity(logoOnWater == nil ? 0.25 : 0), radius: size * 0.02)
                if let ink = logoOnWater, !empty {
                    GlyphView(glyph: glyph, symbol: symbol, size: size * glyphScale, color: ink)
                        .frame(width: size, height: size)
                        .mask(surface)
                }
                if let rim { Circle().strokeBorder(rim, lineWidth: max(1, size * 0.06)) }
            }
            .frame(width: size, height: size)
            .compositingGroup()
            .clipShape(Circle())
        }
        .frame(width: size, height: size)
        .animation(Motion.standard, value: pct)
    }

    private var level: Double { max(0.12, min(1, pct / 100)) }
}

/// Motion used across TUM: Apple's smooth spring (no bounce, natural slow-down).
enum Motion {
    static let standard: Animation = {
        if #available(macOS 14.0, *) { return .smooth(duration: 0.45) }
        return .spring(response: 0.45, dampingFraction: 0.9)
    }()
    /// The menu bar icon turning into the pill and back: quick but smooth (AK). The slot width
    /// uses the same duration (`StatusItemController.morphDuration`), so neighbors glide with it.
    /// Onboarding page changes: a smooth, critically damped spring (no bounce) that starts fast and
    /// settles gently, so pages feel quick without snapping (AK, HIG Motion).
    static let page: Animation = {
        if #available(macOS 14.0, *) { return .smooth(duration: 0.35) }
        return .easeInOut(duration: 0.35)
    }()
    static let morphDuration: Double = 0.35
    static let morph: Animation = {
        if #available(macOS 14.0, *) { return .smooth(duration: morphDuration) }
        return .spring(response: morphDuration, dampingFraction: 0.9)
    }()
}

/// Numbers roll to their new value instead of jumping (macOS 14 and later).
struct RollingNumber: ViewModifier {
    let value: Double
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) { content.contentTransition(.numericText(value: value)) } else { content }
    }
}

/// The menu bar mark. One view that morphs between "all good" (white water ring) and the
/// yellow or red pill: the ring crossfades into the liquid dot, the capsule grows out from
/// behind it, the color shifts and the number rolls, all on the same smooth spring.
struct MorphMark: View {
    let level: Level
    let pct: Double?
    let glyph: NSImage?
    let symbol: String

    private var isPill: Bool { level != .ok && pct != nil }

    static func spoken(_ level: Level, _ pct: Double?) -> String {
        let p = Int((pct ?? 0).rounded())
        switch level {
        case .low: return "Getting low, \(p) percent left"
        case .out: return "Almost out, \(p) percent left"
        case .use: return "Resets soon with \(p) percent unused"
        case .ok: return "TUM, all good"
        }
    }

    var body: some View {
        let c = Pill.colors(level)
        let top = c.top, base = c.base
        HStack(spacing: 4) {
            ZStack {
                TankMark(size: 15, color: .primary)
                    .opacity(isPill ? 0 : 1)
                    .scaleEffect(isPill ? 0.7 : 1)
                LiquidDot(glyph: glyph, symbol: symbol, pct: pct ?? 50,
                          liquid: c.liquid, size: 16, flowing: isPill,
                          logoOnWater: level == .use ? Pill.ink : nil, rim: level == .use ? Pill.ink : nil)
                    .opacity(isPill ? 1 : 0)
                    .scaleEffect(isPill ? 1 : 0.7)
            }
            .frame(width: 16, height: 16)
            if isPill, let p = pct {
                Text("\(Int(p.rounded()))%")
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(c.ink)
                    .modifier(RollingNumber(value: p))
                    .fixedSize()
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.8, anchor: .leading)),
                                            removal: .opacity))
            }
        }
        .padding(.leading, isPill ? 2 : 0)
        .padding(.trailing, isPill ? 8 : 0)
        .frame(height: 20)
        .background(
            Capsule().fill(LinearGradient(colors: [top, base, base], startPoint: .top, endPoint: .bottom))
                .opacity(isPill ? 1 : 0)
        )
        .animation(Motion.morph, value: isPill)
        .animation(Motion.morph, value: level)
        .animation(Motion.morph, value: pct)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isPill ? Self.spoken(level, pct) : "TUM, all good")
    }
}

/// An app's logo mark, or a symbol when no mark is available. White in the menu bar pill
/// (Figma); the primary label color everywhere else, so it reads in Light and Dark Mode.
struct GlyphView: View {
    let glyph: NSImage?
    let symbol: String
    var size: CGFloat
    var color: Color = .primary

    var body: some View {
        if let g = glyph {
            Image(nsImage: templated(g)).renderingMode(.template).resizable().interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(color)
                .frame(width: size, height: size)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: size, height: size)
        }
    }

    private func templated(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.isTemplate = true
        return copy
    }
}

/// Makes a white logo mark from an installed app's icon by removing the icon's
/// background color. Works for any app, so nothing is hardcoded per company.
enum GlyphMaker {
    static func whiteGlyph(from icon: NSImage, size: Int = 96) -> NSImage? {
        let w = size, h = size
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let src = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info),
              let dst = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return nil }
        var rect = NSRect(x: 0, y: 0, width: w, height: h)
        guard let cg = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        src.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let sData = src.data, let dData = dst.data else { return nil }
        let p = sData.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let q = dData.bindMemory(to: UInt8.self, capacity: w * h * 4)

        // Background = most common color on a ring just inside the icon's rounded square.
        var counts: [Int: Int] = [:]
        let ring = Int(Double(w) * 0.17)
        for i in ring..<(w - ring) {
            for (x, y) in [(i, ring), (i, h - ring - 1), (ring, i), (w - ring - 1, i)] {
                let o = (y * w + x) * 4
                guard p[o + 3] > 220 else { continue }
                let key = (Int(p[o]) / 24) << 16 | (Int(p[o + 1]) / 24) << 8 | (Int(p[o + 2]) / 24)
                counts[key, default: 0] += 1
            }
        }
        guard let bg = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        let br = Double((bg >> 16) & 255) * 24 + 12, bgG = Double((bg >> 8) & 255) * 24 + 12, bb = Double(bg & 255) * 24 + 12

        let lo = Int(Double(w) * 0.16), hi = w - lo
        // 1. How strongly each pixel differs from the background.
        var alpha = [Double](repeating: 0, count: w * h)
        var total = 0
        for y in lo..<hi {
            for x in lo..<hi {
                let o = (y * w + x) * 4
                guard p[o + 3] > 200 else { continue }
                total += 1
                let dr = Double(p[o]) - br, dg = Double(p[o + 1]) - bgG, db = Double(p[o + 2]) - bb
                alpha[y * w + x] = min(1, max(0, ((dr * dr + dg * dg + db * db).squareRoot() - 50) / 45))
            }
        }
        // 2. Drop stray specks (tiny isolated dots from the icon's texture or highlights).
        //    They would show up as dots and pull the logo off-center.
        var clean = alpha
        for y in lo..<hi {
            for x in lo..<hi where alpha[y * w + x] > 0 {
                var sum = 0.0
                for yy in max(lo, y - 3)...min(hi - 1, y + 3) {
                    for xx in max(lo, x - 3)...min(hi - 1, x + 3) { sum += alpha[yy * w + xx] }
                }
                if sum < 6 { clean[y * w + x] = 0 }
            }
        }
        // 3. Write the mark and measure it.
        var minX = w, minY = h, maxX = -1, maxY = -1, covered = 0
        var sumA = 0.0, sumX = 0.0, sumY = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let a = clean[y * w + x]
                if a > 0 {
                    sumA += a; sumX += a * Double(x); sumY += a * Double(y)
                    if a > 0.5 {
                        covered += 1
                        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
                let o = (y * w + x) * 4
                let v = UInt8(a * 255)
                q[o] = v; q[o + 1] = v; q[o + 2] = v; q[o + 3] = v
            }
        }
        // Reject results that are clearly not a logo mark (nothing found, or the whole tile).
        let ratio = Double(covered) / Double(max(total, 1))
        guard maxX > minX, maxY > minY, ratio > 0.015, ratio < 0.6 else { return nil }
        guard let out = dst.makeImage() else { return nil }
        // Redraw the mark into a square with its center exactly in the middle.
        let bw = CGFloat(maxX - minX + 1), bh = CGFloat(maxY - minY + 1)
        let side = Int(ceil(max(bw, bh) * 1.08))
        guard let sq = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                 space: space, bitmapInfo: info) else { return nil }
        // Center on the logo's visual weight, which looks centered even for lopsided marks.
        let boxX = CGFloat(minX) + bw / 2, boxY = CGFloat(minY) + bh / 2
        let massX = sumA > 0 ? CGFloat(sumX / sumA) + 0.5 : boxX
        let massY = sumA > 0 ? CGFloat(sumY / sumA) + 0.5 : boxY
        let cx = (boxX + massX) / 2
        let cyFromBottom = CGFloat(h) - (boxY + massY) / 2
        sq.interpolationQuality = .high
        sq.draw(out, in: CGRect(x: CGFloat(side) / 2 - cx, y: CGFloat(side) / 2 - cyFromBottom, width: CGFloat(w), height: CGFloat(h)))
        guard let centered = sq.makeImage() else { return nil }
        return NSImage(cgImage: centered, size: NSSize(width: side, height: side))
    }
}

/// The connect icon from the Figma prototype: an upright plug (drawn the same on every macOS).
struct PlugGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 24
        let ox = r.midX - 12 * s, oy = r.midY - 12 * s
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var p = Path()
        p.move(to: pt(9, 3)); p.addLine(to: pt(9, 7.5))
        p.move(to: pt(15, 3)); p.addLine(to: pt(15, 7.5))
        p.move(to: pt(6, 7.5)); p.addLine(to: pt(18, 7.5)); p.addLine(to: pt(18, 11))
        p.addArc(center: pt(12, 11), radius: 6 * s, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.closeSubpath()
        p.move(to: pt(12, 17)); p.addLine(to: pt(12, 21.5))
        return p
    }
}

/// The Figma Connect button: a blue Liquid Glass circle with the plug tilted 45°.
/// It's a native prominent glass button, so it presses, hovers and focuses like the others.
struct ConnectButton: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text("Connect \(name)")
            } icon: {
                PlugGlyph()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                    .frame(width: 15, height: 15)
                    .rotationEffect(.degrees(45))
            }
        }
        .iconButton(prominent: true)
        .tint(Palette.accent)
        .help("Connect \(name)")
    }
}

/// A row subtitle where a leading "Connected" shows in green (AK) and the rest, like
/// " · 2 min ago", keeps the row's secondary color. The green is deeper in Light Mode so it reads.
func statusText(_ s: String) -> Text {
    let word = "Connected"
    guard s.hasPrefix(word) else { return Text(s) }
    return Text(word).foregroundColor(Palette.connectedText) + Text(String(s.dropFirst(word.count)))
}

/// The trailing control of a connected app's row: a More button, as in System Settings' Wi-Fi list
/// (HIG Pull-down buttons). Everything here is stock SDK:
/// - The button is the same `iconButton()` glass circle as Connect and back, so the sizes match exactly.
/// - The menu is a plain AppKit `NSMenu`, opened as a pull-down just below the button, so it looks and
///   behaves like every other Mac menu (keyboard, VoiceOver, Liquid Glass background).
/// - Items follow the macOS HIG: "Sync", a separator, then "Remove <app>" last. Mac menus don't
///   color destructive items red (that is the iOS rule), so Remove is a normal item.
/// No confirmation, since connecting again undoes it. Right-click on the row offers the same items.
struct AppMenu: View {
    let name: String
    /// Nil for apps TUM can't read yet: there is nothing to sync, so the menu only offers Remove.
    let refresh: (() -> Void)?
    let remove: () -> Void
    @State private var anchor = MenuAnchor.Holder()

    var body: some View {
        Button {
            AppMenuItems.show(name: name, refresh: refresh, remove: remove, below: anchor.view)
        } label: {
            Label("More for \(name)", systemImage: "ellipsis")
        }
        .iconButton()
        .background(MenuAnchor(holder: anchor))
        .help("More for \(name)")
    }
}

/// An invisible view that marks where the More button sits, so its menu can open right below it.
struct MenuAnchor: NSViewRepresentable {
    final class Holder { weak var view: NSView? }
    final class FlippedView: NSView { override var isFlipped: Bool { true } }
    let holder: Holder

    func makeNSView(context: Context) -> NSView {
        let v = FlippedView()
        holder.view = v
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { holder.view = nsView }
}

/// The same items in the More menu and the right-click menu, so both always match (HIG Context menus).
struct AppMenuItems: View {
    let name: String
    let refresh: (() -> Void)?
    let remove: () -> Void

    var body: some View {
        if let refresh {
            Button("Sync", systemImage: "arrow.clockwise", action: refresh)
            Divider()
        }
        Button("Remove \(name)", systemImage: "minus.circle", action: remove)
    }

    /// Opens the items as a standard pull-down menu under `view`.
    @MainActor static func show(name: String, refresh: (() -> Void)?, remove: @escaping () -> Void, below view: NSView?) {
        guard let view else { return }
        let menu = NSMenu()
        if let refresh {
            menu.addItem(ActionItem("Sync", symbol: "arrow.clockwise", action: refresh))
            menu.addItem(.separator())
        }
        menu.addItem(ActionItem("Remove \(name)", symbol: "minus.circle", action: remove))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }
}

/// A menu item that runs a closure.
final class ActionItem: NSMenuItem {
    private let run: () -> Void
    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        run = action
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
    @objc private func fire() { run() }
}

/// The quick view shortcut in a plain sentence, with Apple's key symbols:
/// "Press ⌘T to see all apps". VoiceOver reads it as words.
struct ShortcutHint: View {
    @ObservedObject var store = Store.shared
    var before = "Press"
    var after = "to see all apps"

    var body: some View {
        // "⌘ + T": the key symbols with a "+" between them, so they read as pressed together (AK).
        let keys = store.activeShortcut.keys
        let shortcut = keys.dropLast().reduce(Text("")) { text, key in
            text + Text(Image(systemName: Self.symbol(key))) + Text(" + ")
        } + Text(keys.last ?? "")
        (Text(before + " ") + shortcut.fontWeight(.semibold).foregroundColor(.primary) + Text(" " + after))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel("\(before) \(store.activeShortcut.spoken) \(after)")
    }

    private static func symbol(_ key: String) -> String {
        switch key {
        case "⌘": return "command"
        case "⌥": return "option"
        case "⌃": return "control"
        case "⇧": return "shift"
        default: return "questionmark"
        }
    }
}

/// Minimal week icon: a rounded outline with one line near the top. No date grid.
struct WeekIcon: View {
    var size: CGFloat = 12
    var body: some View {
        let lw = max(1, size * 0.11)
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(lineWidth: lw)
            Rectangle().frame(height: lw).padding(.top, size * 0.3)
        }
        .frame(width: size * 0.92, height: size * 0.86)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The icon for a limit: a clock for the session limit, the minimal week icon otherwise.
struct LimitIcon: View {
    let kind: LimitKind
    var size: CGFloat = 12
    var body: some View {
        Image(systemName: kind == .short ? "clock" : "calendar")
            .font(.system(size: size * 0.9, weight: .regular))
            .frame(width: size, height: size)
    }
}

/// "52%" with a clock (short limit) or calendar (longer limit).
struct LimitValue: View {
    let limit: UsageLimit
    let level: Level
    var size: CGFloat = 13

    var body: some View {
        HStack(spacing: 4) {
            LimitIcon(kind: limit.kind, size: size - 2)
                .foregroundColor(.secondary)
            if limit.isReset {
                Text("Reset").font(.system(size: size - 1, weight: .medium)).foregroundColor(.secondary)
            } else {
                Text("\(limit.isEstimate ? "~" : "")\(Int(limit.percentLeft.rounded()))%")
                    .font(.system(size: size, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Palette.text(level))
            }
        }
    }
}

struct SectionCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard()
    }
}

/// The loading ring used across macOS 26 and Xcode (AK's reference screenshot): a thin gray track
/// with a lighter arc that turns. SwiftUI's circular `ProgressView` draws a pie at small sizes and the
/// system spinner still uses spokes, so the ring is drawn from SDK shapes in system label colors.
/// With Reduce Motion on, the arc stays put and gently fades instead of turning.
struct ActivityRing: View {
    var size: CGFloat = 16
    @State private var turning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let line = max(1.5, size * 0.13)
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.35), lineWidth: line)
            Circle()
                .trim(from: 0, to: 0.3)
                .stroke(Color.primary.opacity(0.85), style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(turning && !reduceMotion ? 270 : -90))
                .opacity(reduceMotion && turning ? 0.4 : 1)
        }
        .padding(line / 2)
        .frame(width: size, height: size)
        .animation(reduceMotion ? .easeInOut(duration: 0.8).repeatForever()
                                : .linear(duration: 0.8).repeatForever(autoreverses: false),
                   value: turning)
        .onAppear { turning = true }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }
}
