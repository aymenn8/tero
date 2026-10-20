import Testing
@testable import TeroCore

@Test func modeChoicesNavigateBackAndSkipDisabledItems() {
  var step = ModeChoiceStep(label: "Choices", choices: [
    .init(id: "first", title: "First", label: "First"),
    .init(id: "disabled", title: "Disabled", label: "Disabled", enabled: false),
    .init(id: "last", title: "Last", label: "Last")
  ], selectedID: "first")
  #expect(step.nextSelection(by: -1) == nil)
  #expect(step.nextSelection(by: 1) == "last")
  step.selectedID = "last"
  #expect(step.nextSelection(by: 1) == nil)
  step.selectedID = nil
  #expect(step.nextSelection(by: -1) == "last")
  #expect(step.nextSelection(by: 1) == "first")
}

@Test func modeChoicesRejectUnknownAndUnavailableIdentifiers() {
  let step = ModeChoiceStep(label: "Formats", choices: [
    .init(id: "png", title: "PNG", label: "PNG"),
    .init(id: "jpeg", title: "JPEG", label: "JPEG", enabled: false)
  ], selectedID: "png")
  #expect(step.allows(nil) && step.allows("png"))
  #expect(!step.allows("jpeg") && !step.allows("arbitrary"))
}

@Test func modeChoicesRecoverWhenDynamicOptionsRemoveTheSelection() {
  let empty = ModeChoiceStep(label: "Sizes", choices: [], selectedID: "old-size")
  #expect(empty.nextSelection(by: 1) == nil)
  let loaded = ModeChoiceStep(label: "Sizes", choices: [
    .init(id: "512", title: "512 px", label: "512 pixels")
  ], selectedID: "old-size")
  #expect(loaded.nextSelection(by: 1) == "512")
  #expect(loaded.nextSelection(by: -1) == "512")
}
