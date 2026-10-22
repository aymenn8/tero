import Foundation

/// Jev recommendations with the person's own Typesafe key. Builds the same provider request
/// as supabase/functions/tero-rank/handler.ts (prompt, catalog, criteria, observed state) and
/// sends it straight from this Mac to Typesafe. Keep both in sync.
struct JevClient: Sendable {
  static let model = "jev-1.13.0"
  static let keyPage = URL(string: "https://typesafe.ai")!
  /// Scopes the short-lived ranking memo when no Tero account is involved.
  static let memoScope = UUID(uuidString: "6A65762D-6F77-6E2D-6B65-790000000000")!

  enum Failure: Error, Equatable { case rejected, unavailable, invalid, timeout }

  var endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!
  var session: URLSession = .shared
  var deadline: Duration = RankingClient.waitBudget
  let key: String

  /// The saved key, used only alongside the person's own AI provider.
  static var stored: JevClient? { AIKeyVault.read(account: AIKeyVault.jevAccount).map { JevClient(key: $0) } }

  /// App action IDs and their catalog rows (tero-rank ACTIONS).
  static let catalogIDs: [String: String] = [
    "shop": "shop", "renameFile": "rename_file", "batchRename": "batch_rename", "moveFiles": "move_files",
    "openMaps": "open_maps", "directions": "directions", "convertUnits": "convert_units",
    "convertCurrencies": "convert_currencies", "convertTimeZones": "convert_time_zones", "checkClaim": "check_claim",
    "tone": "tone", "simplify": "simplify", "improvePrompt": "improve_prompt", "cleanFormatting": "clean_formatting",
    "changeCase": "change_case", "calculate": "calculate", "rewrite": "rewrite", "explain": "explain",
    "translate": "translate", "keyPoints": "key_points", "extractTasks": "extract_tasks", "fix": "fix", "reply": "reply",
    "summarizeFile": "summarize_file", "createTasks": "task_plan", "createEvent": "event_plan"]

  static let criteria = [
    "Unsupported, inappropriate, or unrelated to the observed content.",
    "Possible generic use, but no evidence of this immediate intent.",
    "Useful next step supported by the selected content and context.",
    "Especially fitting next step supported by specific content or context."]

  private static let catalog: [String: [String: String]] = {
    guard let url = Bundle.main.url(forResource: "RankingCatalog", withExtension: "json"),
          let data = try? Data(contentsOf: url) else { return [:] }
    return (try? JSONDecoder().decode([String: [String: String]].self, from: data)) ?? [:]
  }()

  // MARK: - Request

  /// Explicit allowlist of observations, with the same clean-up as the server.
  static func observedState(_ context: RankingContext) throws -> JSONObject {
    guard let input = try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as? JSONObject else { throw Failure.invalid }
    let keys = ["kind", "selection", "applicationID", "applicationName", "windowTitle", "elementRole", "elementLabel",
                "elementDescription", "elementPlaceholder", "surface", "capture", "limitations", "webHost", "nearbyText",
                "editable", "preferredLanguage", "localDate", "timeZone"]
    var state: JSONObject = [:]
    for key in keys {
      guard let value = input[key], !(value is NSNull) else { continue }
      if let text = value as? String, text.isEmpty { continue }
      if let list = value as? [Any], list.isEmpty { continue }
      state[key] = value
    }
    // Repeated wrapper groups have no meaning; keep labels and useful structural roles.
    var containers: [JSONObject] = []
    for container in input["containers"] as? [JSONObject] ?? [] {
      guard let role = container["role"] as? String else { continue }
      let label = (container["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      if (label ?? "").isEmpty && role == "AXGroup" { continue }
      var observation: JSONObject = ["role": role]
      if let label, !label.isEmpty { observation["label"] = label }
      if let previous = containers.last, previous["role"] as? String == role, previous["label"] as? String == observation["label"] as? String { continue }
      containers.append(observation)
    }
    if !containers.isEmpty { state["containers"] = containers }
    if let description = state["elementDescription"] as? String, description == state["elementLabel"] as? String { state["elementDescription"] = nil }
    if let placeholder = state["elementPlaceholder"] as? String,
       placeholder == state["elementLabel"] as? String || placeholder == state["elementDescription"] as? String { state["elementPlaceholder"] = nil }
    if let nearby = state["nearbyText"] as? String, let selection = state["selection"] as? String,
       nearby.trimmingCharacters(in: .whitespacesAndNewlines) == selection.trimmingCharacters(in: .whitespacesAndNewlines) { state["nearbyText"] = nil }
    if context.kind == "files", let files = input["files"] as? [JSONObject] {
      state["files"] = files.map { file in file.filter { ["name", "type", "bytes"].contains($0.key) } }
    }
    return state
  }

  static func providerBody(state: JSONObject, candidates: [String], personalActions: [RankingClient.PersonalCandidate]) throws -> JSONObject {
    guard candidates.count >= 2, Set(candidates).count == candidates.count,
          let task = PromptCatalog.instructions("rank_actions:default") else { throw Failure.invalid }
    var questions: JSONObject = [:]
    for id in candidates {
      let definition: [String: String]
      if let personal = personalActions.first(where: { $0.id == id }) {
        let description = personal.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let offer = switch personal.operation {
          case .move: "Selected files fit this habit; destination folder is already chosen."
          case .rename: "Selected files fit this habit’s naming rules."
          case nil: "Selected text and context support this action."
        }
        definition = ["title": personal.name, "description": description.isEmpty ? personal.instruction : description,
          "when_to_offer": offer, "when_to_avoid": "Unrelated intent or unsupported operations."]
      } else {
        guard let row = catalogIDs[id].flatMap({ catalog[$0] }) else { throw Failure.invalid }
        definition = row
      }
      questions[id] = ["type": "score", "instructions": ["task": task, "action": definition], "criteria": criteria]
    }
    return ["model": model, "state": state, "questions": questions]
  }

  // MARK: - Response

  /// Exact coverage and coherent probabilities, as tero-rank validates them.
  static func scores(from result: Any, ids: [String]) throws -> [SemanticScore] {
    guard let result = result as? JSONObject, result["model"] as? String == model,
          let answers = result["answers"] as? JSONObject, answers.count == ids.count,
          let usage = result["usage"] as? JSONObject, (usage["input_tokens"] as? Int ?? -1) >= 0,
          (usage["output_tokens"] as? Int ?? -1) >= 0 else { throw Failure.invalid }
    return try ids.map { id in
      guard let answer = answers[id] as? JSONObject, answer["type"] as? String == "score",
            let score = (answer["score"] as? NSNumber)?.doubleValue, score.isFinite, (0...3).contains(score),
            let confidence = (answer["confidence"] as? NSNumber)?.doubleValue, confidence.isFinite, (0...1).contains(confidence),
            let raw = answer["probabilities"] as? JSONObject, raw.count == 4 else { throw Failure.invalid }
      var probabilities: [String: Double] = [:]
      for level in 0...3 {
        guard let value = (raw[String(level)] as? NSNumber)?.doubleValue, value.isFinite, (0...1).contains(value) else { throw Failure.invalid }
        probabilities[String(level)] = value
      }
      let values = (0...3).map { probabilities[String($0)]! }
      guard abs(values.reduce(0, +) - 1) <= 0.025,
            abs(values.enumerated().reduce(0) { $0 + Double($1.offset) * $1.element } - score) <= 0.04 else { throw Failure.invalid }
      return SemanticScore(id: id, score: score, confidence: confidence, probabilities: probabilities)
    }
  }

  // MARK: - Calls

  func rank(context: RankingContext, candidates: [String], personalActions: [RankingClient.PersonalCandidate] = []) async throws -> [SemanticScore] {
    try await rank(state: Self.observedState(context), candidates: candidates, personalActions: personalActions)
  }

  /// Confirms the key with a synthetic selection before it is saved.
  func verify() async throws {
    let state: JSONObject = ["kind": "text", "selection": "Thsi is a tset.", "editable": true, "preferredLanguage": "en"]
    _ = try await rank(state: state, candidates: ["fix", "explain"], personalActions: [])
  }

  private func rank(state: JSONObject, candidates: [String], personalActions: [RankingClient.PersonalCandidate]) async throws -> [SemanticScore] {
    let body = try JSONSerialization.data(withJSONObject: Self.providerBody(state: state, candidates: candidates, personalActions: personalActions))
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"; request.timeoutInterval = Double(deadline.components.seconds) + 1; request.cachePolicy = .reloadIgnoringLocalCacheData
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    return try await withThrowingTaskGroup(of: [SemanticScore].self) { group in
      group.addTask { [request, session] in
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw Failure.rejected }
        guard status == 200, data.count <= 65536 else { throw Failure.unavailable }
        return try Self.scores(from: JSONSerialization.jsonObject(with: data), ids: candidates)
      }
      group.addTask { [deadline] in try await Task.sleep(for: deadline); throw Failure.timeout }
      defer { group.cancelAll() }
      guard let result = try await group.next() else { throw Failure.unavailable }
      try Task.checkCancellation()
      return result
    }
  }
}
