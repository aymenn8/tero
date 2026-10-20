import SwiftUI
import AppKit

struct ShortcutRecorder: View {
    let target: ShortcutTarget
    @Bindable var store = ShortcutRegistry.shared
    @State private var recording = false
    @State private var message: String?
    @State private var preview: [String] = []
    var body: some View {
        VStack(alignment: .trailing, spacing: 5) {
            HStack(spacing: 10) {
                Button(action: { message = nil; preview = []; recording = true }) {
                    Group {
                        if let chord = store.bindings[target.id] {
                            Text(chord.keycaps.joined(separator: " ")).font(.system(size: 13, weight: .medium))
                        } else { Text("Record shortcut").font(SettingsStyle.font(11)) }
                    }
                    // An unassigned shortcut stays quiet: a long list of modes shouldn't read as a wall of buttons.
                    .foregroundStyle(store.bindings[target.id] == nil || store.disabled.contains(target.id) ? SettingsStyle.secondary : .white)
                    .frame(minWidth: 114, minHeight: 28)
                    .background(.white.opacity(store.bindings[target.id] == nil ? 0 : 0.025), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(recording ? 0.5 : store.bindings[target.id] == nil ? 0.12 : 0.18),
                            style: StrokeStyle(lineWidth: store.bindings[target.id] == nil ? 1 : 1.5, dash: store.bindings[target.id] == nil && !recording ? [3, 3] : []))
                    }
                }.buttonStyle(.plain).help("Record shortcut for " + target.title)
                .popover(isPresented: $recording, arrowEdge: .top) {
                    VStack(spacing: 0) {
                        VStack(spacing: 12) {
                            HStack(spacing: 5) {
                                if preview.isEmpty { Text("Press a shortcut").font(SettingsStyle.font(12)).foregroundStyle(SettingsStyle.secondary) }
                                ForEach(Array(preview.enumerated()), id: \.offset) { _, key in
                                    Text(key).font(.system(size: 17, weight: .medium))
                                        .frame(minWidth: 30, minHeight: 32).padding(.horizontal, 4)
                                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                }
                            }.frame(height: 68)
                            if let message { Text(message).font(SettingsStyle.font(10)).foregroundStyle(.orange) }
                        }.padding(20).frame(maxWidth: .infinity)
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                        HStack {
                            TeroLogoMark(size: 15)
                            Text(target.title).font(SettingsStyle.font(11, weight: .medium))
                            Spacer()
                            Button("Close  Esc") { recording = false }.buttonStyle(.plain).font(SettingsStyle.font(10)).foregroundStyle(SettingsStyle.secondary)
                        }.padding(12)
                    }.frame(width: 300).background(SettingsStyle.background)
                    .background { ShortcutRecordingControl(target: target, store: store, onRecording: { recording = $0 }, onMessage: { message = $0 }, onPreview: { preview = $0 }) }
                }
                if store.bindings[target.id] != nil {
                    Toggle("Enable shortcut for " + target.title, isOn: Binding(get: { store.isEnabled(target) }, set: { message = store.setEnabled($0, for: target) }))
                        .labelsHidden().toggleStyle(.checkbox).help("Enable or disable this shortcut")
                    Button("Remove shortcut for " + target.title, systemImage: "xmark", action: removeShortcut)
                        .labelStyle(.iconOnly).font(.system(size: 9, weight: .medium)).foregroundStyle(SettingsStyle.secondary)
                        .frame(width: 20, height: 26).buttonStyle(.plain).help("Remove shortcut")
                }
            }
            if !recording, let issue = message ?? store.errors[target.id] {
                Text(issue).font(SettingsStyle.font(10)).foregroundStyle(.orange.opacity(0.85)).frame(maxWidth: 190, alignment: .trailing).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func removeShortcut() {
        message = store.set(nil, for: target)
    }
}

private struct ShortcutRecordingControl: NSViewRepresentable {
    let target: ShortcutTarget
    let store: ShortcutRegistry
    let onRecording: (Bool) -> Void
    let onMessage: (String?) -> Void
    let onPreview: ([String]) -> Void
    func makeNSView(context: Context) -> ShortcutRecordingView { let view = ShortcutRecordingView(); configure(view); return view }
    func updateNSView(_ view: ShortcutRecordingView, context: Context) { configure(view) }
    static func dismantleNSView(_ view: ShortcutRecordingView, coordinator: ()) { view.endRecording() }
    private func configure(_ view: ShortcutRecordingView) {
        view.store = store; view.target = target; view.onRecording = onRecording; view.onMessage = onMessage; view.onPreview = onPreview
        view.setAccessibilityElement(true); view.setAccessibilityRole(.button)
        view.setAccessibilityLabel("Shortcut for " + target.title)
        view.setAccessibilityValue(store.bindings[target.id]?.keycaps.joined(separator: " ") ?? "Not set")
    }
}

private final class ShortcutRecordingView: NSView {
    var store: ShortcutRegistry?
    var target = ShortcutTarget.open
    var onRecording: ((Bool) -> Void)?
    var onMessage: ((String?) -> Void)?
    var onPreview: (([String]) -> Void)?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { DispatchQueue.main.async { [weak self] in self?.beginRecording() } } else { endRecording() }
    }
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var recording = false
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { if recording { endRecording() } else { beginRecording() } }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 49 { beginRecording() } else { super.keyDown(with: event) }
    }
    override func accessibilityPerformPress() -> Bool { beginRecording(); return true }
    private func beginRecording() {
        guard !recording, let window else { return }
        window.makeKey()
        window.makeFirstResponder(self)
        recording = true; store?.suspend(); onMessage?(nil); onRecording?(true)
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endRecording() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                // SwiftUI popovers can route keyboard events through their hosting window.
                // Capture local app events for the lifetime of this visible recorder instead
                // of relying on event.window or transient first-responder changes.
                guard let self, self.recording, self.window != nil, NSApp.isActive else { return false }
                let flags = event.modifierFlags
                self.onPreview?([(NSEvent.ModifierFlags.control,"⌃"),(.option,"⌥"),(.shift,"⇧"),(.command,"⌘")].compactMap { flags.contains($0.0) ? $0.1 : nil })
                if event.type == .flagsChanged { return false }
                return self.record(event) == nil
            }
            return consumed ? nil : event
        }
    }
    func endRecording() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        store?.resume(); onRecording?(false)
    }
    private func record(_ event: NSEvent) -> NSEvent? {
        if event.keyCode == 53 { endRecording(); return nil }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.intersection([.command, .control, .option, .shift]).isEmpty {
            if event.keyCode == 48 { endRecording(); return event }
            if event.keyCode == 51 || event.keyCode == 117 {
                onMessage?(store?.set(nil, for: target)); endRecording(); return nil
            }
        }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= ShortcutChord.command }
        if flags.contains(.control) { modifiers |= ShortcutChord.control }
        if flags.contains(.option) { modifiers |= ShortcutChord.option }
        if flags.contains(.shift) { modifiers |= ShortcutChord.shift }
        let names: [UInt16: String] = [36:"↩",48:"⇥",49:"Space",51:"⌫",117:"⌦",123:"←",124:"→",125:"↓",126:"↑"]
        let key = names[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        let chord = ShortcutChord(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
        if let error = store?.set(chord, for: target) { onMessage?(error); return nil }
        onMessage?(nil); endRecording(); return nil
    }
}
