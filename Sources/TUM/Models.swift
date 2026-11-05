import Foundation
import AppKit

/// Which window a limit belongs to.
/// `short` = session style (Claude/Codex 5 hours), `long` = weekly style,
/// `only` = app has a single limit (Cursor month, Grok week, Gemini day).
enum LimitKind: String, Codable {
    case short, long, only
}

struct UsageLimit: Identifiable, Hashable {
    var id: String { label }
    var kind: LimitKind
    var label: String            // "5 hours", "Week", "Month", "Day"
    var percentLeft: Double      // 0...100
    var resetsAt: Date?
    var isEstimate: Bool = false

    /// True once the reset time has passed but fresh data has not arrived yet.
    var isReset: Bool {
        if let r = resetsAt { return r < Date() }
        return false
    }
}

/// The tabs (AK): Session, Weekly, Monthly. Each app shows the limit of that period. An app
/// without one (Cursor has only a monthly limit) shows its own limits instead, with their icon.
enum WatchMode: String, CaseIterable, Identifiable, Codable {
    case session = "Session"
    case weekly = "Weekly"
    case monthly = "Monthly"

    var id: String { rawValue }

    /// The period a limit belongs to. A daily limit counts as short, like a session.
    static func period(of l: UsageLimit) -> WatchMode {
        switch l.kind {
        case .short: return .session
        case .long: return .weekly
        case .only:
            switch l.label {
            case "Week": return .weekly
            case "Day": return .session
            default: return .monthly
            }
        }
    }

    func matches(_ l: UsageLimit) -> Bool { Self.period(of: l) == self }

    var hint: String {
        switch self {
        case .session: return "Each app shows its session limit"
        case .weekly: return "Each app shows its weekly limit"
        case .monthly: return "Each app shows its monthly limit"
        }
    }
}

enum Level {
    /// `use`: plenty left and the limit resets soon, so TUM suggests using it (the green pill).
    case ok, low, out, use
}

struct ProviderSnapshot {
    var limits: [UsageLimit]
    var fetchedAt: Date
}

/// An AI app found on this Mac.
struct AIApp: Identifiable, Hashable {
    let id: String
    let name: String
    let category: String
    var appURL: URL?
    var supported: Bool          // TUM knows how to read its usage
    var credentialFound: Bool    // a sign-in exists on this Mac
    var hint: String             // what to do when it can't connect yet
    var source: String           // where the numbers come from
    var canConnect: Bool { supported && credentialFound }
    /// Cursor and Grok Bot connect through TUM's own Cursor sign-in, in the browser.
    var usesCursorSignIn: Bool { id == "cursor" || id == "grokbot" }
    /// Copilot signs in with GitHub (a one-time code) when nothing is set up on this Mac yet.
    var usesGitHubSignIn: Bool { id == "copilot" }
}
