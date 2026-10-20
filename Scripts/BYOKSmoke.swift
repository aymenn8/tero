import Foundation
import CoreText

// Synthetic bring-your-own-key checks against Scripts/byok_mock_provider.py.
// No real provider, key or user content is involved.
@MainActor enum GatewayAccess {
  static var usesOwnKey: Bool { AIConfiguration.active != nil }
  static func credential() async -> String? { usesOwnKey ? CorrectionClient.ownKeyCredential : nil }
  static func didRequest() {}
}

@main struct BYOKSmoke {
  static func main() async {
    let port = CommandLine.arguments[1]
    let base = URL(string: "http://127.0.0.1:\(port)/v1")!
    var failures = 0
    func check(_ condition: Bool, _ label: String) {
      print((condition ? "PASS " : "FAIL ") + label)
      if !condition { failures += 1 }
    }
    func body(_ action: String, _ selection: String = "Thsi is a tset.", _ extra: [String: Any] = [:]) -> Data {
      var value: [String: Any] = ["requestID": UUID().uuidString, "action": action, "selection": selection]
      value.merge(extra) { _, new in new }
      return try! JSONSerialization.data(withJSONObject: value)
    }
    func decode(_ data: Data) -> [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }

    for provider in [AIProvider.openAI, .anthropic, .openRouter, .xAI, .ollama] {
      let gateway = LocalGateway(configuration: AIConfiguration(provider: provider, baseURL: base, model: "mock-small", key: "sk-test"))
      let name = provider.title
      do {
        let fix = decode(try await gateway.respond(body("fix")))
        check(fix["text"] as? String == "This is a quick test.", "\(name): fix")
        let points = decode(try await gateway.respond(body("key_points")))
        check(points["text"] as? String == "- First idea\n- Second idea", "\(name): key points")
        let tasks = decode(try await gateway.respond(body("extract_tasks", "Send the report by Friday.")))
        check(tasks["text"] as? String == "- Send the report — Friday", "\(name): extract tasks")
        let intents = decode(try await gateway.respond(body("reply_options", "Can you join on Monday?")))
        check(intents["intents"] as? [String] == ["accept", "decline", "clarify"], "\(name): reply options")
        let plan = decode(try await gateway.respond(body("task_plan", "Nothing planned.",
          ["planningReference": ["localDate": "2026-10-19", "timeZone": "Europe/Paris"]])))
        check((plan["items"] as? [Any])?.isEmpty == true, "\(name): task plan")
        let names = decode(try await gateway.respond(body("rename_files", "Propose filenames.",
          ["files": [["id": "file-0", "text": "Invoice for Orion"]]])))
        check(((names["names"] as? [[String: Any]])?.first?["stem"] as? String) == "orion-invoice", "\(name): rename files")
        let translate = decode(try await gateway.respond(body("translate", "Bonjour", ["targetLanguage": "en"])))
        check(translate["text"] as? String == "This is a quick test.", "\(name): translate")
        var previews: [String] = []
        let streamed = try await gateway.stream(body("explain", "A sentence.", ["stream": true, "responseLanguage": "en"])) { previews.append($0) }
        check(streamed == "This is a quick test." && !previews.isEmpty, "\(name): streamed explain with \(previews.count) previews")
        if provider.supportsWebSearch {
          let ask = try await gateway.stream(body("ask", "Which quiet keyboard?", ["stream": true])) { _ in }
          check(ask.contains("example-shop.com"), "\(name): ask cites its web source")
          let claim = decode(try await gateway.respond(body("check_claim", "The sky is green.", ["replyContext": NSNull()])))
          check((claim["text"] as? String)?.contains("[1 · ") == true, "\(name): check claim requires citations")
          let shop = decode(try await gateway.shop(body("ask", #"{"request":"quiet keyboard","preferences":"","locale":"en"}"#)))
          check(((shop["products"] as? [[String: Any]])?.first?["url"] as? String) == "https://www.example-shop.com/keyboard", "\(name): verified product")
        } else {
          do { _ = try await gateway.respond(body("check_claim", "The sky is green.")); check(false, "\(name): claim refused without web") }
          catch { check((error as? CorrectionClient.Failure) == .needsWebSearch, "\(name): claim refused without web") }
          let ask = try await gateway.stream(body("ask", "What is Swift?", ["stream": true])) { _ in }
          check(!ask.isEmpty, "\(name): offline ask")
        }
      } catch { check(false, "\(name): unexpected \(error)") }
      let models = try? await AIProviderClient(configuration: AIConfiguration(provider: provider, baseURL: base, model: "x", key: "sk-test")).models()
      check(models == ["mock-large", "mock-small"], "\(name): model list")
    }

    // Providers without PDF input receive the document's text layer; OpenAI receives the file itself.
    let pdf = NSMutableData(); var box = CGRect(x: 0, y: 0, width: 300, height: 200)
    let writer = CGContext(consumer: CGDataConsumer(data: pdf)!, mediaBox: &box, nil)!
    writer.beginPDFPage(nil)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "Orion invoice total 80 EUR",
      attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, 14, nil)]))
    writer.textPosition = CGPoint(x: 20, y: 100); CTLineDraw(line, writer)
    writer.endPDFPage(); writer.closePDF()
    let file: [String: Any] = ["mime": "application/pdf", "data": (pdf as Data).base64EncodedString()]
    for provider in [AIProvider.xAI, .openAI] {
      let gateway = LocalGateway(configuration: AIConfiguration(provider: provider, baseURL: base, model: "mock-small", key: "sk-test"))
      let summary = try? await gateway.stream(body("summarize_file", "Summarize the selected file.", ["stream": true, "file": file, "responseLanguage": "en"])) { _ in }
      check(summary == "This is a quick test.", "\(provider.title): summarize PDF")
    }

    // Strict schema rejected → JSON mode, and Markdown fences are tolerated.
    let fallback = LocalGateway(configuration: AIConfiguration(provider: .deepSeek, baseURL: base, model: "no-schema", key: "sk-test"))
    let recovered = decode((try? await fallback.respond(body("fix"))) ?? Data())
    check(recovered["text"] as? String == "This is a quick test.", "Compatible: schema fallback and fenced JSON")

    // Rejected key surfaces a precise error.
    do {
      _ = try await LocalGateway(configuration: AIConfiguration(provider: .openAI, baseURL: base, model: "m", key: "bad-key")).respond(body("fix"))
      check(false, "Rejected key")
    } catch { check((error as? CorrectionClient.Failure) == .providerRejected, "Rejected key") }

    // CorrectionClient routes through the person's own provider when one is active.
    UserDefaults.standard.set(AIProvider.ollama.rawValue, forKey: AIConfiguration.Keys.provider)
    UserDefaults.standard.set(base.absoluteString, forKey: AIConfiguration.Keys.baseURL(.ollama))
    UserDefaults.standard.set("mock-small", forKey: AIConfiguration.Keys.model(.ollama))
    defer { [AIConfiguration.Keys.provider, AIConfiguration.Keys.baseURL(.ollama), AIConfiguration.Keys.model(.ollama)].forEach(UserDefaults.standard.removeObject) }
    let credential = await GatewayAccess.credential()
    check(credential == CorrectionClient.ownKeyCredential, "Own key credential")
    let corrected = try? await CorrectionClient().correct("Thsi is a tset.", requestID: UUID(), credential: credential ?? "")
    check(corrected == "This is a quick test.", "CorrectionClient routes to own provider")

    print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
    exit(failures == 0 ? 0 : 1)
  }
}
