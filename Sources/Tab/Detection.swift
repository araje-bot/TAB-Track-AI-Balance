import Foundation
import AppKit

struct CatalogEntry {
    let id: String
    let name: String
    let category: String
    let appNames: [String]
    let bundleIDs: [String]
    let providerID: String?
    let source: String
    let hint: String
    let symbol: String
    /// Folders in your home that show a command-line AI tool is set up, even with no app.
    var markers: [String] = []
}

/// Known AI apps. Only apps people pay for and run out of are listed (AK): TAB is for making
/// the most of a subscription, so other apps with "AI" in their name are not picked up.
enum Catalog {
    static let all: [CatalogEntry] = [
        CatalogEntry(id: "claude", name: "Claude", category: "Chat & code", appNames: ["Claude"],
                     bundleIDs: ["com.anthropic.claudefordesktop"], providerID: "claude",
                     source: "Claude sign-in",
                     hint: "Sign in to Claude first", symbol: "asterisk"),
        // ChatGPT and Codex share one plan and one set of limits, so they are one app named
        // ChatGPT (AK, 2026-11-09). The id stays "codex", so existing connections carry over.
        // TAB reads the limits through Codex's sign-in. The ChatGPT app's icon comes first.
        CatalogEntry(id: "codex", name: "ChatGPT", category: "Chat & code", appNames: ["ChatGPT", "Codex"],
                     bundleIDs: ["com.openai.chat", "com.openai.codex"], providerID: "codex",
                     source: "Codex sign-in",
                     hint: "Sign in to Codex first", symbol: "chevron.left.forwardslash.chevron.right"),
        CatalogEntry(id: "cursor", name: "Cursor", category: "Code", appNames: ["Cursor"],
                     bundleIDs: ["com.todesktop.230313mzl4w4u92"], providerID: "cursor",
                     source: "Your Cursor account",
                     hint: "One-time sign-in", symbol: "cursorarrow.rays"),
        CatalogEntry(id: "grokbot", name: "Grok Bot", category: "Agents", appNames: ["Grokbot", "Grok Bot", "GrokBot"],
                     bundleIDs: [], providerID: "grokbot",
                     source: "Your Cursor account",
                     hint: "One-time sign-in", symbol: "bolt.fill"),
        CatalogEntry(id: "grok", name: "Grok", category: "Chat & code", appNames: ["Grok"],
                     bundleIDs: [], providerID: "grok",
                     source: "Grok CLI sign-in",
                     hint: "Sign in to Grok first", symbol: "bolt.fill"),
        CatalogEntry(id: "gemini", name: "Gemini", category: "Chat & code", appNames: ["Gemini"],
                     bundleIDs: [], providerID: "gemini",
                     source: "Gemini CLI sign-in",
                     hint: "Google sign-in", symbol: "sparkles", markers: [".gemini"]),
        CatalogEntry(id: "copilot", name: "GitHub Copilot", category: "Code", appNames: ["GitHub Copilot"],
                     bundleIDs: [], providerID: "copilot",
                     source: "Copilot sign-in",
                     hint: "One-time sign-in", symbol: "chevron.left.forwardslash.chevron.right",
                     markers: [".config/github-copilot", ".copilot"]),
        CatalogEntry(id: "antigravity", name: "Antigravity", category: "Code", appNames: ["Antigravity"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Usage view planned", symbol: "arrow.up.circle"),
        CatalogEntry(id: "kiro", name: "Kiro", category: "Code", appNames: ["Kiro"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Kiro CLI support planned", symbol: "chevron.left.forwardslash.chevron.right"),
        CatalogEntry(id: "zed", name: "Zed", category: "Code", appNames: ["Zed"],
                     bundleIDs: ["dev.zed.Zed"], providerID: "zed",
                     source: "Zed sign-in",
                     hint: "Sign in to Zed first", symbol: "chevron.left.forwardslash.chevron.right"),
        CatalogEntry(id: "windsurf", name: "Windsurf", category: "Code", appNames: ["Windsurf"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Usage view planned", symbol: "wind"),
        // Lovable, Canva and CapCut have no way to read their credits at all, so TAB doesn't
        // list them (AK: no data, no point). docs/SYNC-PLAN.md has the details.
        CatalogEntry(id: "ollama", name: "Ollama", category: "Runs on your Mac", appNames: ["Ollama"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Cloud usage planned", symbol: "desktopcomputer"),
    ]

    /// AI apps people use in a browser (v4). Their sign-in happens on their own site, in a TAB
    /// window. Only ChatGPT has a usage reader so far; the rest say they're not supported yet.
    static var webEntries: [CatalogEntry] {
        WebSite.all.map { w in
            CatalogEntry(id: w.id, name: w.name, category: w.category, appNames: [], bundleIDs: [],
                         providerID: w.readsUsage ? w.id : nil, source: "\(w.name) sign-in",
                         hint: w.readsUsage ? "Sign in on \(w.domain)" : "Not supported yet", symbol: "globe")
        }
    }

    /// Web apps, as apps. The featured four come first, in the Figma order. ChatGPT on the web
    /// is left out: it is the same app as ChatGPT on this Mac, so it shows once (AK).
    static var webApps: [AIApp] {
        let order = WebSite.featured + WebSite.all.map(\.id).filter { !WebSite.featured.contains($0) }
        return order.filter { !WebSite.sameAsMacApp.keys.contains($0) }.compactMap(webApp)
    }

    static func webApp(_ id: String) -> AIApp? {
        guard let w = WebSite.site(id) else { return nil }
        let reads = w.readsUsage && WebAuth.enabled
        return AIApp(id: w.id, name: w.name, category: w.category, appURL: nil, supported: reads,
                     credentialFound: reads, hint: reads ? "Sign in on \(w.domain)" : "Not supported yet",
                     source: "\(w.name) sign-in", domain: w.domain)
    }

    /// The kinds of limit each app has (v4): the popover tabs list only apps with that kind.
    static func kinds(_ id: String) -> Set<WatchMode> {
        switch id {
        case "cursor", "copilot", "zed": return [.monthly]
        case "grokbot", "grok": return [.weekly]
        default: return [.session, .weekly]
        }
    }

    static func entry(_ id: String) -> CatalogEntry? { all.first { $0.id == id } ?? webEntries.first { $0.id == id } }
}

enum Detector {
    static func installedApps() -> [String: URL] {
        var found: [String: URL] = [:]
        let dirs = [URL(fileURLWithPath: "/Applications"),
                    homeURL("Applications"),
                    URL(fileURLWithPath: "/Applications/Setapp")]
        for dir in dirs {
            guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for u in items where u.pathExtension == "app" {
                // Real app folders only, never a link, and the first place found wins, so nothing in
                // a home folder can stand in for an app in /Applications (security review).
                let isLink = (try? u.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
                let name = u.deletingPathExtension().lastPathComponent
                if isLink || found[name] != nil { continue }
                found[name] = u
            }
        }
        return found
    }

    static func scan() -> [AIApp] {
        let apps = installedApps()
        var out: [AIApp] = []
        for e in Catalog.all {
            var url: URL? = e.appNames.compactMap { apps[$0] }.first
            if url == nil {
                url = e.bundleIDs.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
            }
            let supported = e.providerID != nil
            let cred = e.providerID.flatMap { Providers.all[$0]?.credentialAvailable() } ?? false
            // Folders count only for command-line tools TAB can read (Copilot). An app TAB can't
            // read must really be installed: a leftover folder (an old Kiro or Lovable) isn't the app.
            let marked = supported && e.markers.contains { FileManager.default.fileExists(atPath: homeURL($0).path) }
            // Gemini can always sign in, but only shows when it's on this Mac (app, CLI or TAB sign-in).
            let present = e.id == "gemini" ? (url != nil || marked || GeminiAuth.signedIn) : (url != nil || cred || marked)
            if !present { continue }
            out.append(AIApp(id: e.id, name: e.name, category: e.category, appURL: url,
                             supported: supported, credentialFound: cred, hint: e.hint, source: e.source))
        }
        return out
    }
}
