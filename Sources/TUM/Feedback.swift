import SwiftUI
import AppKit

/// Feedback goes to TUM's GitHub Issues (AK): free, with no server and no secrets in the app.
/// TUM fills in a new issue in the browser, so the person sees exactly what is sent and sends it
/// themselves. Only their words and the TUM and macOS versions go in, never diagnostics.
enum Feedback {
    static let repo = "https://github.com/araje-bot/TUM-Token-Utilization-Monitor"
    static let maxLength = 2000

    /// GitHub turns away very long links, so emoji-heavy text is trimmed until the link fits.
    static let maxURLLength = 8000

    static func issueURL(_ text: String) -> URL? {
        var words = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
        while let url = link(words), url.absoluteString.utf8.count > maxURLLength {
            words = String(words.dropLast(max(1, words.count / 10)))
        }
        return link(words)
    }

    private static func link(_ words: String) -> URL? {
        guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let first = words.split(whereSeparator: \.isNewline).first.map(String.init) ?? words
        let title = "Feedback: " + (first.count > 60 ? String(first.prefix(59)) + "…" : first)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let body = words + "\n\n---\nTUM \(version), macOS \(os.majorVersion).\(os.minorVersion)"
        guard var c = URLComponents(string: repo + "/issues/new") else { return nil }
        c.queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "body", value: body)]
        // A "+" would read as a space on GitHub's side.
        let query = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        c.percentEncodedQuery = query
        return c.url
    }
}

/// The "Any issues? Let us know" link, a plain text button in the accent color (HIG).
struct FeedbackLink: View {
    var action: () -> Void
    var body: some View {
        Button("Any issues? Let us know", action: action)
            .buttonStyle(.link)
            .font(.callout)
            .help("Send feedback to the TUM team")
    }
}

/// A text box and one button. Sending opens the filled-in GitHub issue in the browser.
struct FeedbackForm: View {
    var sent: () -> Void = {}
    @State private var text = ""
    @FocusState private var focused: Bool

    private var empty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(height: 120)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("What went wrong, or what would help?")
                                .font(.body).foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Your feedback")
                    .onChange(of: text) { t in
                        if t.count > Feedback.maxLength { text = String(t.prefix(Feedback.maxLength)) }
                    }
            }
            Text("This opens a public issue on TUM's GitHub page, so you can check it before sending. Leave out anything private.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(action: send) { ButtonText("Continue on GitHub") }
                    .primaryButton()
                    .disabled(empty)
            }
        }
        .onAppear { focused = true }
    }

    private func send() {
        guard let url = Feedback.issueURL(text) else { return }
        NSWorkspace.shared.open(url)
        text = ""
        sent()
    }
}

/// Feedback as a page inside the popover, with the same back button as an app's detail.
struct FeedbackPage: View {
    var back: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button("Back", systemImage: "chevron.left", action: back)
                    .iconButton()
                    .help("Back")
                Text("Send feedback").font(.title3.weight(.semibold))
                Spacer(minLength: 0)
            }
            FeedbackForm(sent: back)
        }
        .padding(16)
    }
}

/// Feedback as a sheet in Settings.
struct FeedbackSheet: View {
    var done: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Send feedback").font(.title2.bold())
                Spacer()
                Button(action: done) { ButtonText("Cancel") }.secondaryButton()
            }
            FeedbackForm(sent: done)
        }
        .padding(20)
        .frame(width: 440)
    }
}
