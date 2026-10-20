import SwiftUI

/// A native drag region for a custom window header, kept separate from controls.
struct WindowDragRegion: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowDragRegionView {
    WindowDragRegionView()
  }

  func updateNSView(_ view: WindowDragRegionView, context: Context) {}
}
