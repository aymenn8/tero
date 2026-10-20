import Foundation
import CryptoKit

/// Server-only Jev key. One bounded request before presentation; no late visible reordering.
struct RankingClient: Sendable {
  var endpoint = URL(string: "https://ufcsajujaqemlduvpjpi.supabase.co/functions/v1/tero-rank")!
  var session: URLSession = .shared
  static let waitBudget: Duration = .seconds(3)
  var deadline: Duration = waitBudget
  struct PersonalCandidate: Encodable, Sendable {
    let id: String; let name: String; let instruction: String
    var description: String? = nil
    var operation: FileHabitPlan.Operation? = nil
    init(habit: TextHabit) {
      id = "habit_" + habit.id.uuidString.lowercased(); name = habit.name
      instruction = habit.instruction; description = habit.rankingDescription; operation = habit.filePlan?.operation
    }
    init(id: String, name: String, instruction: String) {
      self.id = id; self.name = name; self.instruction = instruction
    }
  }
  struct Request: Encodable { let requestID: UUID; let candidates: [String]; let context: RankingContext; let personalActions: [PersonalCandidate]; var debug = false }
  struct Response: Decodable, Sendable {
    struct Usage: Decodable, Sendable { let inputTokens: Int; let outputTokens: Int; let estimatedCostUSD: Double }
    let requestID: UUID
    let model: String
    let scores: [SemanticScore]
    let usage: Usage
    let promptVersion: Int
    struct Trace: Decodable, Sendable { let providerRequest: String; let providerResponse: String }
    let debug: Trace?
    let latencyMs: Int
  }
  enum Failure: Error { case unavailable, timeout, invalid }
  func rank(context: RankingContext, candidates: [String], personalActions: [PersonalCandidate] = [], credential: String, debug: Bool = false, requestID: UUID = UUID()) async throws -> Response {
    let id = requestID
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"; request.timeoutInterval = 4; request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(Request(requestID: id, candidates: candidates, context: context, personalActions: personalActions, debug: debug))
    return try await withThrowingTaskGroup(of: Response.self) { group in
      group.addTask { [request, session] in
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= (debug ? 262144 : 32768) else { throw Failure.unavailable }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard result.requestID == id, !result.model.isEmpty, result.model.count <= 100, result.promptVersion > 0,
              result.latencyMs >= 0, result.usage.inputTokens >= 0, result.usage.outputTokens >= 0,
              result.usage.estimatedCostUSD.isFinite, result.usage.estimatedCostUSD >= 0 else { throw Failure.invalid }
        return result
      }
      group.addTask { try await Task.sleep(for: deadline); throw Failure.timeout }
      defer { group.cancelAll() }
      guard let result = try await group.next() else { throw Failure.unavailable }
      try Task.checkCancellation()
      return result
    }
  }
}

/// One short-lived result, scoped to account and exact observations. No raw context is retained.
struct RankingMemo {
  private struct Entry {
    let key: Data
    let scores: [SemanticScore]
    let expires: ContinuousClock.Instant
  }
  private var entry: Entry?
  private let lifetime: Duration = .seconds(20)

  private func key(accountID: UUID, context: RankingContext, candidates: [String], personalActions: [RankingClient.PersonalCandidate]) -> Data? {
    struct Input: Encodable { let accountID: UUID; let context: RankingContext; let candidates: [String]; let personalActions: [RankingClient.PersonalCandidate] }
    let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
    guard let bytes = try? encoder.encode(Input(accountID: accountID, context: context, candidates: candidates, personalActions: personalActions)) else { return nil }
    return Data(SHA256.hash(data: bytes))
  }
  mutating func scores(accountID: UUID?, context: RankingContext, candidates: [String], personalActions: [RankingClient.PersonalCandidate] = [], now: ContinuousClock.Instant = .now) -> [SemanticScore]? {
    guard let accountID else { entry = nil; return nil }
    guard let entry else { return nil }
    guard now < entry.expires else { self.entry = nil; return nil }
    guard entry.key == key(accountID: accountID, context: context, candidates: candidates, personalActions: personalActions) else { return nil }
    return entry.scores
  }
  mutating func store(_ scores: [SemanticScore], accountID: UUID, context: RankingContext, candidates: [String], personalActions: [RankingClient.PersonalCandidate] = [], now: ContinuousClock.Instant = .now) {
    guard let key = key(accountID: accountID, context: context, candidates: candidates, personalActions: personalActions) else { return }
    entry = Entry(key: key, scores: scores, expires: now.advanced(by: lifetime))
  }
}
