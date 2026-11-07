import AppKit

/// TAB was called TUM until 2026-11-06 (bundle id edu.umd.inst474.tum). The first TAB launch
/// copies TUM's settings over and quits a TUM that is still running. TAB's own sign-ins move
/// from "TUM … sign-in" to "TAB … sign-in" the first time each is read (`Keychain.readOwn`).
/// Nothing needs reconnecting.
enum Rename {
    static let movedKey = "movedFromTUM"
    private static let newPrefix = "edu.umd.inst474.tab"
    private static let oldPrefix = "edu.umd.inst474.tum"

    /// The old id for this build: .tab becomes .tum, .tab.dev becomes .tum.dev.
    static func oldID(for id: String?) -> String? {
        guard let id = id, id.hasPrefix(newPrefix) else { return nil }
        return oldPrefix + id.dropFirst(newPrefix.count)
    }

    /// Runs once, at launch, before anything reads settings.
    @MainActor static func run() {
        guard let id = Bundle.main.bundleIdentifier, let old = oldID(for: id) else { return }
        let moved = moveSettings(from: old, into: .standard, id: id)
        if moved > 0 { Diagnostics.log("rename: moved \(moved) settings from TUM") }
        quitOld(old)
    }

    /// Copies the old settings into TAB's, once, and only while TAB was never set up (no
    /// connected apps, no onboarding). A few keys can exist before that, since the self-test
    /// runs on the same app. Names that held "TUM" (the menu bar slot's spot) get "TAB".
    /// Returns how many settings came over.
    @discardableResult
    static func moveSettings(from old: String, into d: UserDefaults, id: String) -> Int {
        guard !d.bool(forKey: movedKey) else { return 0 }
        let mine = d.persistentDomain(forName: id) ?? [:]
        d.set(true, forKey: movedKey)
        guard mine["connected"] == nil, mine["onboardingVersion"] == nil,
              let values = d.persistentDomain(forName: old), !values.isEmpty else { return 0 }
        // Launch state belongs to the old app: a crash flag would start TAB in safe mode.
        let skip: Set<String> = ["launchInProgress", "onboardingBuild"]
        let moving = values.filter { !skip.contains($0.key) }
        for (key, value) in moving { d.set(value, forKey: key.replacingOccurrences(of: " TUM", with: " TAB")) }
        return moving.count
    }

    /// Asks a running TUM to quit, so only one icon shows. TUM Dev only quits an old TUM Dev,
    /// never the real app.
    @MainActor private static func quitOld(_ old: String) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: old) {
            app.terminate()
            Diagnostics.log("rename: asked the old TUM to quit")
        }
    }
}
