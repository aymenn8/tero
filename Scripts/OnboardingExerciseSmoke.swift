import AppKit
import SwiftUI

// Shortcut and account boundaries are injected; no external clients are linked here.
struct ShortcutTarget: Equatable { static let open = Self(); let id = "open" }
@MainActor final class ShortcutRegistry {
    static let shared = ShortcutRegistry()
    let errors: [String: String] = [:]
    func isEnabled(_ target: ShortcutTarget) -> Bool { true }
}
struct OnboardingView: View {
    let flow: OnboardingController
    var body: some View { Color.black }
}
@main struct OnboardingExerciseSmoke {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let name = "tero.onboarding.exercise." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let flow = OnboardingController()
        flow.progress = OnboardingProgress(defaults: defaults)
        let text = NSTextView()
        text.string = OnboardingController.practiceExample
        flow.editor = text
        func startPractice() {
            flow.cancelWork(); flow.progress.present(); flow.introReady = true; flow.exerciseSucceeded = false
            for _ in 0..<4 { flow.progress.advance(accountReady: true, shortcutReady: true, demoDone: true, accessReady: true) }
            text.string = OnboardingController.practiceExample; text.selectAll(nil)
        }
        func key(_ code: UInt16) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
        }
        startPractice()
        _ = flow.consume(.open)
        precondition(flow.receivePracticeKey(key(124)) && flow.practiceIndex == 1)
        precondition(flow.receivePracticeKey(key(36)))
        try? await Task.sleep(for: .milliseconds(850))
        precondition(flow.exerciseSucceeded && text.string.contains("let's meet"))
        precondition(!flow.progress.isComplete)
        startPractice(); _ = flow.consume(.open)
        _ = flow.receivePracticeKey(key(124)); _ = flow.receivePracticeKey(key(124)); _ = flow.receivePracticeKey(key(36))
        precondition(flow.choosingLanguage)
        _ = flow.receivePracticeKey(key(36))
        try? await Task.sleep(for: .milliseconds(850))
        precondition(flow.exerciseSucceeded && text.string.hasPrefix("Salut Alex"))
        startPractice(); _ = flow.consume(.open); flow.addToCalendar()
        try? await Task.sleep(for: .milliseconds(850))
        precondition(flow.calendarPreview && !flow.exerciseSucceeded)
        _ = flow.receivePracticeKey(key(36))
        precondition(flow.exerciseSucceeded && !flow.calendarPreview)
        startPractice(); _ = flow.consume(.open); flow.correct(); flow.back()
        try? await Task.sleep(for: .milliseconds(850))
        precondition(!flow.exerciseSucceeded && text.string == OnboardingController.practiceExample)
        startPractice(); _ = flow.consume(.open); flow.correct()
        text.string = "Changed while waiting"
        try? await Task.sleep(for: .milliseconds(850))
        precondition(!flow.exerciseSucceeded && text.string == "Changed while waiting")
        flow.cancelWork(); flow.progress.present(); flow.introReady = true
        for _ in 0..<2 { flow.progress.advance(accountReady: false, shortcutReady: true, demoDone: true, accessReady: true) }
        precondition(flow.progress.step == .capabilities)
        precondition(flow.receivePracticeKey(key(36)))
        precondition(flow.progress.step == .permission, "Return continues immediately without feature demos")
        flow.back(); precondition(flow.progress.step == .capabilities)
        flow.next(); precondition(flow.progress.step == .permission, "Continue is always available")
        flow.next(); precondition(flow.progress.step == .account)
        precondition(flow.visibleSteps.count == 6)
        flow.isAccountConnected = { true }
        flow.skipConnectedAccount()
        precondition(flow.progress.step == .practice && flow.visibleSteps.count == 5)
        flow.back(); precondition(flow.progress.step == .permission)
        flow.next(); precondition(flow.progress.step == .practice)
        flow.isAccountConnected = { false }
        flow.back(); precondition(flow.progress.step == .account)
        var signInCount = 0
        var cancelCount = 0
        var pendingSignIn = false
        flow.beginAccountSignIn = { signInCount += 1; pendingSignIn = true }
        flow.accountSignInPending = { pendingSignIn }
        flow.cancelAccountSignIn = { cancelCount += 1; pendingSignIn = false }
        flow.next(); precondition(flow.progress.step == .account, "Continue must not bypass sign-in")
        precondition(flow.receivePracticeKey(key(36)))
        precondition(signInCount == 1 && flow.progress.step == .account)
        _ = flow.receivePracticeKey(key(36))
        precondition(signInCount == 1, "Repeated Return must not restart sign-in")
        flow.deferAccount()
        precondition(cancelCount == 1 && !pendingSignIn && flow.progress.step == .practice)
        flow.back(); flow.signIn(); flow.back()
        precondition(cancelCount == 2 && !pendingSignIn && flow.progress.step == .permission)
        flow.next(); flow.signIn()
        flow.isAccountConnected = { true }; flow.skipConnectedAccount()
        precondition(flow.progress.step == .practice, "Verified browser return advances the tour")
        flow.progress.close(); flow.show()
        precondition(NSApp.windows.first { $0.title == "Welcome to Tero" }?.isVisible == false)
        try? await Task.sleep(for: .seconds(3))
        precondition(flow.introReady && flow.introFinished)
        // Exercise the actual window dispatch, not only the controller callback.
        let window = NSApp.windows.first { $0.title == "Welcome to Tero" }!
        window.sendEvent(key(36))
        precondition(flow.progress.step == .shortcut)
        flow.demoDone = false; _ = flow.consume(.open)
        window.sendEvent(key(124)); precondition(flow.practiceIndex == 1)
        window.sendEvent(key(124)); precondition(flow.practiceIndex == 2)
        window.sendEvent(key(123)); precondition(flow.practiceIndex == 1)
        window.sendEvent(key(36)); precondition(flow.working)
        try? await Task.sleep(for: .milliseconds(850))
        precondition(flow.demoDone && flow.demoResult == "I appreciate your help yesterday.")
        startPractice()
        window.contentView = text
        text.isEditable = false; text.isSelectable = true
        window.makeFirstResponder(text); text.selectAll(nil)
        let selection = text.selectedRange()
        _ = flow.consume(.open)
        window.sendEvent(key(124)); precondition(flow.practiceIndex == 1)
        window.sendEvent(key(124)); precondition(flow.practiceIndex == 2)
        window.sendEvent(key(123)); precondition(flow.practiceIndex == 1)
        precondition(text.selectedRange() == selection, "Action arrows must preserve the example selection")
        window.sendEvent(key(36))
        try? await Task.sleep(for: .milliseconds(850))
        precondition(flow.exerciseSucceeded && text.string.contains("let's meet"))
        window.contentView = NSHostingView(rootView: OnboardingView(flow: flow))
        flow.progress.present()
        for _ in 0..<4 { flow.progress.advance(accountReady: true, shortcutReady: true, demoDone: true, accessReady: true) }
        flow.exerciseSucceeded = true
        var completions = 0; flow.onComplete = { completions += 1 }
        flow.finish(); flow.finish()
        try? await Task.sleep(for: .seconds(2))
        precondition(!flow.finishing && completions == 1 && flow.progress.isComplete)
        precondition(!NSApp.windows.contains { $0.isVisible && ($0.title == "Tero farewell" || $0.title == "Welcome to Tero") })
        print("PASS: entirely local demos, keyboard choices, translation, calendar preview, cancellation, optional feature previews, intro and farewell")
    }
}
