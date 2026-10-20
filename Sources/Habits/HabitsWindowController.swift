import AppKit
import SwiftUI

@MainActor
final class HabitsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let store = HabitEditorRouter()
    private let account = AccountStore.shared
    private let navigation = SettingsNavigation()
    var clipboard: ClipboardStore?
    var setDeveloper: (Bool) -> Void = { _ in }

    func show(createHabit: Bool = false, accountPage: Bool = false, habitsPage: Bool = false, aiPage: Bool = false) {
        navigation.page = aiPage ? .ai : accountPage ? .account : (createHabit || habitsPage ? .actions : .general)
        store.editorRequest = createHabit ? UUID() : nil
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 610),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Tero Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = NSColor(white: 0.095, alpha: 1)
            window.setFrameAutosaveName("TeroSettingsV2")
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: TeroSettingsView(navigation: navigation, habits: store, account: account, clipboard: clipboard, setDeveloper: setDeveloper).ignoresSafeArea(.container, edges: .top).background(SettingsStyle.background))
            let contentSize = NSSize(width: 800, height: 610)
            window.setContentSize(contentSize)
            window.contentMinSize = contentSize
            window.contentMaxSize = contentSize
            window.collectionBehavior = [.fullScreenNone]
            window.standardWindowButton(.zoomButton)?.isEnabled = false
            window.center()
            self.window = window
        }
        bringToFront()
    }

    /// Development only: renders every Settings page off screen to PNG files, without taking focus.
    func snapshotPages(to folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let size = NSSize(width: 800, height: 1500)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = NSColor(white: 0.095, alpha: 1)
        for page in SettingsNavigation.Page.allCases {
            navigation.page = page
            let host = NSHostingView(rootView: TeroSettingsView(navigation: navigation, habits: store, account: account,
                clipboard: clipboard, setDeveloper: setDeveloper).background(SettingsStyle.background))
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            window.orderFrontRegardless()
            try? await Task.sleep(for: .milliseconds(700))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let name = page.rawValue.lowercased().replacing(/[^a-z]+/, with: "-")
            try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appending(path: name + ".png"))
        }
        window.orderOut(nil)
    }

    func reopen() {
        guard window != nil else { show(); return }
        bringToFront()
    }

    private func bringToFront() {
        NSApp.setActivationPolicy(.regular)
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        account.cancelSignIn()
        NSApp.setActivationPolicy(.accessory)
    }

    func receiveAuthCallback(_ url: URL) -> Bool {
        guard account.receiveCallback(url) else { return false }
        show(accountPage: true)
        return true
    }
}
