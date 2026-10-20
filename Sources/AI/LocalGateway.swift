import Foundation

/// Bring-your-own-key twin of the tero-correct and tero-shop gateways.
/// It accepts the same request body and returns the same response shapes, so callers
/// decode identical results whether AI runs through Tero Pro or the user's own key.
/// Nothing is logged; selected content only travels to the user's chosen provider.
struct LocalGateway {
  let configuration: AIConfiguration

  private static let actions: Set<String> = ["fix", "explain", "check_claim", "translate", "rewrite", "key_points", "extract_tasks",
    "reply_options", "reply", "ask", "ask_refine", "summarize_file", "task_plan", "event_plan", "tone", "simplify",
    "improve_prompt", "result_refine", "text_habit", "habit_design", "rename_files"]

  /// Non-streaming request. Returns the gateway's JSON payload.
  func respond(_ body: Data) async throws -> Data {
    let request = try parse(body)
    let answer = try await AIProviderClient(configuration: configuration).send(try call(for: request))
    var result = try decode(answer, request: request)
    result["requestID"] = request["requestID"]
    return try JSONSerialization.data(withJSONObject: result)
  }

  /// Streaming reading: progress previews, then the validated final text.
  func stream(_ body: Data, update: @escaping @MainActor @Sendable (String) -> Void) async throws -> String {
    let request = try parse(body)
    let action = request["action"] as? String ?? ""
    var last = ""
    let answer = try await AIProviderClient(configuration: configuration).send(try call(for: request)) { raw in
      let preview = StreamPreview.text(raw, action: action)
      guard !preview.isEmpty, preview != last else { return }
      last = preview
      await update(preview)
    }
    guard let text = try decode(answer, request: request)["text"] as? String else { throw CorrectionClient.Failure.invalid }
    return text
  }

  /// Product recommendations for Ask, verified against the provider's own search sources.
  func shop(_ body: Data) async throws -> Data {
    guard let request = try JSONSerialization.jsonObject(with: body) as? JSONObject,
          let selection = request["selection"] as? String, selection.unicodeScalars.count <= 4000,
          let input = try JSONSerialization.jsonObject(with: Data(selection.utf8)) as? JSONObject,
          let query = input["request"] as? String, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
      throw CorrectionClient.Failure.invalid
    }
    guard configuration.provider.supportsWebSearch else { throw CorrectionClient.Failure.needsWebSearch }
    let call = ModelCall(instructions: try PromptCatalog.render("shop", body: ["action": "shop"]), parts: [.text(selection)],
                         schema: ("shopping_products", GatewaySchemas.products), web: .required, maxOutputTokens: 1600)
    let answer = try await AIProviderClient(configuration: configuration).send(call)
    guard answer.searched else { throw CorrectionClient.Failure.invalid }
    let sources = Set((answer.annotations + answer.consulted).compactMap { ShoppingRequest.publicURL($0.url)?.absoluteString })
    guard let value = Self.object(answer.text), let summary = value["summary"] as? String, summary.count <= 600,
          let products = value["products"] as? [JSONObject], products.count <= 3 else { throw CorrectionClient.Failure.invalid }
    var verified: [JSONObject] = []
    for product in products {
      guard let raw = product["url"] as? String, let url = ShoppingRequest.publicURL(raw)?.absoluteString, sources.contains(url),
            !verified.contains(where: { $0["url"] as? String == url }),
            let name = product["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty, name.count <= 120,
            let price = product["price"] as? String, price.count <= 100,
            let reason = product["reason"] as? String, !reason.trimmingCharacters(in: .whitespaces).isEmpty, reason.count <= 400,
            let tradeoff = product["tradeoff"] as? String, tradeoff.count <= 300 else { throw CorrectionClient.Failure.invalid }
      verified.append(["name": name, "price": price, "reason": reason, "tradeoff": tradeoff, "url": url, "imageURL": NSNull()])
    }
    return try JSONSerialization.data(withJSONObject: ["requestID": request["requestID"] ?? "", "summary": summary, "products": verified])
  }

  // MARK: - Request validation (port of tero-correct's input checks)

  private func parse(_ body: Data) throws -> JSONObject {
    guard let request = try JSONSerialization.jsonObject(with: body) as? JSONObject,
          let action = request["action"] as? String, Self.actions.contains(action),
          let selection = request["selection"] as? String, !selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw CorrectionClient.Failure.invalid
    }
    guard selection.unicodeScalars.count <= (action == "result_refine" ? 8000 : 4000) else { throw CorrectionClient.Failure.tooLong }
    let languages = PromptCatalog.languages
    if ["explain", "ask", "summarize_file"].contains(action), languages[request["responseLanguage"] as? String ?? "en"] == nil {
      throw CorrectionClient.Failure.invalid
    }
    if action == "translate", languages[request["targetLanguage"] as? String ?? ""] == nil { throw CorrectionClient.Failure.invalid }
    if action == "reply", !GatewaySchemas.replyIntents.contains(request["replyIntent"] as? String ?? "") { throw CorrectionClient.Failure.invalid }
    if ["result_refine", "text_habit"].contains(action) {
      guard let refinement = request["refinement"] as? String, !refinement.trimmingCharacters(in: .whitespaces).isEmpty,
            refinement.unicodeScalars.count <= 1000 else { throw CorrectionClient.Failure.invalid }
    }
    if action == "summarize_file", request["file"] as? JSONObject == nil { throw CorrectionClient.Failure.invalid }
    if action == "rename_files", (request["files"] as? [JSONObject])?.isEmpty != false { throw CorrectionClient.Failure.invalid }
    return request
  }

  private func call(for request: JSONObject) throws -> ModelCall {
    let action = request["action"] as! String
    let selection = request["selection"] as! String
    let hasContext = ["reply_options", "reply", "explain", "check_claim", "task_plan", "event_plan"].contains(action)
    var parts: [ModelCall.Part]
    switch action {
    case "rename_files":
      parts = []
      for (index, file) in (request["files"] as? [JSONObject] ?? []).enumerated() {
        let id = file["id"] as? String ?? "file-\(index)"
        let entry: JSONObject = ["id": id, "name": file["name"] ?? NSNull(), "content": file["text"] ?? NSNull()]
        parts.append(.text(Self.json(entry)))
        if let attachment = file["file"] as? JSONObject { parts.append(try attachmentPart(attachment, name: id)) }
      }
      if let refinement = request["refinement"] as? String {
        parts.append(.text(Self.json(["personalNamingInstructions": refinement])))
      }
    case "summarize_file":
      parts = [.text("Summarize and explain the attached file."), try attachmentPart(request["file"] as? JSONObject ?? [:], name: "document")]
    default:
      let envelope: JSONObject = hasContext ? ["selection": selection, "context": request["replyContext"] ?? NSNull()]
        : ["result_refine", "text_habit"].contains(action) ? ["selection": selection, "refinement": request["refinement"] ?? ""]
        : ["selection": selection]
      parts = [.text(Self.json(envelope))]
    }
    let reading = ["explain", "ask", "check_claim", "ask_refine", "summarize_file"].contains(action)
    return ModelCall(instructions: try PromptCatalog.render(action, body: request), parts: parts,
                     schema: GatewaySchemas.schema(for: action),
                     web: action == "check_claim" ? .required : action == "ask" && configuration.provider.supportsWebSearch ? .auto : .none,
                     maxOutputTokens: action == "reply_options" ? 512 : reading ? 1024 : 4096)
  }

  private func attachmentPart(_ file: JSONObject, name: String) throws -> ModelCall.Part {
    guard let mime = file["mime"] as? String, let data = file["data"] as? String, !data.isEmpty else { throw CorrectionClient.Failure.invalid }
    switch mime {
    case "application/pdf": return try .document(base64: data, filename: name + ".pdf", for: configuration.provider)
    case "image/jpeg": return .jpeg(base64: data)
    default: throw CorrectionClient.Failure.invalid
    }
  }

  // MARK: - Result validation (port of decodeResult)

  private func decode(_ answer: ModelAnswer, request: JSONObject) throws -> JSONObject {
    let action = request["action"] as! String
    let selection = request["selection"] as! String
    if ["ask", "check_claim"].contains(action) {
      guard let text = AskAnswer.format(answer.text, annotations: answer.annotations, consulted: answer.consulted,
                                        feeds: answer.feeds, requireCitation: action == "check_claim") else { throw CorrectionClient.Failure.invalid }
      return ["text": text]
    }
    guard var result = Self.object(answer.text) else { throw CorrectionClient.Failure.invalid }
    if result["status"] as? String == "unsupported" {
      throw action == "reply_options" ? CorrectionClient.Failure.notMessage : CorrectionClient.Failure.unsupportedContent
    }
    switch action {
    case "habit_design":
      result.removeValue(forKey: "status")
      return ["design": result]
    case "task_plan", "event_plan":
      guard Self.validCommitments(result, source: selection, kind: action == "task_plan" ? "task" : "event") else { throw CorrectionClient.Failure.invalid }
      return ["items": result["items"] ?? []]
    case "rename_files":
      guard let names = result["names"] as? [JSONObject], Self.validNames(names, count: (request["files"] as? [Any])?.count ?? 0) else {
        throw CorrectionClient.Failure.invalidFilenames
      }
      return ["names": names]
    case "reply_options":
      guard let intents = result["intents"] as? [String], intents.count == 3, Set(intents).count == 3,
            intents.allSatisfy(GatewaySchemas.replyIntents.contains) else { throw CorrectionClient.Failure.invalid }
      return ["intents": intents]
    case "extract_tasks":
      guard let tasks = result["tasks"] as? [JSONObject] else { throw CorrectionClient.Failure.invalid }
      let source = { (value: Any?) -> Bool in
        value == nil || value is NSNull || (value as? String).map { !$0.trimmingCharacters(in: .whitespaces).isEmpty && selection.contains($0.trimmingCharacters(in: .whitespaces)) } == true
      }
      guard tasks.allSatisfy({ ($0["action"] as? String).map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } == true && source($0["owner"]) && source($0["deadline"]) }) else {
        throw CorrectionClient.Failure.invalid
      }
      let oneLine = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/\s+/, with: " ") }
      result["text"] = tasks.isEmpty ? "No tasks found." : tasks.map { task in
        let details = [task["owner"], task["deadline"]].compactMap { $0 as? String }.map(oneLine)
        return "- " + oneLine(task["action"] as! String) + (details.isEmpty ? "" : " — " + details.joined(separator: " · "))
      }.joined(separator: "\n")
    case "key_points":
      guard let points = result["points"] as? [String], (1...3).contains(points.count),
            points.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { throw CorrectionClient.Failure.invalid }
      result["text"] = points.map { "- " + $0.trimmingCharacters(in: .whitespacesAndNewlines).replacing(/\s+/, with: " ") }.joined(separator: "\n")
    default: break
    }
    let limit = action == "explain" ? 2000 : action == "ask_refine" ? 4000 : 8000
    guard let text = result["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          text.unicodeScalars.count <= limit else { throw CorrectionClient.Failure.invalid }
    // A common model failure is to echo the transport envelope as the answer.
    if !selection.drop(while: \.isWhitespace).hasPrefix("{"), let envelope = Self.object(text), envelope["selection"] is String {
      throw CorrectionClient.Failure.invalid
    }
    return ["text": text]
  }

  private static func validNames(_ names: [JSONObject], count: Int) -> Bool {
    let ids = (0..<count).map { "file-\($0)" }
    return names.count == count && Set(names.compactMap { $0["id"] as? String }).count == count && names.allSatisfy { name in
      guard name.count == 2, let id = name["id"] as? String, ids.contains(id), let stem = name["stem"] as? String else { return false }
      return !stem.isEmpty && stem == stem.trimmingCharacters(in: .whitespacesAndNewlines) && stem.utf8.count <= 180
        && !stem.hasPrefix(".") && !stem.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || "/:\\".unicodeScalars.contains($0) }
    }
  }

  private static func validCommitments(_ result: JSONObject, source: String, kind: String) -> Bool {
    guard result["status"] as? String == "ok", let items = result["items"] as? [JSONObject], items.count <= 8 else { return false }
    func string(_ value: Any?) -> String? { value as? String }
    func isNull(_ value: Any?) -> Bool { value == nil || value is NSNull }
    let quote = { (value: Any?) in isNull(value) || (string(value).map { !$0.isEmpty && source.contains($0) } ?? false) }
    let date = { (value: Any?) -> Bool in
      guard !isNull(value) else { return true }
      guard let text = string(value), text.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil else { return false }
      return (try? Date(text + "T12:00:00Z", strategy: .iso8601)) != nil
    }
    let time = { (value: Any?) in isNull(value) || string(value)?.wholeMatch(of: /([01]\d|2[0-3]):[0-5]\d/) != nil }
    let zone = { (value: Any?) in isNull(value) || string(value).map { $0.count <= 100 && TimeZone(identifier: $0) != nil } == true }
    let issues = ["ambiguous_date", "ambiguous_zone", "missing_date", "missing_end", "dst_time"]
    return items.allSatisfy { item in
      guard item["kind"] as? String == kind, let title = string(item["title"]), !title.trimmingCharacters(in: .whitespaces).isEmpty,
            title.count <= 300, let evidence = string(item["evidence"]), !evidence.isEmpty, evidence.count <= 1000,
            source.contains(evidence) else { return false }
      return zone(item["timeZone"]) && (isNull(item["scheduleIssue"]) || issues.contains(string(item["scheduleIssue"]) ?? ""))
        && [item["owner"], item["deadline"], item["condition"]].allSatisfy(quote)
        && date(item["date"]) && date(item["endDate"]) && time(item["time"]) && time(item["endTime"])
        && (isNull(item["time"]) || !isNull(item["date"])) && (isNull(item["endTime"]) || !isNull(item["endDate"]))
        && (isNull(item["date"]) || !isNull(item["deadline"])) && (isNull(item["endDate"]) || !isNull(item["deadline"]))
    }
  }

  // MARK: - JSON helpers

  /// Models outside strict JSON mode sometimes wrap the object in Markdown or prose.
  static func object(_ text: String) -> JSONObject? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if let value = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? JSONObject { return value }
    guard let open = trimmed.firstIndex(of: "{"), let close = trimmed.lastIndex(of: "}"), open < close else { return nil }
    return try? JSONSerialization.jsonObject(with: Data(trimmed[open...close].utf8)) as? JSONObject
  }

  private static func json(_ value: JSONObject) -> String {
    (try? JSONSerialization.data(withJSONObject: value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
  }
}
