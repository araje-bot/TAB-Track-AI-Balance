import SwiftUI
import AppKit

/// Feedback anyone can send (AK): no GitHub account, no browser, no sign-in. TUM sends the note
/// straight to a Google Form the TUM team owns; Google can email each one to the team and keeps
/// them all in a sheet. Only what the person types, an optional reply email, and the TUM and
/// macOS versions are sent. Never diagnostics. Until the form is set up, and for people who
/// prefer it, a filled-in GitHub issue is the other way.
enum Feedback {
    static let repo = "https://github.com/araje-bot/TUM-Token-Utilization-Monitor"
    static let maxLength = 2000
    /// GitHub turns away very long links, so emoji-heavy text is trimmed until the link fits.
    static let maxURLLength = 8000

    /// The team's Google Form. From the form's "Get pre-filled link": the id in
    /// .../forms/d/e/<formID>/viewform, and each question's "entry.<number>".
    struct Config: Equatable {
        var formID: String
        var message: String
        var email: String
        var version: String
        var ready: Bool {
            formID.range(of: #"^[A-Za-z0-9_-]{20,120}$"#, options: .regularExpression) != nil
                && [message, email, version].allSatisfy { $0.range(of: #"^entry\.[0-9]{1,15}$"#, options: .regularExpression) != nil }
        }
    }
    /// "TUM feedback" in the team's Google Forms. Only these public ids, never a key.
    static var config = Config(formID: "1FAIpQLSdsAwcxngtGm5yRde79Wc-SBgOTu3JgHa7oL_ggH031kmMnRA",
                               message: "entry.1415545933", email: "entry.119013934", version: "entry.367937481")

    static var versionLine: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return "TUM \(version), macOS \(os.majorVersion).\(os.minorVersion)"
    }

    static func clean(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxLength))
    }

    /// A plain email address, or nothing. Optional, only for a reply.
    static func replyEmail(_ s: String) -> String? {
        let e = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard e.count <= 254, e.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else { return nil }
        return e
    }

    private static func fields(_ text: String, email: String) -> [(String, String)] {
        [(config.message, clean(text)), (config.email, replyEmail(email) ?? ""), (config.version, versionLine)]
    }

    /// Sends the note to the form. True when Google took it.
    static func send(_ text: String, email: String) async -> Bool {
        guard config.ready, !clean(text).isEmpty,
              let url = URL(string: "https://docs.google.com/forms/d/e/\(config.formID)/formResponse") else { return false }
        return (200..<300).contains(await HTTP.postForm(url, fields: fields(text, email: email), host: "docs.google.com"))
    }

    /// The same form in the browser, already filled in, if sending from TUM didn't work.
    static func formURL(_ text: String, email: String) -> URL? {
        guard config.ready, var c = URLComponents(string: "https://docs.google.com/forms/d/e/\(config.formID)/viewform") else { return nil }
        // The reply email stays out of the link, so it never lands in browser history.
        c.queryItems = [URLQueryItem(name: "usp", value: "pp_url")]
            + fields(text, email: "").filter { $0.0 != config.email }.map { URLQueryItem(name: $0.0, value: $0.1) }
        let query = c.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        c.percentEncodedQuery = query
        return c.url
    }

    static func issueURL(_ text: String) -> URL? {
        var words = clean(text)
        while let url = link(words), url.absoluteString.utf8.count > maxURLLength {
            words = String(words.dropLast(max(1, words.count / 10)))
        }
        return link(words)
    }

    private static func link(_ words: String) -> URL? {
        guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let first = words.split(whereSeparator: \.isNewline).first.map(String.init) ?? words
        let title = "Feedback: " + (first.count > 60 ? String(first.prefix(59)) + "…" : first)
        let body = words + "\n\n---\n" + versionLine
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

/// A text box, an optional reply email and Send. Sending stays in TUM; nothing opens.
struct FeedbackForm: View {
    var sent: () -> Void = {}
    @State private var text = ""
    @State private var email = ""
    @State private var phase: Phase = .writing
    @FocusState private var focused: Bool

    enum Phase { case writing, sending, sent, failed }

    private var empty: Bool { Feedback.clean(text).isEmpty }
    private var emailOK: Bool { email.trimmingCharacters(in: .whitespaces).isEmpty || Feedback.replyEmail(email) != nil }
    private var direct: Bool { Feedback.config.ready }

    var body: some View {
        if phase == .sent {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(Palette.green)
                Text("Thanks! The TUM team got your note.").font(.headline)
                Text(Feedback.replyEmail(email) != nil ? "We'll reply by email if we need more." : "We read every one.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { sent() } }
        } else {
            form
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(height: 110)
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
            if direct {
                Card {
                    TextField("Your email, if you'd like a reply", text: $email)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Your email, optional")
                }
            }
            Group {
                if phase == .failed {
                    Text("Couldn't send right now. Check your internet, or open the form in your browser.")
                        .foregroundStyle(Palette.amberText)
                } else if !emailOK {
                    Text("That email doesn't look right. Leave it empty if you don't need a reply.")
                        .foregroundStyle(Palette.amberText)
                } else if direct {
                    Text("Sent to the TUM team through Google Forms. No account needed. Leave out anything private.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("This opens a public issue on TUM's GitHub page, so you can check it before sending. Leave out anything private.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if direct {
                    Button("Use GitHub instead", action: openGitHub)
                        .buttonStyle(.link).font(.callout)
                        .disabled(empty)
                        .help("Open a public issue if you have a GitHub account")
                }
                Spacer(minLength: 0)
                if phase == .failed, let url = Feedback.formURL(text, email: email) {
                    Button { NSWorkspace.shared.open(url) } label: { ButtonText("Open in browser") }
                        .secondaryButton()
                }
                if direct {
                    Button(action: send) {
                        HStack(spacing: 6) {
                            if phase == .sending { ActivityRing(size: 14) }
                            Text(phase == .sending ? "Sending…" : "Send")
                        }
                        .frame(minWidth: ControlMetrics.minTextWidth)
                    }
                    .primaryButton()
                    .disabled(empty || !emailOK || phase == .sending)
                    .keyboardShortcut(.defaultAction)
                } else {
                    Button(action: openGitHub) { ButtonText("Open GitHub") }
                        .primaryButton()
                        .disabled(empty)
                }
            }
        }
        .onAppear { focused = true }
    }

    private func send() {
        phase = .sending
        Task {
            let ok = await Feedback.send(text, email: email)
            withAnimation(Motion.standard) { phase = ok ? .sent : .failed }
        }
    }

    private func openGitHub() {
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
