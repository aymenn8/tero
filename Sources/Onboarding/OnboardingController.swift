import AppKit
import SwiftUI
import Observation

@MainActor @Observable final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()
    var progress = OnboardingProgress()
    var finishing = false
    var introReady = false
    var introFinished = false
    var demoInvoked = false
    var demoDone = false
    var exerciseInvoked = false
    var exerciseSucceeded = false
    var practiceIndex = 0
    var choosingLanguage = false
    var activityTitle = "Correcting"
    var successDetail = "Your words. Mistakes gone."
    var calendarPreview = false
    var demoResult = "Thanks for your help yesterday!"
    static let practiceExample = "Hey Alex, lets meet tomorrow from 3 to 3:30 PM to review the launch."
    var working = false
    var message: String?
    @ObservationIgnored weak var editor: NSTextView?
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var capturedText = ""
    @ObservationIgnored private var capturedRange = NSRange(location: 0, length: 0)
    @ObservationIgnored private var window: NSWindow?
    @ObservationIgnored private var introPanel: NSPanel?
    @ObservationIgnored private var finishPanel: NSPanel?
    @ObservationIgnored var onComplete: (() -> Void)?
    @ObservationIgnored var isAccountConnected: () -> Bool = { false }
    @ObservationIgnored var beginAccountSignIn: () -> Void = { }
    @ObservationIgnored var cancelAccountSignIn: () -> Void = { }
    @ObservationIgnored var accountSignInPending: () -> Bool = { false }
    @ObservationIgnored var accountSignInMessage: () -> String? = { nil }
    var accountConnected: Bool { isAccountConnected() }
    var signingIn: Bool { accountSignInPending() }
    var signInMessage: String? { accountSignInMessage() }
    var visibleSteps: [OnboardingProgress.Step] {
        OnboardingProgress.Step.allCases.filter { $0 != .account || !accountConnected }
    }
    var shortcutReady: Bool {
        ShortcutRegistry.shared.isEnabled(.open) && ShortcutRegistry.shared.errors[ShortcutTarget.open.id] == nil
    }
    func show() {
        guard !finishing else { return }
        if progress.isPresented {
            if introReady { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
            else { introPanel?.orderFrontRegardless() }
            return
        }
        cancelWork()
        introReady = false; introFinished = false; demoInvoked = false; demoDone = false; exerciseSucceeded = false
        progress.present()
        if window == nil {
            let window = OnboardingWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 660),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Welcome to Tero"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.backgroundColor = .black
            window.appearance = NSAppearance(named: .darkAqua)
            let hosting = NSHostingView(rootView: OnboardingView(flow: self).ignoresSafeArea())
            // AppKit owns window geometry. The empty intro and animated pages must
            // never change the window's size through SwiftUI intrinsic sizing.
            hosting.sizingOptions = []
            window.contentView = hosting
            window.setContentSize(NSSize(width: 860, height: 660))
            window.delegate = self
            window.onActionKey = { [weak self] event in self?.receivePracticeKey(event) ?? false }
            window.center()
            self.window = window
        }
        // Keep the actual onboarding window completely offscreen until the logo assembles.
        window?.orderOut(nil)
        presentIntro()
    }
    /// A Dock click may resume an open tour, but must not restart a closed one.
    @discardableResult func resumeFromDock() -> Bool {
        guard progress.isPresented, !finishing else { return false }
        show()
        return true
    }
    private func presentIntro() {
        introPanel?.close()
        guard let window else { return }
        let panel = NSPanel(contentRect: NSRect(x: window.frame.midX - 430, y: window.frame.midY - 360, width: 860, height: 720),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.contentView = NSHostingView(rootView: OnboardingWelcomeScene(
            onReveal: { [weak self] in self?.revealWindow() },
            onComplete: { [weak self] in self?.completeIntro() }))
        introPanel = panel
        panel.orderFrontRegardless()
    }
    private func revealWindow() {
        guard progress.isPresented, !introReady, let window else { return }
        introReady = true
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduced ? 0.2 : 0.5
            window.animator().alphaValue = 1
        }
    }
    private func completeIntro() {
        guard progress.isPresented, introReady else { return }
        introFinished = true
        introPanel?.close()
        introPanel = nil
    }

    func next() {
        // Setting up AI is optional: Continue always moves past that step.
        advance(accountReady: true)
    }
    private func advance(accountReady: Bool) {
        cancelWork()
        progress.advance(accountReady: accountReady, shortcutReady: shortcutReady, demoDone: demoDone,
                         accessReady: true)
    }
    func signIn() {
        guard progress.isPresented, progress.step == .account, !signingIn else { return }
        beginAccountSignIn()
    }
    func deferAccount() {
        guard progress.isPresented, progress.step == .account else { return }
        cancelAccountSignIn()
        advance(accountReady: true)
    }
    func back() {
        if progress.step == .account { cancelAccountSignIn() }
        cancelWork(); exerciseSucceeded = false; progress.back(accountReady: accountConnected)
    }
    func skipConnectedAccount() {
        if progress.isPresented, progress.step == .account, accountConnected { next() }
    }
    func cancelWork() {
        generation = UUID(); work?.cancel(); work = nil
        calendarPreview = false
        choosingLanguage = false
        working = false; exerciseInvoked = false; message = nil
        capturedText = ""; capturedRange = NSRange(location: 0, length: 0)
    }
    /// Invoked by the registered global shortcut or the focused window’s exact chord.
    func consume(_ target: ShortcutTarget) -> Bool {
        guard progress.isPresented || finishing else { return false }
        guard introReady, !finishing, target == .open, shortcutReady else { return true }
        switch progress.step {
        case .shortcut: demoInvoked = true; practiceIndex = 0
        case .practice:
            guard !working, !exerciseSucceeded, !calendarPreview else { return true }
            guard let editor, editor.selectedRange().length > 0 else {
                message = "Select some text in the example first."; return true
            }
            capturedText = editor.string; capturedRange = editor.selectedRange()
            exerciseInvoked = true; practiceIndex = 0; choosingLanguage = false; message = nil
        default: break
        }
        return true
    }
    func runDemo() {
        guard demoInvoked, !working else { return }
        working = true
        let id = generation
        work = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
            guard let self, generation == id, progress.step == .shortcut else { return }
            demoResult = ["Thanks for your help yesterday!", "I appreciate your help yesterday.", "Merci pour ton aide hier !"][practiceIndex]
            working = false; demoDone = true; work = nil
        }
    }
    func chooseTranslation() { choosingLanguage = true; practiceIndex = 0 }
    func selectExample() {
        guard !working, !exerciseSucceeded, let editor else { return }
        editor.window?.makeFirstResponder(editor)
        editor.selectAll(nil)
        message = "Selection ready. Press your Tero shortcut to see the actions."
    }
    func escape() {
        if calendarPreview {
            calendarPreview = false
        } else if choosingLanguage {
            choosingLanguage = false; practiceIndex = 2
        } else { cancelWork() }
    }
    /// Local keyboard routes teach the same arrows/Return gesture in every demo.
    func receivePracticeKey(_ event: NSEvent) -> Bool {
        guard progress.isPresented, introReady, !finishing, event.type == .keyDown,
              editor?.hasMarkedText() != true,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        let isReturn = event.keyCode == 36
        let direction: Int = [123,126].contains(event.keyCode) ? -1 : [124,125].contains(event.keyCode) ? 1 : 0
        guard isReturn || direction != 0 else { return false }
        if working { return true }
        switch progress.step {
        case .welcome: if isReturn { next() }
        case .shortcut:
            guard demoInvoked else { return false }
            if demoDone { if isReturn { next() } }
            else if direction != 0 { practiceIndex = (practiceIndex + direction + 3) % 3 }
            else { runDemo() }
        case .capabilities: if isReturn { next() }
        case .permission: if isReturn { next() }
        case .account: if isReturn { next() }
        case .practice:
            if exerciseSucceeded { if isReturn { finish() }; return true }
            if calendarPreview { if isReturn { createDemoEvent() }; return true }
            guard exerciseInvoked else { if isReturn { selectExample(); return true }; return false }
            let count = choosingLanguage ? 4 : 3
            if direction != 0 { practiceIndex = (practiceIndex + direction + count) % count }
            else if choosingLanguage {
                if practiceIndex == 3 { choosingLanguage = false; practiceIndex = 2 }
                else { translate(to: [ResponseLanguage.french, .english, .spanish][practiceIndex]) }
            } else {
                switch practiceIndex {
                case 0: addToCalendar()
                case 1: correct()
                default: chooseTranslation()
                }
            }
        }
        return true
    }
    func correct() { runAction(.correct) }
    func translate(to language: ResponseLanguage) { runAction(.translate, language: language) }
    func addToCalendar() { runAction(.calendar) }
    private enum ExerciseAction { case correct, translate, calendar }
    private func runAction(_ action: ExerciseAction, language: ResponseLanguage = .french) {
        guard exerciseInvoked, !working, let editor else { return }
        guard editor.string == capturedText, editor.selectedRange() == capturedRange,
              capturedRange.length > 0, NSMaxRange(capturedRange) <= (capturedText as NSString).length else {
            cancelWork(); message = "The selection changed. Select the example and press your shortcut again."; return
        }
        let source = capturedText, range = capturedRange
        guard source == Self.practiceExample, range.location == 0, range.length == (source as NSString).length else {
            message = "This guided demo uses the full example. Press Command-A, then your shortcut."; return
        }
        working = true; message = nil; choosingLanguage = false
        activityTitle = action == .calendar ? "Preparing demo event" : action == .translate ? "Translating example" : "Correcting example"
        let id = generation
        work = Task { [weak self, weak editor] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            guard let self, generation == id, progress.isPresented, progress.step == .practice,
                  let editor, editor.string == source, editor.selectedRange() == range else {
                if let self, generation == id { working = false; exerciseInvoked = false; message = "The example changed. Try a fresh selection." }
                return
            }
            working = false; exerciseInvoked = false; work = nil
            if action == .calendar { calendarPreview = true; return }
            let result: String
            if action == .correct {
                result = "Hey Alex, let's meet tomorrow from 3 to 3:30 PM to review the launch."
            } else {
                switch language {
                case .french: result = "Salut Alex, retrouvons-nous demain de 15 h à 15 h 30 pour faire le point sur le lancement."
                case .spanish: result = "Hola Alex, reunámonos mañana de 15:00 a 15:30 para revisar el lanzamiento."
                default: result = "Hey Alex, let's meet tomorrow from 3 to 3:30 PM to review the launch."
                }
            }
            editor.string = result
            editor.setSelectedRange(NSRange(location: 0, length: (result as NSString).length))
            exerciseSucceeded = true
            successDetail = action == .translate ? "Demo translated to " + language.title + "." : "The example is corrected."
        }
    }
    func createDemoEvent() {
        guard calendarPreview, !working else { return }
        calendarPreview = false
        exerciseSucceeded = true
        successDetail = "Demo event added. Your real calendar is unchanged."
    }
    func finish() {
        guard progress.isPresented, progress.step == .practice, exerciseSucceeded, !finishing, let window else { return }
        // Snapshot only our own visible content before changing the completed UI state.
        let snapshot: NSImage?
        if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let image = NSImage(size: window.frame.size)
            image.addRepresentation(bitmap)
            snapshot = image
        } else { snapshot = nil }
        guard progress.complete(exerciseSucceeded: exerciseSucceeded) else { return }
        cancelWork(); finishing = true
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let snapshot else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                window.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in self?.finishDismissal() }
            }
            return
        }
        let margin: CGFloat = 250
        let panel = NSPanel(contentRect: window.frame.insetBy(dx: -margin, dy: -margin),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Tero farewell"
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.contentView = NSHostingView(rootView: OnboardingFinishScene(snapshot: snapshot, windowSize: window.frame.size,
            margin: margin, onComplete: { [weak self] in self?.finishDismissal() }))
        finishPanel = panel
        panel.orderFrontRegardless()
        window.orderOut(nil)
    }
    private func finishDismissal() {
        guard finishing else { return }
        finishPanel?.close(); finishPanel = nil
        window?.close(); window?.alphaValue = 1
        finishing = false; onComplete?()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !finishing }
    func windowWillClose(_ notification: Notification) {
        if progress.step == .account { cancelAccountSignIn() }
        introPanel?.close(); introPanel = nil
        finishPanel?.close(); finishPanel = nil
        cancelWork(); progress.close()
        if notification.object as? NSWindow === window {
            window = nil
            editor = nil
        }
    }
}

/// Route tutorial navigation before AppKit moves focus between SwiftUI buttons.
/// This stays with the window when SwiftUI replaces an animated step.
@MainActor final class OnboardingWindow: NSWindow {
    var onActionKey: ((NSEvent) -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onActionKey?(event) == true { return }
        super.sendEvent(event)
    }
}
