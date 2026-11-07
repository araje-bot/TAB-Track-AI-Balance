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
        CatalogEntry(id: "codex", name: "Codex", category: "Code", appNames: ["Codex"],
                     bundleIDs: ["com.openai.codex"], providerID: "codex",
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
                     hint: "One-time Google sign-in", symbol: "sparkles", markers: [".gemini"]),
        // ChatGPT isn't listed on its own: its limits are the same as Codex's and show there.
        CatalogEntry(id: "perplexity", name: "Perplexity", category: "Search", appNames: ["Perplexity"],
                     bundleIDs: ["ai.perplexity.mac"], providerID: nil, source: "",
                     hint: "Usage view planned", symbol: "magnifyingglass"),
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

    /// Coming soon (AK): paid creative and work tools with a very large user base whose credits
    /// people run out of, and a real way to read them (docs/SYNC-PLAN.md). Midjourney, Kling and
    /// Runway have none yet, so they aren't promised. One that is installed on this Mac shows
    /// with its real icon, still in Coming soon, until TAB can read it.
    static let planned: [CatalogEntry] = [
        soon("elevenlabs", "ElevenLabs", "Voice", "waveform", "Credits view planned", apps: ["ElevenLabs", "ElevenReader"]),
        soon("higgsfield", "Higgsfield", "Video", "film", "Credits view planned"),
        soon("suno", "Suno", "Music", "music.note", "Credits view planned"),
        soon("manus", "Manus", "Agents", "sparkles", "Credits view planned"),
    ]

    private static func soon(_ id: String, _ name: String, _ category: String, _ symbol: String, _ hint: String,
                             apps: [String]? = nil) -> CatalogEntry {
        CatalogEntry(id: id, name: name, category: category, appNames: apps ?? [name], bundleIDs: [], providerID: nil,
                     source: "", hint: hint, symbol: symbol)
    }

    /// The Coming soon cards, as apps.
    static var plannedApps: [AIApp] {
        planned.map { AIApp(id: $0.id, name: $0.name, category: $0.category, appURL: nil, supported: false,
                            credentialFound: false, hint: $0.hint, source: "") }
    }

    static func entry(_ id: String) -> CatalogEntry? { all.first { $0.id == id } ?? planned.first { $0.id == id } }
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
        for e in Catalog.all + Catalog.planned {
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
