import Foundation
import PDFKit

/// One model request, independent of the provider's dialect.
struct ModelCall {
  enum Part { case text(String), jpeg(base64: String), pdf(base64: String, filename: String) }
  enum Web { case none, auto, required }
  var instructions: String
  var parts: [Part]
  var schema: (name: String, schema: JSONObject)?
  var web: Web = .none
  var maxOutputTokens: Int
}

/// The model's final output, with any web sources it cited or consulted.
struct ModelAnswer {
  var text: String
  var annotations: [WebCitation] = []
  var consulted: [WebCitation] = []
  var feeds: [String] = []
  var searched = false
}

/// One decoded server-sent event, consumed by a single reader.
struct SSEEvent: @unchecked Sendable { let object: JSONObject }

/// Calls a bring-your-own-key provider directly from this Mac.
struct AIProviderClient {
  let configuration: AIConfiguration
  var timeout: TimeInterval = 90

  private var provider: AIProvider { configuration.provider }

  func send(_ call: ModelCall, onText: ((String) async -> Void)? = nil) async throws -> ModelAnswer {
    try call.validate(for: provider)
    switch provider.wire {
    case .openAIResponses: return try await openAIResponses(call, onText: onText)
    case .anthropicMessages: return try await anthropic(call, onText: onText)
    case .openAICompatible: return try await compatible(call, onText: onText)
    }
  }

  /// Model identifiers offered by the provider, for the settings picker.
  func models() async throws -> [String] {
    var request = URLRequest(url: configuration.baseURL.appending(path: "models"), timeoutInterval: 15)
    authorize(&request)
    let (data, response) = try await session().data(for: request)
    try check(response, data: data)
    guard let object = try? JSONSerialization.jsonObject(with: data) as? JSONObject,
          let list = object["data"] as? [JSONObject] ?? object["models"] as? [JSONObject] else { throw CorrectionClient.Failure.invalid }
    return list.compactMap { $0["id"] as? String ?? $0["name"] as? String }.map { $0.replacing(/^models\//, with: "") }.sorted()
  }

  // MARK: - OpenAI Responses

  private func openAIResponses(_ call: ModelCall, onText: ((String) async -> Void)?) async throws -> ModelAnswer {
    var content: [JSONObject] = []
    for part in call.parts {
      switch part {
      case .text(let text): content.append(["type": "input_text", "text": text])
      case .jpeg(let data): content.append(["type": "input_image", "image_url": "data:image/jpeg;base64," + data, "detail": "auto"])
      case .pdf(let data, let name): content.append(["type": "input_file", "filename": name, "file_data": "data:application/pdf;base64," + data])
      }
    }
    var body: JSONObject = ["model": configuration.model, "store": false, "stream": onText != nil,
                            "instructions": call.instructions, "max_output_tokens": call.maxOutputTokens,
                            "input": [["role": "user", "content": content]]]
    if configuration.model.hasPrefix("gpt-6") { body["reasoning"] = ["effort": "none"] }
    if call.web != .none {
      body["tools"] = [["type": "web_search", "search_context_size": "low"]]
      body["tool_choice"] = call.web == .required ? "required" : "auto"
      body["max_tool_calls"] = 2
      body["include"] = ["web_search_call.action.sources"]
    }
    body["text"] = ["format": call.schema.map { ["type": "json_schema", "name": $0.name, "strict": true, "schema": $0.schema] as JSONObject }
                    ?? ["type": "text"]]
    var request = try post("responses", body)
    authorize(&request)
    guard let onText else {
      let (data, response) = try await session().data(for: request)
      try check(response, data: data)
      guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else { throw CorrectionClient.Failure.invalid }
      return try parseResponses(object, plain: call.schema == nil)
    }
    var raw = ""
    for try await item in try await events(request) {
      let event = item.object
      switch event["type"] as? String {
      case "response.output_text.delta":
        guard let delta = event["delta"] as? String else { throw CorrectionClient.Failure.invalid }
        raw += delta
        await onText(raw)
      case "response.completed":
        guard let response = event["response"] as? JSONObject else { throw CorrectionClient.Failure.invalid }
        return try parseResponses(response, plain: call.schema == nil)
      case "error", "response.failed", "response.incomplete", "response.refusal.delta":
        throw CorrectionClient.Failure.invalid
      default: continue
      }
    }
    throw CorrectionClient.Failure.invalid
  }

  private func parseResponses(_ result: JSONObject, plain: Bool) throws -> ModelAnswer {
    guard result["status"] as? String == "completed" else { throw CorrectionClient.Failure.invalid }
    let output = result["output"] as? [JSONObject] ?? []
    let messages = output.filter { $0["type"] as? String == "message" }
    if messages.flatMap({ $0["content"] as? [JSONObject] ?? [] }).contains(where: { $0["type"] as? String == "refusal" }) {
      throw CorrectionClient.Failure.unsupportedContent
    }
    // Search can emit an interim assistant message before its final answer.
    let final = plain ? messages.last { $0["phase"] as? String != "commentary" } : nil
    let parts = (plain ? (final?["content"] as? [JSONObject] ?? []) : messages.flatMap { $0["content"] as? [JSONObject] ?? [] })
      .filter { $0["type"] as? String == "output_text" }
    guard parts.count == 1, let text = parts[0]["text"] as? String else { throw CorrectionClient.Failure.invalid }
    var answer = ModelAnswer(text: text)
    answer.annotations = (parts[0]["annotations"] as? [JSONObject] ?? []).compactMap {
      guard $0["type"] as? String == "url_citation", let url = $0["url"] as? String else { return nil }
      return WebCitation(url: url, title: $0["title"] as? String, start: $0["start_index"] as? Int, end: $0["end_index"] as? Int)
    }
    let searches = output.filter { $0["type"] as? String == "web_search_call" }
    answer.searched = !searches.isEmpty
    let sources = searches.flatMap { (($0["action"] as? JSONObject)?["sources"] as? [JSONObject]) ?? [] }
    answer.consulted = sources.compactMap { source in (source["url"] as? String).map { WebCitation(url: $0, title: source["title"] as? String) } }
    let feedNames = ["oai-weather": "OpenAI weather feed", "oai-sports": "OpenAI sports feed", "oai-finance": "OpenAI finance feed"]
    answer.feeds = Array(Set(sources.compactMap { $0["type"] as? String == "api" ? ($0["name"] as? String).flatMap { feedNames[$0] } : nil })).sorted()
    return answer
  }

  // MARK: - Anthropic Messages

  private func anthropic(_ call: ModelCall, onText: ((String) async -> Void)?) async throws -> ModelAnswer {
    var content: [JSONObject] = []
    for part in call.parts {
      switch part {
      case .text(let text): content.append(["type": "text", "text": text])
      case .jpeg(let data): content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": data]])
      case .pdf(let data, _): content.append(["type": "document", "source": ["type": "base64", "media_type": "application/pdf", "data": data]])
      }
    }
    // A forced tool returns exactly the schema's object. Web search and a forced tool
    // can't be combined, so searched structured answers return JSON as text instead.
    let forcedTool = call.schema != nil && call.web == .none
    var instructions = call.instructions
    if let schema = call.schema, !forcedTool { instructions += Self.jsonInstruction(schema.schema) }
    // Searched answers carry their citations only in the complete message.
    let streaming = onText != nil && call.web == .none
    var body: JSONObject = ["model": configuration.model, "max_tokens": call.maxOutputTokens, "system": instructions,
                            "messages": [["role": "user", "content": content]], "stream": streaming]
    var tools: [JSONObject] = []
    if let schema = call.schema, forcedTool {
      tools.append(["name": schema.name, "description": "Return the complete result.", "input_schema": schema.schema])
      body["tool_choice"] = ["type": "tool", "name": schema.name]
    }
    if call.web != .none { tools.append(["type": "web_search_20250305", "name": "web_search", "max_uses": 2]) }
    if !tools.isEmpty { body["tools"] = tools }
    var request = try post("messages", body)
    authorize(&request)
    guard streaming, let onText else {
      let (data, response) = try await session().data(for: request)
      try check(response, data: data)
      guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject else { throw CorrectionClient.Failure.invalid }
      let answer = try parseAnthropic(object, call: call)
      if let onText { await onText(answer.text) }
      return answer
    }
    var raw = "", stop: String?
    for try await item in try await events(request) {
      let event = item.object
      switch event["type"] as? String {
      case "content_block_delta":
        let delta = event["delta"] as? JSONObject ?? [:]
        if let text = delta["text"] as? String { raw += text } else if let json = delta["partial_json"] as? String { raw += json } else { continue }
        await onText(raw)
      case "message_delta": stop = (event["delta"] as? JSONObject)?["stop_reason"] as? String
      case "message_stop":
        guard stop != "max_tokens" else { throw CorrectionClient.Failure.invalid }
        guard stop != "refusal" else { throw CorrectionClient.Failure.unsupportedContent }
        return ModelAnswer(text: raw)
      case "error": throw CorrectionClient.Failure.invalid
      default: continue
      }
    }
    throw CorrectionClient.Failure.invalid
  }

  private func parseAnthropic(_ result: JSONObject, call: ModelCall) throws -> ModelAnswer {
    switch result["stop_reason"] as? String {
    case "max_tokens": throw CorrectionClient.Failure.invalid
    case "refusal": throw CorrectionClient.Failure.unsupportedContent
    default: break
    }
    let blocks = result["content"] as? [JSONObject] ?? []
    var answer = ModelAnswer(text: "")
    if let tool = blocks.first(where: { $0["type"] as? String == "tool_use" }), let input = tool["input"] {
      answer.text = String(decoding: try JSONSerialization.data(withJSONObject: input), as: UTF8.self)
      return answer
    }
    // Keep only the text after the last search, which is the final answer.
    let lastSearch = blocks.lastIndex { ["server_tool_use", "web_search_tool_result"].contains($0["type"] as? String) } ?? -1
    let textBlocks = blocks.enumerated().filter { $0.offset > lastSearch && $0.element["type"] as? String == "text" }.map(\.element)
    answer.text = textBlocks.compactMap { $0["text"] as? String }.joined()
    answer.annotations = textBlocks.flatMap { $0["citations"] as? [JSONObject] ?? [] }.compactMap {
      ($0["url"] as? String).map { url in WebCitation(url: url, title: nil) }
    }
    let results = blocks.filter { $0["type"] as? String == "web_search_tool_result" }
    answer.searched = !results.isEmpty
    answer.consulted = results.flatMap { $0["content"] as? [JSONObject] ?? [] }.compactMap { item in
      (item["url"] as? String).map { WebCitation(url: $0, title: item["title"] as? String) }
    }
    answer.annotations = answer.annotations.map { citation in
      var citation = citation
      citation.title = answer.consulted.first { $0.url == citation.url }?.title
      return citation
    }
    return answer
  }

  // MARK: - OpenAI-compatible chat completions

  /// Structured output support varies, so try strict schema, then JSON mode, then instructions only.
  private enum JSONMode: CaseIterable { case schema, object, prompt }

  private func compatible(_ call: ModelCall, onText: ((String) async -> Void)?) async throws -> ModelAnswer {
    let modes: [JSONMode] = call.schema == nil ? [.prompt] : JSONMode.allCases
    var lastError: Error = CorrectionClient.Failure.invalid
    for mode in modes {
      do { return try await compatible(call, mode: mode, onText: onText) }
      catch CorrectionClient.Failure.badRequest { lastError = CorrectionClient.Failure.invalid; continue }
    }
    throw lastError
  }

  private func compatible(_ call: ModelCall, mode: JSONMode, onText: ((String) async -> Void)?) async throws -> ModelAnswer {
    var content: [JSONObject] = []
    for part in call.parts {
      switch part {
      case .text(let text): content.append(["type": "text", "text": text])
      case .jpeg(let data): content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + data]])
      case .pdf(let data, let name):
        content.append(["type": "file", "file": ["filename": name, "file_data": "data:application/pdf;base64," + data]])
      }
    }
    var instructions = call.instructions
    if let schema = call.schema, mode != .schema { instructions += Self.jsonInstruction(schema.schema) }
    // Plain string content is the most widely accepted form for text-only requests.
    let userContent: Any = content.count == 1 && content[0]["type"] as? String == "text" ? content[0]["text"] as Any : content
    var body: JSONObject = ["model": configuration.model, "max_tokens": call.maxOutputTokens,
                            "messages": [["role": "system", "content": instructions], ["role": "user", "content": userContent]]]
    if let schema = call.schema {
      switch mode {
      case .schema: body["response_format"] = ["type": "json_schema", "json_schema": ["name": schema.name, "strict": true, "schema": schema.schema]]
      case .object: body["response_format"] = ["type": "json_object"]
      case .prompt: break
      }
    }
    if call.web != .none { body["plugins"] = [["id": "web", "max_results": 3]] }
    // Searched answers carry their citations only in the final message.
    let streaming = onText != nil && call.web == .none
    body["stream"] = streaming
    var request = try post("chat/completions", body)
    authorize(&request)
    guard streaming, let onText else {
      let (data, response) = try await session().data(for: request)
      try check(response, data: data)
      guard let object = try JSONSerialization.jsonObject(with: data) as? JSONObject,
            let choice = (object["choices"] as? [JSONObject])?.first,
            let message = choice["message"] as? JSONObject else { throw CorrectionClient.Failure.invalid }
      guard choice["finish_reason"] as? String != "length" else { throw CorrectionClient.Failure.invalid }
      if let refusal = message["refusal"] as? String, !refusal.isEmpty { throw CorrectionClient.Failure.unsupportedContent }
      var answer = ModelAnswer(text: message["content"] as? String ?? "")
      answer.annotations = (message["annotations"] as? [JSONObject] ?? []).compactMap {
        let citation = $0["url_citation"] as? JSONObject ?? $0
        return (citation["url"] as? String).map { WebCitation(url: $0, title: citation["title"] as? String) }
      }
      answer.searched = call.web != .none && !answer.annotations.isEmpty
      answer.consulted = answer.annotations
      if let onText { await onText(answer.text) }
      return answer
    }
    var raw = "", finish: String?
    for try await item in try await events(request) {
      let event = item.object
      guard let choice = (event["choices"] as? [JSONObject])?.first else { continue }
      if let reason = choice["finish_reason"] as? String { finish = reason }
      if let delta = (choice["delta"] as? JSONObject)?["content"] as? String, !delta.isEmpty {
        raw += delta
        await onText(raw)
      }
    }
    guard finish != "length", !raw.isEmpty else { throw CorrectionClient.Failure.invalid }
    return ModelAnswer(text: raw)
  }

  static func jsonInstruction(_ schema: JSONObject) -> String {
    let json = (try? JSONSerialization.data(withJSONObject: schema, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    return "\n\nRespond with a single JSON object only, without Markdown or commentary, matching this JSON Schema:\n" + json
  }

  // MARK: - Transport

  private func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil; configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = timeout
    return URLSession(configuration: configuration)
  }

  private func post(_ path: String, _ body: JSONObject) throws -> URLRequest {
    var request = URLRequest(url: configuration.baseURL.appending(path: path), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return request
  }

  private func authorize(_ request: inout URLRequest) {
    switch provider.wire {
    case .anthropicMessages:
      request.setValue(configuration.key, forHTTPHeaderField: "x-api-key")
      request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    default:
      if let key = configuration.key { request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
    }
    if provider == .openRouter {
      request.setValue("https://teroflow.app", forHTTPHeaderField: "HTTP-Referer")
      request.setValue("Tero", forHTTPHeaderField: "X-Title")
    }
  }

  private func check(_ response: URLResponse, data: Data?) throws {
    guard let http = response as? HTTPURLResponse else { throw CorrectionClient.Failure.network }
    switch http.statusCode {
    case 200..<300: return
    case 400, 422: throw CorrectionClient.Failure.badRequest
    case 401, 403: throw CorrectionClient.Failure.providerRejected
    case 402: throw CorrectionClient.Failure.providerCredits
    case 404: throw CorrectionClient.Failure.modelUnavailable
    case 413: throw CorrectionClient.Failure.tooLong
    case 429: throw CorrectionClient.Failure.rateLimited
    default: throw CorrectionClient.Failure.network
    }
  }

  /// Server-sent events: each `data:` line is one JSON object.
  private func events(_ request: URLRequest) async throws -> AsyncThrowingStream<SSEEvent, Error> {
    let session = session()
    let (bytes, response) = try await session.bytes(for: request)
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      session.invalidateAndCancel()
      try check(response, data: nil)
    }
    return AsyncThrowingStream { continuation in
      let task = Task {
        defer { session.invalidateAndCancel() }
        do {
          var received = 0
          for try await line in bytes.lines {
            try Task.checkCancellation()
            received += line.utf8.count
            guard received <= 16 * 1024 * 1024, line.utf8.count <= 262_144 else { throw CorrectionClient.Failure.invalid }
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? JSONObject else { continue }
            continuation.yield(SSEEvent(object: object))
          }
          continuation.finish()
        } catch { continuation.finish(throwing: error) }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}

private extension ModelCall {
  func validate(for provider: AIProvider) throws {
    if web == .required && !provider.supportsWebSearch { throw CorrectionClient.Failure.needsWebSearch }
  }
}

extension ModelCall.Part {
  /// Providers without native PDF input receive the document's text layer instead.
  static func document(base64: String, filename: String, for provider: AIProvider) throws -> ModelCall.Part {
    if provider.supportsPDF { return .pdf(base64: base64, filename: filename) }
    guard let data = Data(base64Encoded: base64), let pdf = PDFDocument(data: data),
          let text = pdf.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
      throw CorrectionClient.Failure.scannedPDF
    }
    return .text("Attached PDF \(filename), text only:\n" + String(text.prefix(120_000)))
  }
}
