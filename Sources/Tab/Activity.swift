import Foundation
import AppKit
import CoreServices

/// Watches the folders AI tools write to while you use them, so TAB can check
/// an app right after it was used instead of waiting for the next timer.
/// Only file paths are looked at here. File contents are read only for Codex (see CodexLocal).
final class ActivityWatcher {
    /// Called on the main queue with the app id and the file that changed.
    var onActivity: ((String, URL) -> Void)?

    private var stream: FSEventStreamRef?
    private var roots: [(path: String, id: String)] = []

    static func folders() -> [(path: String, id: String)] {
        let candidates: [(URL, String)] = [
            (homeURL(".claude/projects"), "claude"),
            (homeURL(".config/claude/projects"), "claude"),
            (CodexLocal.sessionsURL, "codex"),
            (homeURL(".gemini/tmp"), "gemini"),
            (homeURL(".grok"), "grok"),
            (homeURL(".grokbot"), "grok"),
            (homeURL("Library/Application Support/Cursor/User/workspaceStorage"), "cursor"),
        ]
        return candidates
            .filter { FileManager.default.fileExists(atPath: $0.0.path) }
            .map { (path: ($0.0.path as NSString).resolvingSymlinksInPath, id: $0.1) }
    }

    /// Starts watching, or restarts if a tool was installed since the last start.
    func start() {
        let now = Self.folders()
        if stream != nil, now.map(\.path) == roots.map(\.path) { return }
        stop()
        roots = now
        guard !roots.isEmpty else { return }

        var ctx = FSEventStreamContext(version: 0,
                                       info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info = info else { return }
            let me = Unmanaged<ActivityWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as? [String]) ?? []
            me.handle(list)
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagIgnoreSelf)
        guard let s = FSEventStreamCreate(kCFAllocatorDefault, callback, &ctx,
                                          roots.map(\.path) as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                          2.0, flags) else { return }
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
        stream = s
        Diagnostics.log("watching activity for: \(Set(roots.map(\.id)).sorted().joined(separator: ", "))")
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func handle(_ paths: [String]) {
        var seen = Set<String>()
        for p in paths {
            guard let root = roots.first(where: { p.hasPrefix($0.path + "/") }) else { continue }
            if p.hasSuffix(".lock") || p.contains("/.DS_Store") { continue }
            // Report each app once per batch, using its most recent file.
            if seen.insert(root.id).inserted || root.id == "codex" {
                onActivity?(root.id, URL(fileURLWithPath: p))
            }
        }
    }

    deinit { stop() }
}

/// Codex writes its own usage numbers into each session file as you work,
/// so TAB can read them on your Mac without contacting OpenAI.
enum CodexLocal {
    static var home: URL {
        if let h = ProcessInfo.processInfo.environment["CODEX_HOME"] { return URL(fileURLWithPath: h) }
        return homeURL(".codex")
    }
    static var sessionsURL: URL { home.appendingPathComponent("sessions") }

    /// Newest usage reading from the hinted file or today's and yesterday's sessions.
    static func latest(hint: URL?) -> (limits: [UsageLimit], at: Date)? {
        var files: [URL] = []
        if let h = hint, h.pathExtension == "jsonl" { files.append(h) }
        if let n = newestSession(), !files.contains(n) { files.append(n) }
        var best: (limits: [UsageLimit], at: Date)? = nil
        for f in files {
            if let r = read(f), best == nil || r.at > best!.at { best = r }
        }
        return best
    }

    private static func newestSession() -> URL? {
        let fm = FileManager.default
        let cal = Calendar.current
        var best: (url: URL, date: Date)? = nil
        for back in 0...1 {
            guard let day = cal.date(byAdding: .day, value: -back, to: Date()) else { continue }
            let c = cal.dateComponents([.year, .month, .day], from: day)
            guard let y = c.year, let m = c.month, let d = c.day else { continue }
            let dir = sessionsURL.appendingPathComponent(String(format: "%04d/%02d/%02d", y, m, d))
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for u in items where u.pathExtension == "jsonl" {
                let mod = (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if best == nil || mod > best!.date { best = (u, mod) }
            }
        }
        return best?.url
    }

    /// Reads only the end of the file and only the usage line. Chat text is skipped.
    static func read(_ url: URL) -> (limits: [UsageLimit], at: Date)? {
        // A plain file only (never a pipe or a link), so reading can't hang or wander off.
        guard Files.isSmallRegularFile(url.path, max: 2 * 1024 * 1024 * 1024),
              let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let size = try? h.seekToEnd() else { return nil }
        let chunk: UInt64 = 512 * 1024
        try? h.seek(toOffset: size > chunk ? size - chunk : 0)
        guard let data = try? h.readToEnd() else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()

        for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\"") {
            guard let d = String(line).data(using: .utf8),
                  let o = try? JSONSerialization.jsonObject(with: d),
                  let rl = J.find(o, keys: ["rate_limits"]), !(rl is NSNull) else { continue }
            // Never later than the file itself or now, so a wrong timestamp can't freeze the numbers.
            let at = min(J.date(J.dig(o, "timestamp")) ?? modified, modified, Date())
            let limits = CodexProvider.limits(from: rl, base: at)
            if !limits.isEmpty { return (limits, at) }
        }
        return nil
    }
}
