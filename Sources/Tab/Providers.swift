import Foundation
import SQLite3
import Security
import CommonCrypto
import CryptoKit
import LocalAuthentication
import AppKit

/// One AI service TAB can read. Like OpenUsage, TAB uses the sign-in each app already
/// keeps on this Mac, so nobody signs in again. Tokens are sent only to that company.
protocol UsageProvider {
    var id: String { get }
    func credentialAvailable() -> Bool
    func fetch() async throws -> [UsageLimit]
    /// `interactive` is true only right after the person clicked Connect or Allow.
    /// Only then may macOS show a Keychain prompt.
    func fetch(interactive: Bool) async throws -> [UsageLimit]
}

extension UsageProvider {
    func fetch() async throws -> [UsageLimit] { try await fetch(interactive: false) }
}

/// Reads a sign-in or settings file. Only a plain file of a sane size is loaded, never a link or
/// something huge (security review).
private func readJSONFile(_ url: URL) -> Any? {
    guard Files.isSmallRegularFile(url.path), let d = try? Data(contentsOf: url) else { return nil }
    return try? JSONSerialization.jsonObject(with: d)
}

private func readSmallText(_ url: URL) -> String? {
    guard Files.isSmallRegularFile(url.path), let d = try? Data(contentsOf: url) else { return nil }
    return String(data: d, encoding: .utf8)
}

private func clampLeft(used: Double) -> Double { max(0, min(100, 100 - used)) }

// MARK: Shared helpers

enum JWT {
    static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var b = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        guard let d = Data(base64Encoded: b) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func expiry(_ token: String) -> Date? {
        J.num(payload(token)?["exp"]).map { Date(timeIntervalSince1970: $0) }
    }

    /// True when the token expires within `margin` seconds.
    static func expiresSoon(_ token: String, margin: TimeInterval = 300) -> Bool {
        guard let e = expiry(token) else { return false }
        return e.timeIntervalSinceNow <= margin
    }
}

/// Keychain reads that never show a prompt unless the person just clicked something.
enum Keychain {
    /// Background (silent) reads are off until onboarding is finished, so nothing can ask for
    /// Keychain access before TAB has explained why. Only a Connect or Allow click reads earlier.
    static var silentReadsAllowed = false
    private static let uiLock = NSLock()

    static func read(service: String, account: String? = nil, interactive: Bool) -> (status: OSStatus, data: Data?) {
        if !interactive && !silentReadsAllowed { return (errSecInteractionNotAllowed, nil) }
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        if let a = account { q[kSecAttrAccount as String] = a }
        var out: CFTypeRef?
        if interactive {
            let status = SecItemCopyMatching(q as CFDictionary, &out)
            return (status, out as? Data)
        }
        // Silent: fail instead of showing a dialog, for both kinds of Keychain item
        // (the older "allow access" dialog ignores the LAContext setting on its own).
        let ctx = LAContext()
        ctx.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = ctx
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        uiLock.lock(); defer { uiLock.unlock() }
        var was: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&was)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(was.boolValue) }
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        return (status, out as? Data)
    }

    /// Reads an internet password (the kind Zed keeps) with its account name. Same rules as `read`:
    /// silent unless the person just clicked, and nothing before onboarding is done.
    static func readInternet(server: String, interactive: Bool) -> (status: OSStatus, account: String?, data: Data?) {
        if !interactive && !silentReadsAllowed { return (errSecInteractionNotAllowed, nil, nil) }
        var q: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                kSecAttrServer as String: server,
                                kSecReturnData as String: true,
                                kSecReturnAttributes as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var out: CFTypeRef?
        let status: OSStatus
        if interactive {
            status = SecItemCopyMatching(q as CFDictionary, &out)
        } else {
            let ctx = LAContext()
            ctx.interactionNotAllowed = true
            q[kSecUseAuthenticationContext as String] = ctx
            q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
            uiLock.lock(); defer { uiLock.unlock() }
            var was: DarwinBoolean = true
            SecKeychainGetUserInteractionAllowed(&was)
            SecKeychainSetUserInteractionAllowed(false)
            defer { SecKeychainSetUserInteractionAllowed(was.boolValue) }
            status = SecItemCopyMatching(q as CFDictionary, &out)
        }
        let item = out as? [String: Any]
        return (status, item?[kSecAttrAccount as String] as? String, item?[kSecValueData as String] as? Data)
    }

    /// Checks an internet password exists without reading its secret. Never prompts.
    static func internetExists(server: String) -> Bool {
        quietlyExists([kSecClass as String: kSecClassInternetPassword,
                       kSecAttrServer as String: server,
                       kSecReturnAttributes as String: true,
                       kSecMatchLimit as String: kSecMatchLimitOne])
    }

    /// Checks an item exists without reading its secret. Never prompts.
    static func exists(service: String) -> Bool {
        quietlyExists([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecReturnAttributes as String: true,
                       kSecMatchLimit as String: kSecMatchLimitOne])
    }

    /// Looks for an item with every prompt turned off, so even a locked keychain can't ask
    /// (these checks run during scans, before onboarding is done).
    private static func quietlyExists(_ query: [String: Any]) -> Bool {
        var q = query
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        uiLock.lock(); defer { uiLock.unlock() }
        var was: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&was)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(was.boolValue) }
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess
    }

    /// Changes one of TAB's own items. In the background (`interactive` false) macOS may never
    /// ask; the change just fails and the caller sees the status (security review L8).
    static func update(service: String, account: String? = nil, data: Data, interactive: Bool) -> OSStatus {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let a = account { q[kSecAttrAccount as String] = a }
        let change = [kSecValueData as String: data] as CFDictionary
        if interactive { return SecItemUpdate(q as CFDictionary, change) }
        q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        uiLock.lock(); defer { uiLock.unlock() }
        var was: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&was)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(was.boolValue) }
        return SecItemUpdate(q as CFDictionary, change)
    }

    /// Deletes one of TAB's own items and says whether it worked.
    static func delete(service: String) -> OSStatus {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary)
    }

    // MARK: TAB's own items (TAB was called TUM until 2026-11-06)

    /// The name one of TAB's own items had before the rename ("TUM Cursor sign-in").
    static func oldName(_ service: String) -> String? {
        service.hasPrefix("TAB ") ? "TUM " + service.dropFirst(4) : nil
    }

    /// Old TUM items that must never be used again: already moved, or removed by the person.
    /// Kept in settings, so an old item macOS wouldn't let TAB delete can never come back.
    static let retiredKey = "retiredOldSignIns"
    private static let retiredLock = NSLock()
    static var retiredStore: UserDefaults = .standard

    static func isRetired(_ old: String) -> Bool {
        retiredLock.lock(); defer { retiredLock.unlock() }
        return retiredStore.stringArray(forKey: retiredKey)?.contains(old) ?? false
    }

    private static func retire(_ old: String) {
        retiredLock.lock(); defer { retiredLock.unlock() }
        var list = retiredStore.stringArray(forKey: retiredKey) ?? []
        if !list.contains(old) { list.append(old); retiredStore.set(list, forKey: retiredKey) }
    }

    /// The old item's name, if one may still be used.
    private static func usableOld(_ service: String) -> String? {
        guard let old = oldName(service), !isRetired(old) else { return nil }
        return old
    }

    /// Whether one of TAB's own items exists, under its new or old name. Never prompts.
    static func ownExists(service: String) -> Bool {
        exists(service: service) || (usableOld(service).map { exists(service: $0) } ?? false)
    }

    /// Reads one of TAB's own items. When only the old TUM item is there, it is copied to the
    /// new name and the old one retired and removed, so nothing needs reconnecting. Same rules
    /// as `read`: silent unless the person just clicked, and nothing before onboarding is done.
    /// A Remove that happens during the move wins: the new copy is deleted again.
    static func readOwn(service: String, account: String, interactive: Bool) -> (status: OSStatus, data: Data?) {
        let r = read(service: service, account: account, interactive: interactive)
        guard r.status == errSecItemNotFound, let old = usableOld(service), exists(service: old) else { return r }
        let o = read(service: old, account: account, interactive: interactive)
        guard o.status == errSecSuccess, let data = o.data else {
            // Cursor and Grok Bot share one item. If the other reader just moved it, use that.
            if o.status == errSecItemNotFound { return read(service: service, account: account, interactive: interactive) }
            return o
        }
        guard !isRetired(old) else { return (errSecItemNotFound, nil) }   // removed while macOS asked
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecAttrLabel as String: service,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                  kSecValueData as String: data]
        let added = SecItemAdd(add as CFDictionary, nil)
        if isRetired(old) {
            // Removed between the check and the add: undo the copy.
            if added == errSecSuccess { _ = delete(service: service) }
            return (errSecItemNotFound, nil)
        }
        if added == errSecSuccess || added == errSecDuplicateItem {
            retire(old)
            quietDelete(service: old)
        }
        Diagnostics.log(added == errSecSuccess ? "keychain: moved a sign-in to its TAB name" : "keychain: move status \(added)")
        return (errSecSuccess, data)
    }

    /// Deletes one of TAB's own items under both names. The old name is retired first, so even
    /// if macOS keeps the old item, TAB never uses it again.
    static func deleteOwn(service: String) -> OSStatus {
        if let old = oldName(service) { retire(old); quietDelete(service: old) }
        return delete(service: service)
    }

    /// Deletes an item with every prompt turned off. If macOS wants to ask, it just stays.
    private static func quietDelete(service: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
        uiLock.lock(); defer { uiLock.unlock() }
        var was: DarwinBoolean = true
        SecKeychainGetUserInteractionAllowed(&was)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(was.boolValue) }
        let status = SecItemDelete(q as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound { Diagnostics.log("keychain: old item stays (\(status))") }
    }

    static func isPermissionProblem(_ s: OSStatus) -> Bool {
        s == errSecInteractionNotAllowed || s == errSecAuthFailed || s == errSecUserCanceled
    }
}

/// Reads one value from an app's SQLite database without locking or changing it.
/// Apps like Cursor keep their newest data in a "-wal" side file until it is merged, so
/// reading the main file alone can return an old, already-replaced sign-in. TAB copies the
/// database with its side files into a private temporary folder, reads the copy (which
/// includes the newest data), and deletes the copy right away.
enum SQLiteRead {
    private static let folderPrefix = "tab-db-"
    private static let maxBytes = 64 * 1024 * 1024

    /// Deletes copies a crash may have left behind (they hold a copy of another app's database).
    /// Only TAB's own "tab-db-" folders, nothing else in the temporary folder.
    static func sweepLeftovers() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil) else { return }
        for u in items where u.lastPathComponent.hasPrefix(folderPrefix) { try? fm.removeItem(at: u) }
    }

    static func value(path: String, sql: String) -> Data? {
        let fm = FileManager.default
        // Only a plain file of a sane size, never a link into something else (security review L7).
        guard Files.isSmallRegularFile(path, max: maxBytes) else { return nil }
        let tmp = fm.temporaryDirectory.appendingPathComponent(folderPrefix + UUID().uuidString, isDirectory: true)
        guard (try? fm.createDirectory(at: tmp, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil else { return nil }
        defer { try? fm.removeItem(at: tmp) }
        let copy = tmp.appendingPathComponent("db.sqlite")
        for suffix in ["", "-wal", "-shm"] where Files.isSmallRegularFile(path + suffix, max: maxBytes) {
            try? fm.copyItem(atPath: path + suffix, toPath: copy.path + suffix)
        }
        guard fm.fileExists(atPath: copy.path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOFOLLOW, nil) == SQLITE_OK else {
            sqlite3_close(db); return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 500)
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(st) }
        guard sqlite3_step(st) == SQLITE_ROW else { return nil }
        let n = Int(sqlite3_column_bytes(st, 0))
        guard n > 0, let p = sqlite3_column_blob(st, 0) else { return nil }
        return Data(bytes: p, count: n)
    }

}

private func formBody(_ pairs: [(String, String)]) -> Data {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
    return pairs.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
        .joined(separator: "&").data(using: .utf8) ?? Data()
}

// MARK: Claude (Claude desktop app, then Claude Code)

struct ClaudeProvider: UsageProvider {
    let id = "claude"
    static let codeService = "Claude Code-credentials"

    private var codeFile: URL {
        if let d = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] { return URL(fileURLWithPath: d).appendingPathComponent(".credentials.json") }
        return homeURL(".claude/.credentials.json")
    }

    func credentialAvailable() -> Bool {
        ClaudeDesktop.hasMaterial() || Keychain.exists(service: Self.codeService) || FileManager.default.fileExists(atPath: codeFile.path)
    }

    func fetch(interactive: Bool) async throws -> [UsageLimit] {
        var lastError: Error = ProviderError.notSignedIn("Open the Claude app or Claude Code once, then try again.")

        // 1. The Claude desktop app keeps its own session fresh while you use it. Read-only.
        if ClaudeDesktop.hasMaterial() {
            do {
                let token = try ClaudeDesktop.accessToken(interactive: interactive)
                return try await Self.usage(token: token)
            } catch { lastError = error; Diagnostics.log("claude desktop: \(Diagnostics.describe(error))") }
        }

        // 2. Claude Code's sign-in, read only. TAB never renews another app's sign-in: renewing
        // spends its refresh token and can sign the person out of Claude Code (security review M1).
        // When it has expired, opening Claude Code renews it and TAB picks up the fresh one.
        do {
            let cred = try loadCode(interactive: interactive)
            if cred.expired { throw ProviderError.expired("Open Claude Code or the Claude app once, then TAB can check it again.") }
            do { return try await Self.usage(token: cred.accessToken) }
            catch ProviderError.http(401) {
                throw ProviderError.expired("Open Claude Code or the Claude app once, then TAB can check it again.")
            }
        } catch ProviderError.needsApproval {
            throw ProviderError.needsApproval
        } catch {
            if case ProviderError.notSignedIn = error, ClaudeDesktop.hasMaterial() { throw lastError }
            throw error
        }
    }

    private struct CodeCredential {
        var document: [String: Any]
        var fromKeychain: Bool
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
        var expired: Bool { (expiresAt ?? .distantFuture).timeIntervalSinceNow < 120 }
    }

    private func loadCode(interactive: Bool) throws -> CodeCredential {
        var doc: [String: Any]? = nil
        var fromKeychain = false
        let r = Keychain.read(service: Self.codeService, interactive: interactive)
        if r.status == errSecSuccess, let d = r.data {
            doc = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
            fromKeychain = doc != nil
        } else if Keychain.isPermissionProblem(r.status), !FileManager.default.fileExists(atPath: codeFile.path) {
            throw interactive ? ProviderError.denied("macOS didn't let TAB check this app. Try again and choose Always Allow.") : ProviderError.needsApproval
        }
        if doc == nil { doc = readJSONFile(codeFile) as? [String: Any] }
        guard let d = doc, let o = d["claudeAiOauth"] as? [String: Any],
              let tok = o["accessToken"] as? String, !tok.isEmpty else {
            throw ProviderError.notSignedIn("Open the Claude app or Claude Code once, then try again.")
        }
        return CodeCredential(document: d, fromKeychain: fromKeychain, accessToken: tok,
                              refreshToken: o["refreshToken"] as? String, expiresAt: J.date(o["expiresAt"]))
    }

    static func usage(token: String) async throws -> [UsageLimit] {
        guard let token = headerSafe(token) else { throw ProviderError.notSignedIn("Open the Claude app or Claude Code once, then try again.") }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-cli/2.1.294 (external, cli)", forHTTPHeaderField: "User-Agent")
        let o = try await HTTP.json(req, provider: "claude")
        let out = parse(o)
        if out.isEmpty { throw ProviderError.format("Claude") }
        return out
    }

    static func parse(_ o: Any) -> [UsageLimit] {
        var out: [UsageLimit] = []
        if let u = J.num(J.dig(o, "five_hour", "utilization")) {
            out.append(UsageLimit(kind: .short, label: "5 hours", percentLeft: clampLeft(used: u),
                                  resetsAt: J.date(J.dig(o, "five_hour", "resets_at"))))
        }
        if let u = J.num(J.dig(o, "seven_day", "utilization")) {
            out.append(UsageLimit(kind: .long, label: "Week", percentLeft: clampLeft(used: u),
                                  resetsAt: J.date(J.dig(o, "seven_day", "resets_at"))))
        }
        return out
    }
}

/// The Claude desktop app's saved session. It is encrypted with a key the app keeps in the
/// Keychain ("Claude Safe Storage"), the standard way Electron apps protect saved data.
/// TAB only borrows a still-valid token and never changes anything the app stores.
enum ClaudeDesktop {
    private static var dir: URL { homeURL("Library/Application Support/Claude") }
    private static let keyService = "Claude Safe Storage"
    private static let keyAccount = "Claude Key"
    private static let apiHost = "https://api.anthropic.com"
    private static var cachedKey: Data?
    private static let lock = NSLock()

    /// Forgets the cached key, when Claude is removed in TAB.
    static func forget() { lock.lock(); cachedKey = nil; lock.unlock() }

    private static func config() -> [String: Any]? {
        readJSONFile(dir.appendingPathComponent("config.json")) as? [String: Any]
    }

    static func hasMaterial() -> Bool {
        guard let c = config() else { return false }
        return c["oauth:tokenCacheV2"] is String || c["oauth:tokenCache"] is String
    }

    static func accessToken(interactive: Bool) throws -> String {
        guard let c = config() else { throw ProviderError.notSignedIn("Open the Claude app and sign in, then try again.") }
        let key = try safeStorageKey(interactive: interactive)
        let account = (c["lastKnownAccountUuid"] as? String)?.lowercased()
        let org = activeOrganization(key: key)
        var best: (token: String, rank: (Int, Int, Double))? = nil
        for cacheKey in ["oauth:tokenCacheV2", "oauth:tokenCache"] {
            guard let b64 = c[cacheKey] as? String, let enc = Data(base64Encoded: b64),
                  let plain = try? decrypt(enc, key: key),
                  let cache = (try? JSONSerialization.jsonObject(with: plain)) as? [String: Any] else { continue }
            for (rawKey, value) in cache {
                var k = rawKey
                if rawKey.hasPrefix("acct:") {
                    guard let bar = rawKey.firstIndex(of: "|") else { continue }
                    let owner = String(rawKey.dropFirst(5)[..<bar]).lowercased()
                    if let a = account, owner != a { continue }
                    k = String(rawKey[rawKey.index(after: bar)...])
                }
                guard let range = k.range(of: ":\(apiHost):") else { continue }
                let head = k[..<range.lowerBound]
                guard let colon = head.firstIndex(of: ":") else { continue }
                let client = String(head[..<colon]).lowercased()
                let entryOrg = String(head[head.index(after: colon)...]).lowercased()
                let scopes = k[range.upperBound...].split(whereSeparator: \.isWhitespace).map(String.init)
                guard scopes.contains("user:profile") else { continue }
                if let o = org, entryOrg != o { continue }
                guard let e = value as? [String: Any], let tok = e["token"] as? String, !tok.isEmpty,
                      let exp = J.num(e["expiresAt"]), exp > Date().timeIntervalSince1970 * 1000 + 120_000 else { continue }
                let full = scopes.contains("user:inference")
                let rank = ((client == "9d1c250a-e61b-44d9-88ed-5944d1962f5e" && full) ? 1 : 0, full ? 1 : 0, exp)
                if best == nil || rank > best!.rank { best = (tok, rank) }
            }
            if best != nil { break }
        }
        guard let t = best?.token else { throw ProviderError.expired("Open the Claude app once, then TAB can check it again.") }
        return t
    }

    private static func safeStorageKey(interactive: Bool) throws -> Data {
        lock.lock(); let cached = cachedKey; lock.unlock()
        if let k = cached { return k }
        let r = Keychain.read(service: keyService, account: keyAccount, interactive: interactive)
        if Keychain.isPermissionProblem(r.status) {
            throw interactive ? ProviderError.denied("macOS didn't let TAB check this app. Try again and choose Always Allow.") : ProviderError.needsApproval
        }
        guard r.status == errSecSuccess, let d = r.data, let password = String(data: d, encoding: .utf8), !password.isEmpty else {
            throw ProviderError.notSignedIn("Open the Claude app and sign in, then try again.")
        }
        let key = try deriveKey(password)
        lock.lock(); cachedKey = key; lock.unlock()
        return key
    }

    static func deriveKey(_ password: String) throws -> Data {
        let pw = Data(password.utf8), salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let n = key.count
        let rc = key.withUnsafeMutableBytes { kb in
            pw.withUnsafeBytes { pb in
                salt.withUnsafeBytes { sb in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         pb.bindMemory(to: Int8.self).baseAddress, pw.count,
                                         sb.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                         kb.bindMemory(to: UInt8.self).baseAddress, n)
                }
            }
        }
        guard rc == kCCSuccess else { throw ProviderError.format("Claude") }
        return key
    }

    static func decrypt(_ enc: Data, key: Data) throws -> Data {
        guard enc.count > 3, enc.prefix(3) == Data("v10".utf8) else { throw ProviderError.format("Claude") }
        let payload = Data(enc.dropFirst(3))
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var out = Data(count: payload.count + kCCBlockSizeAES128)
        var outLen = 0
        let cap = out.count
        let status = out.withUnsafeMutableBytes { ob in
            payload.withUnsafeBytes { pb in
                key.withUnsafeBytes { kb in
                    iv.withUnsafeBytes { ib in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                                kb.baseAddress, key.count, ib.baseAddress, pb.baseAddress, payload.count,
                                ob.baseAddress, cap, &outLen)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw ProviderError.format("Claude") }
        return out.prefix(outLen)
    }

    /// The organization the app is currently using, from its "lastActiveOrg" cookie.
    private static func activeOrganization(key: Data) -> String? {
        for rel in ["Cookies", "Network/Cookies"] {
            let path = dir.appendingPathComponent(rel).path
            for host in [".claude.ai", "claude.ai"] {
                let sql = "SELECT CASE WHEN length(value) > 0 THEN CAST(value AS BLOB) ELSE encrypted_value END FROM cookies WHERE name = 'lastActiveOrg' AND host_key = '\(host)' ORDER BY last_update_utc DESC LIMIT 1"
                guard var raw = SQLiteRead.value(path: path, sql: sql) else { continue }
                if raw.prefix(3) == Data("v10".utf8) {
                    guard var plain = try? decrypt(raw, key: key) else { continue }
                    let hash = Data(SHA256.hash(data: Data(host.utf8)))
                    if plain.starts(with: hash) { plain = plain.dropFirst(hash.count) }
                    raw = Data(plain)
                }
                if let s = String(data: raw, encoding: .utf8), UUID(uuidString: s) != nil { return s.lowercased() }
            }
        }
        return nil
    }
}

// MARK: Codex (Codex sign-in: 5 hour + weekly)

struct CodexProvider: UsageProvider {
    let id = "codex"
    private static let keychainService = "Codex Auth"

    private var home: URL {
        if let h = ProcessInfo.processInfo.environment["CODEX_HOME"] { return URL(fileURLWithPath: h) }
        return homeURL(".codex")
    }
    private var file: URL { home.appendingPathComponent("auth.json") }

    /// Codex CLI's Keychain account name for a home folder ("cli|" + first 8 bytes of SHA-256 of its real path).
    private var keychainAccount: String {
        let real = (home.path as NSString).resolvingSymlinksInPath
        return "cli|" + SHA256.hash(data: Data(real.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func credentialAvailable() -> Bool {
        FileManager.default.fileExists(atPath: file.path) || Keychain.exists(service: Self.keychainService)
    }

    func fetch(interactive: Bool) async throws -> [UsageLimit] {
        let (doc, _) = try load(interactive: interactive)
        guard let tokens = doc["tokens"] as? [String: Any], let access = tokens["access_token"] as? String, !access.isEmpty else {
            throw ProviderError.notSignedIn("Open Codex and sign in, then try again.")
        }
        // Read only: TAB never renews Codex's sign-in, which could sign the person out of Codex
        // (security review M1). Codex renews it itself; its local session files cover the gap.
        do {
            return try await usage(access: access, account: headerSafe(tokens["account_id"] as? String, max: 128))
        } catch ProviderError.http(401) {
            throw ProviderError.expired("Open Codex once, then TAB can check it again.")
        }
    }

    private func load(interactive: Bool) throws -> ([String: Any], Bool) {
        if let d = readJSONFile(file) as? [String: Any] { return (d, false) }
        let r = Keychain.read(service: Self.keychainService, account: keychainAccount, interactive: interactive)
        if r.status == errSecSuccess, let data = r.data, let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] { return (d, true) }
        if Keychain.isPermissionProblem(r.status) { throw interactive ? ProviderError.denied("macOS didn't let TAB check this app. Try again and choose Always Allow.") : ProviderError.needsApproval }
        throw ProviderError.notSignedIn("Open Codex and sign in, then try again.")
    }

    private func usage(access: String, account: String?) async throws -> [UsageLimit] {
        guard let access = headerSafe(access) else { throw ProviderError.notSignedIn("Open Codex and sign in, then try again.") }
        var req = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        req.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
        if let a = account { req.setValue(a, forHTTPHeaderField: "ChatGPT-Account-Id") }
        let r = try await HTTP.json(req, provider: id)
        let limits = Self.limits(from: J.find(r, keys: ["rate_limit", "rate_limits"]) ?? r, base: Date())
        if limits.isEmpty { throw ProviderError.format("Codex") }
        return limits
    }

    /// Shared by the network reading and the local session file reading.
    static func limits(from rl: Any, base: Date) -> [UsageLimit] {
        var windows: [(seconds: Double, used: Double, reset: Date?)] = []
        for key in ["primary_window", "primary", "secondary_window", "secondary"] {
            guard let w = J.dig(rl, key) as? [String: Any] else { continue }
            let used = J.num(w["used_percent"]) ?? 0      // left out by the service when it's 0
            let secs = J.num(w["limit_window_seconds"]) ?? J.num(w["window_minutes"]).map { $0 * 60 } ?? 0
            var reset = J.date(w["reset_at"]) ?? J.date(w["resets_at"])
            if reset == nil, let after = J.num(w["reset_after_seconds"]) ?? J.num(w["resets_in_seconds"]) {
                reset = base.addingTimeInterval(after)
            }
            windows.append((secs, used, reset))
        }
        windows.sort { $0.seconds < $1.seconds }
        return windows.enumerated().map { (i, w) in
            let kind: LimitKind = windows.count == 1 ? (w.seconds >= 6 * 86400 ? .long : .only) : (i == 0 ? .short : .long)
            return UsageLimit(kind: kind, label: Self.label(seconds: w.seconds), percentLeft: clampLeft(used: w.used), resetsAt: w.reset)
        }
    }

    static func label(seconds: Double) -> String {
        if seconds <= 0 { return "Limit" }
        let h = seconds / 3600
        if h < 24 { return "\(Int(h.rounded())) hours" }
        let d = h / 24
        if d >= 6 && d <= 8 { return "Week" }
        if d >= 27 { return "Month" }
        return "\(Int(d.rounded())) days"
    }
}

// MARK: Cursor (Cursor app sign-in) and Grok Bot (Cursor's agent app, same sign-in)

/// The sign-in the Cursor app (and Grok Bot) keep on this Mac. Newer Cursor versions keep the
/// live sign-in in the Keychain and can leave an old one in their database, so TAB tries every
/// place in turn and keeps whichever works. A renewed token stays in memory only.
/// TAB's own Cursor sign-in, used by Cursor and Grok Bot.
/// Current Cursor versions keep a sign-in on disk that other apps can't use, so TAB signs in
/// the way Cursor's own command-line tool does: it opens cursor.com in the browser, the person
/// approves once, and TAB picks up the result (PKCE, so nothing usable travels in the link).
/// The token lives only in TAB's own Keychain item, is renewed before it ends (60 days), and is
/// deleted when the person removes both Cursor and Grok Bot. TAB never reads Cursor's files.
enum CursorAuth {
    static let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    static let service = "TAB Cursor sign-in"
    private static let account = "cursor"
    private static let server = URL(string: "https://api2.cursor.sh")!
    private static var working: String?
    private static let lock = NSLock()
    /// Counts sign-outs, so a renewal that was already running when the person removed Cursor
    /// never saves its result and brings the sign-in back (security review).
    private static var generation = 0

    private struct Tokens: Codable { var access: String; var refresh: String }

    private static func currentGeneration() -> Int { lock.lock(); defer { lock.unlock() }; return generation }
    private static func currentWorking() -> String? { lock.lock(); defer { lock.unlock() }; return working }

    /// Remembers the token that works, unless a sign-out happened since `gen` was read.
    private static func setWorking(_ token: String?, ifGeneration gen: Int) {
        lock.lock(); defer { lock.unlock() }
        if generation == gen { working = token }
    }

    // MARK: Sign-in

    /// Opens Cursor's sign-in page in the browser and waits (up to 5 minutes) for the person
    /// to approve. Saves the result in TAB's Keychain item. Cancelling the task stops waiting.
    static func signIn(open: (URL) -> Void = { NSWorkspace.shared.open($0) }) async throws {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw ProviderError.http(0) }
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let uuid = UUID().uuidString.lowercased()
        var page = URLComponents(string: "https://cursor.com/loginDeepControl")!
        page.queryItems = [URLQueryItem(name: "challenge", value: challenge), URLQueryItem(name: "uuid", value: uuid),
                           URLQueryItem(name: "mode", value: "login"), URLQueryItem(name: "redirectTarget", value: "cli")]
        guard let pageURL = page.url else { throw ProviderError.http(0) }
        Diagnostics.log("cursor sign-in: opened the browser")
        open(pageURL)

        var poll = URLComponents(url: server.appendingPathComponent("auth/poll"), resolvingAgainstBaseURL: false)!
        poll.queryItems = [URLQueryItem(name: "uuid", value: uuid), URLQueryItem(name: "verifier", value: verifier)]
        let deadline = Date().addingTimeInterval(300)
        let gen = currentGeneration()
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            do {
                let r = try await HTTP.json(URLRequest(url: poll.url!), provider: "cursor-signin")
                if let a = headerSafe(J.find(r, keys: ["accessToken"]) as? String) {
                    let rt = headerSafe(J.find(r, keys: ["refreshToken"]) as? String) ?? a
                    guard save(Tokens(access: a, refresh: rt), interactive: true) else {
                        throw ProviderError.denied("TAB couldn't finish signing in. Try again.")
                    }
                    Diagnostics.log("cursor sign-in: done, token \(describe(a))")
                    setWorking(a, ifGeneration: gen)
                    return
                }
            } catch ProviderError.http(let code) where code == 404 || code == 202 || code == 0 {
                continue   // not approved yet
            } catch ProviderError.expired, ProviderError.rateLimited {
                throw ProviderError.notSignedIn("Cursor didn't accept the sign-in. Click Try again.")
            } catch let e as URLError where e.code != .cancelled {
                continue   // brief network trouble; keep waiting
            }
        }
        throw ProviderError.notSignedIn("That took too long. Click Try again to sign in.")
    }

    /// Whether TAB has its own Cursor sign-in. Never reads the secret and never prompts.
    static var signedIn: Bool { Keychain.ownExists(service: service) }

    /// Deletes TAB's Cursor sign-in (when both Cursor and Grok Bot are removed).
    static func signOut() {
        let status = Keychain.deleteOwn(service: service)
        lock.lock(); working = nil; generation += 1; lock.unlock()
        Diagnostics.log(status == errSecSuccess || status == errSecItemNotFound
                        ? "cursor sign-in: removed" : "cursor sign-in: remove failed (\(status))")
    }

    /// Cursor and Grok Bot can always be connected: the sign-in happens in the browser.
    static func available() -> Bool { true }

    // MARK: Keychain

    private static func load(interactive: Bool) throws -> Tokens {
        let r = Keychain.readOwn(service: service, account: account, interactive: interactive)
        if Keychain.isPermissionProblem(r.status) {
            throw interactive ? ProviderError.denied("macOS didn't let TAB check this app. Try again and choose Always Allow.") : ProviderError.needsApproval
        }
        guard r.status == errSecSuccess, let d = r.data else {
            throw ProviderError.notSignedIn("Click Connect to sign in to Cursor.")
        }
        guard let t = try? JSONDecoder().decode(Tokens.self, from: d), headerSafe(t.access) != nil, headerSafe(t.refresh) != nil else {
            // Unreadable: drop it, so the next Connect signs in again instead of failing forever.
            Diagnostics.log("cursor sign-in: stored item unreadable, removing it")
            signOut()
            throw ProviderError.notSignedIn("Click Connect to sign in to Cursor.")
        }
        return t
    }

    private static func save(_ t: Tokens, interactive: Bool) -> Bool {
        guard let data = try? JSONEncoder().encode(t) else { return false }
        let updated = Keychain.update(service: service, account: account, data: data, interactive: interactive)
        if updated == errSecSuccess { return true }
        if updated != errSecItemNotFound { Diagnostics.log("cursor sign-in: update failed (\(updated))") }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service,
                                  kSecAttrAccount as String: account,
                                  kSecAttrLabel as String: service,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                  kSecValueData as String: data]
        let added = SecItemAdd(add as CFDictionary, nil)
        if added != errSecSuccess { Diagnostics.log("cursor sign-in: save failed (\(added))") }
        return added == errSecSuccess
    }

    // MARK: Requests

    /// Calls one of Cursor's dashboard services with TAB's sign-in, renewing it when needed.
    static func dashboard(_ method: String, interactive: Bool = false) async throws -> Any {
        let gen = currentGeneration()
        if let w = currentWorking(), !JWT.expiresSoon(w, margin: 7 * 86_400) {
            do { return try await call(method, w) }
            catch ProviderError.expired, ProviderError.http(401) { setWorking(nil, ifGeneration: gen) }
        }
        guard signedIn else { throw ProviderError.notSignedIn("Click Connect to sign in to Cursor.") }
        var t = try load(interactive: interactive)
        // Renew a week early, so the sign-in survives a Mac that's off around the end date.
        if JWT.expiresSoon(t.access, margin: 7 * 86_400) { t = (try? await renew(t, interactive: interactive)) ?? t }
        do {
            let r = try await call(method, t.access)
            setWorking(t.access, ifGeneration: gen)
            return r
        } catch ProviderError.expired, ProviderError.http(401) {
            t = try await renew(t, interactive: interactive)
            let r = try await call(method, t.access)
            setWorking(t.access, ifGeneration: gen)
            return r
        }
    }

    /// The sign-in that last worked, for cursor.com requests.
    static func token(interactive: Bool = false) async throws -> String {
        if let w = currentWorking() { return w }
        _ = try await dashboard("GetPlanInfo", interactive: interactive)
        guard let t = currentWorking() else { throw ProviderError.notSignedIn("Click Connect to sign in to Cursor.") }
        return t
    }

    /// Cursor answers with a new access token, which also serves as the next refresh token.
    private static func renew(_ t: Tokens, interactive: Bool) async throws -> Tokens {
        let gen = currentGeneration()
        var req = URLRequest(url: server.appendingPathComponent("oauth/token"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["grant_type": "refresh_token", "client_id": clientID, "refresh_token": t.refresh])
        let r = try await HTTP.json(req, provider: "cursor-token")
        let given = headerSafe(J.find(r, keys: ["access_token", "accessToken"]) as? String)
        Diagnostics.log("cursor renewal: shouldLogout=\((J.dig(r, "shouldLogout") as? Bool).map(String.init) ?? "missing"), new token \(describe(given))")
        guard (J.dig(r, "shouldLogout") as? Bool) != true, let access = given else {
            // Cursor ended this sign-in. Drop it, so Connect opens the browser again instead of
            // trying the dead token forever (security review).
            signOut()
            throw ProviderError.notSignedIn("Cursor signed TAB out. Click Connect to sign in again.")
        }
        let fresh = Tokens(access: access, refresh: headerSafe(J.find(r, keys: ["refresh_token", "refreshToken"]) as? String) ?? access)
        // Removed while this ran: the result is thrown away, never saved.
        guard currentGeneration() == gen else { throw ProviderError.notSignedIn("Click Connect to sign in to Cursor.") }
        _ = save(fresh, interactive: interactive)
        return fresh
    }

    private static func call(_ method: String, _ tok: String) async throws -> Any {
        var req = URLRequest(url: server.appendingPathComponent("aiserver.v1.DashboardService/\(method)"))
        req.httpMethod = "POST"
        req.httpBody = Data("{}".utf8)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        req.setValue("Bearer " + tok, forHTTPHeaderField: "Authorization")
        return try await HTTP.json(req, provider: "cursor")
    }

    // MARK: Helpers

    static func base64URL(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Safe facts about a token for the log. Never the token itself.
    private static func describe(_ t: String?) -> String {
        guard let t = t, !t.isEmpty else { return "none" }
        let exp = JWT.expiry(t).map { $0 > Date() ? "valid" : "expired" } ?? "no-expiry"
        return "jwt=\(JWT.payload(t) != nil) \(exp) length=\(t.count)"
    }

    static func userID(fromToken t: String) -> String? {
        guard let sub = JWT.payload(t)?["sub"] as? String else { return nil }
        return sub.split(separator: "|").last.map(String.init)
    }
}

struct CursorProvider: UsageProvider {
    let id = "cursor"
    func credentialAvailable() -> Bool { CursorAuth.available() }

    func fetch(interactive: Bool) async throws -> [UsageLimit] {
        var firstError: Error? = nil
        do {
            let o = try await CursorAuth.dashboard("GetCurrentPeriodUsage", interactive: interactive)
            if let out = Self.parse(o) { return out }
        } catch { firstError = error }
        // Backup: the same numbers from cursor.com, with the same sign-in.
        guard let tok = try? await CursorAuth.token(interactive: interactive) else {
            throw firstError ?? ProviderError.notSignedIn("Open Cursor and sign in again.")
        }
        guard let user = CursorAuth.userID(fromToken: tok) else {
            Diagnostics.log("cursor: sign-in token has no account id")
            throw firstError ?? ProviderError.format("Cursor")
        }
        var web = URLRequest(url: URL(string: "https://cursor.com/api/usage-summary")!)
        web.setValue("WorkosCursorSessionToken=\(user)%3A%3A\(tok)", forHTTPHeaderField: "Cookie")
        do {
            let o = try await HTTP.json(web, provider: "cursor-web")
            if let out = Self.parse(o) { return out }
        } catch { if firstError == nil { firstError = error } }
        throw firstError ?? ProviderError.format("Cursor")
    }

    static func userID(fromToken t: String) -> String? { CursorAuth.userID(fromToken: t) }

    /// Cursor leaves numbers out entirely when they are 0, so a plan with no number yet means 0% used.
    static func parse(_ o: Any) -> [UsageLimit]? {
        let plan = (J.find(o, keys: ["planUsage"]) as? [String: Any])
            ?? (J.dig(o, "individualUsage", "plan") as? [String: Any])
        var used = J.num(J.find(o, keys: ["totalPercentUsed"]))
        if used == nil, let p = plan {
            if let spend = J.num(p["totalSpend"]) ?? J.num(p["used"]), let limit = J.num(p["limit"]), limit > 0 {
                used = spend / limit * 100
            } else if let remaining = J.num(p["remaining"]), let limit = J.num(p["limit"]), limit > 0 {
                used = (limit - remaining) / limit * 100
            } else {
                used = 0
            }
        }
        if used == nil, let spend = J.num(J.find(o, keys: ["totalSpend"])), let limit = J.num(J.find(o, keys: ["limit"])), limit > 0 {
            used = spend / limit * 100
        }
        guard let u = used else { return nil }
        return [UsageLimit(kind: .only, label: "Month", percentLeft: clampLeft(used: u),
                           resetsAt: J.date(J.find(o, keys: ["billingCycleEnd"])))]
    }
}

struct GrokBotProvider: UsageProvider {
    let id = "grokbot"
    func credentialAvailable() -> Bool { CursorAuth.available() }

    func fetch(interactive: Bool) async throws -> [UsageLimit] {
        let o = try await CursorAuth.dashboard("GetSandUsageStatus", interactive: interactive)
        guard let out = Self.parse(o) else { throw ProviderError.format("Grok Bot") }
        return out
    }

    static func parse(_ o: Any) -> [UsageLimit]? {
        if (J.dig(o, "usesPooledEnterpriseAllowance") as? Bool) == true { return nil }
        if (J.dig(o, "hasNonZeroIncludedLimit") as? Bool) == false || (J.dig(o, "includedLimitZero") as? Bool) == true { return nil }
        guard o is [String: Any] else { return nil }
        let used = J.num(J.dig(o, "usagePercent")) ?? 0     // left out when 0
        let reset = J.date(J.dig(o, "nextResetTimestampUtc"))
        return [UsageLimit(kind: .only, label: "Week", percentLeft: clampLeft(used: used), resetsAt: reset)]
    }
}

// MARK: Grok (Grok CLI sign-in: weekly shared pool)

struct GrokProvider: UsageProvider {
    let id = "grok"
    private var file: URL { homeURL(".grok/auth.json") }

    func credentialAvailable() -> Bool { FileManager.default.fileExists(atPath: file.path) }

    func fetch(interactive: Bool) async throws -> [UsageLimit] {
        // The xAI entry, picked the same way every time (sorted keys), never a random one.
        guard let doc = readJSONFile(file) as? [String: Any],
              let entry = doc.keys.sorted().compactMap({ doc[$0] as? [String: Any] }).first(where: { $0["key"] is String }),
              let token = entry["key"] as? String else {
            throw ProviderError.notSignedIn("Sign in to Grok first, then try again.")
        }
        // Read only: TAB never renews Grok's sign-in, which could sign the person out of Grok
        // (security review M1). Opening Grok renews it.
        if JWT.expiresSoon(token, margin: 0) { throw ProviderError.expired("Open Grok once, then TAB can check it again.") }
        do { return try await usage(token) }
        catch ProviderError.http(401) { throw ProviderError.expired("Open Grok once, then TAB can check it again.") }
    }

    private func usage(_ token: String) async throws -> [UsageLimit] {
        guard let token = headerSafe(token) else { throw ProviderError.notSignedIn("Sign in to Grok first, then try again.") }
        var req = URLRequest(url: URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!)
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        req.setValue("xai-grok-cli", forHTTPHeaderField: "X-XAI-Token-Auth")
        let r = try await HTTP.json(req, provider: id)
        guard let out = Self.parse(r) else { throw ProviderError.format("Grok") }
        return out
    }

    /// The weekly shared pool. The percent is left out entirely when it's 0.
    static func parse(_ r: Any) -> [UsageLimit]? {
        guard let config = J.dig(r, "config") as? [String: Any] else { return nil }
        let used = J.num(config["creditUsagePercent"]) ?? 0
        let period = config["currentPeriod"] as? [String: Any]
        let weekly = (period?["type"] as? String)?.contains("WEEKLY") ?? true
        return [UsageLimit(kind: weekly ? .long : .only, label: weekly ? "Week" : "Month",
                           percentLeft: clampLeft(used: used), resetsAt: J.date(period?["end"]))]
    }
}

// MARK: GitHub Copilot (monthly premium requests)

/// Uses the GitHub sign-in that Copilot's editor plugins or the GitHub CLI already keep.
/// Only github.com tokens are used, and only sent to api.github.com.
/// TAB's own GitHub sign-in for Copilot, using GitHub's device flow (the one-time code that the
/// GitHub CLI and VS Code use): TAB shows a short code and opens github.com, the person approves,
/// and TAB keeps the token only in its own Keychain item. Removing Copilot deletes it.
/// Only used when no Copilot sign-in already exists on this Mac (VS Code or GitHub CLI).
enum GitHubAuth {
    /// GitHub Copilot's public app id, the one Copilot's own sign-ins use.
    static let clientID = "Iv1.b507a08c87ecfe98"
    static let service = "TAB GitHub sign-in"
    private static let account = "github"

    struct DeviceCode: Equatable { let code: String; let url: URL }

    static var signedIn: Bool { Keychain.ownExists(service: service) }

    /// Starts the sign-in, hands the code to show, opens github.com, and waits until approved.
    static func signIn(show: @MainActor @escaping (DeviceCode) -> Void,
                       open: (URL) -> Void = { NSWorkspace.shared.open($0) }) async throws {
        var start = URLRequest(url: URL(string: "https://github.com/login/device/code")!)
        start.httpMethod = "POST"
        start.setValue("application/json", forHTTPHeaderField: "Accept")
        start.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        start.httpBody = formBody([("client_id", clientID), ("scope", "read:user")])
        let r = try await HTTP.json(start, provider: "github-signin")
        guard let device = J.dig(r, "device_code") as? String, let user = J.dig(r, "user_code") as? String,
              let page = (J.dig(r, "verification_uri") as? String).flatMap(URL.init(string:)),
              page.scheme == "https", page.host == "github.com" else {
            // Only ever open github.com, whatever the reply says (security review L2).
            throw ProviderError.format("GitHub")
        }
        // Poll every 1 to 60 seconds, for at most 15 minutes, whatever the reply asks for.
        var wait = min(max(J.num(J.dig(r, "interval")) ?? 5, 1), 60)
        let deadline = Date().addingTimeInterval(min(max(J.num(J.dig(r, "expires_in")) ?? 900, 60), 900))
        await show(DeviceCode(code: user, url: page))
        Diagnostics.log("github sign-in: showed the code and opened the browser")
        open(page)

        while Date() < deadline {
            try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            var poll = URLRequest(url: URL(string: "https://github.com/login/oauth/access_token")!)
            poll.httpMethod = "POST"
            poll.setValue("application/json", forHTTPHeaderField: "Accept")
            poll.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            poll.httpBody = formBody([("client_id", clientID), ("device_code", device),
                                      ("grant_type", "urn:ietf:params:oauth:grant-type:device_code")])
            guard let o = try? await HTTP.json(poll, provider: "github-signin") else { continue }
            if let token = headerSafe(J.dig(o, "access_token") as? String) {
                guard save(token) else { throw ProviderError.denied("TAB couldn't finish signing in. Try again.") }
                Diagnostics.log("github sign-in: done")
                return
            }
            switch J.dig(o, "error") as? String {
            case "authorization_pending": continue
            case "slow_down": wait = min(wait + 5, 60)
            case "access_denied": throw ProviderError.notSignedIn("The sign-in was cancelled on GitHub.")
            case "expired_token": throw ProviderError.notSignedIn("That code expired. Click Try again for a new one.")
            default: continue
            }
        }
        throw ProviderError.notSignedIn("That took too long. Click Try again to sign in.")
    }

    static func token(interactive: Bool) throws -> String? {
        guard signedIn else { return nil }
        let r = Keychain.readOwn(service: service, account: account, interactive: interactive)
        if Keychain.isPermissionProblem(r.status) {
            throw interactive ? ProviderError.denied("macOS didn't let TAB check this app. Try again and choose Always Allow.") : ProviderError.needsApproval
        }
        return r.data.flatMap { String(data: $0, encoding: .utf8) }
    }

    static func signOut() {
        let status = Keychain.deleteOwn(service: service)
        Diagnostics.log(status == errSecSuccess || status == errSecItemNotFound
                        ? "github sign-in: removed" : "github sign-in: remove failed (\(status))")
    }

    private static func save(_ token: String) -> Bool {
        let data = Data(token.utf8)
        if Keychain.update(service: service, account: account, data: data, interactive: true) == errSecSuccess { return true }
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecAttrLabel as String: service,
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                  kSecValueData as String: data]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

struct CopilotProvider: UsageProvider {
    let id = "copilot"
    private var editorFiles: [URL] { [homeURL(".config/github-copilot/apps.json"), homeURL(".config/github-copilot/hosts.json")] }
    private var ghHosts: URL { homeURL(".config/gh/hosts.yml") }

    /// Copilot can always be connected: TAB signs in with GitHub when nothing is set up yet.
    func credentialAvailable() -> Bool { true }

    /// A real github.com sign-in from VS Code or the GitHub CLI is on this Mac. A file alone is not
    /// enough: after `gh auth logout` the file stays but holds no token (security review).
    func hasLocalSignIn() -> Bool {
        if editorToken() != nil { return true }
        if let text = readSmallText(ghHosts), Self.ghToken(fromHostsYAML: text) != nil { return true }
        return Keychain.exists(service: "gh:github.com")
    }

    /// The github.com token VS Code's Copilot keeps, if any.
    private func editorToken() -> String? {
        for f in editorFiles {
            guard let o = readJSONFile(f) as? [String: Any] else { continue }
            for (k, v) in o where k == "github.com" || k.hasPrefix("github.com:") {
                if let t = headerSafe((v as? [String: Any])?["oauth_token"] as? String) { return t }
            }
        }
        return nil
    }

    private func token(interactive: Bool) throws -> String {
        // TAB's own GitHub sign-in first, then the ones VS Code or the GitHub CLI keep.
        if let own = headerSafe(try GitHubAuth.token(interactive: interactive)) { return own }
        if let t = editorToken() { return t }
        if let text = readSmallText(ghHosts), let t = headerSafe(Self.ghToken(fromHostsYAML: text)) { return t }
        let r = Keychain.read(service: "gh:github.com", interactive: interactive)
        if r.status == errSecSuccess, let d = r.data, var t = String(data: d, encoding: .utf8) {
            // GitHub CLI stores it as "go-keyring-base64:<base64>".
            if t.hasPrefix("go-keyring-base64:"), let raw = Data(base64Encoded: String(t.dropFirst(18))),
               let decoded = String(data: raw, encoding: .utf8) { t = decoded }
            if let safe = headerSafe(t.trimmingCharacters(in: .whitespacesAndNewlines)) { return safe }
        }
        if Keychain.isPermissionProblem(r.status) {
            throw interactive ? ProviderError.denied("macOS didn't let TAB check this app. Try again and choose Always Allow.") : ProviderError.needsApproval
        }
        throw ProviderError.notSignedIn("Click Connect to sign in with GitHub.")
    }

    /// The `oauth_token` inside the `github.com:` block of GitHub CLI's hosts.yml.
    static func ghToken(fromHostsYAML text: String) -> String? {
        var inGitHub = false
        for line in text.components(separatedBy: .newlines) {
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") { inGitHub = line.trimmingCharacters(in: .whitespaces) == "github.com:" ; continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            if inGitHub, t.hasPrefix("oauth_token:") {
                let v = t.dropFirst("oauth_token:".count).trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
        }
        return nil
    }

    func fetch(interactive: Bool) async throws -> [UsageLimit] {
        let tok = try token(interactive: interactive)
        var req = URLRequest(url: URL(string: "https://api.github.com/copilot_internal/user")!)
        req.setValue("token " + tok, forHTTPHeaderField: "Authorization")
        req.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        req.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        req.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        let r = try await HTTP.json(req, provider: id)
        guard let out = Self.parse(r) else { throw ProviderError.format("Copilot") }
        return out
    }

    /// Premium requests left this month. Unlimited plans report -1 and are shown as full.
    static func parse(_ r: Any) -> [UsageLimit]? {
        let reset = J.date(J.dig(r, "quota_reset_date")) ?? J.date(J.dig(r, "limited_user_reset_date"))
        for key in ["premium_interactions", "chat", "completions"] {
            guard let s = J.dig(r, "quota_snapshots", key) as? [String: Any] else { continue }
            if (s["unlimited"] as? Bool) == true || J.num(s["entitlement"]) == -1 { continue }
            if let pct = J.num(s["percent_remaining"]) {
                return [UsageLimit(kind: .only, label: "Month", percentLeft: max(0, min(100, pct)), resetsAt: reset)]
            }
            if let left = J.num(s["remaining"]), let total = J.num(s["entitlement"]), total > 0 {
                return [UsageLimit(kind: .only, label: "Month", percentLeft: max(0, min(100, left / total * 100)), resetsAt: reset)]
            }
        }
        if J.dig(r, "quota_snapshots") != nil {
            return [UsageLimit(kind: .only, label: "Month", percentLeft: 100, resetsAt: reset)]
        }
        return nil
    }
}

// MARK: Gemini (the Gemini app's 5-hour and weekly limits, or the Gemini CLI's daily quota)

/// Gemini app users (most people) connect with TAB's own Google sign-in (`GeminiAuth`), which
/// reads the limits gemini.google.com/usage shows. Workspace and Code Assist accounts that still
/// use the Gemini CLI sign-in keep working through it, read only, without TAB signing in.
struct GeminiProvider: UsageProvider {
    let id = "gemini"
    private var file: URL { homeURL(".gemini/oauth_creds.json") }
    let base = "https://cloudcode-pa.googleapis.com/v1internal"

    /// Gemini can always be connected: TAB signs in with Google when nothing works yet.
    func credentialAvailable() -> Bool { true }
    /// A Gemini CLI sign-in file is on this Mac.
    var hasCLISignIn: Bool { FileManager.default.fileExists(atPath: file.path) }

    func fetch(interactive: Bool) async throws -> [UsageLimit] {
        if GeminiAuth.signedIn { return try await GeminiAuth.fetch(interactive: interactive) }
        guard hasCLISignIn else { throw ProviderError.notSignedIn("Sign in to Google in TAB to see Gemini's limits.") }
        return try await fetchCLI()
    }

    private func post(_ path: String, _ body: [String: Any], token: String) async throws -> Any {
        guard let token = headerSafe(token) else { throw ProviderError.notSignedIn("Sign in to Gemini first, then try again.") }
        var req = URLRequest(url: URL(string: base + ":" + path)!)
        req.httpMethod = "POST"
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return try await HTTP.json(req, provider: id)
    }

    /// The Gemini CLI path: its own sign-in file, read only (never renewed).
    func fetchCLI() async throws -> [UsageLimit] {
        guard let o = readJSONFile(file), let fileToken = J.dig(o, "access_token") as? String else {
            throw ProviderError.notSignedIn("Sign in to Gemini first, then try again.")
        }
        let tok = fileToken
        if let exp = J.date(J.dig(o, "expiry_date")), exp < Date().addingTimeInterval(60) {
            throw ProviderError.expired("Open the Gemini CLI once, then TAB can check it again.")
        }
        let meta: [String: Any] = ["metadata": ["ideType": "IDE_UNSPECIFIED", "platform": "PLATFORM_UNSPECIFIED", "pluginType": "GEMINI"]]
        let load = try await post("loadCodeAssist", meta, token: tok)
        var project = J.find(load, keys: ["cloudaicompanionProject"])
        if let d = project as? [String: Any] { project = d["id"] }
        var body: [String: Any] = [:]
        if let p = project as? String { body["project"] = p }
        let q: Any
        do { q = try await post("retrieveUserQuota", body, token: tok) }
        catch ProviderError.http(let code) where code == 400 {
            // Google ended the Gemini CLI sign-in for personal, AI Pro and Ultra accounts (2026-06-18).
            throw ProviderError.notSignedIn("Sign in to Google in TAB to see Gemini's limits.")
        }
        guard let out = Self.parse(q) else { throw ProviderError.format("Gemini") }
        return out
    }

    static func parse(_ q: Any) -> [UsageLimit]? {
        guard let buckets = J.find(q, keys: ["buckets"]) as? [[String: Any]], !buckets.isEmpty else { return nil }
        let fractions = buckets.compactMap { J.num($0["remainingFraction"]) }
        guard let minFrac = fractions.min() else { return nil }
        let reset = buckets.compactMap { J.date($0["resetTime"]) }.min()
        return [UsageLimit(kind: .only, label: "Day", percentLeft: max(0, min(100, minFrac * 100)), resetsAt: reset)]
    }
}

// MARK: Zed (the editor's own sign-in: monthly edit predictions)

/// Zed keeps its sign-in in the Keychain after you sign in inside the editor: an internet password
/// for https://zed.dev whose account is your Zed user id. TAB only reads it (never changes or
/// renews it) and sends it only to Zed's own cloud, the same call the editor makes.
/// Path from CodexBar's Zed provider (docs/SYNC-PLAN.md).
struct ZedProvider: UsageProvider {
    let id = "zed"
    static let server = "https://zed.dev"
    static let usageURL = URL(string: "https://cloud.zed.dev/client/users/me")!

    func credentialAvailable() -> Bool { Keychain.internetExists(server: Self.server) }

    private func authorization(interactive: Bool) throws -> String {
        let r = Keychain.readInternet(server: Self.server, interactive: interactive)
        if Keychain.isPermissionProblem(r.status) {
            throw interactive ? ProviderError.denied("macOS didn't let TAB check Zed. Try again and choose Always Allow.") : ProviderError.needsApproval
        }
        guard r.status == errSecSuccess, let d = r.data,
              let header = Self.header(user: r.account, token: String(data: d, encoding: .utf8)) else {
            throw ProviderError.notSignedIn("Sign in to Zed first, then try again.")
        }
        return header
    }

    /// "<user id> <token>", the way the editor sends it. Each part is checked on its own, since a
    /// header value with a space in it would never pass `headerSafe` as a whole.
    static func header(user: String?, token: String?) -> String? {
        guard let u = user?.trimmingCharacters(in: .whitespacesAndNewlines),
              u.range(of: #"^[0-9]{1,20}$"#, options: .regularExpression) != nil,
              let t = headerSafe(token?.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return "\(u) \(t)"
    }

    func fetch(interactive: Bool) async throws -> [UsageLimit] {
        var req = URLRequest(url: Self.usageURL)
        req.setValue(try authorization(interactive: interactive), forHTTPHeaderField: "Authorization")
        let r: Any
        do { r = try await HTTP.json(req, provider: id) }
        catch ProviderError.expired { throw ProviderError.expired("Sign in to Zed again, then TAB can check it.") }
        guard let out = Self.parse(r) else { throw ProviderError.format("Zed") }
        return out
    }

    /// Edit predictions left this billing period. Plans with no cap (Pro and up) say "unlimited"
    /// and show as full, like Copilot's unlimited plans.
    static func parse(_ r: Any) -> [UsageLimit]? {
        guard let p = J.dig(r, "plan", "usage", "edit_predictions") as? [String: Any],
              let used = J.num(p["used"]), used >= 0 else { return nil }
        let reset = J.date(J.dig(r, "plan", "subscription_period", "ended_at"))
        let raw = p["limit"]
        if (raw as? String) == "unlimited" {
            return [UsageLimit(kind: .only, label: "Month", percentLeft: 100, resetsAt: reset)]
        }
        guard let limit = J.num(raw) ?? J.num((raw as? [String: Any])?["limited"]), limit > 0 else { return nil }
        return [UsageLimit(kind: .only, label: "Month", percentLeft: clampLeft(used: used / limit * 100), resetsAt: reset)]
    }
}

enum Providers {
    static let all: [String: UsageProvider] = [
        "zed": ZedProvider(),
        "claude": ClaudeProvider(),
        "codex": CodexProvider(),
        "cursor": CursorProvider(),
        "grokbot": GrokBotProvider(),
        "grok": GrokProvider(),
        "gemini": GeminiProvider(),
        "copilot": CopilotProvider(),
    ]
}
