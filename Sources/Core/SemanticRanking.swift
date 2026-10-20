import Foundation

/// Bounded, ephemeral observations for semantic ranking. No file paths or file contents.
struct RankingContext: Encodable, Sendable {
  struct File: Encodable, Sendable { let name: String; let type: String?; let bytes: Int? }
  let kind: String
  let selection: String?
  let applicationID: String?
  let applicationName: String?
  let windowTitle: String?
  let elementRole: String?
  let elementLabel: String?
  let elementDescription: String?
  let elementPlaceholder: String?
  struct Container: Encodable, Sendable { let role: String; let label: String? }
  let containers: [Container]?
  let surface: String?
  let capture: String?
  let limitations: [String]?
  let webHost: String?
  let nearbyText: String?
  let editable: Bool?
  let preferredLanguage: String
  let localDate: String
  let timeZone: String
  let files: [File]?

  init?(_ context: RecommendationContext) {
    let source = context.source
    guard source?.capture != .protectedField else { return nil }
    switch context.content {
    case .none: return nil
    case .text(_, let editable):
      guard let text = context.selectionText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
      kind = "text"; selection = String(text.prefix(2000)); self.editable = editable; files = nil
    case .files:
      guard let observations = source?.files, !observations.isEmpty, observations.count <= 20 else { return nil }
      kind = "files"; selection = nil; editable = nil
      files = observations.map { .init(name: String($0.name.prefix(160)), type: $0.typeIdentifier.map { String($0.prefix(120)) },
                                      bytes: $0.byteCount.flatMap { $0 >= 0 ? $0 : nil }) }
    }
    applicationID = context.applicationID.map { String($0.prefix(180)) }
    applicationName = source?.applicationName.map { String($0.prefix(120)) }
    windowTitle = source?.windowTitle.map { String($0.prefix(160)) }
    elementRole = source?.elementRole.map { String($0.prefix(80)) }
    elementLabel = source?.elementLabel.map { String($0.prefix(160)) }
    elementDescription = source?.elementDescription.map { String($0.prefix(256)) }
    elementPlaceholder = source?.elementPlaceholder.map { String($0.prefix(256)) }
    containers = source.map { $0.containers.prefix(15).map { Container(role: String($0.role.prefix(80)), label: $0.label.map { String($0.prefix(160)) }) } }
    surface = source?.surface.rawValue
    capture = source?.capture.rawValue
    limitations = source.map { $0.limitations.map(\.rawValue).sorted() }
    webHost = source?.webHost.map { String($0.prefix(253)) }
    nearbyText = kind == "text" ? source?.nearbyText.map { String($0.prefix(800)) } : nil
    let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = .current; formatter.dateFormat = "yyyy-MM-dd"
    preferredLanguage = ResponseLanguage.load().rawValue
    localDate = formatter.string(from: source?.capturedAt ?? .now)
    timeZone = TimeZone.current.identifier
  }
}

struct SemanticScore: Codable, Equatable, Sendable {
  let id: String
  let score: Double
  let confidence: Double
  var probabilities: [String: Double]? = nil
}

enum SemanticRankingPolicy {
  private static func validProbabilities(_ score: SemanticScore) -> Bool {
    guard let probabilities = score.probabilities else { return true } // Older gateway responses.
    guard Set(probabilities.keys) == Set(["0", "1", "2", "3"]) else { return false }
    let values = (0...3).map { probabilities[String($0)]! }
    return values.allSatisfy { $0.isFinite && (0...1).contains($0) }
      && abs(values.reduce(0, +) - 1) <= 0.025
      && abs(values.enumerated().reduce(0) { $0 + Double($1.offset) * $1.element } - score.score) <= 0.04
  }
  /// Coverage is exact; a malformed response cannot add, lose or enable a capability.
  /// All eligible actions share one relevance order. Exact ties preserve local order.
  static func apply(_ scores: [SemanticScore], to local: [ActionRecommendation]) -> [ActionRecommendation]? {
    let ids = local.map { $0.target.rankingID }
    guard scores.count == ids.count, Set(ids).count == ids.count,
          Set(scores.map(\.id)) == Set(ids), Set(scores.map(\.id)).count == scores.count,
          scores.allSatisfy({ validProbabilities($0) && $0.score.isFinite && (0...3).contains($0.score) && $0.confidence.isFinite && (0...1).contains($0.confidence) }) else { return nil }
    let values = Dictionary(uniqueKeysWithValues: scores.map { ($0.id, $0.score) })
    return local.enumerated().sorted { left, right in
      let a = values[left.element.target.rankingID]!, b = values[right.element.target.rankingID]!
      return a == b ? left.offset < right.offset : a > b
    }.map(\.element)
  }
}
