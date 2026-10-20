import Foundation

struct CorrectionClient: Sendable {
  var endpoint = URL(string: "https://ufcsajujaqemlduvpjpi.supabase.co/functions/v1/tero-correct")!
  var requestSession: URLSession? = nil
  private struct Request: Encodable { let requestID: UUID; let action: String; let selection: String; let responseLanguage: String?; let targetLanguage: String?; let replyContext: ReplyContext?; let replyIntent: ReplyIntent?; var stream = false; var file: FileSummaryInput? = nil; var planningReference: PlanningReference? = nil; var style: String? = nil; var refinement: String? = nil; var files: [FileNamingInput]? = nil }
  private struct OptionsResult: Decodable { let requestID: UUID; let intents: [ReplyIntent] }
  private struct Result: Decodable { let requestID: UUID; let text: String }
  enum Failure: Error, LocalizedError, Equatable {
    case allowanceReached, unavailable, tooLong, rateLimited, network, invalid, notMessage, invalidFilenames
    // Bring-your-own-key provider outcomes.
    case badRequest, providerRejected, providerCredits, modelUnavailable, needsWebSearch, scannedPDF, unsupportedContent
    var errorDescription: String? {
      switch self {
      case .allowanceReached: "Your Tero Pro allowance is used up for now."
      case .unavailable: "Add an AI provider in Settings → AI to use AI actions."
      case .badRequest: "The AI provider couldn’t handle this request. Try another model in Settings → AI."
      case .providerRejected: "Your AI provider rejected the key. Check it in Settings → AI."
      case .providerCredits: "Your AI provider account has no credits left."
      case .modelUnavailable: "This model isn’t available from your provider. Choose another in Settings → AI."
      case .needsWebSearch: "This action needs web search: use OpenAI, Anthropic or OpenRouter in Settings → AI."
      case .scannedPDF: "This PDF has no text layer. Use OpenAI, Anthropic or OpenRouter to read scanned pages."
      case .unsupportedContent: "The model declined this request."
      case .tooLong: "Select up to 4,000 characters for this preview."
      case .rateLimited: "AI is busy. Try again in a moment."
      case .network: "The request failed. Try again in a moment."
      case .notMessage: "Select a message to reply to."
      case .invalid: "No complete response received. Your text is unchanged."
      case .invalidFilenames: "Couldn’t generate complete filenames. Try again."
      }
    }
  }

  struct PlanningReference: Encodable, Sendable {
    let localDate: String
    let timeZone: String
    static func current() -> Self {
      let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = .current
      formatter.dateFormat = "yyyy-MM-dd"
      return .init(localDate: formatter.string(from: .now), timeZone: TimeZone.current.identifier)
    }
  }
  func plan(_ selection: String, destination: CommitmentDestination, context: ReplyContext? = nil, requestID: UUID, credential: String) async throws -> [CommitmentDraft] {
    struct PlanResult: Decodable { let requestID: UUID; let items: [CommitmentDraft] }
    let data = try await send(Request(requestID: requestID, action: destination == .reminders ? "task_plan" : "event_plan",
      selection: selection, responseLanguage: nil, targetLanguage: nil, replyContext: context, replyIntent: nil,
      planningReference: .current()), credential: credential, retryServerFailure: true)
    guard let result = try? JSONDecoder().decode(PlanResult.self, from: data), result.requestID == requestID,
          result.items.count <= 8, result.items.allSatisfy({ $0.kind == destination.kind && $0.valid(for: selection) }) else { throw Failure.invalid }
    return result.items
  }

  func renameFiles(_ files: [FileNamingInput], requestID: UUID, credential: String, refinement: String? = nil) async throws -> [String] {
    struct NamesResult: Decodable { let requestID: UUID; let names: [FileNameProposal] }
    let data = try await send(Request(requestID: requestID, action: "rename_files", selection: "Propose filenames from the attached contents.",
      responseLanguage: nil, targetLanguage: nil, replyContext: nil, replyIntent: nil, refinement: refinement, files: files), credential: credential)
    guard let result = try? JSONDecoder().decode(NamesResult.self, from: data), result.requestID == requestID else { throw Failure.invalidFilenames }
    do { return try FileNameProposal.ordered(result.names, count: files.count, format: refinement == nil) } catch { throw Failure.invalidFilenames }
  }

  func designHabit(_ request: String, current: TextHabit?, requestID: UUID, credential: String, repairingFilePlan: Bool = false) async throws -> HabitDesign {
    struct Current: Encodable { let name: String; let instruction: String; let filePlan: FileHabitPlan? }
    struct Input: Encodable { let request: String; let current: Current? }
    let input = Input(request: request, current: current.map { Current(name: $0.name, instruction: $0.instruction, filePlan: $0.filePlan) })
    let selection = String(decoding: try JSONEncoder().encode(input), as: UTF8.self)
    let data = try await send(Request(requestID: requestID, action: "habit_design", selection: selection,
      responseLanguage: nil, targetLanguage: nil, replyContext: nil, replyIntent: nil), credential: credential)
    struct Envelope: Decodable { let requestID: UUID; let design: HabitDesign }
    let response = try JSONDecoder().decode(Envelope.self, from: data)
    guard response.requestID == requestID, response.design.isValid else { throw Failure.invalid }
    if response.design.needsFileRenamePlan {
      guard !repairingFilePlan, request.unicodeScalars.count <= 2000 else { throw Failure.invalid }
      // One bounded repair of a structurally valid but incorrectly typed draft.
      // Request real filename samples instead of relabeling a text-only preview.
      let clarification = "\nThis habit converts SELECTED FILENAMES, not selected text. Return filePlan with operation rename, usesContents false, and suitable filters. Return real fileSamples; sample must be empty. Preserve extensions."
      return try await designHabit(request + clarification, current: current, requestID: UUID(), credential: credential, repairingFilePlan: true)
    }
    return response.design
  }

  func shop(_ input: String, requestID: UUID, credential: String) async throws -> ShoppingResult {
    if let local = Self.localGateway(credential) {
      let body = try JSONEncoder().encode(Request(requestID: requestID, action: "ask", selection: input,
        responseLanguage: nil, targetLanguage: nil, replyContext: nil, replyIntent: nil))
      let value = try JSONDecoder().decode(ShoppingResult.self, from: try await local.shop(body))
      guard value.requestID == requestID, value.valid else { throw Failure.invalid }
      return value
    }
    let url = endpoint.deletingLastPathComponent().appendingPathComponent("tero-shop")
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
    request.httpMethod = "POST"
    request.setValue("Bearer " + credential, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(Request(requestID: requestID, action: "ask", selection: input,
      responseLanguage: nil, targetLanguage: nil, replyContext: nil, replyIntent: nil))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil; configuration.urlCache = nil
    let session = requestSession ?? URLSession(configuration: configuration)
    defer { if requestSession == nil { session.invalidateAndCancel() } }
    let (data, response) = try await session.data(for: request)
    try Task.checkCancellation()
    await GatewayAccess.didRequest()
    guard let http = response as? HTTPURLResponse else { throw Failure.network }
    if http.statusCode == 401 { throw Failure.unavailable }
    if http.statusCode == 402 { throw Failure.allowanceReached }
    guard http.statusCode == 200, data.count <= 32768 else { throw Failure.network }
    let value = try JSONDecoder().decode(ShoppingResult.self, from: data)
    guard value.requestID == requestID, value.valid else { throw Failure.invalid }
    return value
  }

  func correct(_ selection: String, requestID: UUID, credential: String) async throws -> String {
    try await perform(selection, action: "fix", requestID: requestID, credential: credential)
  }

  func rewrite(_ selection: String, requestID: UUID, credential: String) async throws -> String {
    try await perform(selection, action: "rewrite", requestID: requestID, credential: credential)
  }

  func transform(_ selection: String, action: String, style: TextStyle? = nil, requestID: UUID, credential: String) async throws -> String {
    try await perform(selection, action: action, requestID: requestID, credential: credential, style: style)
  }

  func refinePrompt(_ prompt: String, requestID: UUID, credential: String) async throws -> String {
    let text = try await perform(prompt, action: "ask_refine", requestID: requestID, credential: credential)
    guard text.unicodeScalars.count <= 4000 else { throw Failure.invalid }
    return text
  }

  func keyPoints(_ selection: String, requestID: UUID, credential: String) async throws -> String {
    try await perform(selection, action: "key_points", requestID: requestID, credential: credential)
  }

  func extractTasks(_ selection: String, requestID: UUID, credential: String) async throws -> String {
    try await perform(selection, action: "extract_tasks", requestID: requestID, credential: credential)
  }

  func explain(_ selection: String, language: ResponseLanguage = .english, requestID: UUID, credential: String) async throws -> String {
    try await perform(selection, action: "explain", language: language, requestID: requestID, credential: credential)
  }

  func translate(_ selection: String, language: ResponseLanguage, requestID: UUID, credential: String) async throws -> String {
    try await perform(selection, action: "translate", language: language, requestID: requestID, credential: credential)
  }

  func replyOptions(_ selection: String, context: ReplyContext?, requestID: UUID, credential: String) async throws -> [ReplyIntent] {
    let data = try await send(Request(requestID: requestID, action: "reply_options", selection: selection,
      responseLanguage: nil, targetLanguage: nil, replyContext: context, replyIntent: nil), credential: credential)
    guard let result = try? JSONDecoder().decode(OptionsResult.self, from: data), result.requestID == requestID,
          result.intents.count == 3, Set(result.intents).count == 3 else { throw Failure.invalid }
    return result.intents
  }

  func reply(_ selection: String, context: ReplyContext?, intent: ReplyIntent, requestID: UUID, credential: String) async throws -> String {
    try await perform(selection, action: "reply", context: context, intent: intent, requestID: requestID, credential: credential)
  }

  /// Reading only. A partial answer is never returned as a completed result.
  func reading(_ text: String, action: String, language: ResponseLanguage? = nil,
               context: ReplyContext? = nil, intent: ReplyIntent? = nil,
               requestID: UUID, credential: String,
               update: @escaping @MainActor @Sendable (String) -> Void, file: FileSummaryInput? = nil, style: TextStyle? = nil, refinement: String? = nil) async throws -> String {
    guard text.unicodeScalars.count <= (action == "result_refine" ? 8000 : 4000) else { throw Failure.tooLong }
    let payload = Request(requestID: requestID, action: action, selection: text,
      responseLanguage: ["explain", "summarize_file"].contains(action) ? language?.rawValue : nil,
      targetLanguage: action == "translate" ? language?.rawValue : nil,
      replyContext: context, replyIntent: intent, stream: true, file: file, style: style?.rawValue, refinement: refinement)
    if let local = Self.localGateway(credential) {
      let text = try await local.stream(try JSONEncoder().encode(payload), update: update)
      guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            text.unicodeScalars.count <= (action == "explain" ? 2000 : 8000) else { throw Failure.invalid }
      return text
    }
    var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: ["ask", "check_claim", "summarize_file"].contains(action) ? 60 : 30)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    if file != nil { request.setValue("1", forHTTPHeaderField: "X-Tero-File") }
    request.httpBody = try JSONEncoder().encode(payload)
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil; config.urlCache = nil
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let (bytes, response) = try await session.bytes(for: request)
    await GatewayAccess.didRequest()
    guard let response = response as? HTTPURLResponse else { throw Failure.invalid }
    switch response.statusCode {
    case 200: break
    case 401, 403: throw Failure.unavailable
    case 503: throw Failure.network
    case 402: await GatewayAccess.didRequest(); throw Failure.allowanceReached
    case 413: throw Failure.tooLong
    case 429: throw Failure.rateLimited
    default: throw Failure.network
    }
    guard response.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/x-ndjson") == true else { throw Failure.invalid }
    struct Event: Decodable { let requestID: UUID; let type: String; let text: String }
    var received = 0
    let limit = action == "explain" ? 2000 : 8000
    for try await line in bytes.lines {
      try Task.checkCancellation()
      received += line.utf8.count
      // Progress events are bounded full snapshots, so long translations can
      // legitimately transfer much more than the final answer's byte length.
      guard received <= 64 * 1024 * 1024, line.utf8.count <= 65536,
            let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)),
            event.requestID == requestID, event.text.unicodeScalars.count <= limit else { throw Failure.invalid }
      switch event.type {
      case "progress": await update(event.text)
      case "done":
        guard !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Failure.invalid }
        await GatewayAccess.didRequest()
        return event.text
      case "error": throw Failure.invalid
      default: throw Failure.invalid
      }
    }
    throw Failure.invalid
  }

  private func perform(_ selection: String, action: String, language: ResponseLanguage? = nil, context: ReplyContext? = nil, intent: ReplyIntent? = nil, requestID: UUID, credential: String, style: TextStyle? = nil) async throws -> String {
    let data = try await send(Request(requestID: requestID, action: action, selection: selection,
      responseLanguage: ["explain", "summarize_file"].contains(action) ? language?.rawValue : nil,
      targetLanguage: action == "translate" ? language?.rawValue : nil, replyContext: context, replyIntent: intent, style: style?.rawValue), credential: credential)
    guard let result = try? JSONDecoder().decode(Result.self, from: data),
      result.requestID == requestID, !result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      result.text.unicodeScalars.count <= (action == "explain" ? 2000 : 8000) else { throw Failure.invalid }
    return result.text
  }

  /// The credential `GatewayAccess` returns when requests use the person's own AI key.
  static let ownKeyCredential = "own-ai-key"

  private static func localGateway(_ credential: String) -> LocalGateway? {
    guard credential == ownKeyCredential, let configuration = AIConfiguration.active else { return nil }
    return LocalGateway(configuration: configuration)
  }

  private func send(_ payload: Request, credential: String, retryServerFailure: Bool = false) async throws -> Data {
    guard payload.selection.unicodeScalars.count <= 4000 else { throw Failure.tooLong }
    if let local = Self.localGateway(credential) { return try await local.respond(try JSONEncoder().encode(payload)) }
    var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: payload.files == nil ? 30 : 60)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(credential)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(payload)
    if payload.files != nil { request.setValue("1", forHTTPHeaderField: "X-Tero-File") }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    let session = requestSession ?? URLSession(configuration: configuration)
    defer { if requestSession == nil { session.invalidateAndCancel() } }
    let data: Data
    let rawResponse: URLResponse
    do { (data, rawResponse) = try await session.data(for: request) }
    catch {
      try Task.checkCancellation()
      if retryServerFailure, let transport = error as? URLError,
         [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(transport.code) {
        try await Task.sleep(for: .milliseconds(250))
        return try await send(payload, credential: credential)
      }
      throw error
    }
    await GatewayAccess.didRequest()
    try Task.checkCancellation()
    guard let response = rawResponse as? HTTPURLResponse else { throw Failure.invalid }
    if CommandLine.arguments.contains("--evaluate-fixtures"), response.statusCode != 200 {
      struct GatewayError: Decodable { let error: String }
      let code = (try? JSONDecoder().decode(GatewayError.self, from: data))?.error
      let allowed = ["invalid_reference", "invalid_input", "invalid_result", "provider_error", "request_failed", "incomplete_result", "unsupported", "rate_limited"]
      print("Fixture gateway: action=\(payload.action), status=\(response.statusCode), code=\(code.flatMap { allowed.contains($0) ? $0 : nil } ?? "unknown")")
    }
    // Planning only prepares a review. Retrying this read-only call never creates
    // Apple items, and retains the same source, date reference and request identifier.
    if retryServerFailure, [500, 502, 504].contains(response.statusCode) {
      try await Task.sleep(for: .milliseconds(250))
      return try await send(payload, credential: credential)
    }
    switch response.statusCode {
    case 200: break
    case 401, 403: throw Failure.unavailable
    case 503: throw Failure.network
    case 400: throw Failure.invalid
    case 402: await GatewayAccess.didRequest(); throw Failure.allowanceReached
    case 413: throw Failure.tooLong
    case 429: throw Failure.rateLimited
    case 422: throw payload.action == "reply_options" ? Failure.notMessage : Failure.invalid
    default: throw Failure.network
    }
    guard data.count <= 65536 else { throw Failure.invalid }
    return data
  }
}
