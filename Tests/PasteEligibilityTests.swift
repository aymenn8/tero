import Foundation
import Testing
@testable import TeroCore

@Test func pasteRequiresAnEditableCapturedRange() {
  var selected = SelectionReadout(applicationName: "Test", processIdentifier: 1, status: .selected("120"))
  #expect(!selected.canPaste)
  selected.targetID = UUID()
  selected.metadata = SelectionMetadata(range: NSRange(location: 0, length: 3), controlBounds: nil,
                                       selectionBounds: nil, isEditable: false)
  #expect(!selected.canPaste)
  selected.metadata = SelectionMetadata(range: NSRange(location: 0, length: 3), controlBounds: nil,
                                       selectionBounds: nil, isEditable: true)
  #expect(selected.canPaste)
  selected.metadata = SelectionMetadata(range: NSRange(location: 0, length: 0), controlBounds: nil,
                                       selectionBounds: nil, isEditable: true)
  #expect(!selected.canPaste)
}
