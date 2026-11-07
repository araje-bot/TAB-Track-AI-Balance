import SwiftUI
import AppKit
import ServiceManagement

/// Settings uses the native grouped form, so it picks up the current macOS look
/// (Liquid Glass on macOS 26 and later) and stays correct on older versions.
@MainActor
struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var connectTarget: AIApp? = nil
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var copied = false
    @State private var feedback = false
    var showWelcome: () -> Void = {}

    /// The title sits in the window's own title bar (see `AppDelegate.openSettings`), as in
    /// macOS settings windows. The content is a standard grouped form.
    var body: some View {
        form
        .frame(minWidth: 580, maxWidth: .infinity, minHeight: 660, maxHeight: .infinity)
        .sheet(item: $connectTarget) { app in
            ConnectSheet(store: store, app: app, done: { connectTarget = nil })
        }
        .sheet(isPresented: $feedback) { FeedbackSheet(done: { feedback = false }) }
        .onAppear { store.scan() }
    }

    private var form: some View {
        Form {
            // The privacy promise comes first (AK: very important), styled like the welcome screen's
            // cards: a large filled symbol, a headline and one plain line.
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill").symbolRenderingMode(.hierarchical).foregroundStyle(.tint)
                        .font(.largeTitle).frame(width: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your info stays secure").font(.headline)
                        Text("TAB has no server. Each sign-in goes only to its own app to check usage. Your prompts and work are never saved or sent.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
            }

            if store.menuBarHidden {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TAB's menu bar icon is hidden").font(.headline)
                            Text("Hold ⌘ and drag it to the right end of the menu bar.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }

            Section {
                // Only apps TAB can read (AK). The others wait in Coming soon.
                let ready = store.readyToConnect
                if ready.isEmpty {
                    Text("No AI apps found yet. Install one and TAB will find it.")
                        .foregroundStyle(.secondary)
                }
                ForEach(ready) { app in appRow(app) }
            } header: {
                HStack {
                    Text("Your AI apps")
                    Spacer()
                    FindAppsButton(store: store)
                }
            }

            let later = store.comingSoon
            if !later.isEmpty {
                // Apps TAB can't read yet, on this Mac or planned: nothing to click yet (AK).
                Section("Coming soon") {
                    ForEach(later) { app in
                        HStack(spacing: 12) {
                            AppTile(icon: store.icon(app.id), symbol: store.symbol(app.id), size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name).foregroundStyle(.secondary)
                                Text(app.hint).font(.subheadline).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            Spacer()
                        }
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(app.name), coming soon. \(app.hint)")
                    }
                }
            }

            Section("Nudges") {
                SettingRow("Usage monitoring", subtitle: "Which limit TAB watches for you") {
                    SegmentedChoice(selection: $store.watch, options: WatchMode.segments, label: "Usage monitoring")
                }
                SettingRow("Turn yellow at", subtitle: "When the icon turns yellow") {
                    SegmentedChoice(selection: $store.threshold, options: Thresholds.yellow, label: "Turn yellow at")
                }
                SettingRow("Show usage when I open a low app", subtitle: "A quick look when you open an app that's running low") {
                    Toggle("Show usage when I open a low app", isOn: $store.headsUpOnOpen).labelsHidden().toggleStyle(.switch).controlSize(.regular)
                }
            }

            Section("Quick view") {
                // A shortcut another app owns is explained in the row's own subtitle, so choosing one
                // never adds or removes a row and the form doesn't jump (AK).
                SettingRow("See all apps", subtitle: store.shortcutSubtitle("Hold the keys to see every app")) {
                    ShortcutPicker(store: store)
                }
            }

            Section("General") {
                SettingRow("Welcome screens", subtitle: "See the welcome tour again") {
                    // An icon button like the others in TAB, with a filled play symbol: "play the tour
                    // again" (AK). SF Symbols already centers the triangle optically; the extra 1pt
                    // nudge right looked off (AK), so it sits slightly left of that.
                    Button(action: showWelcome) {
                        Label {
                            Text("Show welcome screens again")
                        } icon: {
                            Image(systemName: "play.fill").offset(x: -0.5)
                        }
                    }
                        .iconButton()
                        .help("Show welcome screens again")
                }
                SettingRow("Always show in Dock", subtitle: "Keep TAB in the Dock, even with no window open") {
                    Toggle("Always show in Dock", isOn: $store.alwaysInDock).labelsHidden().toggleStyle(.switch).controlSize(.regular)
                }
                // Only an installed TAB can start at login. A copy on the disk image or in a temporary
                // folder would leave a broken login item behind (security review L14).
                SettingRow("Open at login", subtitle: Self.installedInApplications ? "Start TAB when you turn on your Mac" : "Move TAB to Applications first") {
                    Toggle("Open at login", isOn: $openAtLogin).labelsHidden().toggleStyle(.switch).controlSize(.regular)
                        .disabled(!Self.installedInApplications)
                        .onChange(of: openAtLogin) { on in
                            guard Self.installedInApplications else { return }
                            do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                            catch { Diagnostics.log("login item: \(Diagnostics.describe(error))") }
                        }
                }
            }

            Section {
                // Both buttons sit together on the right, 10pt apart like other button pairs (AK).
                HStack(spacing: 10) {
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Diagnostics.contents(), forType: .string)
                        copied = true
                    } label: { ButtonText(copied ? "Copied" : "Copy diagnostics") }
                    .secondaryButton()
                    .help("For support. It holds no sign-ins, prompts or work.")
                    // Red text like Remove (AK): deeper in Light Mode, lighter in Dark Mode, both readable.
                    Button { NSApp.terminate(nil) } label: { ButtonText("Quit TAB").foregroundStyle(Palette.redText) }.secondaryButton()
                }
                HStack {
                    Spacer()
                    FeedbackLink { feedback = true }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private func appRow(_ app: AIApp) -> some View {
        HStack(spacing: 12) {
            AppTile(icon: store.icon(app.id), symbol: store.symbol(app.id), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.headline)
                    statusText(detail(app)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if store.needsApproval.contains(app.id) {
                // One more step to finish: just Connect, never Allow and Remove side by side (AK).
                ConnectButton(name: app.name) { connectTarget = app }
            } else if store.connected.contains(app.id) {
                AppMenu(name: app.name, refresh: store.readsUsage(app.id) ? { refresh(app) } : nil, remove: { remove(app) })
            } else if app.canConnect {
                ConnectButton(name: app.name) { connectTarget = app }
            }
        }
        .contentShape(Rectangle())
        // Right-click offers the same actions as the More button (HIG Context menus).
        .contextMenu {
            if store.connected.contains(app.id) {
                AppMenuItems(name: app.name, refresh: store.readsUsage(app.id) ? { refresh(app) } : nil, remove: { remove(app) })
            } else if app.canConnect {
                Button("Connect \(app.name)") { connectTarget = app }
            }
        }
    }

    /// True when TAB runs from /Applications or ~/Applications, the only places a login item may point at.
    static var installedInApplications: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    private func refresh(_ app: AIApp) { Task { await store.syncNow(app.id) } }
    private func remove(_ app: AIApp) { withAnimation { store.disconnect(app.id) } }

    private func detail(_ app: AIApp) -> String {
        if store.connected.contains(app.id) {
            if let e = store.errors[app.id] { return e }
            return store.connectedText(app.id)
        }
        if app.usesCursorSignIn && !CursorAuth.signedIn { return app.hint }
        if app.usesGitHubSignIn && !GitHubAuth.signedIn && !CopilotProvider().hasLocalSignIn() { return app.hint }
        if app.usesGoogleSignIn && !GeminiAuth.signedIn && !GeminiProvider().hasCLISignIn { return app.hint }
        if !app.supported { return app.hint }
        return app.canConnect ? app.source : app.hint
    }
}
