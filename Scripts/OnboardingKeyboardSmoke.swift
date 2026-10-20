import AppKit
import Carbon

enum Action: String { case translate; var title: String { rawValue } }
struct ActionDefinition { let id: Action }
enum ActionCatalog { static let definitions = [ActionDefinition(id: .translate)] }
@MainActor final class RecordingRegistrar: ShortcutRegistering {
    var onTrigger: (() -> Void)?
    func register(keyCode: UInt32, modifiers: UInt32) -> OSStatus { noErr }
    func unregister() {}
}
@main struct OnboardingKeyboardSmoke {
    @MainActor static func main() {
        let suite = "tero.onboarding.keyboard." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ShortcutRegistry(defaults: defaults, factory: { RecordingRegistrar() })
        store.start()
        let keyboard = OnboardingKeyboard(store: store)
        func event(_ type: NSEvent.EventType, _ code: UInt16, _ key: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code)!
        }
        keyboard.begin()
        _ = keyboard.receive(event(.keyDown, 40, "k", [.command, .shift]))
        precondition(keyboard.recording && keyboard.pressed == Set(["⇧", "⌘", "K"]))
        precondition(store.bindings["open"] == .standard, "Do not save until release")
        _ = keyboard.receive(event(.keyUp, 40, "k", [.command, .shift]))
        precondition(!keyboard.recording && store.bindings["open"]?.keyCode == 40)
        precondition(keyboard.pressed.isEmpty)
        keyboard.begin()
        _ = keyboard.receive(event(.keyDown, 0, "a"))
        precondition(keyboard.message != nil && keyboard.recording)
        _ = keyboard.receive(event(.keyDown, 53, ""))
        precondition(!keyboard.recording && store.bindings["open"]?.keyCode == 40)
        let duplicate = ShortcutChord(keyCode: 8, modifiers: ShortcutChord.control, key: "C")
        precondition(store.set(duplicate, for: .clipboard) == nil)
        keyboard.begin()
        _ = keyboard.receive(event(.keyDown, 8, "c", [.control]))
        _ = keyboard.receive(event(.keyUp, 8, "c", [.control]))
        precondition(keyboard.recording && keyboard.message?.contains("Clipboard") == true)
        precondition(store.bindings["open"]?.keyCode == 40)
        keyboard.stop()
        precondition(!keyboard.recording && keyboard.pressed.isEmpty)
        _ = keyboard.receive(event(.keyDown, 40, "k", [.command, .shift]))
        precondition(keyboard.pressed.contains("K"))
        _ = keyboard.receive(event(.keyUp, 40, "k"))
        precondition(keyboard.pressed.isEmpty)
        _ = store.setEnabled(false, for: .open)
        keyboard.begin()
        _ = keyboard.receive(event(.keyDown, 40, "k", [.command, .shift]))
        _ = keyboard.receive(event(.keyUp, 40, "k", [.command, .shift]))
        precondition(store.isEnabled(.open) && !keyboard.recording)
        var invocations = 0
        keyboard.onInvoke = { invocations += 1 }
        precondition(keyboard.receive(event(.keyDown, 40, "k", [.command, .shift])) == nil)
        precondition(invocations == 1)
        _ = keyboard.receive(event(.keyDown, 40, "k", [.command]))
        precondition(invocations == 1, "Require the exact modifier mask")
        _ = store.setEnabled(false, for: .open)
        _ = keyboard.receive(event(.keyDown, 40, "k", [.command, .shift]))
        precondition(invocations == 1, "Disabled shortcuts cannot invoke locally")
        store.stop()
        print("PASS: release-to-save, pressed feedback, invalid chord, Escape, duplicate preservation, teardown, enable")
    }
}
