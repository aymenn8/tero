import AppKit
import SwiftUI

struct ShortcutTarget: Equatable { static let open = Self(); let id = "open" }
@MainActor final class ShortcutRegistry {
    static let shared = ShortcutRegistry()
    var errors: [String:String] = [:]
    var bindings = ["open": ShortcutChord.standard]
    func isEnabled(_ target: ShortcutTarget) -> Bool { true }
    func suspend() {}
    func resume() {}
    func set(_ chord: ShortcutChord, for target: ShortcutTarget) -> String? { nil }
    func setEnabled(_ value: Bool, for target: ShortcutTarget) -> String? { nil }
}
@main struct OnboardingLayoutSmoke {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let name = "tero.onboarding.layout." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let flow = OnboardingController()
        flow.progress = OnboardingProgress(defaults: defaults)
        func assertSize(_ window: NSWindow) {
            let size = window.contentView!.bounds.size
            precondition(abs(size.width - 860) < 1 && abs(size.height - 660) < 1,
                         "SwiftUI transitions must not resize the native onboarding window: \(size)")
        }
        precondition(!flow.resumeFromDock(), "Dock must not start an unopened tour")
        flow.show()
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(500))
            let w = NSApp.windows.first { $0.title == "Welcome to Tero" }!
            assertSize(w)
        }
        let window = NSApp.windows.first { $0.title == "Welcome to Tero" }!
        precondition(flow.resumeFromDock(), "Dock resumes the active tour")
        flow.demoDone = true
        for _ in 0..<5 {
            if flow.progress.step == .account { flow.deferAccount() } else { flow.next() }
            try? await Task.sleep(for: .milliseconds(450))
            assertSize(window)
            if flow.progress.step == .capabilities, let view = window.contentView,
               let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/tero-capabilities-preview.png"))
            }
        }
        window.close()
        precondition(!flow.resumeFromDock() && !flow.progress.isPresented,
                     "Dock must not restart a closed unfinished tour")
        flow.show()
        try? await Task.sleep(for: .seconds(3))
        let reopened = NSApp.windows.first { $0.title == "Welcome to Tero" && $0 !== window }!
        assertSize(reopened)
        precondition(flow.progress.step == .welcome && flow.introReady && flow.introFinished)
        reopened.close()
        precondition(!flow.resumeFromDock())
        print("PASS: actual SwiftUI layout stays 860×660 through intro/all pages/replay; Dock resumes only open tours")
    }
}
