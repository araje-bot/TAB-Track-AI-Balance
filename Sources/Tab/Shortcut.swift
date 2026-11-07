import SwiftUI
import AppKit
import Carbon.HIToolbox

/// The quick view shortcut (AK): always two keys, one of ⌘, ⌥ or ⌃ plus one letter, number or
/// Space. ⌘T and ⌥T are ready to pick; Custom records your own within the same rules, so it
/// can't get complicated. Shortcuts macOS and every app rely on are refused with a reason.
/// It is a registered shortcut, so it needs no permission and TAB never sees other keys.
struct ShortcutChoice: Hashable {
    enum Modifier: String, CaseIterable {
        case command, option, control
        var glyph: String { switch self { case .command: return "⌘"; case .option: return "⌥"; case .control: return "⌃" } }
        var word: String { switch self { case .command: return "Command"; case .option: return "Option"; case .control: return "Control" } }
        var carbon: Int { switch self { case .command: return cmdKey; case .option: return optionKey; case .control: return controlKey } }
    }

    let modifier: Modifier
    /// What the key says: "T", "5" or "Space".
    let key: String
    /// The physical key, so it works with any keyboard layout.
    let keyCode: UInt16

    static let commandT = ShortcutChoice(modifier: .command, key: "T", keyCode: UInt16(kVK_ANSI_T))
    static let optionT = ShortcutChoice(modifier: .option, key: "T", keyCode: UInt16(kVK_ANSI_T))
    static let optionSpace = ShortcutChoice(modifier: .option, key: "Space", keyCode: UInt16(kVK_Space))
    /// The two ready-made picks. Anything else is the person's custom one.
    static let presets: [ShortcutChoice] = [.commandT, .optionT]
    /// Tried in this order when another app owns the chosen shortcut.
    static let fallbacks: [ShortcutChoice] = [.commandT, .optionT, .optionSpace]

    var keys: [String] { [modifier.glyph, key] }
    var spoken: String { "\(modifier.word) \(key)" }
    /// Keys with a "+" between them ("⌘ + T"), so it's clear they're pressed together (AK).
    var glyphs: String { keys.joined(separator: " + ") }

    // MARK: Saving

    var stored: String { "\(modifier.rawValue):\(key):\(keyCode)" }

    init(modifier: Modifier, key: String, keyCode: UInt16) {
        self.modifier = modifier; self.key = key; self.keyCode = keyCode
    }

    /// Reads a saved shortcut, including the names older versions saved.
    init?(stored: String) {
        switch stored {
        case "commandT": self = .commandT; return
        case "optionT": self = .optionT; return
        case "optionSpace": self = .optionSpace; return
        default: break
        }
        let parts = stored.split(separator: ":").map(String.init)
        guard parts.count == 3, let m = Modifier(rawValue: parts[0]), let code = UInt16(parts[2]),
              case .success(let s) = Self.check(modifiers: [m], key: parts[1], keyCode: code) else { return nil }
        self = s
    }

    // MARK: The rules

    /// The physical letter and number keys, so a saved value can never point at Esc or another key.
    static let plainKeyCodes: Set<Int> = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I,
        kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
        kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ]

    /// Shortcuts that would break something people use every day.
    static let reserved: Set<String> = {
        let command = "ACFHMNOPQSVWXZ".map { "command:\($0)" }
        return Set(command + ["command:Space", "control:Space"])
    }()

    /// Turns a key press into a shortcut, or says in a few words why it can't be one.
    static func make(_ event: NSEvent) -> Result<ShortcutChoice, ShortcutProblem> {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.shift) { return .failure(.oneModifier) }
        var mods: [Modifier] = []
        if flags.contains(.command) { mods.append(.command) }
        if flags.contains(.option) { mods.append(.option) }
        if flags.contains(.control) { mods.append(.control) }
        let key: String
        if event.keyCode == UInt16(kVK_Space) { key = "Space" }
        else { key = (event.charactersIgnoringModifiers ?? "").uppercased() }
        return check(modifiers: mods, key: key, keyCode: event.keyCode)
    }

    static func check(modifiers: [Modifier], key: String, keyCode: UInt16) -> Result<ShortcutChoice, ShortcutProblem> {
        guard !modifiers.isEmpty else { return .failure(.needsModifier) }
        guard modifiers.count == 1 else { return .failure(.oneModifier) }
        let isSpace = key == "Space" && keyCode == UInt16(kVK_Space)
        let isPlain = key.count == 1 && key.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
            && plainKeyCodes.contains(Int(keyCode))
        guard isSpace || isPlain else { return .failure(.plainKey) }
        let s = ShortcutChoice(modifier: modifiers[0], key: key, keyCode: keyCode)
        if reserved.contains("\(s.modifier.rawValue):\(s.key)") { return .failure(.usedByMac(s.glyphs)) }
        return .success(s)
    }
}

/// Why a key press can't be the shortcut, in one short line for the row's subtitle.
enum ShortcutProblem: Error, Equatable {
    case needsModifier, oneModifier, plainKey, usedByMac(String)
    var message: String {
        switch self {
        case .needsModifier: return "Hold ⌘, ⌥ or ⌃ with the key"
        case .oneModifier: return "Use just one of ⌘, ⌥ or ⌃"
        case .plainKey: return "Use a letter, a number or Space"
        case .usedByMac(let g): return "\(g) is used by macOS. Try another"
        }
    }
}

/// The "See all apps" control: ⌘ + T, ⌥ + T, and Custom, in the usual segmented look.
/// Custom always opens a small box under it (AK): plain instructions, a field that shows the keys
/// as they're pressed, then Save. A saved custom shortcut is already in the box.
struct ShortcutPicker: View {
    @ObservedObject var store: Store

    private enum Slot: Hashable { case preset(ShortcutChoice), custom }

    private var selection: Binding<Slot> {
        Binding(
            // Custom stays highlighted while its box is open. Cancel goes back to the old pick.
            get: { store.recordingShortcut || !ShortcutChoice.presets.contains(store.shortcutChoice) ? .custom : .preset(store.shortcutChoice) },
            set: { slot in
                switch slot {
                case .preset(let p): store.stopRecordingShortcut(); store.shortcutChoice = p
                // Custom always opens the box (AK), with the saved keys already in it.
                case .custom: store.startRecordingShortcut()
                }
            })
    }

    private var options: [(Slot, String)] {
        // Always the word Custom (AK): showing the saved keys there hid the option.
        ShortcutChoice.presets.map { (Slot.preset($0), $0.glyphs) } + [(.custom, "Custom")]
    }

    private var editing: Binding<Bool> {
        Binding(get: { store.recordingShortcut }, set: { if !$0 { store.stopRecordingShortcut() } })
    }

    var body: some View {
        SegmentedChoice(selection: selection, options: options, label: "Shortcut",
                        reselect: { if $0 == .custom { store.startRecordingShortcut() } })
            .help("Pick keys, or click Custom to make your own")
            .popover(isPresented: editing, arrowEdge: .bottom) { ShortcutEditor(store: store) }
    }
}

/// The box for making your own shortcut: what to press, the keys as they're pressed, then Save.
struct ShortcutEditor: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make your own shortcut").font(.headline)
            Text("Hold \u{2318}, \u{2325} or \u{2303} and press a letter, a number or Space. Your keys show up in the box.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ShortcutField(store: store)
            Group {
                if let p = store.shortcutProblem {
                    Text(p.message).foregroundStyle(Palette.amberText)
                } else if let c = store.pendingShortcut {
                    Text("Click Save to use \(c.glyphs).").foregroundStyle(.secondary)
                } else {
                    Text("Esc cancels.").foregroundStyle(.tertiary)
                }
            }
            .font(.callout)
            .lineLimit(1)
            HStack(spacing: 10) {
                Spacer()
                Button { store.stopRecordingShortcut() } label: { ButtonText("Cancel") }
                    .secondaryButton()
                Button { store.saveRecordedShortcut() } label: { ButtonText("Save") }
                    .primaryButton()
                    .disabled(store.pendingShortcut == nil)
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}

/// Looks like a text field and works like one: it has the focus while the box is open, shows the
/// keys pressed, and only listens inside TAB's own window. No keyboard monitoring, no permission.
private struct ShortcutField: View {
    @ObservedObject var store: Store

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: "keyboard").foregroundStyle(.secondary)
            if let c = store.pendingShortcut {
                Text(c.glyphs).font(.title3.weight(.semibold)).foregroundStyle(.primary)
            } else {
                Text("Press your keys").foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color(nsColor: .textBackgroundColor), in: shape)
        .overlay(shape.strokeBorder(Color.accentColor, lineWidth: 2))
        .overlay(ShortcutRecorder(store: store))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut")
        .accessibilityValue(store.pendingShortcut?.glyphs ?? "Press your keys")
    }
}

/// Listens for key presses while the box is open, and only there: it is the box's focused view.
private struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var store: Store

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.store = store
        return v
    }

    /// The box closed or went away mid-recording: stop, so the working shortcut comes back.
    static func dismantleNSView(_ v: RecorderView, coordinator: ()) {
        if let s = v.store, s.recordingShortcut { DispatchQueue.main.async { s.stopRecordingShortcut() } }
    }

    func updateNSView(_ v: RecorderView, context: Context) {
        v.store = store
        if store.recordingShortcut, v.window?.firstResponder !== v {
            DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        }
    }

    final class RecorderView: NSView {
        weak var store: Store?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if store?.recordingShortcut == true { DispatchQueue.main.async { self.window?.makeFirstResponder(self) } }
        }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

        // ⌘ shortcuts arrive here before keyDown.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self, store?.recordingShortcut == true else { return false }
            handle(event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard store?.recordingShortcut == true else { return super.keyDown(with: event) }
            handle(event)
        }

        /// Return with no ⌘, ⌥ or ⌃ held means Save. With one held, it's a key being tried.
        static func plain(_ event: NSEvent) -> Bool {
            event.modifierFlags.intersection(.deviceIndependentFlagsMask).isDisjoint(with: [.command, .option, .control])
        }

        private func handle(_ event: NSEvent) {
            guard let store = store else { return }
            switch Int(event.keyCode) {
            case kVK_Escape: store.stopRecordingShortcut()
            case kVK_Return where Self.plain(event), kVK_ANSI_KeypadEnter where Self.plain(event):
                store.saveRecordedShortcut()
            default: store.recorded(ShortcutChoice.make(event))
            }
        }
    }
}
