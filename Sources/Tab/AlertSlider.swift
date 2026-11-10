import SwiftUI

/// The two alert levels (AK, 2026-11-09, replaces the two-handle range bar). The bar read as a
/// range you could pick up and drag, its handles were two identical white knobs, and red stopped
/// at 25% with nothing on screen saying why. Now each level is its own row, "Turn yellow at" and
/// "Turn red at", with a standard slider in that color and its value next to it.
///
/// Neither slider ever stops early. Red runs 5 to 55 and yellow 10 to 60. When one would pass the
/// other, the other moves along with it, so red always stays 5 under yellow
/// (`Store.setRedAt`, `setYellowAt`).
struct LevelSlider: View {
    @ObservedObject var store: Store
    /// The red level ("Turn red at"), or the yellow one.
    let red: Bool

    private var value: Double { red ? store.redAt : store.yellowAt }
    private var name: String { red ? "Turn red at" : "Turn yellow at" }

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: Binding(get: { value }, set: { red ? store.setRedAt($0) : store.setYellowAt($0) }),
                   in: red ? Store.redRange : Store.yellowRange, step: Store.levelGap)
                .labelsHidden()
                .tint(red ? Pill.redLiquid : Pill.amberLiquid)
                .frame(width: 200)
                .accessibilityLabel(name)
                .accessibilityValue("\(Int(value)) percent left")
            Text("\(Int(value))%")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(red ? Pill.redText : Pill.amberText)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
        .help(red ? "The icon turns red at \(Int(value))% left or less" : "The icon turns yellow at \(Int(value))% left or less")
    }

    static let yellowTitle = "Turn yellow at"
    static let yellowSubtitle = "When an app is getting low"
    static let redTitle = "Turn red at"
    static let redSubtitle = "When an app is almost out"
}

/// The three states in a row (v4 screen 03): Plenty left, Getting low and Almost out, with the
/// chosen levels in each line. The pills preview the levels live.
struct LevelStates: View {
    @ObservedObject var store: Store

    var body: some View {
        let r = Int(store.redAt), y = Int(store.yellowAt)
        HStack(spacing: 8) {
            state("Plenty left", "Above \(y)%") { TankMark(size: 30, color: .primary) }
            arrow
            state("Getting low", "\(y)% or less") {
                PillView(glyph: store.glyph(store.demoID), symbol: store.symbol(store.demoID),
                         pct: ((store.redAt + store.yellowAt) / 2).rounded(.down), level: .low, scale: 1.45)
            }
            arrow
            state("Almost out", "\(r)% or less") {
                PillView(glyph: store.glyph(store.demoID), symbol: store.symbol(store.demoID),
                         pct: (store.redAt / 2).rounded(.down), level: .out, scale: 1.45)
            }
        }
        .animation(Motion.standard, value: store.redAt)
        .animation(Motion.standard, value: store.yellowAt)
    }

    private var arrow: some View {
        // Two chevrons with no line, a lighter step forward (AK, 2026-11-09).
        Image(systemName: "chevron.right.2").font(.body).foregroundStyle(Palette.subtitle).accessibilityHidden(true)
    }

    private func state<V: View>(_ label: String, _ detail: String, @ViewBuilder _ v: () -> V) -> some View {
        VStack(spacing: 6) {
            v().frame(height: 34)
            Text(label).font(.headline)
            Text(detail).font(.caption).foregroundStyle(Palette.subtitle).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
