import AppKit
import SwiftUI
import Observation

/// Window-scoped key feedback. Only an explicit click starts recording.
@MainActor @Observable final class OnboardingKeyboard {
    var recording = false
    var pressed = Set<String>()
    var preview: [String] = []
    var message: String?
    var onInvoke: (() -> Void)?
    var onActionKey: ((NSEvent) -> Bool)?
    private var candidate: ShortcutChord?
    private var downKey: String?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private weak var window: NSWindow?
    private let store: ShortcutRegistry
    init(store: ShortcutRegistry = .shared) { self.store = store }
    func attach(to window: NSWindow?) {
        guard self.window !== window else { return }
        stop(); self.window = window
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, self.window?.isKeyWindow == true else { return false }
                return self.receive(event) == nil
            }
            return consumed ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }
    func begin() {
        guard !recording else { return }
        candidate = nil; preview = []; pressed = []; message = nil
        store.suspend(); recording = true
    }
    func cancel() {
        if recording { store.resume() }
        recording = false; candidate = nil; downKey = nil; preview = []; pressed = []
    }
    func stop() {
        cancel()
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        window = nil
    }
    func receive(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let modifiers: [(NSEvent.ModifierFlags, UInt32, String)] = [(.control, ShortcutChord.control, "⌃"), (.option, ShortcutChord.option, "⌥"), (.shift, ShortcutChord.shift, "⇧"), (.command, ShortcutChord.command, "⌘")]
        let caps = modifiers.filter { flags.contains($0.0) }.map(\.2)
        if event.type == .flagsChanged {
            pressed = Set(caps + (downKey.map { [$0] } ?? []))
            if recording, candidate == nil { preview = caps }
            return event
        }
        if event.type == .keyUp {
            downKey = nil
            pressed = Set(caps + (downKey.map { [$0] } ?? []))
            if recording, let candidate, event.keyCode == candidate.keyCode {
                message = store.set(candidate, for: .open)
                if message == nil {
                    message = store.setEnabled(true, for: .open)
                    cancel()
                } else { self.candidate = nil }
                return nil
            }
            return recording ? nil : event
        }
        guard !event.isARepeat else { return recording ? nil : event }
        if recording, event.keyCode == 53 { cancel(); return nil }
        let names: [UInt16: String] = [36:"↩",48:"⇥",49:"Space",51:"⌫",117:"⌦",123:"←",124:"→",125:"↓",126:"↑"]
        let key = names[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        if !recording {
            if onActionKey?(event) == true { return nil }
            // Local fallback while the onboarding window owns focus. Carbon handles global use.
            let mask = modifiers.filter { flags.contains($0.0) }.reduce(UInt32(0)) { $0 | $1.1 }
            if let chord = store.bindings[ShortcutTarget.open.id], UInt32(event.keyCode) == chord.keyCode,
               mask == chord.modifiers, store.isEnabled(.open), let onInvoke {
                downKey = chord.key; pressed = Set(caps + [chord.key])
                onInvoke()
                return nil
            }
            // Match physical codes so feedback works independently of keyboard layout.
            if let chord = store.bindings[ShortcutTarget.open.id], event.keyCode == chord.keyCode { downKey = chord.key; pressed = Set(caps + [chord.key]) }
            else { pressed = Set(caps) }
            return event
        }
        if event.keyCode == 48, flags.isEmpty { cancel(); return event }
        let mask = modifiers.filter { flags.contains($0.0) }.reduce(UInt32(0)) { $0 | $1.1 }
        let chord = ShortcutChord(keyCode: UInt32(event.keyCode), modifiers: mask, key: key)
        downKey = key; preview = caps + [key]; pressed = Set(preview)
        guard chord.isValid else { message = "Use ⌘, ⌃ or ⌥ with a key."; candidate = nil; return nil }
        candidate = chord; message = nil
        return nil
    }
}

struct OnboardingKeyboardCapture: NSViewRepresentable {
    let keyboard: OnboardingKeyboard
    func makeNSView(context: Context) -> CaptureView { let view = CaptureView(); view.keyboard = keyboard; return view }
    func updateNSView(_ view: CaptureView, context: Context) { view.keyboard = keyboard }
    static func dismantleNSView(_ view: CaptureView, coordinator: ()) { view.keyboard?.stop() }
    final class CaptureView: NSView {
        var keyboard: OnboardingKeyboard?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Avoid publishing observation changes during a SwiftUI layout pass.
            Task { @MainActor [weak self] in guard let self else { return }; keyboard?.attach(to: window) }
        }
    }
}
