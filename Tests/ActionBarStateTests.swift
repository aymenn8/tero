import Testing
@testable import TeroCore

@Test func navigationWrapsInBothDirections() {
    var state = ActionBarState()
    state.move(by: -1)
    #expect(state.selected == .search)
    state.move(by: 1)
    #expect(state.selected == .explain)
}

@Test func escapeReturnsFromMoreBeforeClosing() {
    var state = ActionBarState()
    state.select(.more)
    state.activate()
    #expect(state.actions == [.fix, .rewrite, .keyPoints, .back, .search])
    let firstEscapeCloses = state.escape()
    #expect(!firstEscapeCloses)
    #expect(state.selected == .explain)
    let secondEscapeCloses = state.escape()
    #expect(secondEscapeCloses)
}

@Test func executionCannotBeChangedOrStartedTwice() {
    var state = ActionBarState()
    state.activate()
    state.move(by: 1)
    state.select(.explain)
    state.activate()
    #expect(state.executing == .explain)
    #expect(state.selected == .explain)
    let escapeCloses = state.escape()
    #expect(escapeCloses)
}

@Test func hiddenActionsCannotBeSelected() {
    var state = ActionBarState()
    state.select(.rewrite)
    #expect(state.selected == .explain)
}
