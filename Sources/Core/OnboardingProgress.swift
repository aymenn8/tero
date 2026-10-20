import Foundation

/// Closing or pressing a shortcut never completes setup. Only a successful exercise does.
struct OnboardingProgress {
    enum Step: Int, CaseIterable { case welcome, shortcut, capabilities, permission, account, practice }
    private(set) var step: Step = .welcome
    private(set) var isPresented = false
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var isComplete: Bool { defaults.bool(forKey: "onboardingCompletedV1") }
    mutating func present() { step = .welcome; isPresented = true }
    mutating func close() { isPresented = false }
    mutating func back(accountReady: Bool = false) {
        step = Step(rawValue: max(0, step.rawValue - 1)) ?? .welcome
        if step == .account && accountReady { step = .permission }
    }
    mutating func advance(accountReady: Bool, shortcutReady: Bool, demoDone: Bool, accessReady: Bool) {
        guard isPresented, step != .practice else { return }
        guard step != .shortcut || (shortcutReady && demoDone) else { return }
        guard step != .permission || accessReady else { return }
        guard step != .account || accountReady else { return }
        step = Step(rawValue: step.rawValue + 1) ?? step
        if step == .account && accountReady { step = .practice }
    }
    mutating func complete(exerciseSucceeded: Bool) -> Bool {
        guard isPresented, step == .practice, exerciseSucceeded else { return false }
        defaults.set(true, forKey: "onboardingCompletedV1")
        isPresented = false
        return true
    }
}
