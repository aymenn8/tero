"""Run real SwiftUI-App panel layout cycles on a Mac (briefly displays test panels).
Uses synthetic selection data only. --ask-focus-only keeps the window delegate
and exercises native focus; other layout fixtures isolate external focus changes.
"""
from pathlib import Path
import subprocess
import tempfile
import sys

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="tero-panel-layout-") as folder:
    temp = Path(folder)
    controller = temp / "PanelController.swift"
    controller.write_text((root / "Sources/Panel/PanelController.swift").read_text() + '\n// Test driver in a temporary copy: no production API or AX permissions needed.\nextension PanelController {\n  func presentSmokeStatus(_ status: SelectionReadout.Status) {\n    invocationPointer = CGPoint(x: 650, y: 500)\n    selection = SelectionReadout(applicationName: "UI smoke test", processIdentifier: 0, status: status)\n    if case .selected(let text) = status { state = ActionBarState(calculationAvailable: QuickCalculation.number(text) != nil) }\n    show()\n    panel?.delegate = nil // Isolate layout from external focus changes during this test.\n  }\n  var smokeVisible: Bool { panel?.isVisible == true }\n}\n')
    controller.write_text(controller.read_text() + '\nextension PanelController {\n  func smokeMakeSelectionEditable() {\n    selection?.metadata = SelectionMetadata(range: NSRange(location: 0, length: 4), controlBounds: nil, selectionBounds: nil, isEditable: true)\n    selection?.targetID = UUID()\n  }\n  func smokeReturnKey() {\n    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\\r", charactersIgnoringModifiers: "\\r", isARepeat: false, keyCode: 36)!\n    _ = handle(event)\n  }\n}\n')
    controller.write_text(controller.read_text() + '\nextension PanelController {\n  @discardableResult func smokeNavigationKey(_ code: UInt16, modifiers: NSEvent.ModifierFlags = []) -> Bool {\n    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!\n    return handle(event)\n  }\n}\n')
    controller.write_text(controller.read_text() + '\nextension PanelController {\n  func smokeType(_ text: String) {\n    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: panel?.windowNumber ?? 0, context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0)!\n    panel?.sendEvent(event)\n  }\n  func smokeSnapshot(_ name: String) {\n    guard let view = panel?.contentView, let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }\n    view.cacheDisplay(in: view.bounds, to: image)\n    try? image.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/tero-search-" + name + ".png"))\n  }\n}\n')
    controller.write_text(controller.read_text() + '\nextension PanelController {\n  func smokeUtility(_ action: Action, _ text: String) {\n    presentSmokeStatus(.selected(text))\n    state = ActionBarState(recommendations: RecommendationEngine.rank(context: RecommendationContext(selection: selection!, applicationID: nil)))\n    beginActionSearch(query: action.title)\n    choose(action)\n  }\n}\n')
    # Intercept only transform paste dispatch in the temporary test controller.
    # This verifies routing without sending any key event to a real source app.
    controller.write_text(controller.read_text().replace(
        '  private(set) var state = ActionBarState()',
        '  var smokePasteAttempts: [String] = []\n  private(set) var state = ActionBarState()'
    ).replace('self.pasteCalculation(corrected)', 'self.smokePasteAttempts.append(corrected)'))
    # Exercise the production cancellation path with a delayed synthetic provider.
    original = controller.read_text()
    call = 'try await CorrectionClient().correct(text, requestID: id, credential: credential)'
    assert call in original and 'await GatewayAccess.credential()' in original
    original = original.replace(call, 'try await self.smokeCorrect(text)')
    original = original.replace('await GatewayAccess.credential()', 'Optional("smoke-credential")').replace('guard let credential = Optional', 'guard let _ = Optional')
    original += '\nextension PanelController {\n  func smokeCorrect(_ text: String) async throws -> String {\n    try? await Task.sleep(for: .milliseconds(350))\n    return text == "unchanged" ? text : "Corrected"\n  }\n}\n'
    original = original.replace('try await CorrectionClient().explain(text, language: language, requestID: id, credential: credential)', 'try await self.smokeCorrect(text)')
    original = original.replace('let language = ResponseLanguage.load()', '_ = ResponseLanguage.load()')
    original = original.replace('try await CorrectionClient().translate(text, language: translation, requestID: id, credential: credential)', 'try await self.smokeCorrect(text)')
    original = original.replace('if let translation {', 'if translation != nil {')
    original = original.replace('try await CorrectionClient().transform(text, action: gatewayAction, style: style, requestID: id, credential: credential)', 'try await self.smokeCorrect(text)')
    original = original.replace('try await CorrectionClient().rewrite(text, requestID: id, credential: credential)', 'try await self.smokeCorrect(text)')
    original = original.replace('try await CorrectionClient().keyPoints(text, requestID: id, credential: credential)', 'try await self.smokeCorrect(text) + \"\\n- Second idea\"')
    original = original.replace('try await CorrectionClient().extractTasks(text, requestID: id, credential: credential)', '(text == \"No pending tasks fixture\" ? \"No tasks found.\" : try await self.smokeCorrect(text) + \"\\n- Check the links\")')
    original = original.replace('try await CorrectionClient().replyOptions(text, context: context, requestID: id, credential: credential)', 'try await self.smokeReplyOptions(text, context: context)')
    original = original.replace('try await CorrectionClient().reply(text, context: context, intent: replyIntent, requestID: id, credential: credential)', 'try await self.smokeReply(text, context: context, intent: replyIntent)')
    original = original.replace('  var smokePasteAttempts: [String] = []', '  var smokeReplyRequests: [(String, ReplyContext?, ReplyIntent?)] = []\n  var smokePasteAttempts: [String] = []')
    original += '\nextension PanelController {\n  func smokeSetReplyContext() {\n    var context = InvocationContext(capturedAt: .now, applicationID: "test.chat")\n    context.capture = .observed\n    context.applicationName = "Test chat"\n    context.nearbyText = "Synthetic nearby context"\n    invocationContext = context\n  }\n  func smokeReplyOptions(_ text: String, context: ReplyContext?) async throws -> [ReplyIntent] {\n    smokeReplyRequests.append((text, context, nil))\n    try? await Task.sleep(for: .milliseconds(350))\n    if text == "Not a message" { throw CorrectionClient.Failure.notMessage }\n    return [.accept, .decline, .alternative]\n  }\n  func smokeReply(_ text: String, context: ReplyContext?, intent: ReplyIntent) async throws -> String {\n    smokeReplyRequests.append((text, context, intent))\n    try? await Task.sleep(for: .milliseconds(350))\n    return "Reply: " + intent.rawValue\n  }\n}\n'
    original = original.replace('try await CorrectionClient().reading(', 'try await self.smokeReading(')
    original = original.replace('try await CorrectionClient().refinePrompt(original, requestID: id, credential: credential)',
      'try await PanelController.smokeRefine(original)')
    original += '''
extension PanelController {
  static func smokeRefine(_ text: String) async throws -> String {
    // Intentionally finishes after cancellation to exercise the stale-result guard.
    try? await Task.sleep(for: .milliseconds(400))
    if text == "Error fixture" { throw CorrectionClient.Failure.network }
    return "Refined: " + text
  }
}
'''
    original = original.replace('credential: credential', 'credential: "fixture"')
    original += '\nextension PanelController {\n  func smokeReadingResult(_ text: String) { askMode = true; askVisible = false; askQuestionPreview = "Synthetic question"; showExplanation(text) }\n  var smokeFrame: NSRect? { panel?.frame }\n  var smokeClipboardPreparedContext: InvocationContext? { clipboardPrepared?.context }\n  func smokeIsolate() { panel?.delegate = nil }\n  func smokeReading(_ text: String, action: String, language: ResponseLanguage? = nil, context: ReplyContext? = nil, intent: ReplyIntent? = nil, requestID: UUID, credential: String, update: @escaping @MainActor @Sendable (String) -> Void, file: FileSummaryInput? = nil, style: TextStyle? = nil, refinement: String? = nil) async throws -> String {\n    try await Task.sleep(for: .milliseconds(300))\n    update("Partial fixture")\n    try await Task.sleep(for: .milliseconds(500))\n    if text == "Stream error fixture" { throw CorrectionClient.Failure.invalid }\n    if action == "result_refine" { return "Revised: " + (refinement ?? "") }\n    if action == "reply", let intent { return try await smokeReply(text, context: context, intent: intent) }\n    if action == "extract_tasks" { return text == "No pending tasks fixture" ? "No tasks found." : "Corrected\\n- Check the links" }\n    if action == "key_points" { return "Corrected\\n- Second idea" }\n    return action == "ask" || action == "explain" || action == "summarize_file" ? "Complete fixture [OpenAI](https://openai.com)" : "Corrected"\n  }\n}\n'
    original += '''
extension PanelController {
  func smokeCapturedEmptyHome() {
    selection = SelectionReadout(applicationName: "Focus fixture", processIdentifier: 0, status: .noSelection)
    homeVisible = selection?.opensHome == true
    panel?.delegate = self
    show()
  }
}
'''
    original = original.replace('  var smokePasteAttempts: [String] = []',
      '  var smokeOpenedLinks: [URL] = []\n  var smokePasteAttempts: [String] = []')
    original = original.replace('readingCardKeepsOpen = true\n    NSWorkspace.shared.open(url)',
      'readingCardKeepsOpen = true\n    smokeOpenedLinks.append(url)')
    original += '''
extension PanelController {
  func smokeRestoreWindowDelegate() { panel?.delegate = self }
  func smokeMakeKey() { panel?.makeKeyAndOrderFront(nil) }
  func smokeFitReading(_ text: String) { explanationText = text; resizeReadingCard(text) }
}
'''
    if "--file-summary-only" in sys.argv:
        original = original.replace('try await reader.validates(fileContext),\n                fileContext.fileOrigin != .finder || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"', 'true')
    plan_call = 'try await CorrectionClient().plan(text, destination: destination, context: ReplyContext(self?.invocationContext), requestID: id, credential: "fixture")'
    assert plan_call in original
    original = original.replace(plan_call, 'try await PanelController.smokePlan(text, destination: destination)')
    original = original.replace('CommitmentSession(drafts, destination: destination)', 'CommitmentSession(drafts, destination: destination, connection: SmokePlanningConnection())')
    original += """
extension PanelController {
  var smokeCommitmentError: String? { correctionMessage }
  func smokeReviewSession(_ value: CommitmentSession) { commitmentSession = value; updateCommitmentPresentation() }
  static func smokePlan(_ text: String, destination: CommitmentDestination) async throws -> [CommitmentDraft] {
    try await Task.sleep(for: .milliseconds(600))
    if text == "No pending work." { return [] }
    return [.init(kind: destination.kind, title: "Call", owner: nil, deadline: "tomorrow", condition: nil,
      evidence: text, date: "2026-10-07", time: destination == .calendar ? "15:00" : nil,
      endDate: destination == .calendar ? "2026-10-07" : nil, endTime: destination == .calendar ? "15:30" : nil)]
  }
}
"""
    if "--reinvoke-only" in sys.argv:
        start = original.index("  private func captureAndShow() {")
        end = original.index("  private func rankInvocation(", start)
        original = original[:start] + "  private func captureAndShow() { smokeRecaptures += 1 }\n\n" + original[end:]
        original = original.replace('let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier', 'let frontPID = smokeFrontPID', 1)
    original = original.replace('  private(set) var state = ActionBarState()', '  var smokeFrontPID: Int32? = ProcessInfo.processInfo.processIdentifier\n  var smokeRecaptures = 0\n  private(set) var state = ActionBarState()', 1)
    original += """
extension PanelController {
  func smokeOldSource() { sourceApplication = NSRunningApplication.current }
  func smokeReleaseKey() { panel?.resignKey() }
}
"""
    # Exercise the real non-key opening surface with a delayed synthetic ranking provider.
    ranking_call = 'try await RankingClient(deadline: remaining).rank(context: observations, candidates: candidates, personalActions: personalActions, credential: "fixture", debug: inspect, requestID: requestID)'
    assert ranking_call in original, 'Ranking provider interception must match'
    original = original.replace(ranking_call, 'try await self.smokeRanking(candidates)')
    original += """
extension PanelController {
  var smokeOpeningIsKey: Bool { panel?.isKeyWindow == true }
  func smokeBeginOpening(_ text: String = "synthetic selection") {
    selection = SelectionReadout(applicationName: "Opening fixture", processIdentifier: 0, status: .selected(text))
    invocationPointer = CGPoint(x: 650, y: 500)
    let context = RecommendationContext(selection: selection!, applicationID: "fixture")
    let id = UUID(); captureID = id
    captureTask = Task { [weak self] in
      guard let self else { return }
      let recommendations = await self.rankInvocation(context)
      guard !Task.isCancelled, self.captureID == id else { return }
      self.captureID = nil; self.captureTask = nil
      self.state = ActionBarState(recommendations: recommendations)
      self.show()
    }
  }
  func smokeRanking(_ ids: [String]) async throws -> RankingClient.Response {
    if selection?.status == .selected("offline") { throw RankingClient.Failure.unavailable }
    try await Task.sleep(for: .milliseconds(600))
    return .init(requestID: UUID(), model: "jev-1.13.0", scores: ids.map { id in
      .init(id: id, score: id == "reply" ? 3 : id == "createEvent" ? 2.8 : id == "fix" ? 2.5 : 0.1, confidence: 0.9)
    }, usage: .init(inputTokens: 300, outputTokens: 10, estimatedCostUSD: 0.0000126), promptVersion: 2, debug: nil, latencyMs: 600)
  }
}
"""
    if "--opening-only" in sys.argv:
        # The opening fixture exercises delayed ranking without a real account,
        # credentials, quota cache or telemetry initialization.
        original = original.replace('guard accountID != nil else { return local }', '')
        original = original.replace('guard let credential = await GatewayAccess.credential(), AccountStore.shared.user?.id == accountID else { return local }', 'let credential = "fixture"')
        original = original.replace('defer { GatewayAccess.didRequest() }', '')
        original = original.replace('guard AccountStore.shared.user?.id == accountID, let accountID else { return local }', 'let accountID = UUID()')
    if "--icons-only" in sys.argv or "--opening-only" in sys.argv:
        import re
        original = re.sub(r'GatewayAccess\.event\([^\n]*?\)', '()', original)
    if "--unified-ask-only" in sys.argv:
        import re
        original = re.sub(r'GatewayAccess\.event\([^\n]*?\)', '()', original)
        original = original.replace('defer { GatewayAccess.didRequest() }', '')
        original = original.replace('try await RankingClient().rank(context: context,\n            candidates: ShoppingRequest.routingCandidates, credential: "fixture")',
                                    'try await self.smokeAskRanking(question)')
        assert 'try await RankingClient().rank(context: context,' not in original
        original += """
extension PanelController {
  func smokeAskRanking(_ question: String) async throws -> RankingClient.Response {
    try? await Task.sleep(for: .milliseconds(250))
    if question == "Offline question" { throw RankingClient.Failure.unavailable }
    return .init(requestID: UUID(), model: "jev-fixture", scores: [
      .init(id: "shop", score: question == "Product request" ? 2.8 : 0.2, confidence: 0.9),
      .init(id: "explain", score: question == "Product request" ? 0.2 : 2.8, confidence: 0.9)
    ], usage: .init(inputTokens: 0, outputTokens: 0, estimatedCostUSD: 0), promptVersion: 1, debug: nil, latencyMs: 250)
  }
}
"""
    controller.write_text(original)
    if "--utilities-only" in sys.argv:
        original = original.replace('opened: { [weak self] in self?.closeExplanation() })',
          'opened: { [weak self] in self?.closeExplanation() }, services: SmokeUtilityServices())')
        controller.write_text(original)
    sources = [*sorted((root / "Sources/Shop").glob("*.swift")), *sorted((root / "Sources/AI").glob("*.swift")), *sorted((root / "Sources/Core").glob("*.swift")),
               *sorted((root / "Sources/UI").glob("*.swift")), *sorted((root / "Sources/Planning").glob("*.swift")), *sorted((root / "Sources/Utilities").glob("*.swift")),
               *sorted((root / "Sources/Habits").glob("*.swift")),
               *sorted((root / "Sources/Auth").glob("*.swift")),
               *sorted((root / "Sources/Clipboard").glob("*.swift")),
               root / "Sources/Settings/SettingsComponents.swift",
               root / "Sources/Panel/TeroPanel.swift",
               *sorted((root / "Sources/Selection").glob("*.swift")),
               controller, root / "Scripts/PanelLayoutSmoke.swift"]
    sources = [p for p in sources if not p.stem.endswith(" 2") and p.name not in ["TeroSettingsView.swift", "HabitsWindowController.swift", "AccountView.swift"]]
    if "--unified-ask-only" in sys.argv:
        session_path = root / "Sources/Shop/ShoppingSession.swift"
        session_copy = temp / "ShoppingSession.swift"
        session_copy.write_text(session_path.read_text().replace('await GatewayAccess.credential()', 'Optional("fixture")')
          .replace('try await CorrectionClient().shop(input, requestID: id, credential: credential)',
                   'ShoppingResult(requestID: id, summary: "Synthetic products", products: [ShoppingProduct(name: "Quiet keyboard", price: "80 EUR", reason: "Quiet switches", tradeoff: "Wired", url: "https://example.com/keyboard", imageURL: nil)])'))
        sources = [session_copy if path == session_path else path for path in sources]
    binary = temp / "panel-layout-smoke"
    if "--files-only" in sys.argv:
        session_path = root / "Sources/UI/FileWorkflowSession.swift"
        session_copy = temp / "FileWorkflowSession.swift"
        fixture_session = session_path.read_text().replace('try await FinderSelectionReader().validates(context)', 'true')
        fixture_session = fixture_session.replace('guard let credential = GatewayCredential.read() else { throw CorrectionClient.Failure.unavailable }\n        let proposed = try await CorrectionClient().renameFiles(inputs, requestID: UUID(), credential: credential)',
          'try await Task.sleep(for: .milliseconds(120))\n        let proposed = inputs.enumerated().map { $0.offset == 0 ? "Orion Invoice" : "Orion Launch Notes" }')
        session_copy.write_text(fixture_session)
        sources = [session_copy if path == session_path else path for path in sources]
    controller.write_text(controller.read_text() + '''
extension PanelController {
  func smokeFileSelection(_ context: InvocationContext) {
    homeVisible = false
    invocationContext = context
    fileContext = context
    state = ActionBarState(recommendations: RecommendationEngine.rank(context: .init(fileContext: context)))
    show()
    panel?.delegate = nil
  }
}
''')
    # Compile a stable local snapshot: iCloud hydration can change source metadata
    # while Swift reads the project, even when no developer edits are made.
    import shutil
    stable_sources = []
    for index, source in enumerate(sources):
        target = temp / "sources" / str(index) / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(source.read_text().replace("NSPasteboard.general", 'NSPasteboard(name: NSPasteboard.Name("tero.inline-refinement.fixture"))'))
        stable_sources.append(target)
    sources = stable_sources
    subprocess.run(["swiftc", "-swift-version", "6", "-parse-as-library", "-whole-module-optimization",
                    "-module-cache-path", "/tmp/tero-layout-swift-cache",
                    *map(str, sources), "-o", str(binary)], check=True)
    if "--keep-binary" in sys.argv:
        import shutil
        shutil.copyfile(binary, "/tmp/tero-hints-fixture")
        Path("/tmp/tero-hints-fixture").chmod(0o700)
    flags = [flag for flag in ["--unified-ask-only", "--icons-only", "--result-refinement-only", "--opening-only", "--clipboard-menu-only", "--clipboard-only", "--files-only", "--brand-only", "--utilities-only", "--text-messages-only", "--reinvoke-only", "--commitments-only", "--file-summary-only", "--translation-options-only", "--actions-only", "--extract-tasks-only", "--search-only", "--search-navigation-only", "--reply-only", "--reading-only", "--ask-focus-only", "--ask-refine-only"] if flag in sys.argv]
    for flag in flags or [None]:
        subprocess.run([str(binary), *([flag] if flag else [])], check=True, timeout=45)
