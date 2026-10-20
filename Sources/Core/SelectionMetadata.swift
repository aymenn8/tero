import CoreGraphics
import Foundation

struct SelectionMetadata: Equatable, Sendable {
  /// AX ranges use UTF-16 offsets, not Swift Character indices.
  let range: NSRange?
  /// All rectangles here retain AX's global, top-left coordinate system.
  let controlBounds: CGRect?
  let selectionBounds: CGRect?
  /// A positive API capability hint, not a guarantee of safe replacement or undo.
  let isEditable: Bool

  var anchorBounds: CGRect? {
    selectionBounds
  }

  static func validRange(location: Int, length: Int) -> NSRange? {
    guard location >= 0, location != NSNotFound, length >= 0,
      location <= Int.max - length
    else { return nil }
    return NSRange(location: location, length: length)
  }
}
