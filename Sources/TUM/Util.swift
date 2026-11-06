import Foundation
import SwiftUI
import AppKit

func homeURL(_ relative: String) -> URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relative)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: alpha)
    }
}

/// Colors come from the system, so they follow Light and Dark Mode, Increase Contrast and
/// the person's accent color. The only fixed colors are the Figma menu bar pill's (`Pill`).
enum Palette {
    static let green = Color.green
    static let accent = Color.accentColor
    static let neutralBlue = Color.accentColor
    static let amberText = Pill.amberText
    static let redText = Pill.redText

    /// The water in a usage circle: blue when fine, and the Figma pill's yellow and red when low.
    static func water(_ l: Level) -> Color {
        // Healthy water is a clear sky blue at the same brightness and strength as the Figma
        // yellow and red (AK: the faded blue looked dull next to them; full system blue was harsh).
        switch l { case .ok: return Pill.blueLiquid; case .low: return Pill.amberLiquid; case .out: return Pill.redLiquid; case .use: return Pill.greenLiquid }
    }
    static func text(_ l: Level) -> Color {
        // The same hues as the water in the circles (AK), so a number and its circle always match.
        switch l { case .ok: return .primary; case .low: return Pill.amberText; case .out: return Pill.redText; case .use: return Pill.greenText }
    }
}

/// The Figma menu bar pill. Brand colors, kept exactly.
enum Pill {
    static let amber = Color(hex: 0xE0A400)
    static let amberTop = Color(hex: 0xE6B42E)
    static let red = Color(hex: 0xC62F35)
    static let redTop = Color(hex: 0xCE494D)
    static let amberLiquid = Color(hex: 0xFFB800)
    static let redLiquid = Color(hex: 0xFF6165)
    static let ink = Color(hex: 0x1C1C1E)
    /// "Use it before it resets" (AK): a glossy green with the same dark ink as amber.
    static let green = Color(hex: 0x30B058)
    static let greenTop = Color(hex: 0x4CC172)
    static let greenLiquid = Color(hex: 0x5EDB82)
    /// Healthy water in the usage circles, matched to the amber and red liquids.
    static let blueLiquid = Color(hex: 0x4FA3FF)

    /// Text in the water colors (AK), readable on TUM's cards in both modes (WCAG AA, 4.5:1 or
    /// more). Dark Mode uses the liquids themselves (red a touch lighter to reach 4.5:1 on a
    /// card); Light Mode uses deeper shades of the same hues.
    static let amberText = adaptive(light: 0x845F00, dark: 0xFFB800)
    static let redText = adaptive(light: 0xB3282E, dark: 0xFF7B7F)
    static let greenText = adaptive(light: 0x1B7536, dark: 0x5EDB82)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        func ns(_ h: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255,
                    blue: CGFloat(h & 0xff) / 255, alpha: 1)
        }
        return Color(nsColor: NSColor(name: nil) { a in
            a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? ns(dark) : ns(light)
        })
    }

    static func colors(_ l: Level) -> (top: Color, base: Color, liquid: Color, ink: Color) {
        switch l {
        case .use: return (greenTop, green, greenLiquid, ink)
        case .out: return (redTop, red, redLiquid, .white)
        default: return (amberTop, amber, amberLiquid, ink)
        }
    }
}

/// Small helpers for reading JSON whose exact shape may change.
enum J {
    static func dig(_ o: Any?, _ path: String...) -> Any? {
        var cur = o
        for p in path {
            guard let d = cur as? [String: Any] else { return nil }
            cur = d[p]
        }
        return cur
    }

    /// A finite number, or nil. "nan" and "inf" (which a string can parse to) are rejected, since
    /// converting them to Int crashes the app (security review L1).
    static func num(_ o: Any?) -> Double? {
        let v: Double?
        if let n = o as? NSNumber { v = n.doubleValue }
        else if let d = o as? Double { v = d }
        else if let i = o as? Int { v = Double(i) }
        else if let s = o as? String { v = Double(s) }
        else { v = nil }
        guard let x = v, x.isFinite else { return nil }
        return x
    }

    /// Depth-first search for the first value whose key matches (case-insensitive).
    static func find(_ o: Any?, keys: [String]) -> Any? {
        let wanted = Set(keys.map { $0.lowercased() })
        func walk(_ x: Any?, depth: Int) -> Any? {
            if depth > 8 { return nil }
            if let d = x as? [String: Any] {
                for (k, v) in d where wanted.contains(k.lowercased()) { return v }
                for (_, v) in d { if let r = walk(v, depth: depth + 1) { return r } }
            } else if let a = x as? [Any] {
                for v in a { if let r = walk(v, depth: depth + 1) { return r } }
            }
            return nil
        }
        return walk(o, depth: 0)
    }

    static func date(_ o: Any?) -> Date? {
        if let s = o as? String {
            if let n = Double(s) { return date(n) }
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f1.date(from: s) { return d }
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            return f2.date(from: s)
        }
        if let n = num(o) {
            if n <= 0 { return nil }
            return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
        }
        return nil
    }

    /// Key paths only (never values) for the diagnostics log. Keys are chosen by the service, so
    /// only plain names are kept: letters, digits, "_", "." and "-", at most 40 long, with no run
    /// of four or more digits and nothing that looks like an id. Anything else becomes "<key>",
    /// so a reply can never put an email, an id or a forged line into the log (security review).
    static func keyPaths(_ o: Any?, prefix: String = "", out: inout [String], limit: Int = 80) {
        if let d = o as? [String: Any] {
            for k in d.keys.sorted() {
                guard out.count < limit else { return }
                let plain = k.range(of: #"^[A-Za-z0-9_.\-]{1,40}$"#, options: .regularExpression) != nil
                    && k.range(of: #"[0-9]{4,}"#, options: .regularExpression) == nil
                    && UUID(uuidString: k) == nil
                    && k.range(of: #"^[0-9a-fA-F\-]{16,}$"#, options: .regularExpression) == nil
                let safe = plain ? k : "<key>"
                let p = prefix.isEmpty ? safe : prefix + "." + safe
                out.append(p)
                keyPaths(d[k], prefix: p, out: &out, limit: limit)
            }
        } else if let a = o as? [Any], let first = a.first {
            keyPaths(first, prefix: prefix + "[]", out: &out, limit: limit)
        }
    }
}

/// Writes HTTP status and JSON key names (never values or tokens) to
/// ~/Library/Logs/TUM/diagnostics.log so broken parsers can be fixed.
enum Diagnostics {
    static let url = homeURL("Library/Logs/TUM/diagnostics.log")
    private static let queue = DispatchQueue(label: "tum.diagnostics")
    private static let maxBytes = 512 * 1024

    private static let maxLine = 2000

    static func log(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(stamp)] \(clean(line))\n"
        queue.async { write(text) }
    }

    /// Writes right away. Used when the app may be about to quit.
    static func logNow(_ line: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = "[\(stamp)] \(clean(line))\n"
        queue.sync { write(text) }
    }

    /// One line of at most 2000 characters, with every control character turned into a space, so
    /// nothing from a reply or an error can forge a log line (security review).
    static func clean(_ s: String) -> String {
        String(s.prefix(maxLine).unicodeScalars.map { ($0.value < 0x20 || $0.value == 0x7F) ? " " : Character($0) })
    }

    /// Only this user can read the log, it is never written through a link, and it never grows
    /// past 512 KB (trimmed at a whole line). Security review L5.
    private static func write(_ text: String) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        let fd = Darwin.open(url.path, O_RDWR | O_APPEND | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        fchmod(fd, 0o600)
        var st = stat()
        if fstat(fd, &st) == 0, st.st_size > off_t(maxBytes) {
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
            lseek(fd, 0, SEEK_SET)
            if let data = try? handle.readToEnd() {
                var keep = data.suffix(maxBytes / 2)
                if let nl = keep.firstIndex(of: 0x0A) { keep = keep[keep.index(after: nl)...] }
                if ftruncate(fd, 0) == 0 {
                    keep.withUnsafeBytes { p in _ = Darwin.write(fd, p.baseAddress, p.count) }
                }
            }
        }
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { p in _ = Darwin.write(fd, p.baseAddress, p.count) }
    }

    static func log(provider: String, status: Int, json: Any?) {
        var keys: [String] = []
        J.keyPaths(json, out: &keys)
        log("\(provider) HTTP \(status) keys: \(keys.joined(separator: ", "))")
    }

    /// A short, safe note about any error for the log: TUM's own error kinds by name, anything
    /// else by domain and code. Never the error's text, which can hold names or paths.
    static func describe(_ error: Error) -> String {
        if let p = error as? ProviderError {
            switch p {
            case .notSignedIn: return "not signed in"
            case .expired: return "expired"
            case .http(let c): return "http \(c)"
            case .format: return "format changed"
            case .rateLimited: return "rate limited"
            case .denied: return "denied"
            case .needsApproval: return "needs approval"
            }
        }
        if error is CancellationError { return "cancelled" }
        let e = error as NSError
        return "\(e.domain) \(e.code)"
    }

    static func contents() -> String {
        (try? String(contentsOf: url)) ?? "No diagnostics yet."
    }
}

enum ProviderError: LocalizedError {
    case notSignedIn(String)
    case expired(String)
    case http(Int)
    case format(String)
    case rateLimited(Date)
    case denied(String)
    /// The Keychain needs the person's OK. Only asked after they click, never in the background.
    case needsApproval

    var errorDescription: String? {
        switch self {
        case .notSignedIn(let m): return m
        case .expired(let m): return m
        case .http(let c): return "This service isn't responding right now (\(c)). TUM will try again."
        case .format(let n): return "\(n) changed how it shows usage. Update TUM to see it again."
        case .rateLimited: return "Checking again in a few minutes."
        case .denied(let m): return m
        case .needsApproval: return "One more click to finish connecting."
        }
    }
}

enum HTTP {
    /// Nothing is cached or stored: no response cache, no cookies, no saved credentials.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.urlCredentialStorage = nil
        c.tlsMinimumSupportedProtocolVersion = .TLSv12
        c.timeoutIntervalForResource = 30   // a whole request never takes longer than this
        return URLSession(configuration: c, delegate: SameHostRedirects(), delegateQueue: nil)
    }()

    static func json(_ req: URLRequest, provider: String) async throws -> Any {
        var r = req
        r.timeoutInterval = 20
        guard r.url?.scheme == "https" else { throw ProviderError.http(0) }
        if r.value(forHTTPHeaderField: "User-Agent") == nil { r.setValue("TUM/0.1 (macOS)", forHTTPHeaderField: "User-Agent") }
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await session.data(for: r)
        // Usage replies are small. Anything huge is not what TUM asked for.
        guard data.count <= 1_000_000 else { throw ProviderError.http(0) }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = try? JSONSerialization.jsonObject(with: data)
        // The Cursor sign-in polls every 2 seconds and gets "not yet" (404 or 202) until the person
        // approves. Those replies would only fill the log.
        if !(provider == "cursor-signin" && (code == 404 || code == 202)) {
            Diagnostics.log(provider: provider, status: code, json: obj)
        }
        // For errors, also note the service's short error code, like "invalid_grant". Free-text
        // messages are never logged: they can hold emails, names or ids (security review M5).
        if !(200..<300).contains(code), let o = obj {
            let reasons = ["code", "error", "type"].compactMap { k -> String? in
                guard let v = J.find(o, keys: [k]) as? String,
                      v.range(of: #"^[A-Za-z0-9_.\-]{1,64}$"#, options: .regularExpression) != nil,
                      v.range(of: #"[0-9]{6,}"#, options: .regularExpression) == nil else { return nil }
                return "\(k)=\(v)"
            }
            if !reasons.isEmpty { Diagnostics.log("\(provider) reason: \(reasons.joined(separator: "; "))") }
        }
        if code == 429 {
            // Honor the service's Retry-After (seconds), never less than 5 minutes or more than a day.
            let after = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 0
            throw ProviderError.rateLimited(Date().addingTimeInterval(min(max(after.isFinite ? after : 0, 300), 86_400)))
        }
        if code == 401 || code == 403 { throw ProviderError.expired("Open the app once, then TUM can check it again.") }
        guard (200..<300).contains(code), let o = obj else { throw ProviderError.http(code) }
        return o
    }
}

/// Follows a redirect only within the same https host and port, so a sign-in token can never be
/// carried to a different site (security review L3).
private final class SameHostRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard let from = task.originalRequest?.url, let to = request.url,
              let fromHost = from.host, fromHost == to.host, to.scheme == "https",
              (from.port ?? 443) == (to.port ?? 443) else { return nil }
        return request
    }
}

/// Checks on files TUM reads, which anything on this Mac could have written.
enum Files {
    /// Far more than any sign-in or settings file needs.
    static let maxReadBytes = 16 * 1024 * 1024

    /// True for a plain file (never a link, a folder or a pipe) of a sane size.
    static func isSmallRegularFile(_ path: String, max: Int = maxReadBytes) -> Bool {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              (a[.type] as? FileAttributeType) == .typeRegular,
              let size = a[.size] as? Int, size <= max else { return false }
        return true
    }
}

/// A value that may go into an HTTP header: printable ASCII only, with a sane length, so a crafted
/// sign-in file can never add headers or break a request (security review).
func headerSafe(_ s: String?, max: Int = 8192) -> String? {
    guard let s = s, !s.isEmpty, s.count <= max,
          s.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7E }) else { return nil }
    return s
}

enum Format {
    static func when(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(d) {
            f.dateFormat = cal.component(.minute, from: d) == 0 ? "h a" : "h:mm a"
            return "at " + f.string(from: d)
        }
        if cal.isDateInTomorrow(d) {
            f.dateFormat = "h a"
            return "tomorrow at " + f.string(from: d)
        }
        if d.timeIntervalSinceNow < 6 * 86400 {
            f.dateFormat = "EEEE"
            return "on " + f.string(from: d)
        }
        f.dateFormat = "MMM d"
        return "on " + f.string(from: d)
    }

    /// "3 PM", "Friday" or "Nov 18" for "may run out before ..."
    static func short(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(d) { f.dateFormat = cal.component(.minute, from: d) == 0 ? "h a" : "h:mm a"; return f.string(from: d) }
        if d.timeIntervalSinceNow < 6 * 86400 { f.dateFormat = "EEEE"; return f.string(from: d) }
        f.dateFormat = "MMM d"; return f.string(from: d)
    }

    static func ago(_ d: Date) -> String {
        let s = -d.timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60)) min ago" }
        return "\(Int(s / 3600)) hr ago"
    }
}
