import SwiftUI

// Sample data for the Xcode previews, the Developer menu and the self-test. It is in release
// builds too, because `--self-test` runs on the installed app. A sample store saves to a scratch
// settings suite and never fetches anything.

extension Store {
    /// Sample apps for previews and fakes. Uses the real app (with its icon) when it is installed.
    func sampleApp(_ id: String) -> AIApp {
        if let a = app(id) { return a }
        let e = Catalog.entry(id)
        return AIApp(id: id, name: e?.name ?? id.capitalized, category: e?.category ?? "AI app", appURL: nil,
                     supported: e?.providerID != nil, credentialFound: true, hint: e?.hint ?? "", source: e?.source ?? "")
    }

    /// Limits for one app at `pct` left: a session limit plus a roomier weekly one.
    static func sampleLimits(_ id: String, pct: Double) -> [UsageLimit] {
        let hour: TimeInterval = 3600
        if id == "cursor" {
            return [UsageLimit(kind: .only, label: "Month", percentLeft: pct, resetsAt: Date().addingTimeInterval(12 * 24 * hour))]
        }
        return [UsageLimit(kind: .short, label: "5 hours", percentLeft: pct, resetsAt: Date().addingTimeInterval(2.5 * hour)),
                UsageLimit(kind: .long, label: "Week", percentLeft: min(100, pct + 35), resetsAt: Date().addingTimeInterval(4 * 24 * hour))]
    }

    /// A weekly limit that resets in 9 hours with 85% left: TUM's "use it" recommendation.
    static func useItLimits(_ id: String) -> [UsageLimit] {
        [UsageLimit(kind: .short, label: "5 hours", percentLeft: 90, resetsAt: Date().addingTimeInterval(3 * 3600)),
         UsageLimit(kind: .long, label: "Week", percentLeft: 85, resetsAt: Date().addingTimeInterval(9 * 3600))]
    }

    /// A store filled with sample data, for previews. Nothing is saved and nothing is fetched.
    static func preview(apps: [String: Double] = ["claude": 62, "codex": 88],
                        onboardingDone: Bool = true, threshold: Double = 25,
                        mode: WatchMode = .session) -> Store {
        // A scratch settings suite, so sample data never touches the real settings.
        let suite = "edu.umd.inst474.tum.preview"
        let scratch = UserDefaults(suiteName: suite) ?? UserDefaults()
        scratch.removePersistentDomain(forName: suite)
        let s = Store(defaults: scratch)
        s.devFrozen = true
        s.detected = Detector.scan()
        for id in apps.keys where s.app(id) == nil { s.detected.append(s.sampleApp(id)) }
        s.watch = mode
        s.threshold = threshold
        s.onboardingDone = onboardingDone
        s.connected = apps.keys.sorted()
        for (id, pct) in apps {
            s.snapshots[id] = ProviderSnapshot(limits: sampleLimits(id, pct: pct), fetchedAt: Date())
        }
        return s
    }
}
