import Foundation

enum PanelPlacement {
  static let contentInset: CGFloat = 12
  static let actionHeight: CGFloat = 30
  static let anchorGap: CGFloat = 8

  static func validBounds(_ rect: CGRect) -> Bool {
    rect.origin.x.isFinite && rect.origin.y.isFinite
      && rect.width.isFinite && rect.height.isFinite
      && rect.width > 0 && rect.height > 0
      && rect.maxX.isFinite && rect.maxY.isFinite
  }

  static func appKitRect(fromAX rect: CGRect, primaryScreenTop: CGFloat) -> CGRect? {
    guard validBounds(rect), primaryScreenTop.isFinite else { return nil }
    let converted = CGRect(
      x: rect.minX, y: primaryScreenTop - rect.maxY,
      width: rect.width, height: rect.height)
    return validBounds(converted) ? converted : nil
  }

  /// Prefer the display containing most of the target, not the mouse pointer.
  static func screenIndex(for anchor: CGRect, screens: [CGRect]) -> Int? {
    var bestIndex: Int?
    var bestArea: CGFloat = 0
    for (index, screen) in screens.enumerated() {
      let overlap = screen.intersection(anchor)
      guard !overlap.isNull else { continue }
      let area = overlap.width * overlap.height
      if area > bestArea {
        bestIndex = index
        bestArea = area
      }
    }
    return bestIndex
  }

  static func frame(
    panelSize: CGSize, anchor: CGRect?, pointer: CGPoint,
    visibleFrame: CGRect
  ) -> CGRect {
    let safe = visibleFrame.insetBy(dx: 8, dy: 8)
    let size = CGSize(
      width: min(panelSize.width, safe.width), height: min(panelSize.height, safe.height))
    // Only selection geometry anchors the bar. A control can span an entire document.
    let target =
      anchor.flatMap { validBounds($0) ? $0 : nil }
      ?? CGRect(origin: pointer, size: .zero)
    let above = target.maxY + anchorGap
    let below = target.minY - anchorGap - size.height
    let y = above + size.height <= safe.maxY ? above : below
    let x = target.midX - size.width / 2
    return CGRect(
      x: min(max(x, safe.minX), safe.maxX - size.width),
      y: min(max(y, safe.minY), safe.maxY - size.height),
      width: size.width, height: size.height)
  }
}
