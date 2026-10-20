import Foundation

@main struct OnboardingSmoke {
    static func main() {
        let name = "tero.onboarding.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var flow = OnboardingProgress(defaults: defaults)
        func advance(_ account: Bool = false, _ shortcut: Bool = true, _ demo: Bool = true, _ access: Bool = true) {
            flow.advance(accountReady: account, shortcutReady: shortcut, demoDone: demo, accessReady: access)
        }
        precondition(!flow.isComplete)
        flow.present()
        precondition(!flow.complete(exerciseSucceeded: true))
        advance()
        precondition(flow.step == .shortcut)
        advance(false, true, false)
        precondition(flow.step == .shortcut)
        advance(false, false)
        precondition(flow.step == .shortcut)
        advance()
        precondition(flow.step == .capabilities)
        flow.advance(accountReady: false, shortcutReady: true, demoDone: true, accessReady: true)
        precondition(flow.step == .permission, "Feature previews never require interaction")
        precondition(flow.step == .permission)
        advance(false, true, true, false)
        precondition(flow.step == .permission)
        advance()
        precondition(flow.step == .account)
        advance()
        precondition(flow.step == .account)
        advance(true)
        precondition(flow.step == .practice)
        precondition(!flow.complete(exerciseSucceeded: false))
        flow.close()
        precondition(!flow.isComplete)
        flow.present()
        advance(true); advance(true); advance(true); advance(true)
        precondition(flow.step == .practice, "Connected accounts skip sign-in")
        flow.back(accountReady: true)
        precondition(flow.step == .permission, "Back also skips the connected account page")
        advance(true)
        precondition(flow.complete(exerciseSucceeded: true))
        precondition(flow.isComplete && !flow.isPresented)
        var restarted = OnboardingProgress(defaults: defaults)
        precondition(restarted.isComplete)
        restarted.present(); restarted.back(); restarted.close()
        precondition(restarted.step == .welcome && restarted.isComplete)
        print("PASS: demo/access/account gates, account skip, result-only completion, interruption, persistence and replay")
    }
}
