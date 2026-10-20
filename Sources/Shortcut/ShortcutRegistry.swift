import Foundation
import Observation
import Carbon

struct ShortcutTarget: Hashable, Identifiable {
    let id: String
    let title: String
    static let open = Self(id: "open", title: "Open Tero")
    static let clipboard = Self(id: "clipboard", title: "Clipboard")
    static let ask = Self(id: "ask", title: "Ask")
    static func mode(_ action: Action) -> Self { .init(id: "mode." + action.rawValue, title: action.title) }
    static var all: [Self] { [.open, .clipboard, .ask] + ActionCatalog.definitions.map { .mode($0.id) } }
    var action: Action? { id.hasPrefix("mode.") ? Action(rawValue: String(id.dropFirst(5))) : nil }
}

@MainActor protocol ShortcutRegistering: AnyObject {
    var onTrigger: (() -> Void)? { get set }
    func register(keyCode: UInt32, modifiers: UInt32) -> OSStatus
    func unregister()
}
extension GlobalShortcutManager: ShortcutRegistering {}

@MainActor @Observable final class ShortcutRegistry {
    static let shared = ShortcutRegistry()
    private(set) var bindings: [String: ShortcutChord]
    private(set) var disabled: Set<String>
    private(set) var errors: [String: String] = [:]
    @ObservationIgnored var onTrigger: ((ShortcutTarget) -> Void)?
    @ObservationIgnored private var managers: [String: any ShortcutRegistering] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let factory: () -> any ShortcutRegistering
    @ObservationIgnored private var recording = false
    @ObservationIgnored private var started = false
    init(defaults: UserDefaults = .standard, factory: @escaping () -> any ShortcutRegistering = { GlobalShortcutManager() }) {
        self.defaults = defaults
        self.factory = factory
        disabled = Set(defaults.stringArray(forKey: "disabledShortcutsV1") ?? []).intersection(Set(ShortcutTarget.all.map(\.id)))
        if let data = defaults.data(forKey: "customShortcutsV1"), let saved = try? JSONDecoder().decode([String: ShortcutChord].self, from: data) {
            let known = Set(ShortcutTarget.all.map(\.id))
            bindings = saved.filter { known.contains($0.key) && $0.value.isValid }
        } else { bindings = [ShortcutTarget.open.id: defaults.bool(forKey: "alternateShortcutV3") ? .alternate : .standard] }
    }
    func start() { guard !started else { return }; started = true; registerAll() }
    func stop() { managers.values.forEach { $0.unregister() }; managers = [:]; started = false }
    func suspend() { recording = true; managers.values.forEach { $0.unregister() }; managers = [:] }
    func resume() { guard recording else { return }; recording = false; if started { registerAll() } }
    @discardableResult func set(_ chord: ShortcutChord?, for target: ShortcutTarget) -> String? {
        if let chord {
            guard chord.isValid else { return "Use ⌘, ⌃ or ⌥ with a key." }
            if let duplicate = ShortcutTarget.all.first(where: { $0.id != target.id && bindings[$0.id]?.matches(chord) == true }) {
                return "Already assigned to \(duplicate.title)."
            }
            if bindings[target.id]?.matches(chord) == true { return nil }
            let manager = managers[target.id] ?? makeManager(target)
            guard manager.register(keyCode: chord.keyCode, modifiers: chord.modifiers) == noErr else {
                if managers[target.id] == nil { manager.unregister() }
                return "This shortcut is unavailable. Choose another combination."
            }
            if recording || disabled.contains(target.id) { manager.unregister() } else { managers[target.id] = manager }
        } else { managers.removeValue(forKey: target.id)?.unregister() }
        bindings[target.id] = chord
        if chord == nil { disabled.remove(target.id); persistDisabled() }
        errors[target.id] = nil
        if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: "customShortcutsV1") }
        return nil
    }
    func isEnabled(_ target: ShortcutTarget) -> Bool { bindings[target.id] != nil && !disabled.contains(target.id) }
    @discardableResult func setEnabled(_ enabled: Bool, for target: ShortcutTarget) -> String? {
        guard let chord = bindings[target.id] else { return nil }
        if enabled {
            guard disabled.contains(target.id) else { return nil }
            if started && !recording {
                let manager = makeManager(target)
                guard manager.register(keyCode: chord.keyCode, modifiers: chord.modifiers) == noErr else {
                    manager.unregister(); return "This shortcut is unavailable. Choose another combination."
                }
                managers[target.id] = manager
            }
            disabled.remove(target.id)
        } else {
            managers.removeValue(forKey: target.id)?.unregister()
            disabled.insert(target.id)
        }
        errors[target.id] = nil; persistDisabled(); return nil
    }
    private func persistDisabled() { defaults.set(Array(disabled).sorted(), forKey: "disabledShortcutsV1") }
    private func makeManager(_ target: ShortcutTarget) -> any ShortcutRegistering {
        let manager = factory()
        manager.onTrigger = { [weak self] in self?.onTrigger?(target) }
        return manager
    }
    private func registerAll() {
        guard !recording else { return }
        for target in ShortcutTarget.all {
            guard let chord = bindings[target.id], !disabled.contains(target.id) else { continue }
            let manager = makeManager(target)
            if manager.register(keyCode: chord.keyCode, modifiers: chord.modifiers) == noErr {
                managers[target.id] = manager; errors[target.id] = nil
            } else { manager.unregister(); errors[target.id] = "Shortcut unavailable. Choose another combination." }
        }
    }
}
