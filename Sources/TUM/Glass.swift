import SwiftUI

/// TUM's design layer, built on Apple's HIG for macOS 26.
/// - Buttons use the SDK's Liquid Glass button styles as one family, all at one size
///   (`ControlMetrics.size`): `.glassProminent` capsule for the one main action, `.glass` capsule
///   for the rest, glass circles for icon-only buttons. Choices use the SDK's own picker.
/// - Content sits in native containers (`GroupBox`, grouped `Form`) on system colors.
/// - `.glassEffect` is only used on TUM's own floating layers (quick view, hover tip, the
///   fallback panel). Shapes inside panels are concentric.
/// - Text uses the system text styles and label colors, and follows Light and Dark Mode.
enum Radius {
    static let card: CGFloat = 18      // content cards: soft, continuous corners like macOS 26 containers
    static let panel: CGFloat = 22     // TUM's own glass panels (quick view, fallback panel)
    static let tip: CGFloat = 16       // the hover tip, soft like the cards
    static let tile: CGFloat = 0.225   // usage tiles, the macOS app icon shape (share of size)
}

extension View {

    // MARK: Surfaces

    /// Floating glass panel. Only for TUM's own floating layers.
    /// It also sets the container shape, so concentric shapes inside follow its corners.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = Radius.panel) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self.containerShape(shape).glassEffect(.regular, in: shape)
        } else {
            self.containerShape(shape).background(.regularMaterial, in: shape)
        }
    }

    /// A content block in TUM's card (see `Card`).
    func contentCard() -> some View {
        Card { self }
    }

    /// A content block inside one of TUM's glass panels: the system fill in a shape that is
    /// concentric with the panel's corners (macOS 26), as the HIG asks for nested shapes.
    @ViewBuilder
    func innerCard() -> some View {
        if #available(macOS 26.0, *) {
            self.background(.fill.tertiary, in: ConcentricRectangle(corners: .concentric(minimum: 8), isUniform: true))
        } else if #available(macOS 14.0, *) {
            self.background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            self.background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    // MARK: Buttons

    /// The one main action in a view: a prominent Liquid Glass capsule in the accent color.
    @ViewBuilder
    func primaryButton() -> some View {
        if ControlMetrics.capture {
            self.buttonStyle(CaptureButtonStyle(prominent: true, circle: false))
        } else if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent).buttonBorderShape(.capsule).controlSize(ControlMetrics.size)
        } else {
            self.buttonStyle(.borderedProminent).controlSize(ControlMetrics.size)
        }
    }

    /// Every other text button: a Liquid Glass capsule.
    @ViewBuilder
    func secondaryButton() -> some View {
        if ControlMetrics.capture {
            self.buttonStyle(CaptureButtonStyle(prominent: false, circle: false))
        } else if #available(macOS 26.0, *) {
            self.buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(ControlMetrics.size)
        } else {
            self.buttonStyle(.bordered).controlSize(ControlMetrics.size)
        }
    }

    /// An icon-only button (back, settings, connect): a Liquid Glass circle, the same height as
    /// the text buttons. `prominent` tints it with the accent color (the Figma Connect button).
    @ViewBuilder
    func iconButton(prominent: Bool = false) -> some View {
        if ControlMetrics.capture {
            self.labelStyle(SquareIcon()).buttonStyle(CaptureButtonStyle(prominent: prominent, circle: true))
        } else if #available(macOS 26.0, *) {
            if prominent {
                self.labelStyle(SquareIcon()).buttonStyle(.glassProminent).buttonBorderShape(.circle).controlSize(ControlMetrics.size)
            } else {
                self.labelStyle(SquareIcon()).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(ControlMetrics.size)
            }
        } else {
            self.labelStyle(SquareIcon()).buttonStyle(prominent ? AnyPrimitiveButtonStyle(.borderedProminent) : AnyPrimitiveButtonStyle(.bordered))
                .controlSize(ControlMetrics.size)
        }
    }
}

/// One control size for every button and picker in TUM, so main, other and icon buttons match.
enum ControlMetrics {
    static let size: ControlSize = .large
    /// The icon box inside icon-only buttons. With the system's padding, the circle comes out
    /// exactly as tall as a text button at `size` (the self-test checks this).
    static let iconBox: CGFloat = 16
    /// The outer size of every icon circle (Connect, back, More).
    static let round: CGFloat = 28
    /// Every text button's label width (AK: one width for all primary and secondary buttons,
    /// with or without an icon). Fits the longest label ("Copy diagnostics"); keep new labels
    /// within it. The system adds the same side padding to every button.
    static let minTextWidth: CGFloat = 104
    /// Picture taking only (`--snapshots`): offscreen captures can't draw Liquid Glass buttons
    /// (labels come out black on dark), so they get a plain look-alike instead. Never set in the app.
    static var capture = false
}

/// The look-alike for snapshots: the same 28pt capsule or circle, accent fill for the main action,
/// a light system fill for the rest, and readable labels in both modes.
struct CaptureButtonStyle: ButtonStyle {
    let prominent: Bool
    let circle: Bool

    func makeBody(configuration: Configuration) -> some View {
        CaptureButtonBody(configuration: configuration, prominent: prominent, circle: circle)
    }

    private struct CaptureButtonBody: View {
        let configuration: Configuration
        let prominent: Bool
        let circle: Bool
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let fill: AnyShapeStyle = prominent ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.1))
            configuration.label
                .font(.body)
                .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary))
                .padding(.horizontal, circle ? 0 : 14)
                .frame(minWidth: ControlMetrics.round, minHeight: ControlMetrics.round)
                .background {
                    if circle { Circle().fill(fill) } else { Capsule().fill(fill) }
                }
                .opacity(enabled ? 1 : 0.4)
        }
    }
}

/// Icon-only label in a fixed square box, so every glass circle is the same size and round.
/// The title stays for VoiceOver and tooltips.
struct SquareIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration)
            .labelStyle(.iconOnly)
            .frame(width: ControlMetrics.iconBox, height: ControlMetrics.iconBox)
    }
}

/// Lets the fallback pick a bordered style at run time.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: PrimitiveButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// One settings row: the title and a one-line plain-words subtitle on the leading edge, the
/// control on the trailing edge, both centered vertically, and the same height for every row
/// whatever the control is (AK). Used in Advanced settings and on the onboarding nudges step.
struct SettingRow<Control: View>: View {
    static var height: CGFloat { 48 }
    /// What a grouped `Form` adds above and below each row (measured on macOS 26). Rows outside a
    /// form (onboarding) add it themselves so they match Settings.
    static var formInset: CGFloat { 10 }
    let title: String
    let subtitle: String
    @ViewBuilder var control: Control
    init(_ title: String, subtitle: String, @ViewBuilder control: () -> Control) {
        self.title = title; self.subtitle = subtitle; self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lineLimit(1)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            control
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .contain)
    }
}

/// A content card: the system's soft fill with continuous (squircle) corners, like the rounded
/// containers in macOS 26. No border. One radius and padding everywhere (AK: softer edges).
struct Card<Content: View>: View {
    var padding: CGFloat = 12
    /// Usually `Radius.card`. A card that holds a rounded block of its own uses the concentric
    /// radius (inner radius + padding), so both curves stay evenly spaced (HIG).
    var cornerRadius: CGFloat = Radius.card
    /// A hairline in the system separator color around the card, for cards that sit side by side
    /// as separate items (welcome screen).
    var bordered = false
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardFill(shape: shape))
            .overlay {
                if bordered { shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1) }
            }
    }
}

private struct CardFill<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.background(.fill.tertiary, in: shape)
        } else {
            content.background(Color.primary.opacity(0.05), in: shape)
        }
    }
}

/// Button label with a consistent minimum width, so paired buttons line up.
/// Every text button's label, at one shared minimum width (`ControlMetrics.minTextWidth`).
/// The system then adds the same side padding to all of them. Pass a symbol for icon and text.
struct ButtonText: View {
    let text: String
    var symbol: String? = nil
    init(_ text: String, systemImage: String? = nil) { self.text = text; self.symbol = systemImage }
    var body: some View {
        Group {
            if let symbol = symbol { Label(text, systemImage: symbol).labelStyle(.titleAndIcon) } else { Text(text) }
        }
        .frame(minWidth: ControlMetrics.minTextWidth)
    }
}

/// Scan for more apps, the HIG way: a glass icon button with the standard Refresh symbol
/// (`arrow.clockwise`), the same size as the other icon buttons. While it scans, the system
/// spinner takes its place with no label ("avoid labeling a spinning progress indicator"), then
/// the arrow returns. TUM also scans by itself whenever onboarding or Settings opens.
struct FindAppsButton: View {
    @ObservedObject var store: Store

    /// One glass button that never moves. While TUM scans, the arrow inside it is replaced by the
    /// system activity indicator (`ProgressView`, the HIG's spinner for a short task next to the
    /// control that started it, no label), and the button is dimmed so it can't be pressed twice.
    var body: some View {
        Button { Task { await store.scanAnimated() } } label: {
            Label {
                Text("Scan for more apps")
            } icon: {
                ZStack {
                    if store.scanning {
                        ActivityRing().transition(.opacity)
                    } else {
                        Image(systemName: "arrow.clockwise").transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: store.scanning)
            }
        }
        .iconButton()
        .disabled(store.scanning)
        .help(store.scanning ? "Scanning for AI apps" : "Scan for more apps")
        .accessibilityValue(store.scanning ? "Scanning" : "")
    }
}

/// Every tab control in TUM: a rounded track inside its section, with one selection pill that
/// slides smoothly to the chosen option (the matched-geometry pattern from Nil Coalescing's
/// "custom segmented control", since SwiftUI can't restyle the system picker). The pill is a
/// solid raised shape, not glass, so it stays crisp while it moves (AK).
/// Plain buttons, so clicks always register (also inside forms). Equal-width segments (HIG),
/// arrow keys move the choice, and VoiceOver sees a standard segmented picker.
struct SegmentedChoice<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    var label: String = ""
    /// Fill the available width (popover) instead of fitting the labels.
    var switchesView = false
    /// Called when the option that's already chosen is clicked again.
    var reselect: ((T) -> Void)? = nil

    @Namespace private var pill
    @Environment(\.colorScheme) private var scheme
    private let inset: CGFloat = 3

    var body: some View {
        EqualWidthRow(fill: switchesView) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let chosen = option.0 == selection
                Button { choose(option.0) } label: {
                    // One font and weight for every option, so labels never shift when the choice
                    // changes; color and the sliding pill show which one is chosen (AK).
                    Text(option.1)
                        .font(.body.weight(.medium))
                        .foregroundStyle(chosen ? .primary : .secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background {
                            if chosen {
                                Capsule()
                                    .fill(scheme == .dark ? Color.white.opacity(0.16) : Color.white)
                                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.14), radius: 2, y: 1)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .padding(inset)
        .background(Capsule().fill(Color.primary.opacity(scheme == .dark ? 0.08 : 0.06)))
        .modifier(ArrowKeys(move: move))
        .accessibilityRepresentation {
            Picker(label, selection: $selection) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, option in Text(option.1).tag(option.0) }
            }
            .pickerStyle(.segmented)
        }
    }

    private func choose(_ value: T) {
        guard value != selection else { reselect?(value); return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { selection = value }
    }

    private func move(_ step: Int) {
        guard let i = options.firstIndex(where: { $0.0 == selection }) else { return }
        let j = min(max(i + step, 0), options.count - 1)
        choose(options[j].0)
    }
}

/// Left and right arrows move the choice when the control has keyboard focus (macOS 14+).
private struct ArrowKeys: ViewModifier {
    let move: (Int) -> Void
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .focusable()
                .focusEffectDisabled()
                .onMoveCommand { d in
                    if d == .left { move(-1) } else if d == .right { move(1) }
                }
        } else {
            content
        }
    }
}

/// Lays out segments at one equal width (the widest label's), as the HIG asks for segmented
/// controls. With `fill`, they share the whole proposed width instead.
private struct EqualWidthRow: Layout {
    var fill = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let n = CGFloat(max(subviews.count, 1))
        let widest = sizes.map(\.width).max() ?? 0
        let tallest = sizes.map(\.height).max() ?? 0
        if fill, let w = proposal.width, w.isFinite { return CGSize(width: max(w, widest * n), height: tallest) }
        return CGSize(width: widest * n, height: tallest)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let w = bounds.width / CGFloat(max(subviews.count, 1))
        for (i, view) in subviews.enumerated() {
            view.place(at: CGPoint(x: bounds.minX + CGFloat(i) * w, y: bounds.midY), anchor: .leading,
                       proposal: ProposedViewSize(width: w, height: bounds.height))
        }
    }
}

extension WatchMode {
    static var segments: [(WatchMode, String)] { allCases.map { ($0, $0.rawValue) } }
}

/// "Turn yellow at" choices. Red is automatic at 10%, so yellow always starts above it.
enum Thresholds {
    static let yellow: [(Double, String)] = [(20, "20%"), (25, "25%"), (40, "40%")]
}
