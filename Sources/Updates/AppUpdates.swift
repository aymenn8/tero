import AppKit
import Sparkle
import Observation

/// Only the production bundle may update itself; Dev never installs a public build.
@MainActor
@Observable
final class AppUpdates {
    static let shared = AppUpdates()
    @ObservationIgnored private var observation: NSKeyValueObservation?
    var canCheck = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    var available: Bool { Bundle.main.bundleIdentifier == "com.aymenkadri.tero" }

    func start() {
        guard available, controller == nil else { return }
        let updates = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller = updates
        observation = updates.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let allowed = change.newValue ?? false
            Task { @MainActor [weak self] in self?.canCheck = allowed }
        }
    }

    func menuItem() -> NSMenuItem? {
        guard let controller else { return nil }
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        item.target = controller
        return item
    }

    func check() { controller?.checkForUpdates(nil) }
}
