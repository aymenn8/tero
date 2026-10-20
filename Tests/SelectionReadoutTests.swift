import Testing

@testable import TeroCore

@Test func whitespaceSelectionIsNotDiscarded() {
  #expect(SelectionReadout.status(for: " \n\t") == .selected(" \n\t"))
  #expect(SelectionReadout.status(for: "") == .noSelection)
}

@Test func previewTruncatesWithoutSplittingUnicodeOrChangingCapturedText() {
  let text = String(repeating: "👩🏽‍💻", count: 241)
  let result = SelectionReadout(
    applicationName: "Fixture", processIdentifier: 1, status: .selected(text))
  #expect(result.preview == String(repeating: "👩🏽‍💻", count: 240) + "…")
  #expect(result.status == .selected(text))
  #expect(result.characterCount == 241)
}

@Test func unavailableStatesNeverExposePreviewContent() {
  for status: SelectionReadout.Status in [
    .noSelection, .permissionRequired, .unsupported, .protectedField, .unavailable,
  ] {
    let result = SelectionReadout(applicationName: "Fixture", processIdentifier: 1, status: status)
    #expect(result.preview == nil)
    #expect(result.characterCount == nil)
  }
}

@Test func homeRequiresAnExplicitEmptySelection() {
  for status: SelectionReadout.Status in [.selected("fixture"), .noSelection, .permissionRequired,
    .unsupported, .protectedField, .unavailable] {
    let result = SelectionReadout(applicationName: "Fixture", processIdentifier: 1, status: status)
    #expect(result.opensHome == (status == .noSelection))
  }
}
