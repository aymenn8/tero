import AppKit

final class TeroPanel: NSPanel {
    var acceptsFocus = true
    var handleKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { acceptsFocus }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, handleKey?(event) == true { return }
        super.sendEvent(event)
    }
}
