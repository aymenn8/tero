import Foundation

typealias JSONObject = [String: Any]

/// Published Tero prompts, bundled for bring-your-own-key requests.
/// Mirrors tero-correct/prompt-store.ts: same variants, placeholders and refusal to render
/// a prompt that misses a required value.
enum PromptCatalog {
  static let languages: [String: String] = [
    "en": "English", "fr": "French", "es": "Spanish", "de": "German", "it": "Italian", "pt": "Portuguese",
    "nl": "Dutch", "ar": "Arabic", "zh": "Chinese (Simplified)", "ja": "Japanese", "ko": "Korean", "hi": "Hindi"]

  private struct Entry: Decodable { let version: Int; let instructions: String }
  private static let entries: [String: Entry] = {
    guard let url = Bundle.main.url(forResource: "Prompts", withExtension: "json"),
          let data = try? Data(contentsOf: url) else { return [:] }
    return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
  }()

  /// Raw published instructions for a prompt key such as "rank_actions:default".
  static func instructions(_ key: String) -> String? { entries[key]?.instructions }

  static func variant(for body: JSONObject) -> String {
    switch body["action"] as? String {
    case "rewrite": body["style"] as? String ?? "natural"
    case "tone": body["style"] as? String ?? ""
    case "reply": body["replyIntent"] as? String ?? ""
    default: "default"
    }
  }

  static func render(_ action: String, body: JSONObject) throws -> String {
    guard let template = entries[action + ":" + variant(for: body)]?.instructions else { throw CorrectionClient.Failure.invalid }
    let reference = body["planningReference"] as? JSONObject
    let values: [String: String?] = [
      "target_language": (body["targetLanguage"] as? String).flatMap { languages[$0] },
      "output_language": languages[body["responseLanguage"] as? String ?? "en"],
      "current_date": Self.today(),
      "reference_date": reference?["localDate"] as? String,
      "time_zone": reference?["timeZone"] as? String]
    let required: [String] = switch action {
    case "translate": ["target_language"]
    case "explain", "summarize_file": ["output_language"]
    case "ask", "check_claim": ["current_date"]
    case "task_plan", "event_plan": ["reference_date", "time_zone"]
    default: []
    }
    guard required.allSatisfy({ template.contains("{{\($0)}}") }) else { throw CorrectionClient.Failure.invalid }
    var output = template
    for match in template.matches(of: /\{\{([^{}]+)\}\}/) {
      guard let value = values[String(match.1)] ?? nil else { throw CorrectionClient.Failure.invalid }
      output = output.replacing(String(match.0), with: value)
    }
    return output
  }

  private static func today() -> String {
    // The gateway used the UTC calendar day; keep identical behaviour.
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let parts = calendar.dateComponents([.year, .month, .day], from: .now)
    return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
  }
}

/// JSON schemas for structured actions, identical to the gateway's.
enum GatewaySchemas {
  static func parse(_ json: String) -> JSONObject {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? JSONObject ?? [:]
  }
  static let replyIntents = ["accept", "decline", "clarify", "thank", "acknowledge", "alternative", "more_time",
                             "apologize", "support", "offer_help", "follow_up"]

  static var correction: JSONObject { parse(#"{"type":"object","additionalProperties":false,"properties":{"status":{"type":"string","enum":["ok","unsupported"]},"text":{"type":["string","null"]}},"required":["status","text"]}"#) }
  static var keyPoints: JSONObject { parse(#"{"type":"object","additionalProperties":false,"properties":{"status":{"type":"string","enum":["ok","unsupported"]},"points":{"type":["array","null"],"items":{"type":"string"},"minItems":1,"maxItems":3}},"required":["status","points"]}"#) }
  static var extractTasks: JSONObject { parse(#"{"type":"object","additionalProperties":false,"properties":{"status":{"type":"string","enum":["ok","unsupported"]},"tasks":{"type":["array","null"],"items":{"type":"object","additionalProperties":false,"properties":{"action":{"type":"string"},"owner":{"type":["string","null"]},"deadline":{"type":["string","null"]}},"required":["action","owner","deadline"]}}},"required":["status","tasks"]}"#) }
  static var replyOptions: JSONObject { parse(#"{"type":"object","additionalProperties":false,"properties":{"status":{"type":"string","enum":["ok","unsupported"]},"intents":{"type":["array","null"],"minItems":3,"maxItems":3,"items":{"type":"string","enum":[]}}},"required":["status","intents"]}"#)
    .settingIntents(replyIntents) }
  static var commitments: JSONObject { parse(#"{"type":"object","additionalProperties":false,"properties":{"status":{"type":"string","enum":["ok","unsupported"]},"items":{"type":["array","null"],"maxItems":8,"items":{"type":"object","additionalProperties":false,"properties":{"kind":{"type":"string","enum":["task","event"]},"title":{"type":"string"},"owner":{"type":["string","null"]},"deadline":{"type":["string","null"]},"condition":{"type":["string","null"]},"evidence":{"type":"string"},"date":{"type":["string","null"]},"time":{"type":["string","null"]},"endDate":{"type":["string","null"]},"endTime":{"type":["string","null"]},"timeZone":{"type":["string","null"]},"scheduleIssue":{"type":["string","null"],"enum":["ambiguous_date","ambiguous_zone","missing_date","missing_end","dst_time",null]}},"required":["kind","title","owner","deadline","condition","evidence","date","time","endDate","endTime","timeZone","scheduleIssue"]}}},"required":["status","items"]}"#) }
  static var naming: JSONObject { parse(#"{"type":"object","additionalProperties":false,"properties":{"status":{"type":"string","enum":["ok","unsupported"]},"names":{"type":"array","minItems":1,"maxItems":20,"items":{"type":"object","additionalProperties":false,"properties":{"id":{"type":"string"},"stem":{"type":"string"}},"required":["id","stem"]}}},"required":["status","names"]}"#) }
  static var habitDesign: JSONObject { parse(#"{"type":"object","additionalProperties":false,"properties":{"status":{"type":"string","enum":["ok","clarify","unsupported"]},"name":{"type":"string"},"instruction":{"type":"string"},"summary":{"type":"string"},"sample":{"type":"string"},"question":{"type":["string","null"]},"filePlan":{"anyOf":[{"type":"null"},{"type":"object","additionalProperties":false,"properties":{"operation":{"type":"string","enum":["rename","move"]},"usesContents":{"type":"boolean"},"extensions":{"type":"array","maxItems":8,"items":{"type":"string"}},"nameContains":{"type":"array","maxItems":5,"items":{"type":"string"}}},"required":["operation","extensions","nameContains","usesContents"]}]},"fileSamples":{"type":"array","maxItems":3,"items":{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string"},"content":{"type":"string"}},"required":["name","content"]}}},"required":["status","name","instruction","summary","sample","question","filePlan","fileSamples"]}"#) }
  static var products: JSONObject { parse(#"{"type":"object","additionalProperties":false,"properties":{"summary":{"type":"string"},"products":{"type":"array","maxItems":3,"items":{"type":"object","additionalProperties":false,"properties":{"name":{"type":"string"},"price":{"type":"string"},"reason":{"type":"string"},"tradeoff":{"type":"string"},"url":{"type":"string"}},"required":["name","price","reason","tradeoff","url"]}}},"required":["summary","products"]}"#) }

  /// Schema name and definition per action; nil means a plain-text answer.
  static func schema(for action: String) -> (name: String, schema: JSONObject)? {
    switch action {
    case "ask", "check_claim": nil
    case "habit_design": ("habit_design", habitDesign)
    case "rename_files": ("file_names", naming)
    case "task_plan", "event_plan": (action, commitments)
    case "reply_options": ("reply_options", replyOptions)
    case "reply", "ask_refine": (action, correction)
    case "extract_tasks": ("extract_tasks", extractTasks)
    case "key_points": ("key_points", keyPoints)
    case "rewrite": ("rewrite", correction)
    case "explain": ("explanation", correction)
    case "translate": ("translation", correction)
    default: ("correction", correction)
    }
  }
}

private extension Dictionary where Key == String, Value == Any {
  func settingIntents(_ intents: [String]) -> JSONObject {
    var value = self
    guard var properties = value["properties"] as? JSONObject, var list = properties["intents"] as? JSONObject,
          var items = list["items"] as? JSONObject else { return value }
    items["enum"] = intents; list["items"] = items; properties["intents"] = list; value["properties"] = properties
    return value
  }
}

/// Progressive previews of a partially streamed JSON answer (port of previewJSON).
enum StreamPreview {
  static func text(_ source: String, action: String) -> String {
    if ["ask", "check_claim"].contains(action) { return AskAnswer.hideCitations(source) }
    if action == "extract_tasks" { return values("action", in: source).map { "- " + $0 }.joined(separator: "\n") }
    if action == "key_points" {
      guard let open = source.range(of: #""points"\s*:\s*\["#, options: .regularExpression) else { return "" }
      let items = String(source[open.upperBound...])
      let normalized = items.replacing(/(^|,\s*)"/) { $0.output.1 + "\"point\":\"" }
      return values("point", in: normalized).map { "- " + $0 }.joined(separator: "\n")
    }
    return values("text", in: source).joined()
  }

  /// Every complete-or-partial string value of `key`, decoding only complete escapes.
  private static func values(_ key: String, in source: String) -> [String] {
    let scalars = Array(source.unicodeScalars)
    let marker = Array("\"\(key)\"".unicodeScalars)
    var results: [String] = []
    var index = 0
    while index + marker.count <= scalars.count {
      guard Array(scalars[index..<index + marker.count]) == marker else { index += 1; continue }
      var cursor = index + marker.count
      while cursor < scalars.count, scalars[cursor].properties.isWhitespace { cursor += 1 }
      guard cursor < scalars.count, scalars[cursor] == ":" else { index += 1; continue }
      cursor += 1
      while cursor < scalars.count, scalars[cursor].properties.isWhitespace { cursor += 1 }
      guard cursor < scalars.count, scalars[cursor] == "\"" else { index = cursor; continue }
      let start = cursor + 1
      var end = start, escaped = false
      while end < scalars.count {
        let char = scalars[end]
        if !escaped && char == "\"" { break }
        escaped = !escaped && char == "\\"
        end += 1
      }
      var prefix = String(String.UnicodeScalarView(scalars[start..<end]))
      while !prefix.isEmpty {
        if let data = ("\"" + prefix + "\"").data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String {
          results.append(decoded); break
        }
        prefix.removeLast()
      }
      index = end + 1
    }
    return results
  }
}

/// A web source the model consulted or cited.
struct WebCitation: Sendable, Equatable {
  let url: String
  var title: String?
  var start: Int?
  var end: Int?
}

/// Port of ask-web.ts: citation markers become numbered links, sources are listed.
enum AskAnswer {
  static func hideCitations(_ text: String) -> String {
    text.replacing(/\u{E200}cite\u{E202}[^\u{E201}]*\u{E201}/, with: "").replacing(/\u{E200}[^\u{E201}]*$/, with: "")
  }

  static func safeURL(_ raw: String) -> String? {
    guard raw.count <= 512, let url = URL(string: raw), ["http", "https"].contains(url.scheme ?? ""),
          url.host != nil, url.user == nil, url.password == nil else { return nil }
    return url.absoluteString
  }

  static func format(_ text: String, annotations: [WebCitation], consulted: [WebCitation], feeds: [String],
                     requireCitation: Bool) -> String? {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.unicodeScalars.count <= 3000 else { return nil }
    let cited = annotations.compactMap { a in safeURL(a.url).map { WebCitation(url: $0, title: a.title, start: a.start, end: a.end) } }
    let read = consulted.compactMap { a in safeURL(a.url).map { WebCitation(url: $0, title: a.title) } }
    if requireCitation && cited.isEmpty { return nil }
    var seen = Set<String>()
    let sources = (cited.isEmpty ? read : cited).filter { seen.insert($0.url).inserted }.prefix(4)
    let markdownURL = { (url: String) in url.replacing("(", with: "%28").replacing(")", with: "%29") }
    var output = text
    let scalars = Array(text.unicodeScalars)
    for annotation in cited {
      guard let index = sources.firstIndex(where: { $0.url == annotation.url }),
            let start = annotation.start, let end = annotation.end, start >= 0, end <= scalars.count, start < end else { continue }
      let token = String(String.UnicodeScalarView(scalars[start..<end]))
      guard token.hasPrefix("\u{E200}cite\u{E202}") else { continue }
      if let range = output.range(of: token) {
        output.replaceSubrange(range, with: "[\(index - sources.startIndex + 1)](\(markdownURL(annotation.url)))")
      }
    }
    output = hideCitations(output).trimmingCharacters(in: .whitespacesAndNewlines)
    if !sources.isEmpty {
      output += "\n\n" + sources.enumerated().map { offset, source in
        let host = (URL(string: source.url)?.host ?? source.url).replacing(/^www\./, with: "")
        let title = String((source.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? host)
          .prefix(80).replacing(/[\r\n]/, with: " ").replacing(/[\\\[\]]/) { "\\" + $0.output }
        return "[\(offset + 1) · \(title)](\(markdownURL(source.url)))"
      }.joined(separator: "\n")
    }
    if cited.isEmpty && !feeds.isEmpty { output += "\n\nSource: " + feeds.joined(separator: ", ") + "." }
    return output
  }
}
