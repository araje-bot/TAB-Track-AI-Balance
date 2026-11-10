import SwiftUI

/// "Alert levels" (v4): one bar with two handles. Red runs from 0 to the Almost out level, yellow
/// from there to the Getting low level, and the rest stays neutral, so the zones always touch and
/// never overlap. Almost out goes from 0 to 25; Getting low from Almost out + 5 up to 60. The
/// handles can't cross (`Store.setRedAt` and `setYellowAt` clamp). Steps of 5.
struct AlertRangeSlider: View {
    @ObservedObject var store: Store
    var step: Double = 5

    private let knob: CGFloat = 20
    private let track: CGFloat = 5
    private let bubbleH: CGFloat = 20
    private let bubbleW: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { g in
                let w = g.size.width - knob
                let rx = knob / 2 + w * CGFloat(store.redAt / 100)
                let yx = knob / 2 + w * CGFloat(store.yellowAt / 100)
                let (rb, yb) = bubbles(rx, yx, width: g.size.width)
                ZStack(alignment: .topLeading) {
                    // One continuous bar, rounded only at its two outer ends.
                    HStack(spacing: 0) {
                        Rectangle().fill(Pill.redLiquid).frame(width: max(0, rx))
                        Rectangle().fill(Pill.amberLiquid).frame(width: max(0, yx - rx))
                        Rectangle().fill(Color.primary.opacity(0.18))
                    }
                    .frame(height: track)
                    .clipShape(Capsule())
                    .offset(y: bubbleH + 10 + (knob - track) / 2)

                    bubble("\(Int(store.redAt))%", fill: Pill.red, text: .white).position(x: rb, y: bubbleH / 2)
                    bubble("\(Int(store.yellowAt))%", fill: Pill.amber, text: Pill.ink).position(x: yb, y: bubbleH / 2)

                    handle("Almost out", value: store.redAt, x: rx, width: w) { store.setRedAt($0) }
                    handle("Getting low", value: store.yellowAt, x: yx, width: w) { store.setYellowAt($0) }
                }
                .coordinateSpace(name: "alertTrack")
            }
            .frame(height: bubbleH + 10 + knob)

            HStack {
                Text("0%")
                Spacer()
                Text("50%")
                Spacer()
                Text("100%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .accessibilityHidden(true)
        }
        .animation(Motion.standard, value: store.redAt)
        .animation(Motion.standard, value: store.yellowAt)
    }

    /// Bubble centers, pushed apart when the handles are close so the two never overlap.
    private func bubbles(_ rx: CGFloat, _ yx: CGFloat, width: CGFloat) -> (CGFloat, CGFloat) {
        var r = rx, y = yx
        let need = bubbleW + 4
        if y - r < need {
            let mid = (r + y) / 2
            r = mid - need / 2
            y = mid + need / 2
        }
        let lo = bubbleW / 2, hi = width - bubbleW / 2
        if r < lo { y += lo - r; r = lo }
        if y > hi { r -= y - hi; y = hi }
        return (r, y)
    }

    private func bubble(_ s: String, fill: Color, text: Color) -> some View {
        Text(s)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(text)
            .frame(width: bubbleW, height: bubbleH)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }

    private func handle(_ name: String, value: Double, x: CGFloat, width w: CGFloat, set: @escaping (Double) -> Void) -> some View {
        Circle()
            .fill(.white)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
            .frame(width: knob, height: knob)
            .contentShape(Circle().inset(by: -8))
            .position(x: x, y: bubbleH + 10 + knob / 2)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("alertTrack")).onChanged { g in
                let v = Double((g.location.x - knob / 2) / max(w, 1)) * 100
                set((v / step).rounded() * step)
            })
            .accessibilityElement()
            .accessibilityLabel(name)
            .accessibilityValue("\(Int(value)) percent left")
            .accessibilityAdjustableAction { d in
                switch d {
                case .increment: set(value + step)
                case .decrement: set(value - step)
                @unknown default: break
                }
            }
            .help("\(name) at \(Int(value))%")
    }
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
            state("Getting low", "\(y)% to \(r)%") {
                PillView(glyph: store.glyph(store.demoID), symbol: store.symbol(store.demoID),
                         pct: ((store.redAt + store.yellowAt) / 2).rounded(.down), level: .low, scale: 1.45)
            }
            arrow
            state("Almost out", "\(r)% or less") {
                PillView(glyph: store.glyph(store.demoID), symbol: store.symbol(store.demoID),
                         pct: (store.redAt / 2).rounded(.down), level: .out, scale: 1.45)
            }
        }
    }

    private var arrow: some View {
        Image(systemName: "arrow.right").font(.body).foregroundStyle(.secondary).accessibilityHidden(true)
    }

    private func state<V: View>(_ label: String, _ detail: String, @ViewBuilder _ v: () -> V) -> some View {
        VStack(spacing: 6) {
            v().frame(height: 34)
            Text(label).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// "Alert levels" with the slider filling the row (onboarding, Settings).
struct AlertLevelsRow: View {
    @ObservedObject var store: Store
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alert levels").font(.body)
            AlertRangeSlider(store: store)
        }
    }
}
