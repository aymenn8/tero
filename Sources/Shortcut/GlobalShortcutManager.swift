import Carbon

@MainActor final class GlobalShortcutManager {
    var onTrigger: (() -> Void)?
    private static var nextID: UInt32 = 0
    private let id: UInt32
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: (UInt32, UInt32)?
    init() { Self.nextID += 1; id = Self.nextID }
    func register(keyCode: UInt32, modifiers: UInt32) -> OSStatus {
        if let current, current.0 == keyCode, current.1 == modifiers { return noErr }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
                guard let context, let event else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr else { return OSStatus(eventNotHandledErr) }
                return MainActor.assumeIsolated {
                    let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(context).takeUnretainedValue()
                    guard identifier.signature == 0x5445524F, identifier.id == manager.id else { return OSStatus(eventNotHandledErr) }
                    manager.onTrigger?()
                    return noErr
                }
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return status }
        }
        var candidate: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x5445524F, id: id), GetApplicationEventTarget(), 0, &candidate)
        guard status == noErr else { return status } // Keep the previous working binding on failure.
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = candidate; current = (keyCode, modifiers)
        return noErr
    }
    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
        current = nil
    }
}
