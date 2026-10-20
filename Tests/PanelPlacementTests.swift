import Foundation
import Testing

@testable import TeroCore

@Test func axCoordinatesConvertAcrossVerticallyStackedScreens() {
  let main = PanelPlacement.appKitRect(
    fromAX: CGRect(x: 100, y: 200, width: 500, height: 100), primaryScreenTop: 900)
  #expect(main == CGRect(x: 100, y: 600, width: 500, height: 100))
  let above = PanelPlacement.appKitRect(
    fromAX: CGRect(x: -900, y: -500, width: 500, height: 100), primaryScreenTop: 900)
  #expect(above == CGRect(x: -900, y: 1300, width: 500, height: 100))
}

@Test func placementKeepsPanelAboveSelection() {
  let anchor = CGRect(x: 300, y: 400, width: 600, height: 100)
  let frame = PanelPlacement.frame(
    panelSize: CGSize(width: 440, height: 54), anchor: anchor, pointer: .zero,
    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
  #expect(frame.midX == anchor.midX)
  #expect(frame.minY == anchor.maxY + PanelPlacement.anchorGap)
}

@Test func edgePlacementStaysInsideVisibleScreen() {
  let screen = CGRect(x: -1440, y: 900, width: 1440, height: 860)
  for target in [
    CGRect(x: -1440, y: 1740, width: 40, height: 20),
    CGRect(x: -40, y: 900, width: 40, height: 20),
  ] {
    let frame = PanelPlacement.frame(
      panelSize: CGSize(width: 440, height: 54), anchor: target, pointer: .zero,
      visibleFrame: screen)
    #expect(screen.insetBy(dx: 8, dy: 8).contains(frame))
  }
}

@Test func screenFollowsTargetRatherThanPointer() {
  let screens = [
    CGRect(x: 0, y: 0, width: 1440, height: 900),
    CGRect(x: -1440, y: 0, width: 1440, height: 900),
  ]
  #expect(
    PanelPlacement.screenIndex(
      for: CGRect(x: -600, y: 100, width: 400, height: 300), screens: screens) == 1)
  #expect(
    PanelPlacement.screenIndex(
      for: CGRect(x: 9000, y: 100, width: 400, height: 300), screens: screens) == nil)
}

@Test func invalidGeometryAndRangesAreDiscarded() {
  #expect(
    PanelPlacement.appKitRect(
      fromAX: CGRect(x: 0, y: 0, width: 0, height: 100), primaryScreenTop: 900) == nil)
  #expect(SelectionMetadata.validRange(location: -1, length: 4) == nil)
  #expect(SelectionMetadata.validRange(location: NSNotFound, length: 1) == nil)
  #expect(SelectionMetadata.validRange(location: Int.max - 1, length: 5) == nil)
  #expect(SelectionMetadata.validRange(location: 3, length: 7) == NSRange(location: 3, length: 7))
}

@Test func selectionAnchorNeverFallsBackToWholeControl() {
  let control = CGRect(x: 100, y: 100, width: 500, height: 400)
  let selectedLine = CGRect(x: 130, y: 230, width: 100, height: 20)
  let editable = SelectionMetadata(
    range: nil, controlBounds: control, selectionBounds: selectedLine, isEditable: true)
  let unconfirmed = SelectionMetadata(
    range: nil, controlBounds: control, selectionBounds: selectedLine, isEditable: false)
  #expect(editable.anchorBounds == selectedLine)
  #expect(unconfirmed.anchorBounds == selectedLine)
  let missing = SelectionMetadata(
    range: nil, controlBounds: control, selectionBounds: nil, isEditable: true)
  #expect(missing.anchorBounds == nil)
}

@Test func placementFlipsBelowNearTop() {
  let anchor = CGRect(x: 300, y: 850, width: 100, height: 20)
  let frame = PanelPlacement.frame(
    panelSize: CGSize(width: 440, height: 54), anchor: anchor,
    pointer: .zero, visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
  #expect(frame.maxY == anchor.minY - PanelPlacement.anchorGap)
  #expect(!frame.intersects(anchor))
}

@Test func missingBoundsPlacesPanelNearInvocationPointer() {
  let pointer = CGPoint(x: 900, y: 300)
  let frame = PanelPlacement.frame(
    panelSize: CGSize(width: 440, height: 54), anchor: nil,
    pointer: pointer, visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
  #expect(frame.midX == pointer.x)
  #expect(frame.minY == pointer.y + PanelPlacement.anchorGap)
}

@Test func onlyRealSelectionEnablesActionsAndPermissionNoticePersists() {
  for status in [SelectionReadout.Status.noSelection, .unsupported, .protectedField, .unavailable] {
    let readout = SelectionReadout(applicationName: "Test", processIdentifier: 1, status: status)
    #expect(!readout.hasSelection)
    #expect(readout.isTransient)
  }
  let permission = SelectionReadout(
    applicationName: "Test", processIdentifier: 1, status: .permissionRequired)
  #expect(!permission.hasSelection)
  #expect(!permission.isTransient)
  let selected = SelectionReadout(
    applicationName: "Test", processIdentifier: 1, status: .selected("Bonjour"))
  #expect(selected.hasSelection)
  #expect(!selected.isTransient)
}
