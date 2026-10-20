import AppKit
import QuickLookUI
import SwiftUI

struct ClipboardQuickLook: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var url: URL?
        var scoped = false
        func release() {
            if scoped { url?.stopAccessingSecurityScopedResource() }
            url = nil
            scoped = false
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact)!
        view.autostarts = false
        view.shouldCloseWithWindow = false
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        guard context.coordinator.url != url else { return }
        view.previewItem = nil
        context.coordinator.release()
        context.coordinator.url = url
        context.coordinator.scoped = url.startAccessingSecurityScopedResource()
        view.autostarts = false
        view.previewItem = url as NSURL
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: Coordinator) {
        view.previewItem = nil
        view.close()
        coordinator.release()
    }
}
