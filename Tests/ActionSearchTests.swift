import Testing
@testable import TeroCore

@Test func actionSearchPagesHaveThreeSuggestionsAndNoCopy() {
  var state = ActionBarState()
  #expect(state.suggestions == [.explain, .translate, .askSelection])
  #expect(state.actions.suffix(2) == [.more, .search])
  state.select(.search); state.activate()
  #expect(state.isSearching && state.page == .main)
  let closesSearch = state.escape()
  #expect(!closesSearch)
  state.select(.more); state.activate()
  #expect(state.suggestions == [.fix, .rewrite, .keyPoints])
  #expect(state.actions.suffix(2) == [.back, .search])
  #expect(Action(rawValue: "copy") == nil)
  state.select(.search); state.activate()
  #expect(state.isSearching && state.executing == nil)
  #expect(state.suggestions.count == 3)
}

@Test func actionSearchMatchesNamesAndFrenchKeywords() {
  var state = ActionBarState()
  state.beginSearch(query: "TrAnS")
  #expect(state.suggestions == [.translate])
  state.updateSearch("résumé")
  #expect(state.suggestions == [.keyPoints])
  state.updateSearch("  TÂCHES  ")
  #expect(state.suggestions == [.extractTasks, .createTasks])
  state.updateSearch("extract task")
  #expect(state.suggestions == [.extractTasks])
  state.updateSearch("fix")
  #expect(state.suggestions == [.fix])
  state.activate()
  #expect(state.executing == .fix)
  state.updateSearch("translate")
  #expect(state.executing == .fix && state.searchQuery == "fix")
}

@Test func actionSearchCapsResultsAndResetsStaleSelection() {
  var state = ActionBarState()
  state.beginSearch(query: "e")
  #expect(state.suggestions.count == 3)
  state.move(by: 1)
  state.updateSearch("zzzzzz")
  #expect(state.suggestions.isEmpty)
  state.activate(); state.move(by: 1)
  #expect(state.executing == nil)
  state.updateSearch("rewrite")
  #expect(state.selected == .rewrite)
  state.activate()
  #expect(state.executing == .rewrite)
}

@Test func actionSearchEscapeReturnsToItsOriginAndOptionsKeepQuery() {
  var state = ActionBarState()
  state.select(.more); state.activate()
  state.beginSearch(query: "translate")
  state.activate()
  state.returnFromOptions()
  #expect(state.isSearching && state.searchQuery == "translate" && state.selected == .translate)
  let escapedSearch = state.escape()
  #expect(!escapedSearch)
  #expect(state.page == .more && !state.isSearching && state.searchQuery.isEmpty)
  #expect(state.selected == .search)
  let escapedPage = state.escape()
  #expect(!escapedPage)
  #expect(state.page == .main && state.selected == .explain)
  let closes = state.escape()
  #expect(closes)
}

@Test func actionSearchOnlyReturnsAvailableCandidatesAndReopenClearsIt() {
  var state = ActionBarState(calculationAvailable: true)
  state.beginSearch(query: "rewrite")
  #expect(state.suggestions.isEmpty)
  state.updateSearch("math")
  #expect(state.suggestions == [.calculate])
  state = ActionBarState()
  #expect(!state.isSearching && state.searchQuery.isEmpty)
  var empty = ActionBarState(recommendations: [])
  empty.beginSearch(query: "fix"); empty.activate()
  #expect(!empty.isSearching && empty.executing == nil)
}
