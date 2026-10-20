import AppKit

final class WindowDragRegionView: NSView {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }

  override func mouseDown(with event: NSEvent) {
    // Hand the original event to macOS; it owns tracking and screen transitions.
    window?.performDrag(with: event)
  }
}
