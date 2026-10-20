import Foundation

/// Local name/keyword lookup, independent of AI execution and source text.
enum ActionSearch {
  static func results(for query: String, candidates: [Action]) -> [Action] {
    let query = normalized(query)
    guard !query.isEmpty else { return Array(candidates.prefix(3)) }
    let tokens = query.split(separator: " ").map(String.init)
    return candidates.enumerated().compactMap { index, action -> (Action, Int, Int)? in
      guard let definition = action.definition else { return nil }
      let title = normalized(definition.title)
      let terms = [title] + definition.searchTerms.map(normalized)
      guard tokens.allSatisfy({ token in terms.contains { $0.contains(token) } }) else { return nil }
      let score = title == query ? 3 : title.hasPrefix(query) ? 2 : title.contains(query) ? 1 : 0
      return (action, score, index)
    }.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 > $1.1 }.prefix(3).map(\.0)
  }

  /// Search all eligible recommendations, including personal modes beyond the nine visible ones.
  static func results(for query: String, recommendations: [ActionRecommendation], habits: [TextHabit]) -> [ActionRecommendation.Target] {
    let query = normalized(query)
    guard !query.isEmpty else { return Array(recommendations.prefix(3)).map(\.target) }
    let tokens = query.split(separator: " ").map(String.init)
    return recommendations.enumerated().compactMap { index, recommendation -> (ActionRecommendation.Target, Int, Int)? in
      let title: String, terms: [String]
      switch recommendation.target {
      case .native(let action):
        guard let definition = action.definition else { return nil }
        title = normalized(definition.title)
        terms = [title] + definition.searchTerms.map(normalized)
      case .habit(let id):
        guard let habit = habits.first(where: { $0.id == id && $0.enabled }) else { return nil }
        title = normalized(habit.name)
        terms = [title, normalized(habit.summary ?? ""), normalized(habit.instruction)]
      }
      guard tokens.allSatisfy({ token in terms.contains { $0.contains(token) } }) else { return nil }
      let score = title == query ? 3 : title.hasPrefix(query) ? 2 : title.contains(query) ? 1 : 0
      return (recommendation.target, score, index)
    }.sorted { $0.1 == $1.1 ? $0.2 < $1.2 : $0.1 > $1.1 }.prefix(3).map(\.0)
  }

  private static func normalized(_ value: String) -> String {
    value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
      .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }
}
