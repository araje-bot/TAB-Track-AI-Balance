import SwiftUI
import AppKit
import Carbon.HIToolbox

/// The quick view shortcut (AK): always two keys, one of ⌘, ⌥ or ⌃ plus one letter, number or
/// Space. ⌘T and ⌥T are ready to pick; Custom records your own within the same rules, so it
/// can't get complicated. Shortcuts macOS and every app rely on are refused with a reason.
/// It is a registered shortcut, so it needs no permission and TUM never sees other keys.
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
/// Picking Custom (or clicking it again) records a new one in place. Esc or clicking away cancels.
struct ShortcutPicker: View {
    @ObservedObject var store: Store

    private enum Slot: Hashable { case preset(ShortcutChoice), custom }

    private var selection: Binding<Slot> {
        Binding(
            get: {
                if store.recordingShortcut { return .custom }
                return ShortcutChoice.presets.contains(store.shortcutChoice) ? .preset(store.shortcutChoice) : .custom
            },
            set: { slot in
                switch slot {
                case .preset(let p): store.stopRecordingShortcut(); store.shortcutChoice = p
                case .custom: store.startRecordingShortcut()
                }
            })
    }

    private var options: [(Slot, String)] {
        ShortcutChoice.presets.map { (Slot.preset($0), $0.glyphs) } + [(.custom, store.customShortcut?.glyphs ?? "Custom")]
    }

    var body: some View {
        SegmentedChoice(selection: selection, options: options, label: "Shortcut",
                        reselect: { if $0 == .custom { store.startRecordingShortcut() } })
            .background(ShortcutRecorder(store: store).frame(width: 1, height: 1).opacity(0))
            .help(store.recordingShortcut ? "Press the keys, or Esc to cancel" : "Pick keys, or record your own with Custom")
    }
}

/// Listens for the next key press while recording, and only in this TUM window: it is the window's
/// focused view, like a text field. No keyboard monitoring and no permission.
private struct ShortcutRecorder: NSViewRepresentable {
    @ObservedObject var store: Store

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.store = store
        return v
    }

    /// The window closed or the view went away mid-recording: stop, so the shortcut comes back.
    static func dismantleNSView(_ v: RecorderView, coordinator: ()) {
        if let s = v.store, s.recordingShortcut { DispatchQueue.main.async { s.stopRecordingShortcut() } }
    }

    func updateNSView(_ v: RecorderView, context: Context) {
        v.store = store
        if store.recordingShortcut, v.window?.firstResponder !== v {
            DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        } else if !store.recordingShortcut, v.window?.firstResponder === v {
            DispatchQueue.main.async { v.window?.makeFirstResponder(nil) }
        }
    }

    final class RecorderView: NSView {
        weak var store: Store?
        override var acceptsFirstResponder: Bool { true }

        override func resignFirstResponder() -> Bool {
            // Clicking anywhere else cancels, like Esc.
            if let s = store, s.recordingShortcut { DispatchQueue.main.async { s.stopRecordingShortcut() } }
            return true
        }

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

        private func handle(_ event: NSEvent) {
            guard let store = store else { return }
            if event.keyCode == UInt16(kVK_Escape) { store.stopRecordingShortcut(); return }
            store.recorded(ShortcutChoice.make(event))
        }
    }
}
