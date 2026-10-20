import AppKit
import SwiftUI

/// Observes a drag without consuming normal clicks, menus or Quick Look controls.
struct ClipboardFileDrag: NSViewRepresentable {
    let entry: ClipboardEntry
    let started: () -> Void
    let ended: (Bool) -> Void
    let unavailable: () -> Void

    func makeNSView(context: Context) -> ClipboardFileDragView { ClipboardFileDragView() }
    func updateNSView(_ view: ClipboardFileDragView, context: Context) {
        view.entry = entry
        view.started = started
        view.ended = ended
        view.unavailable = unavailable
    }
    static func dismantleNSView(_ view: ClipboardFileDragView, coordinator: ()) { view.stopObserving() }
}

@MainActor
final class ClipboardFileDragView: NSView, NSDraggingSource {
    var entry: ClipboardEntry?
    var started: (() -> Void)?
    var ended: ((Bool) -> Void)?
    var unavailable: (() -> Void)?
    private var monitor: Any?
    private var down: NSEvent?
    private var scopedURLs: [URL] = []
    private var dragging = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.observe(event) == nil
            }
            return consumed ? nil : event
        }
    }

    func stopObserving() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        down = nil
    }

    private func observe(_ event: NSEvent) -> NSEvent? {
        guard !dragging else { return event }
        if event.type == .leftMouseUp { down = nil; return event }
        if event.type == .leftMouseDown {
            down = nil
            guard event.window === window, entry?.kind == .files,
                  !event.modifierFlags.contains(.control) else { return event }
            let point = convert(event.locationInWindow, from: nil)
            if visibleRect.contains(point) { down = event }
            return event
        }
        guard event.type == .leftMouseDragged, event.window === window, let down else { return event }
        let distance = hypot(event.locationInWindow.x - down.locationInWindow.x,
                             event.locationInWindow.y - down.locationInWindow.y)
        guard distance >= 5 else { return event }
        self.down = nil
        guard let entry, let urls = ClipboardCapture.resolvedFiles(entry), !urls.isEmpty else {
            unavailable?()
            return nil
        }
        scopedURLs = urls.filter { $0.startAccessingSecurityScopedResource() }
        let items = Self.draggingItems(for: urls, at: convert(down.locationInWindow, from: nil))
        dragging = true
        let session = beginDraggingSession(with: items, event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
        return nil
    }

    static func draggingItems(for urls: [URL], at point: NSPoint) -> [NSDraggingItem] {
        urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let offset = CGFloat(min(index, 3) * 3)
            item.setDraggingFrame(NSRect(x: point.x - 20 + offset, y: point.y - 20 - offset, width: 40, height: 40),
                                  contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) { started?() }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
        scopedURLs = []
        dragging = false
        down = nil
        ended?(operation != [])
    }
}
