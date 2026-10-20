import Foundation
import Carbon

// Minimal catalogue for this isolated shortcut registry check, no app or AI calls.
enum Action: String { case translate, rewrite; var title: String { rawValue.capitalized } }
struct ActionDefinition { let id: Action }
enum ActionCatalog { static let definitions = [ActionDefinition(id: .translate), ActionDefinition(id: .rewrite)] }

@MainActor final class FakeShortcut: ShortcutRegistering {
    var onTrigger: (() -> Void)?
    var reject = false
    var active = false
    func register(keyCode: UInt32, modifiers: UInt32) -> OSStatus { if reject { return -1 }; active = true; return noErr }
    func unregister() { active = false }
}
@main struct ShortcutsSmoke {
    @MainActor static func main() {
        let suite = "tero.shortcuts.fixture." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var managers: [FakeShortcut] = []
        let store = ShortcutRegistry(defaults: defaults) { let manager = FakeShortcut(); managers.append(manager); return manager }
        let ask = ShortcutChord(keyCode: 0, modifiers: ShortcutChord.command | ShortcutChord.shift, key: "A")
        precondition(ask.isValid && ask.keycaps == ["⇧", "⌘", "A"])
        precondition(!ShortcutChord(keyCode: 0, modifiers: ShortcutChord.shift, key: "A").isValid)
        precondition(store.bindings["open"] == .standard)
        store.start()
        precondition(store.set(ask, for: .ask) == nil)
        precondition(store.set(ask, for: .clipboard)?.contains("Ask") == true)
        precondition(store.bindings["clipboard"] == nil)
        var triggered: [String] = []
        store.onTrigger = { triggered.append($0.id) }
        managers.last!.onTrigger?()
        precondition(triggered == ["ask"])
        let previous = store.bindings["ask"]
        managers.last!.reject = true
        let different = ShortcutChord(keyCode: 1, modifiers: ShortcutChord.command | ShortcutChord.shift, key: "S")
        precondition(store.set(different, for: .ask) != nil)
        precondition(store.bindings["ask"] == previous && managers.last!.active)
        let restored = ShortcutRegistry(defaults: defaults) { FakeShortcut() }
        precondition(restored.bindings["ask"] == ask)
        precondition(store.setEnabled(false, for: .ask) == nil)
        precondition(store.bindings["ask"] == ask && !store.isEnabled(.ask))
        precondition(!managers.last!.active)
        let disabledRestored = ShortcutRegistry(defaults: defaults) { FakeShortcut() }
        precondition(!disabledRestored.isEnabled(.ask) && disabledRestored.bindings["ask"] == ask)
        precondition(store.setEnabled(true, for: .ask) == nil && store.isEnabled(.ask))
        store.suspend()
        precondition(managers.allSatisfy { !$0.active })
        precondition(store.set(nil, for: .ask) == nil)
        store.resume()
        precondition(store.bindings["ask"] == nil)
        store.stop()
        precondition(managers.allSatisfy { !$0.active })
        print("PASS: keycaps, modifiers, migration, duplicate rejection, target routing, conflict rollback, persistence, recording suspension and removal")
    }
}
