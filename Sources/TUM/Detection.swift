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

/// Known AI apps. Anything not listed is still picked up by name keywords
/// and shown as "found" so people see TUM noticed it.
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
                     hint: "Sign in to Gemini first", symbol: "sparkles"),
        // ChatGPT isn't listed on its own: its limits are the same as Codex's and show there.
        CatalogEntry(id: "perplexity", name: "Perplexity", category: "Search", appNames: ["Perplexity"],
                     bundleIDs: ["ai.perplexity.mac"], providerID: nil, source: "",
                     hint: "Sign-in support planned", symbol: "magnifyingglass"),
        CatalogEntry(id: "copilot", name: "GitHub Copilot", category: "Code", appNames: ["GitHub Copilot"],
                     bundleIDs: [], providerID: "copilot",
                     source: "Copilot sign-in",
                     hint: "One-time sign-in", symbol: "chevron.left.forwardslash.chevron.right",
                     markers: [".config/github-copilot", ".copilot"]),
        CatalogEntry(id: "mscopilot", name: "Microsoft Copilot", category: "Chat", appNames: ["Copilot", "Microsoft Copilot"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Account sign-in planned", symbol: "bubble.left.and.bubble.right.fill"),
        CatalogEntry(id: "antigravity", name: "Antigravity", category: "Code", appNames: ["Antigravity"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Google sign-in planned", symbol: "arrow.up.circle", markers: [".gemini/antigravity"]),
        CatalogEntry(id: "kiro", name: "Kiro", category: "Code", appNames: ["Kiro"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "AWS sign-in planned", symbol: "chevron.left.forwardslash.chevron.right", markers: [".kiro"]),
        CatalogEntry(id: "lovable", name: "Lovable", category: "Build apps", appNames: ["Lovable"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Credits view planned", symbol: "heart", markers: [".lovable"]),
        CatalogEntry(id: "zed", name: "Zed", category: "Code", appNames: ["Zed"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Zed sign-in planned", symbol: "chevron.left.forwardslash.chevron.right"),
        CatalogEntry(id: "midjourney", name: "Midjourney", category: "Images", appNames: ["Midjourney"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Credits view planned", symbol: "photo"),
        CatalogEntry(id: "elevenlabs", name: "ElevenLabs", category: "Voice", appNames: ["ElevenLabs", "ElevenReader"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Credits view planned", symbol: "waveform"),
        CatalogEntry(id: "suno", name: "Suno", category: "Music", appNames: ["Suno"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Credits view planned", symbol: "music.note"),
        CatalogEntry(id: "runway", name: "Runway", category: "Video", appNames: ["Runway"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Credits view planned", symbol: "film"),
        CatalogEntry(id: "higgsfield", name: "Higgsfield", category: "Video", appNames: ["Higgsfield"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Credits view planned", symbol: "film"),
        CatalogEntry(id: "windsurf", name: "Windsurf", category: "Code", appNames: ["Windsurf"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Windsurf sign-in planned", symbol: "wind", markers: [".codeium/windsurf"]),
        CatalogEntry(id: "ollama", name: "Ollama", category: "Runs on your Mac", appNames: ["Ollama"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Local, so no limits", symbol: "desktopcomputer", markers: [".ollama"]),
        CatalogEntry(id: "lmstudio", name: "LM Studio", category: "Runs on your Mac", appNames: ["LM Studio"],
                     bundleIDs: [], providerID: nil, source: "",
                     hint: "Local, so no limits", symbol: "desktopcomputer"),
    ]

    static func entry(_ id: String) -> CatalogEntry? { all.first { $0.id == id } }
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

    /// Apps that are already covered by another entry, so the scan never lists them on their own.
    /// ChatGPT's limits are Codex's and show under Codex (AK).
    static let coveredElsewhere: Set<String> = ["ChatGPT"]

    static let keywords = ["GPT", "Copilot", "LLM", "Gemini", "Llama", "Mistral", "Grok", "DeepSeek", "Claude", "Perplexity", "Ollama"]

    /// Helper apps that come with AI tools (URL handlers, updaters) are not apps people use.
    static let helperWords = ["URL Handler", "Helper", "Updater", "Uninstall", "Installer", "Launcher", "Crash Reporter"]

    static func looksLikeAI(_ name: String) -> Bool {
        if helperWords.contains(where: { name.range(of: $0, options: .caseInsensitive) != nil }) { return false }
        let tokens = name.components(separatedBy: CharacterSet.alphanumerics.inverted)
        if tokens.contains("AI") { return true }
        return keywords.contains { name.range(of: $0, options: .caseInsensitive) != nil }
    }

    static func scan() -> [AIApp] {
        let apps = installedApps()
        var out: [AIApp] = []
        var usedNames = coveredElsewhere
        for e in Catalog.all {
            var url: URL? = e.appNames.compactMap { apps[$0] }.first
            if url == nil {
                url = e.bundleIDs.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
            }
            let cred = e.providerID.flatMap { Providers.all[$0]?.credentialAvailable() } ?? false
            // Also counts command-line tools that are set up but have no Mac app.
            let marked = e.markers.contains { FileManager.default.fileExists(atPath: homeURL($0).path) }
            if url == nil && !cred && !marked { continue }
            e.appNames.forEach { usedNames.insert($0) }
            let hint = e.providerID != nil && !cred ? e.hint : e.hint
            out.append(AIApp(id: e.id, name: e.name, category: e.category, appURL: url,
                             supported: e.providerID != nil, credentialFound: cred,
                             hint: hint, source: e.source))
        }
        for (name, url) in apps.sorted(by: { $0.key < $1.key }) where !usedNames.contains(name) && looksLikeAI(name) && name.count <= 32 {
            out.append(AIApp(id: "other:" + name, name: name, category: "AI app", appURL: url,
                             supported: false, credentialFound: false,
                             hint: "Not supported yet", source: ""))
        }
        return out
    }
}
