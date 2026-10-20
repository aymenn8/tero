struct ActionBarState: Equatable, Sendable {
  enum Page: Sendable { case main, more }
  let calculationAvailable: Bool
  private let candidates: [Action]
  private var primary: [Action] { Array(candidates.prefix(3)) }
  private var secondary: [Action] { Array(candidates.dropFirst(3).prefix(3)) }

  init(calculationAvailable: Bool = false) {
    self.init(recommendations: RecommendationEngine.rank(context: .init(
      applicationID: nil, content: .text(isNumber: calculationAvailable, editable: nil))))
  }

  /// Freeze ranking and eligibility for this invocation; search never adds an executor.
  init(recommendations: [ActionRecommendation]) {
    var seen = Set<Action>()
    candidates = recommendations.compactMap {
      guard case .native(let action) = $0.target,
            ActionCatalog.definition(for: action) != nil,
            seen.insert(action).inserted else { return nil }
      return action
    }
    calculationAvailable = candidates.contains(.calculate)
    selected = candidates.first ?? .back
  }

  private(set) var page: Page = .main
  private(set) var selected: Action
  private(set) var executing: Action?
  private(set) var isSearching = false
  private(set) var searchQuery = ""
  private(set) var searchSession = 0
  var hasTextHabits = false

  /// Use the existing text transformation presentation/delivery, with a separate habit request.
  mutating func beginTextHabit() {
    guard executing == nil, hasTextHabits else { return }
    executing = .rewrite
  }

  var suggestions: [Action] {
    if isSearching { return ActionSearch.results(for: searchQuery, candidates: candidates) }
    return page == .main ? primary : secondary
  }

  var actions: [Action] {
    guard !candidates.isEmpty else { return [] }
    if isSearching { return suggestions }
    let row = page == .main
      ? primary + (secondary.isEmpty ? [.search] : [.more, .search])
      : secondary + [.back, .search]
    return row
  }

  mutating func move(by offset: Int) {
    guard executing == nil, let index = actions.firstIndex(of: selected) else { return }
    selected = actions[((index + offset) % actions.count + actions.count) % actions.count]
  }

  mutating func select(_ action: Action) {
    guard executing == nil, actions.contains(action) else { return }
    selected = action
  }

  /// Recommendation pages may contain an eligible mode beyond the legacy second row.
  mutating func selectRecommended(_ action: Action) {
    guard executing == nil, candidates.contains(action) else { return }
    selected = action
  }

  mutating func activate() {
    guard executing == nil, actions.contains(selected) || candidates.contains(selected) else { return }
    switch selected {
    case .more:
      page = .more
      selected = secondary.first ?? .search
    case .back:
      page = .main
      selected = primary.first ?? .back
    case .search: beginSearch()
    default: executing = selected
    }
  }

  mutating func beginSearch(query: String = "") {
    guard executing == nil, !candidates.isEmpty else { return }
    searchSession += 1
    isSearching = true
    updateSearch(query)
  }

  mutating func updateSearch(_ query: String) {
    guard isSearching, executing == nil else { return }
    searchQuery = query
    selected = suggestions.first ?? .back
  }

  mutating func endSearch() {
    guard executing == nil else { return }
    isSearching = false
    searchQuery = ""
    selected = page == .more ? .search : (primary.first ?? .back)
  }

  mutating func returnFromOptions() {
    executing = nil
    if isSearching { searchSession += 1 }
  }

  /// Search and the second page each consume Escape before closing the panel.
  mutating func escape() -> Bool {
    if executing != nil { return true }
    if isSearching { endSearch(); return false }
    if page == .more {
      page = .main
      selected = primary.first ?? .back
      return false
    }
    return true
  }
}
