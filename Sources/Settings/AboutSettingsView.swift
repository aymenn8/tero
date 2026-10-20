import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 12) {
                Image(nsImage: TeroLogoMark.appIcon).resizable().interpolation(.high).frame(width: 72, height: 72)
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Tero").font(SettingsStyle.font(23, weight: .semibold))
                Text("\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.1") · Beta")
                    .font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 15)
            SettingsGroup(title: "Updates") {
                SettingsRow(title: "Check for updates", detail: AppUpdates.shared.available
                            ? "Get the latest version of Tero."
                            : "Automatic updates are available in Tero Prod. This is Tero Dev.") {
                    Button("Check for updates…", action: AppUpdates.shared.check)
                        .buttonStyle(SettingsPill())
                        .disabled(!AppUpdates.shared.available || !AppUpdates.shared.canCheck)
                }
            }
            SettingsGroup(title: "Explore") {
                SettingsRow(title: "Tero Manual", detail: "Actions, shortcuts and how Tero works.") { Button("Read") { SettingsStyle.open("docs") }.buttonStyle(SettingsPill()) }
                SettingsDivider()
                SettingsRow(title: "Changelog", detail: "New features and improvements.") { Button("View") { SettingsStyle.open("changelog") }.buttonStyle(SettingsPill()) }
                SettingsDivider()
                SettingsRow(title: "Email updates", detail: "Choose whether to receive changelogs in your account.") { Button("Manage") { AccountStore.shared.openBilling() }.buttonStyle(SettingsPill()) }
            }
            SettingsGroup(title: "Contact") {
                SettingsRow(title: "Help & feedback", detail: "aymen@kadri.live") { Button("Send feedback") { FeedbackWindow.shared.show() }.buttonStyle(SettingsPill()) }
            }
            Text("Tero is in beta. More actions and improvements are on the way.").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary)
        }
    }
}

@MainActor final class FeedbackWindow: NSWindowController {
    static let shared = FeedbackWindow()
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Send Feedback"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(white: 0.095, alpha: 1)
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() {
        if window?.isVisible != true {
            window?.setContentSize(NSSize(width: 440, height: 600))
            window?.contentView = NSHostingView(rootView: FeedbackForm().preferredColorScheme(.dark))
            window?.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct FeedbackForm: View {
    @State private var category = ""
    @State private var description = ""
    @State private var diagnostics = false
    @State private var submitting = false
    @State private var sent = false
    @State private var error: String?
    @State private var submissionID = UUID()
    @State private var task: Task<Void, Never>?
    private var valid: Bool { !category.isEmpty && (10...8000).contains(description.trimmingCharacters(in: .whitespacesAndNewlines).count) }
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(systemName: sent ? "checkmark.bubble.fill" : "bubble.left.and.exclamationmark.bubble.right.fill")
                    .font(.system(size: 28)).foregroundStyle(sent ? Color.green : Color.blue)
                    .frame(width: 54, height: 54).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                Text(sent ? "Thanks for your feedback." : "Send Feedback").font(SettingsStyle.font(23, weight: .semibold))
                Text(sent ? "Your message helps shape the next version of Tero." : "Found a bug or have an idea? We'd love to hear it.")
                    .font(SettingsStyle.font(12)).foregroundStyle(SettingsStyle.secondary).multilineTextAlignment(.center).lineSpacing(3)
            }.padding(.top, 48).padding(.bottom, 28)
            if !sent {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Category").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary)
                    Picker("Category", selection: $category) {
                        Text("Select a category").tag("")
                        Text("Bug report").tag("bug")
                        Text("Feature request").tag("idea")
                        Text("Other feedback").tag("other")
                    }.labelsHidden().frame(maxWidth: .infinity).controlSize(.large)
                    Text("Description").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).padding(.top, 8)
                    ZStack(alignment: .topLeading) {
                        if description.isEmpty { Text("Tell us what happened or what you'd like to see…").font(SettingsStyle.font(12)).foregroundStyle(SettingsStyle.secondary).padding(10).allowsHitTesting(false) }
                        TextEditor(text: $description).font(SettingsStyle.font(12)).scrollContentBackground(.hidden).padding(6)
                    }.frame(height: 140).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14)) }
                    HStack { Text("At least 10 characters"); Spacer(); Text("\(description.count) / 8000") }.font(SettingsStyle.font(10)).foregroundStyle(SettingsStyle.secondary)
                    Toggle("Include app & macOS version", isOn: $diagnostics).font(SettingsStyle.font(12)).padding(.top, 12)
                    Text("No prompts, clipboard content or logs are included.").font(SettingsStyle.font(10)).foregroundStyle(SettingsStyle.secondary)
                    if let error { Text(error).font(SettingsStyle.font(11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                    if AccountStore.shared.user == nil {
                        Button("Sign in to send feedback") { AccountStore.shared.signIn() }.buttonStyle(SettingsPill())
                    }
                }.disabled(submitting).padding(.horizontal, 24)
            }
            Spacer(minLength: 16)
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            HStack {
                Button(sent ? "Close" : "Cancel") { FeedbackWindow.shared.close() }.keyboardShortcut(.cancelAction).buttonStyle(SettingsPill())
                Spacer()
                if !sent {
                    Button(submitting ? "Sending…" : "Submit Feedback", action: submit).keyboardShortcut(.return, modifiers: .command)
                        .buttonStyle(SettingsPill()).disabled(!valid || submitting || AccountStore.shared.user == nil)
                }
            }.padding(18)
        }.frame(width: 440, height: sent ? 280 : 600).background(SettingsStyle.background)
            .onChange(of: sent) { _, value in if value { FeedbackWindow.shared.window?.setContentSize(NSSize(width: 440, height: 280)) } }
            .onChange(of: description) { _, value in if value.count > 8000 { description = String(value.prefix(8000)) } }
            .onDisappear { task?.cancel() }
    }
    private func submit() {
        guard valid, !submitting else { return }
        submitting = true; error = nil
        let id = submissionID, text = description, kind = category, include = diagnostics
        task = Task { @MainActor in
            do {
                try await AccountStore.shared.submitFeedback(id: id, category: kind, description: text, diagnostics: include)
                guard !Task.isCancelled else { return }
                sent = true
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
            submitting = false
        }
    }
}
