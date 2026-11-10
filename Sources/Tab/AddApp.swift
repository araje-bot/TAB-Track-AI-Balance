import SwiftUI
import AppKit

/// Add app (v4 screen 08): a search field, then apps on this Mac and on the web that aren't
/// connected yet. Each row is just the icon, the name and the Connect button.
@MainActor
struct AddAppList: View {
    @ObservedObject var store: Store
    var connect: (AIApp) -> Void
    @State private var query = ""

    static let webInfo = "Opens the app's own sign-in page. TAB only reads how much you have left."

    var body: some View {
        let mac = store.addable(web: false, matching: query)
        let web = store.addable(web: true, matching: query)
        VStack(alignment: .leading, spacing: 14) {
            SearchField(text: $query, prompt: "Search AI apps")
            if mac.isEmpty && web.isEmpty {
                Text(query.isEmpty ? "Every app TAB knows is connected." : "No apps match \u{201C}\(query)\u{201D}.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
            if !mac.isEmpty {
                group(GroupTitle("On this Mac"), mac)
            }
            if !web.isEmpty {
                group(HStack(spacing: 4) {
                    GroupTitle("On the web")
                    // Not a button: hovering shows what signing in on the web means.
                    Image(systemName: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .help(Self.webInfo)
                        .accessibilityLabel(Self.webInfo)
                }, web)
            }
        }
    }

    private func group<T: View>(_ title: T, _ apps: [AIApp]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            title
            VStack(spacing: 0) {
                ForEach(apps) { app in row(app) }
            }
        }
    }

    private func row(_ app: AIApp) -> some View {
        HStack(spacing: 10) {
            AppTile(icon: store.icon(app.id), symbol: store.symbol(app.id), size: 28)
            Text(app.name).font(.body.weight(.medium)).lineLimit(1)
            Spacer(minLength: 8)
            ConnectButton(name: app.name) { connect(app) }
        }
        .padding(.horizontal, 8)
        .frame(height: 42)
        .contentShape(Rectangle())
    }
}

/// A rounded search field in the system fill, like the ones in System Settings.
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.callout).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Clear")
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

/// The Add app page inside the popover, with a back button.
@MainActor
struct AddAppPage: View {
    @ObservedObject var store: Store
    var back: () -> Void
    var connect: (AIApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Button("Back", systemImage: "chevron.left", action: back)
                    .iconButton()
                    .help("Back")
                Text("Add app").font(.title3.weight(.semibold))
                Spacer(minLength: 0)
            }
            // Hugs the list, and scrolls once it would make the popover too tall.
            ScrollView(showsIndicators: false) {
                AddAppList(store: store, connect: connect)
                    .background(GeometryReader { g in Color.clear.preference(key: ListHeightKey.self, value: g.size.height) })
            }
            .frame(height: min(max(listHeight, 120), 360))
            .onPreferenceChange(ListHeightKey.self) { listHeight = $0 }
        }
        .padding(16)
        .fixedSize(horizontal: false, vertical: true)
    }
    @State private var listHeight: CGFloat = 300
}

private struct ListHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The same list as a sheet, for onboarding and Settings.
@MainActor
struct AddAppSheet: View {
    @ObservedObject var store: Store
    var connect: (AIApp) -> Void
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add app").font(.title2.bold())
            ScrollView { AddAppList(store: store, connect: connect).padding(.trailing, 4) }
                .frame(maxHeight: 420)
            HStack {
                Spacer()
                Button(action: done) { ButtonText("Done") }
                    .keyboardShortcut(.cancelAction)
                    .secondaryButton()
            }
        }
        .padding(24)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
