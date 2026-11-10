import SwiftUI
import AppKit
import ServiceManagement

/// Settings uses the native grouped form, so it picks up the current macOS look
/// (Liquid Glass on macOS 26 and later) and stays correct on older versions.
@MainActor
struct SettingsView: View {
    @ObservedObject var store: Store
    @State private var connectTarget: AIApp? = nil
    @State private var accountTarget: AIApp? = nil
    @State private var adding = false
    /// Apps showing their accounts. Apps with several start open (v4 screen 12).
    @State private var expanded: Set<String> = []
    @State private var dragging: String?
    @ObservedObject private var updates = UpdateChecker.shared
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
        .sheet(item: $accountTarget) { app in
            ConnectSheet(store: store, app: app, addingAccount: true, done: { accountTarget = nil })
        }
        .sheet(isPresented: $adding) {
            AddAppSheet(store: store, connect: { app in
                adding = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { connectTarget = app }
            }, done: { adding = false })
        }
        .sheet(isPresented: $feedback) { FeedbackSheet(done: { feedback = false }) }
        .onAppear {
            store.scan()
            expanded = Set(store.connected.filter { store.accountList($0).count > 1 })
        }
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
                        Text("TAB only reads what's left").font(.headline)
                        Text("It never sees your prompts or work. Each sign-in stays on this Mac and only talks to its own app.")
                            .font(.subheadline).foregroundStyle(Palette.subtitle)
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
                                .font(.callout).foregroundStyle(Palette.subtitle)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
            }

            Section {
                // Apps on this Mac TAB can read, plus web apps that are connected (v4).
                let apps = store.settingsApps
                if apps.isEmpty {
                    Text("No AI apps found yet. Install one, or add one you use in a browser.")
                        .foregroundStyle(Palette.subtitle)
                }
                ForEach(apps) { app in appRow(app) }
            } header: {
                HStack(spacing: 8) {
                    Text("Your apps")
                    Spacer()
                    FindAppsButton(store: store)
                    Button { adding = true } label: { ButtonText("Add app", systemImage: "plus") }
                        .secondaryButton()
                }
            }

            Section("Nudges") {
                SettingRow("Usage monitoring", subtitle: "Which limit TAB watches for you") {
                    SegmentedChoice(selection: $store.watch, options: WatchMode.segments, label: "Usage monitoring")
                }
                SettingRow(LevelSlider.yellowTitle, subtitle: LevelSlider.yellowSubtitle) {
                    LevelSlider(store: store, red: false)
                }
                SettingRow(LevelSlider.redTitle, subtitle: LevelSlider.redSubtitle) {
                    LevelSlider(store: store, red: true)
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
                // The version from the app itself, and a check that asks GitHub only when clicked (v4).
                SettingRow("TAB \(Updates.current)", subtitle: updates.line) {
                    Button { updates.check() } label: {
                        ButtonText(updateTitle)
                    }
                    .secondaryButton()
                    .disabled(updates.state == .checking)
                }
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
                // Both buttons sit together in the right corner, 10pt apart (AK, 2026-11-09: back
                // from centered).
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
                // The feedback link sits in the right corner too, under Quit TAB (AK).
                HStack {
                    Spacer()
                    FeedbackLink { feedback = true }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var updateTitle: String {
        if case .available = updates.state { return "How to update" }
        return "Check for updates"
    }

    @ViewBuilder private func appRow(_ app: AIApp) -> some View {
        let on = store.connected.contains(app.id)
        let open = on && expanded.contains(app.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AppTile(icon: store.icon(app.id), symbol: store.symbol(app.id), size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.headline)
                    detailText(app).font(.subheadline).lineLimit(2)
                }
                Spacer()
                if store.needsApproval.contains(app.id) {
                    // One more step to finish: just Connect, never Allow and Remove side by side (AK).
                    ConnectButton(name: app.name) { connectTarget = app }
                } else if on {
                    AppMenu(name: app.name, refresh: store.readsUsage(app.id) ? { refresh(app) } : nil, remove: { remove(app) },
                            addAccount: store.canAddAccount(app.id) ? { accountTarget = app } : nil)
                } else if app.canConnect || app.isWeb {
                    ConnectButton(name: app.name) { connectTarget = app }
                }
            }
            .contentShape(Rectangle())
            // Clicking a connected app with several accounts shows or hides them.
            .onTapGesture {
                guard on, store.accountList(app.id).count > 1 else { return }
                withAnimation(Motion.standard) {
                    if expanded.contains(app.id) { expanded.remove(app.id) } else { expanded.insert(app.id) }
                }
            }
            if open { accounts(app) }
        }
        // Right-click offers the same actions as the More button (HIG Context menus).
        .contextMenu {
            if on {
                AppMenuItems(name: app.name, refresh: store.readsUsage(app.id) ? { refresh(app) } : nil, remove: { remove(app) },
                             addAccount: store.canAddAccount(app.id) ? { accountTarget = app } : nil)
            } else if app.canConnect || app.isWeb {
                Button("Connect \(app.name)") { connectTarget = app }
            }
        }
    }

    /// An app's accounts, top first, indented under its name. Drag to reorder.
    private func accounts(_ app: AIApp) -> some View {
        let list = store.accountList(app.id)
        return VStack(spacing: 8) {
            ForEach(Array(list.enumerated()), id: \.element.id) { i, a in
                AccountRow(store: store, appID: app.id, account: a, stale: store.isStale(app.id))
                    .opacity(dragging == a.id ? 0.4 : 1)
                    .onDrag {
                        dragging = a.id
                        return NSItemProvider(object: a.id as NSString)
                    }
                    .onDrop(of: [.text], delegate: AccountDrop(store: store, appID: app.id, target: a.id, dragging: $dragging))
                    .contextMenu {
                        if i > 0 { Button("Use first") { withAnimation(Motion.standard) { store.useFirst(app.id, account: a.id) } } }
                        Button("Remove account") { withAnimation(Motion.standard) { store.removeAccount(app.id, account: a.id) } }
                    }
            }
            if store.canAddAccount(app.id) {
                HStack {
                    Spacer()
                    Button { accountTarget = app } label: { ButtonText("Add account", systemImage: "plus") }
                        .secondaryButton()
                }
            }
        }
        .padding(.leading, 44)
        .animation(Motion.standard, value: list.map(\.id))
    }

    /// True when TAB runs from /Applications or ~/Applications, the only places a login item may point at.
    static var installedInApplications: Bool {
        let path = Bundle.main.bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/Applications/")
    }

    private func refresh(_ app: AIApp) { Task { await store.syncNow(app.id) } }
    private func remove(_ app: AIApp) { withAnimation { store.disconnect(app.id) } }

    /// "Connected" or "2 accounts" in a brighter gray (AK: less color), anything after it, like
    /// " · Just now", in the subtitle gray. A problem or "Not connected" is all subtitle gray.
    private func detailText(_ app: AIApp) -> Text {
        guard store.connected.contains(app.id) else { return Text("Not connected").foregroundColor(Palette.subtitle) }
        if let e = store.errors[app.id] { return Text(e).foregroundColor(Palette.subtitle) }
        let line = store.accountsLine(app.id)
        let head = line.components(separatedBy: " · ").first ?? line
        return connectedLabel(head)
            + Text(String(line.dropFirst(head.count))).foregroundColor(Palette.subtitle)
    }
}
