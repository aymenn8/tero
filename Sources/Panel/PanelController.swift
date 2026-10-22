import AppKit
// The C API exposes its immutable prompt key as a mutable global declaration.
@preconcurrency import ApplicationServices
import Observation
import SwiftUI

@MainActor @Observable
final class PanelController: NSObject, NSWindowDelegate {
  private(set) var rankingTrace: String? {
    didSet { onContextChange?(invocationContext, selection) }
  }
  func clearRankingTrace() { rankingTrace = nil }
  private(set) var rankingDiagnostic = "Local" {
    didSet { onContextChange?(invocationContext, selection) }
  }
  private(set) var state = ActionBarState()
  private(set) var invocationOpening = false
  private(set) var appeared = false
  private(set) var closing = false
  private(set) var activeShortcut: String?
  @ObservationIgnored private var feedbackTask: Task<Void, Never>?
  @ObservationIgnored private var closingTask: Task<Void, Never>?
  private(set) var isPasting = false
  private(set) var pasteMessage: String?
  private(set) var calculatorValue: Decimal?
  var clipboardStore: ClipboardStore?
  private(set) var clipboardVisible = false
  private(set) var clipboardPresented = false
  private(set) var clipboardClosing = false
  private(set) var clipboardActionEntryID: UUID?
  var clipboardPinnedOnly = false
  private(set) var clipboardActionMenuPresented = false
  var clipboardModeQuery = ""
  var clipboardModeSelectedID: String?
  private(set) var clipboardModeActions: [Action] = []
  @ObservationIgnored private var clipboardPrepared: (entryID: UUID, readout: SelectionReadout, context: InvocationContext, recommendations: [ActionRecommendation], workspace: URL?)?
  var clipboardModeStep: ModeChoiceStep {
    let choices = ActionSearch.results(for: clipboardModeQuery, candidates: clipboardModeActions).map {
      ModeChoice(id: $0.rawValue, title: $0.title, label: $0.accessibilityLabel, iconName: $0.iconName)
    }
    return ModeChoiceStep(label: "Clipboard actions", choices: choices, selectedID: clipboardModeSelectedID, backLabel: "Close actions · Escape")
  }
  func searchClipboardModes(_ query: String) {
    clipboardModeQuery = query
    clipboardModeSelectedID = clipboardModeStep.choices.first?.id
  }
  func closeClipboardEntryMenu() {
    clipboardActionMenuPresented = false
    if let workspace = clipboardPrepared?.workspace { try? FileManager.default.removeItem(at: workspace) }
    clipboardPrepared = nil
    clipboardModeActions = []
  }
  func chooseClipboardMode(_ id: String?) {
    guard let id, let action = Action(rawValue: id) else { closeClipboardEntryMenu(); return }
    guard let prepared = clipboardPrepared, prepared.entryID == selectedClipboardEntry?.id,
          clipboardModeActions.contains(action) else { closeClipboardEntryMenu(); return }
    clipboardPrepared = nil; clipboardActionMenuPresented = false
    clipboardWorkspace = prepared.workspace
    animateClipboardExit { [weak self] in
      guard let self else { return }
      let oldTarget = self.selection?.targetID
      Task { [selectionEngine = self.selectionEngine] in await selectionEngine.clearTarget(oldTarget) }
      self.clipboardVisible = false; self.clipboardPresented = false
      self.clipboardStore?.browsing = false
      self.clipboardActionEntryID = prepared.entryID
      self.sourceApplication = nil; self.selection = prepared.readout; self.invocationContext = prepared.context
      self.homeVisible = false
      self.fileContext = prepared.context.files.isEmpty ? nil : prepared.context
      self.state = ActionBarState(recommendations: prepared.recommendations)
      self.show()
      self.beginActionSearch(query: action.title)
      self.choose(action)
    }
  }
  @ObservationIgnored private var clipboardTransition: Task<Void, Never>?
  @ObservationIgnored private var clipboardWorkspace: URL?
  private(set) var clipboardDragging = false
  var clipboardFilter: ClipboardKind?
  var clipboardQuery = ""
  var clipboardSelectedID: UUID?
  private(set) var clipboardMessage: String?
  var clipboardEntries: [ClipboardEntry] {
    (clipboardStore?.history.entries ?? []).filter {
      (clipboardFilter == nil || $0.kind == clipboardFilter) && (!clipboardPinnedOnly || $0.isPinned) && $0.matches(clipboardQuery)
    }
  }
  var selectedClipboardEntry: ClipboardEntry? { clipboardEntries.first { $0.id == clipboardSelectedID } }
  var clipboardCanPaste: Bool { selection?.canInsertClipboard == true && selectedClipboardEntry != nil }
  private(set) var homeVisible = false
  private(set) var shoppingSession: ShoppingSession?
  private(set) var askVisible = false
  private(set) var askMode = false
  private(set) var askQuestionPreview: String?
  /// Set while the Ask composer is about the captured selection rather than a standalone question.
  private(set) var selectionAskMode: SelectionAskMode?
  var selectionAskPreview: String? {
    guard case .selected(let text) = selection?.status else { return nil }
    return String(text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(160))
  }
  var askQuery = "" {
    didSet {
      guard askQuery != oldValue else { return }
      askEditorHeight = Self.askEditorHeight(for: askQuery)
      resizeAskEditor()
    }
  }
  /// Cached on every `askQuery` change: views read it several times per render, and
  /// measuring rebuilds a whole TextKit stack.
  private(set) var askEditorHeight: CGFloat = PanelController.askEditorHeight(for: "")
  private var askPanelSize: CGSize {
    CGSize(width: AskInputView.width + 2 * PanelPlacement.contentInset,
           height: askEditorHeight + AskInputView.verticalChrome + (selectionAskMode == nil ? 0 : AskInputView.selectionChrome)
             + 2 * PanelPlacement.contentInset)
  }
  private static func shoppingPanelSize(_ session: ShoppingSession) -> CGSize {
    CGSize(width: 440 + 2 * PanelPlacement.contentInset, height: session.height + 2 * PanelPlacement.contentInset)
  }
  private var actionRowPanelWidth: CGFloat {
    max(440, presentedRowWidth + 2 * PanelPlacement.contentInset + (clipboardActionEntryID == nil ? 0 : 36))
  }
  private static func askEditorHeight(for query: String) -> CGFloat {
    let storage = NSTextStorage(string: query + "\u{200B}", attributes: [.font: NSFont.systemFont(ofSize: 14)])
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: 332, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    layout.ensureLayout(for: container)
    // Include the insertion line after a trailing newline; cap the viewport at six lines.
    return min(110, max(22, ceil(layout.usedRect(for: container).height) + 2))
  }
  private(set) var askRouting = false
  private(set) var askRefining = false
  private(set) var askRefineError: String?
  @ObservationIgnored private var askRefineTask: Task<Void, Never>?
  @ObservationIgnored private var askRefineID: UUID?
  @ObservationIgnored private var askPromptRevision: (original: String, refined: String)?
  private(set) var readingInProgress = false
  private(set) var readingError: String?
  var homeSelectedIndex = 0
  var homeRowWidth: CGFloat {
    30 + CGFloat(homeActions.count) * ActionBubble.spacing + homeActions.reduce(CGFloat.zero) {
      $0 + ActionBubble.width(title: $1.title, leadingSymbol: $1.iconName)
    }
  }
  var homeActions: [HomeAction] { [.ask, .clipboard, .createHabit] }
  @ObservationIgnored var onHomeAction: ((HomeAction) -> Void)?
  @ObservationIgnored var onContextChange: ((InvocationContext?, SelectionReadout?) -> Void)?
  private(set) var invocationContext: InvocationContext? {
    didSet { if invocationContext == nil { rankingTrace = nil }; onContextChange?(invocationContext, selection) }
  }
  private(set) var selection: SelectionReadout?
  private(set) var correctionFinished = false
  private(set) var choosingTranslationLanguage = false
  private(set) var translationTarget = ResponseLanguage.english
  private(set) var translationBackSelected = false
  private var translationPage = 0
  private var translationChoiceQuery = ""
  private var translationMoreSelected = false
  private(set) var choosingTextOptions = false
  private var selectedTextOption: String?
  private(set) var refiningResult = false
  var readingTitle: String { textHabitTitle ?? (askMode ? "Ask" : state.executing == .translate ? "Translation · \(translationTarget.title)" : (state.executing?.title ?? "Result")) }
  private var resultBeforeRefinement: String?
  var canRestoreResult: Bool { readingError != nil && resultBeforeRefinement != nil }
  private var resultWasAsk = false
  private var previousQuestionPreview: String?
  private(set) var fileWorkflow: FileWorkflowSession?
  private(set) var videoDownload: VideoDownloadSession?
  /// Files captured for this invocation (Finder or a clipboard entry); file actions read them.
  private(set) var fileContext: InvocationContext?
  private(set) var replyIntents: [ReplyIntent] = []
  private(set) var replyIntentIndex = 0
  private(set) var replyDrafting = false
  @ObservationIgnored private var replyContext: ReplyContext?
  private(set) var utilitySession: SelectionUtilitySession?
  private(set) var commitmentSession: CommitmentSession?
  private(set) var explanationText: String?
  @ObservationIgnored private var readingCardKeepsOpen = false
  private(set) var explanationContentHeight: CGFloat = 80
  private(set) var correctionText: String?
  private(set) var allowanceReached = false
  private(set) var signInRequired = false
  private(set) var correctionMessage: String?
  private(set) var textHabitTitle: String?
  private var actionRecommendations: [ActionRecommendation] = []
  private(set) var actionSelection = 0
  private(set) var actionPage = 0
  var presentedActions: [ActionRecommendation.Target] {
    let recommendations = actionRecommendations.isEmpty
      ? state.suggestions.map { ActionRecommendation(target: .native($0), priority: 0, reason: .generalText) }
      : actionRecommendations
    if state.isSearching {
      return ActionSearch.results(for: state.searchQuery, recommendations: recommendations, habits: TextHabitStore.shared.habits)
    }
    return ActionRecommendationPages.targets(recommendations, page: actionPage)
  }
  private func changeActionPage(by offset: Int) {
    actionPage = max(0, actionPage + offset)
    actionSelection = 1
    resizeActionRow()
  }
  func title(for target: ActionRecommendation.Target) -> String {
    switch target {
    case .native(let action): action.title
    case .habit(let id): TextHabitStore.shared.habits.first { $0.id == id }?.name ?? "Personal action"
    }
  }
  func icon(for target: ActionRecommendation.Target) -> String? {
    switch target {
    case .native(let action): action.isNavigationIcon ? nil : action.iconName
    case .habit(let id): TextHabitStore.shared.habits.first { $0.id == id }?.resolvedIconName ?? "sparkles"
    }
  }
  var presentedRowWidth: CGFloat {
    CGFloat(30) + ActionBubble.spacing * CGFloat(presentedActions.count)
      + presentedActions.reduce(CGFloat.zero) { $0 + (icon(for: $1) == nil ? 30 : ActionBubble.width(title: title(for: $1), leadingSymbol: icon(for: $1))) }
  }
  func choosePresented(_ target: ActionRecommendation.Target) {
    guard state.executing == nil else { return }
    actionSelection = presentedActions.firstIndex(of: target) ?? 0
    switch target {
    case .native(.search): beginActionSearch()
    case .native(.more): changeActionPage(by: 1)
    case .native(.back): changeActionPage(by: -1)
    case .native(.allActions): dismiss(restoreFocus: false); onHomeAction?(.habits)
    case .native(let action):
      guard selection?.hasSelection == true || fileContext != nil else { return }
      state.selectRecommended(action)
      guard state.selected == action else { return }
      activate()
    case .habit(let id):
      TextHabitStore.shared.refreshOwner()
      guard let habit = TextHabitStore.shared.habits.first(where: { $0.id == id && $0.enabled }) else { return }
      if let plan = habit.filePlan {
        guard let context = fileContext, plan.accepts(context.files) else { return }
        let kind: FileWorkflowKind = plan.operation == .move ? .move : context.files.count == 1 ? .rename : .batchRename
        fileWorkflow = FileWorkflowSession(kind: kind, context: context,
          back: { [weak self] in self?.backFromFileWorkflow() },
          changed: { [weak self] in self?.updateFileWorkflowPresentation() },
          habit: habit)
        if plan.operation == .rename { fileWorkflow?.suggestName() }
        updateFileWorkflowPresentation(); return
      }
      guard case .selected(let text) = selection?.status else { return }
      if !aiAllowanceAvailable { showAllowanceReached(); return }
      state.hasTextHabits = true; state.beginTextHabit(); textHabitTitle = habit.name
      resizeActionRow(); panel?.makeFirstResponder(nil)
      startCorrection(text, habit: habit)
    }
  }
  @ObservationIgnored private var correctionID: UUID?
  @ObservationIgnored private var correctionTask: Task<Void, Never>?
  @ObservationIgnored private var panel: TeroPanel?
  @ObservationIgnored private var sourceApplication: NSRunningApplication?
  @ObservationIgnored private var pasteTask: Task<Void, Never>?
  @ObservationIgnored private var execution: Task<Void, Never>?
  @ObservationIgnored private let selectionEngine = SelectionEngine()
  @ObservationIgnored private let fileContextReader = FinderSelectionReader()
  @ObservationIgnored private var rankingMemo = RankingMemo()
  @ObservationIgnored private var captureTask: Task<Void, Never>?
  @ObservationIgnored private var captureID: UUID?
  @ObservationIgnored private var noticeDismissal: Task<Void, Never>?
  @ObservationIgnored private var invocationPointer = CGPoint.zero

  func prepareSelectionSource(processIdentifier: Int32) {
    Task { [selectionEngine] in
      await selectionEngine.prepareAccessibility(processIdentifier: processIdentifier)
    }
  }

  func toggle() {
    if clipboardClosing || clipboardDragging { return }
    if clipboardVisible { closeClipboardWindow(); return }
    if isPasting {
      dismiss(restoreFocus: false)
      return
    }
    if captureID != nil {
      cancelCapture()
      return
    }
    if let panel, panel.isVisible {
      let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
      let ownPID = ProcessInfo.processInfo.processIdentifier
      let changedApplication = frontPID != nil && frontPID != ownPID
        && frontPID != sourceApplication?.processIdentifier
      let sourceOwnsFocus = !panel.isKeyWindow && frontPID != ownPID
      if changedApplication || sourceOwnsFocus {
        // A result kept open across Settings/link navigation is not the current
        // invocation. Do not restore its old app or consume the next selection.
        dismiss(restoreFocus: false)
        captureAndShow()
      } else {
        dismiss()
      }
      return
    }
    captureAndShow()
  }

  func openHomeShortcut(_ action: HomeAction) {
    guard action == .ask || action == .clipboard,
          !isPasting else { return }
    if action == .clipboard && clipboardVisible { closeClipboardWindow(); return }
    if action == .clipboard,
       let source = NSWorkspace.shared.frontmostApplication,
       source.processIdentifier != ProcessInfo.processInfo.processIdentifier {
      cancelCapture()
      dismiss(restoreFocus: false)
      invocationPointer = NSEvent.mouseLocation
      sourceApplication = source
      let id = UUID()
      captureID = id
      captureTask = Task { [weak self, selectionEngine] in
        let readout = await selectionEngine.capture(applicationName: source.localizedName ?? "Application",
          processIdentifier: source.processIdentifier, applicationID: source.bundleIdentifier)
        guard !Task.isCancelled, let self, self.captureID == id else { return }
        self.captureID = nil
        self.captureTask = nil
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier else {
          await selectionEngine.clearTarget(readout.targetID)
          return
        }
        self.selection = readout
        self.homeVisible = true
        self.runHomeAction(.clipboard)
      }
      return
    }
    showHome()
    runHomeAction(action)
  }

  func openModeShortcut(_ action: Action) {
    guard action.definition != nil, !isPasting, !clipboardDragging else { return }
    cancelCapture()
    dismiss(restoreFocus: false)
    captureAndShow(requestedAction: action)
  }

  private func finishModeShortcut(_ action: Action?) {
    guard let action else { return }
    if state.actions.contains(action), selection?.hasSelection == true || fileContext != nil { choose(action); return }
    homeVisible = false
    // Preserve permission/protected-field notices instead of masking them as empty selection.
    if let selection, !selection.hasSelection && !selection.opensHome { return }
    showCorrectionMessage("Select compatible text or files to use " + action.title + ".")
  }

  private func captureAndShow(requestedAction: Action? = nil) {
    execution?.cancel()
    noticeDismissal?.cancel()
    invocationPointer = NSEvent.mouseLocation
    state = ActionBarState()
    rankingDiagnostic = "Local"
    appeared = false
    selection = nil
    invocationContext = nil
    homeVisible = false
    homeSelectedIndex = 0
    guard let source = NSWorkspace.shared.frontmostApplication,
      source.processIdentifier != ProcessInfo.processInfo.processIdentifier
    else { showHome(); if requestedAction != nil { homeVisible = false; finishModeShortcut(requestedAction) }; return }
    sourceApplication = source
    invocationContext = InvocationContext(capturedAt: .now, applicationID: source.bundleIdentifier)
    invocationContext?.applicationName = source.localizedName
    let id = UUID()
    captureID = id
    captureTask = Task { [weak self, selectionEngine] in
      defer {
        if self?.captureID == id {
          self?.cancelCapture()
        }
      }
      if source.bundleIdentifier == "com.apple.finder" {
        guard let self, let base = self.invocationContext else { return }
        let context = try? await self.fileContextReader.captureContext(base: base)
        guard !Task.isCancelled, self.captureID == id else { return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier else {
          self.invocationContext = nil
          return
        }
        self.invocationContext = context
        if let context {
          self.fileContext = context.files.isEmpty ? nil : context
          let recommendations = await self.rankInvocation(.init(fileContext: context), requestedAction: requestedAction)
          guard !Task.isCancelled, self.captureID == id,
                NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier else { return }
          self.actionRecommendations = recommendations; self.actionSelection = 1; self.actionPage = 0
          self.state = ActionBarState(recommendations: recommendations)
          self.fileContext = recommendations.isEmpty ? nil : context
        }
        self.captureID = nil
        self.captureTask = nil
        self.homeVisible = self.fileContext == nil
        self.show()
        self.finishModeShortcut(requestedAction)
        return
      }
      // Capture before the panel becomes key so the source still owns focus.
      let result = await selectionEngine.capture(
        applicationName: source.localizedName ?? "Application",
        processIdentifier: source.processIdentifier, applicationID: source.bundleIdentifier)
      guard !Task.isCancelled, let self, self.captureID == id else { return }
      guard NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier
      else {
        self.sourceApplication = nil
        return
      }
      self.selection = result
      self.invocationContext = result.context
      self.homeVisible = result.opensHome
      let context = RecommendationContext(selection: result, applicationID: source.bundleIdentifier)
      let recommendations = await self.rankInvocation(context, requestedAction: requestedAction)
      guard !Task.isCancelled, self.captureID == id,
            NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier else { return }
      self.captureID = nil
      self.captureTask = nil
      self.actionRecommendations = recommendations; self.actionSelection = 1; self.actionPage = 0
      self.state = ActionBarState(recommendations: recommendations)
      self.show()
      self.finishModeShortcut(requestedAction)
    }
  }

  private func rankInvocation(_ context: RecommendationContext, requestedAction: Action? = nil) async -> [ActionRecommendation] {
    rankingTrace = nil
    let inspect = Bundle.main.isTeroDevBuild && UserDefaults.standard.bool(forKey: "developerContextInspector")
    TextHabitStore.shared.refreshOwner()
    let habits = TextHabitStore.shared.habits
    let personalActions = habits.filter { $0.isEligible(in: context) }.map { RankingClient.PersonalCandidate(habit: $0) }
    let local = RecommendationEngine.rank(context: context, personalActions: habits)
    if let requestedAction { rankingDiagnostic = "Direct shortcut"; return local.filter { $0.target == .native(requestedAction) } }
    if !GatewayAccess.usesOwnKey, AccountStore.shared.usage?.canRank == false, (AccountStore.shared.usage?.resetDate ?? .distantPast) > .now { rankingDiagnostic = "Local · recommendation allowance reached"; return local }
    let rankingLocal = (ShoppingRequest.isActivated ? local : local.filter { $0.target != .native(.shop) })
      .filter { if case .native(let action) = $0.target { return action.definition?.rankedOnServer != false } else { return true } }
    // Local-only actions keep their place ahead of the semantic ranking.
    let localOnly = local.filter { if case .native(let action) = $0.target { return action.definition?.rankedOnServer == false } else { return false } }
    let candidates = rankingLocal.map { $0.target.rankingID }
    guard candidates.count >= 2, let observations = RankingContext(context) else { return local }
    let accountID = AccountStore.shared.user?.id
    // With an own AI key, Jev runs only with the person's own Typesafe key, straight from this Mac.
    let ownJev = GatewayAccess.usesOwnKey ? JevClient.stored : nil
    let memoScope = ownJev != nil ? JevClient.memoScope : accountID
    if !inspect, let scores = rankingMemo.scores(accountID: memoScope, context: observations, candidates: candidates, personalActions: personalActions),
       let ranked = SemanticRankingPolicy.apply(scores, to: rankingLocal) {
      rankingDiagnostic = "Jev · recent selection"; return SemanticRankingPolicy.merge(localOnly: localOnly, ranked: ranked)
    }
    if let ownJev {
      return await rankWithOwnJev(ownJev, observations: observations, candidates: candidates, personalActions: personalActions,
                                  local: local, rankingLocal: rankingLocal, localOnly: localOnly)
    }
    // Signed-out and own-key invocations without a Typesafe key stay entirely local:
    // with an own key nothing about the selection reaches Tero's servers.
    guard accountID != nil, !GatewayAccess.usesOwnKey else { rankingDiagnostic = "Local rules"; return local }
    let started = ContinuousClock.now
    // Capture is complete. A non-key, click-through branded bubble can now
    // acknowledge the shortcut without stealing the source editor's focus.
    state = ActionBarState(recommendations: local)
    invocationOpening = true
    rankingDiagnostic = "Jev · awaiting scores"
    show(opening: true)
    do {
      defer { GatewayAccess.didRequest() }
      guard let credential = await GatewayAccess.credential(), AccountStore.shared.user?.id == accountID else { return local }
      try Task.checkCancellation()
      // Authentication time is part of the existing ranking wait budget, not an extra wait.
      let remaining = RankingClient.waitBudget - started.duration(to: .now)
      guard remaining > .zero else { rankingDiagnostic = "Local · authentication wait"; return local }
      let requestID = UUID()
      if inspect, UserDefaults.standard.bool(forKey: "developerContextInspector") {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(RankingClient.Request(requestID: requestID, candidates: candidates, context: observations, personalActions: personalActions, debug: true)) {
          rankingTrace = "Request to Tero ranking gateway (JSON body, no credentials)\n" + String(decoding: data, as: UTF8.self)
        }
      }
      let result = try await RankingClient(deadline: remaining).rank(context: observations, candidates: candidates, personalActions: personalActions, credential: credential, debug: inspect, requestID: requestID)
      try Task.checkCancellation()
      guard let ranked = SemanticRankingPolicy.apply(result.scores, to: rankingLocal) else {
        rankingDiagnostic = "Local · invalid ranking"; return local
      }
      guard AccountStore.shared.user?.id == accountID, let accountID else { return local }
      if inspect, UserDefaults.standard.bool(forKey: "developerContextInspector"), let trace = result.debug {
        let scoreRows = result.scores.sorted { $0.score > $1.score }.map { score in
          let label = habits.first { "habit_" + $0.id.uuidString.lowercased() == score.id }?.name ?? Action(rawValue: score.id)?.title ?? score.id
          return "\(label): \(String(format: "%.3f", score.score))/3 · confidence \(String(format: "%.3f", score.confidence))"
        }.joined(separator: "\n")
        rankingTrace = "Scores (descending)\n\(scoreRows)\n\nJev request (JSON body, no credentials)\n\(trace.providerRequest)\n\nJev response (validated scores and probabilities)\n\(trace.providerResponse)"
      }
      rankingMemo.store(result.scores, accountID: accountID, context: observations, candidates: candidates, personalActions: personalActions)
      let elapsed = started.duration(to: .now).components
      let totalMs = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
      rankingDiagnostic = "Jev · \(totalMs) ms total / \(result.latencyMs) ms server · \(result.usage.inputTokens) in / \(result.usage.outputTokens) out · prompt v\(result.promptVersion)"
      return SemanticRankingPolicy.merge(localOnly: localOnly, ranked: ranked)
    } catch {
      if !Task.isCancelled { rankingDiagnostic = (error as? RankingClient.Failure) == .timeout ? "Local · Jev exceeded 3 s" : error is RankingClient.Failure ? "Local · ranking gateway unavailable" : "Local · network fallback" }
      return local
    }
  }

  /// Same presentation and wait budget as Tero Pro ranking; the request goes to Typesafe directly.
  private func rankWithOwnJev(_ jev: JevClient, observations: RankingContext, candidates: [String],
                              personalActions: [RankingClient.PersonalCandidate], local: [ActionRecommendation],
                              rankingLocal: [ActionRecommendation], localOnly: [ActionRecommendation]) async -> [ActionRecommendation] {
    let started = ContinuousClock.now
    state = ActionBarState(recommendations: local)
    invocationOpening = true
    rankingDiagnostic = "Jev (your key) · awaiting scores"
    show(opening: true)
    do {
      let scores = try await jev.rank(context: observations, candidates: candidates, personalActions: personalActions)
      try Task.checkCancellation()
      guard GatewayAccess.usesOwnKey, let ranked = SemanticRankingPolicy.apply(scores, to: rankingLocal) else {
        rankingDiagnostic = "Local · invalid ranking"; return local
      }
      rankingMemo.store(scores, accountID: JevClient.memoScope, context: observations, candidates: candidates, personalActions: personalActions)
      let elapsed = started.duration(to: .now).components
      rankingDiagnostic = "Jev (your key) · \(elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000) ms"
      return SemanticRankingPolicy.merge(localOnly: localOnly, ranked: ranked)
    } catch {
      if !Task.isCancelled {
        rankingDiagnostic = switch error as? JevClient.Failure {
          case .timeout: "Local · Jev exceeded 3 s"
          case .rejected: "Local · Typesafe key rejected"
          default: "Local · Jev unavailable"
        }
      }
      return local
    }
  }

  func showHome() {
    GatewayAccess.event("panel_opened")
    cancelCapture()
    dismiss(restoreFocus: false)
    invocationPointer = NSEvent.mouseLocation
    sourceApplication = NSWorkspace.shared.frontmostApplication
    homeSelectedIndex = 0
    homeVisible = true
    show()
  }

  func runHomeAction(_ action: HomeAction) {
    GatewayAccess.event("action_selected", mode: action.rawValue)
    guard homeVisible, action.isAvailable else { return }
    if action == .ask {
      if !aiAllowanceAvailable { showAllowanceReached(); return }
      noticeDismissal?.cancel()
      noticeDismissal = nil
      homeVisible = false
      askVisible = true
      askMode = true
      askQuery = ""
      // Keep the top edge anchored while the composer replaces the home bubbles.
      if let panel {
        setPanelFrame(width: askPanelSize.width, height: askPanelSize.height, display: true)
        panel.makeKeyAndOrderFront(nil)
      } else { show() }
      return
    }
    if action == .clipboard {
      guard let clipboardStore else { return }
      clipboardStore.refreshRetention()
      clipboardStore.browsing = true
      homeVisible = false
      clipboardVisible = true
      clipboardQuery = ""
      clipboardFilter = nil
      clipboardPinnedOnly = false
      clipboardMessage = nil
      resetClipboardSelection()
      presentClipboard()
      return
    }
    dismiss(restoreFocus: false)
    onHomeAction?(action)
  }

  func beginResultRefinement() {
    guard let text = explanationText, !text.isEmpty, !readingInProgress, readingError == nil, !closing else { return }
    cancelAskRefinement()
    askPromptRevision = nil
    resultBeforeRefinement = text
    resultWasAsk = askMode
    previousQuestionPreview = askQuestionPreview
    refiningResult = true
    askVisible = true
    askQuery = ""
    readingCardKeepsOpen = false
    resizeAskEditor()
    panel?.makeKeyAndOrderFront(nil)
  }

  func restoreResult() {
    guard let result = resultBeforeRefinement else { return }
    correctionTask?.cancel()
    correctionID = nil
    cancelAskRefinement()
    askPromptRevision = nil
    askVisible = false
    refiningResult = false
    askQuery = ""
    askMode = resultWasAsk
    askQuestionPreview = previousQuestionPreview
    resultBeforeRefinement = nil
    readingInProgress = false
    readingError = nil
    showExplanation(result)
  }

  func backFromAsk() {
    if refiningResult, resultBeforeRefinement != nil { restoreResult(); return }
    guard askVisible else { return }
    if selectionAskMode != nil { returnFromSelectionAsk(); return }
    dismiss()
  }

  private func beginSelectionAsk() {
    noticeDismissal?.cancel()
    noticeDismissal = nil
    selectionAskMode = .detected(canReplace: selection?.canPaste == true)
    askQuery = ""
    askRefineError = nil
    askVisible = true
    setPanelFrame(width: askPanelSize.width, height: askPanelSize.height, centered: true, display: true)
    panel?.makeKeyAndOrderFront(nil)
  }

  /// Escape keeps the captured selection and returns to its actions.
  private func returnFromSelectionAsk() {
    cancelAskRefinement()
    selectionAskMode = nil
    askVisible = false
    askQuery = ""
    askRefineError = nil
    state.returnFromOptions()
    resizeActionRow()
  }

  private func submitSelectionAsk(_ request: String, mode: SelectionAskMode) {
    guard case .selected(let text) = selection?.status else { returnFromSelectionAsk(); return }
    guard let instruction = mode.instruction(for: request) else {
      askRefineError = "Keep your request under \(SelectionAskMode.requestLimit) characters"; return
    }
    askVisible = false
    selectionAskMode = nil
    askQuery = ""
    askMode = true
    askQuestionPreview = String(request.split(whereSeparator: { $0.isWhitespace }).prefix(12).joined(separator: " ").prefix(100))
    switch mode {
    case .explain:
      startReading(text, action: "text_habit", refinement: instruction)
    case .write:
      // Same delivery as the other writing actions: replace a revalidated editable
      // selection, otherwise show a reading card with explicit copy.
      resizeActionRow()
      startCorrection(text, instruction: instruction)
    }
  }

  func submitAsk() {
    guard askVisible, !askRefining else { return }
    if !aiAllowanceAvailable { showAllowanceReached(); return }
    let question = askQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !question.isEmpty else { return }
    if refiningResult, let result = resultBeforeRefinement {
      guard question.unicodeScalars.count <= 1000 else { askRefineError = "Keep changes under 1,000 characters"; return }
      askVisible = false
      refiningResult = false
      startReading(result, action: "result_refine", refinement: question)
      askQuery = ""
      return
    }
    if let mode = selectionAskMode { submitSelectionAsk(question, mode: mode); return }
    guard question.unicodeScalars.count <= 4000 else { askRefineError = "Keep your request under 4,000 characters"; return }
    let id = UUID()
    let accountID = AccountStore.shared.user?.id
    askRefineID = id
    askRefining = true
    askRouting = true
    askRefineError = nil
    askRefineTask = Task { [weak self] in
      guard let self else { return }
      var products = false
      // Reuse the deployed Jev catalog. Longer prompts stay with Ask rather than
      // classifying a truncated request whose meaning could have changed.
      // Product routing uses Tero Pro's ranking service, or Jev with the person's own Typesafe key
      // when their provider can search products. Otherwise own-key Ask answers directly.
      let ownJev = GatewayAccess.usesOwnKey && AIConfiguration.active?.provider.supportsWebSearch == true ? JevClient.stored : nil
      if let ownJev, question.unicodeScalars.count <= 2000,
         let context = RankingContext(RecommendationContext(selection: SelectionReadout(
           applicationName: "Tero Ask", processIdentifier: 0, status: .selected(question)), applicationID: nil)) {
        if let scores = try? await ownJev.rank(context: context, candidates: ShoppingRequest.routingCandidates) {
          products = ShoppingRequest.shouldShowProducts(scores)
        }
      } else if !GatewayAccess.usesOwnKey, question.unicodeScalars.count <= 2000,
         let context = RankingContext(RecommendationContext(selection: SelectionReadout(
           applicationName: "Tero Ask", processIdentifier: 0, status: .selected(question)), applicationID: nil)) {
        do {
          guard let credential = await GatewayAccess.credential() else { throw CorrectionClient.Failure.unavailable }
          try Task.checkCancellation()
          guard AccountStore.shared.user?.id == accountID else { throw CancellationError() }
          defer { GatewayAccess.didRequest() }
          let result = try await RankingClient().rank(context: context,
            candidates: ShoppingRequest.routingCandidates, credential: credential)
          products = ShoppingRequest.shouldShowProducts(result.scores)
        } catch {
          // An unavailable or ambiguous recommendation keeps the normal Ask path.
        }
      }
      guard !Task.isCancelled, self.askRefineID == id, self.askVisible,
            self.askQuery.trimmingCharacters(in: .whitespacesAndNewlines) == question else { return }
      self.askRefining = false; self.askRouting = false
      self.askRefineTask = nil; self.askRefineID = nil
      guard AccountStore.shared.user?.id == accountID else { return }
      self.askVisible = false
      self.askQuery = ""
      self.askPromptRevision = nil
      if products { self.startShopping(question); return }
      self.askQuestionPreview = String(question.split(whereSeparator: { $0.isWhitespace }).prefix(12).joined(separator: " ").prefix(100))
      self.startReading(question, action: "ask")
    }
  }

  private func startShopping(_ request: String) {
    guard aiAllowanceAvailable else { showAllowanceReached(); return }
    shoppingSession?.cancel()
    homeVisible = false; askVisible = false
    shoppingSession = ShoppingSession(request: request,
      back: { [weak self] in self?.dismiss() },
      changed: { [weak self] in self?.updateShoppingPresentation() },
      denied: { [weak self] needsSignIn in self?.showAllowanceReached(needsSignIn: needsSignIn) })
    if panel?.isVisible == true {
      updateShoppingPresentation()
      panel?.makeKeyAndOrderFront(nil)
    } else { show() }
    shoppingSession?.search(skip: true)
  }
  func updateShoppingPresentation() {
    guard let session = shoppingSession else { return }
    let size = Self.shoppingPanelSize(session)
    setPanelFrame(width: size.width, height: size.height)
  }

  func updateAskQuery(_ query: String) {
    if query != askQuery { cancelAskRefinement(); askPromptRevision = nil }
    askQuery = query
    askRefineError = nil
  }

  func refineAskPrompt() {
    guard askVisible, !askRefining, selectionAskMode == nil else { return }
    if !aiAllowanceAvailable { showAllowanceReached(); return }
    let original = askQuery
    guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    askRefineError = nil
    guard original.unicodeScalars.count <= 4000 else { askRefineError = "Prompt too long"; return }
    let id = UUID()
    askRefineID = id
    askRefining = true
    askRefineTask = Task { [weak self] in
      do {
        guard let credential = await GatewayAccess.credential() else { throw CorrectionClient.Failure.unavailable }
        let refined = try await CorrectionClient().refinePrompt(original, requestID: id, credential: credential)
        guard !Task.isCancelled, let self, self.askVisible, self.askRefineID == id,
              self.askQuery == original else { return }
        self.askRefining = false
        self.askRefineID = nil
        self.askRefineTask = nil
        self.askPromptRevision = (original, refined)
        self.askQuery = refined
      } catch {
        guard !Task.isCancelled, let self, self.askRefineID == id else { return }
        if self.handleAllowanceFailure(error) { return }
        self.cancelAskRefinement()
        self.askRefineError = "Couldn't refine. Try again."
      }
    }
  }

  private func cancelAskRefinement() {
    askRefineTask?.cancel()
    askRefineTask = nil
    askRefineID = nil
    askRefining = false
    askRouting = false
    askRefineError = nil
  }

  private func presentClipboard() {
    clipboardTransition?.cancel()
    clipboardClosing = false; clipboardPresented = false
    show()
    clipboardTransition = Task { [weak self] in
      await Task.yield()
      guard !Task.isCancelled, let self, self.clipboardVisible else { return }
      self.clipboardPresented = true
    }
  }
  private func animateClipboardExit(_ completion: @escaping @MainActor () -> Void) {
    guard !clipboardClosing else { return }
    clipboardTransition?.cancel(); clipboardClosing = true; clipboardPresented = false
    clipboardTransition = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 100 : 240)) } catch { return }
      guard let self, self.clipboardVisible else { return }
      self.clipboardClosing = false
      completion()
    }
  }
  func closeClipboardWindow() { animateClipboardExit { [weak self] in self?.dismiss(restoreFocus: false) } }
  func toggleClipboardPin() {
    guard let entry = selectedClipboardEntry, let store = clipboardStore else { return }
    clipboardMessage = store.togglePin(entry) ? nil : store.error ?? "You can pin up to 20 entries."
    if !clipboardEntries.contains(where: { $0.id == clipboardSelectedID }) { resetClipboardSelection() }
  }
  func copyClipboardLink(domain: Bool) {
    guard let entry = selectedClipboardEntry, let text = domain ? entry.webURL?.host : entry.cleanedLink?.absoluteString else { return }
    guard clipboardStore?.copy(text) == true else { clipboardMessage = "Could not copy this link."; return }
    clipboardMessage = domain ? "Domain copied" : entry.cleanedLink == entry.webURL ? "Link copied · no tracking removed" : "Clean link copied"
    flashShortcut("⌘C", for: .milliseconds(900), clearingClipboardMessage: true)
  }
  func beginClipboardEntryActions() {
    guard clipboardVisible, !clipboardClosing, let entry = selectedClipboardEntry else { return }
    closeClipboardEntryMenu()
    var context = InvocationContext(capturedAt: .now, applicationID: entry.sourceBundleID)
    context.applicationName = entry.sourceName; context.surface = .reading; context.capture = .observed
    var workspace: URL?
    if entry.kind == .files {
      guard let urls = ClipboardCapture.resolvedFiles(entry), urls.count <= 20 else {
        clipboardMessage = "Use up to 20 available files."; return
      }
      context.fileOrigin = .clipboardFiles(entry.id); context.fileCapture = .observed
      context.files = urls.map { .read($0) }
    } else if entry.kind == .image {
      do {
        guard let data = entry.imageData else { return }
        let folder = try LocalFileIO.workspace(); workspace = folder
        let url = folder.appendingPathComponent("Clipboard image.png")
        try data.write(to: url, options: .atomic)
        context.fileOrigin = .clipboardImage(entry.id); context.fileCapture = .observed; context.files = [.read(url)]
      } catch {
        if let workspace { try? FileManager.default.removeItem(at: workspace) }
        clipboardMessage = "Could not prepare this image."; return
      }
    }
    let readout = SelectionReadout(applicationName: entry.sourceName ?? "Clipboard", processIdentifier: 0,
      status: context.files.isEmpty ? .selected(entry.text) : .noSelection, context: context)
    let recommendations = RecommendationEngine.rank(context: context.files.isEmpty
      ? .init(selection: readout, applicationID: context.applicationID) : .init(fileContext: context))
    guard !recommendations.isEmpty else {
      if let workspace { try? FileManager.default.removeItem(at: workspace) }
      clipboardMessage = "No available modes for this entry."; return
    }
    clipboardPrepared = (entry.id, readout, context, recommendations, workspace)
    clipboardModeActions = recommendations.compactMap { if case .native(let action) = $0.target { return action }; return nil }
    clipboardModeQuery = ""
    clipboardModeSelectedID = clipboardModeStep.choices.first?.id
    clipboardActionMenuPresented = true

  }

  func backToClipboardEntry() {
    guard clipboardActionEntryID != nil, state.executing == nil else { return }
    if let workspace = clipboardWorkspace { try? FileManager.default.removeItem(at: workspace) }
    clipboardWorkspace = nil; clipboardActionEntryID = nil
    fileContext = nil; selection = nil; invocationContext = nil
    clipboardVisible = true; clipboardStore?.browsing = true
    presentClipboard()
  }

  var clipboardPrimaryTitle: String { clipboardCanPaste ? "Paste" : "Copy" }

  func performClipboardPrimary() {
    useClipboardEntry(paste: clipboardCanPaste)
  }

  func openClipboardEntry(reveal: Bool = false) {
    guard clipboardVisible, let entry = selectedClipboardEntry else { return }
    if entry.kind == .link, let url = entry.webURL {
      if NSWorkspace.shared.open(url) { closeClipboardWindow() }
      else { clipboardMessage = "This link could not be opened." }
    } else if entry.kind == .files {
      guard let urls = ClipboardCapture.resolvedFiles(entry) else { clipboardMessage = "File unavailable. It may have moved or been deleted."; return }
      if reveal { NSWorkspace.shared.activateFileViewerSelecting(urls); closeClipboardWindow(); return }
      guard let url = urls.first else { return }
      // Executables and scripts are revealed rather than launched from history.
      let blocked = ["app", "sh", "command", "scpt", "applescript", "workflow", "pkg", "dmg", "exe"]
      if blocked.contains(url.pathExtension.lowercased()) || FileManager.default.isExecutableFile(atPath: url.path) {
        NSWorkspace.shared.activateFileViewerSelecting([url]); closeClipboardWindow(); return
      }
      if NSWorkspace.shared.open(url) { closeClipboardWindow() }
      else { clipboardMessage = "This file could not be opened." }
    }
  }

  func beginClipboardDrag(_ entry: ClipboardEntry) {
    clipboardSelectedID = entry.id
    clipboardDragging = true
    clipboardMessage = nil
    // Keep the hosting hierarchy alive until AppKit ends the drag.
    panel?.orderOut(nil)
  }

  func endClipboardDrag(_ accepted: Bool) {
    clipboardDragging = false
    if accepted {
      // The destination accepts the drop; Tero does not perform any file mutation.
      clipboardStore?.browsing = false
      dismiss(restoreFocus: false)
    } else if clipboardVisible {
      panel?.makeKeyAndOrderFront(nil)
    }
  }

  func unavailableClipboardDrag() {
    clipboardMessage = "Files unavailable. They may have moved or been deleted."
  }

  func resetClipboardSelection() { clipboardSelectedID = clipboardEntries.first?.id }

  func backFromClipboard() {
    guard !isPasting else { return }
    animateClipboardExit { [weak self] in self?.dismiss() }
  }

  func useClipboardEntry(paste: Bool) {
    guard clipboardVisible, !isPasting, let entry = selectedClipboardEntry, let clipboardStore else { return }
    if !paste {
      guard clipboardStore.copy(entry) else { clipboardMessage = "Could not copy this entry."; return }
      flashShortcut("⌘C")
      return
    }
    guard let original = selection, original.canInsertClipboard, let source = sourceApplication,
          !source.isTerminated else { return }
    isPasting = true
    pasteTask = Task { [weak self, selectionEngine] in
      guard let self else { return }
      let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
      guard front == source.processIdentifier || front == ProcessInfo.processInfo.processIdentifier else {
        self.isPasting = false; self.dismiss(restoreFocus: false); return
      }
      self.panel?.resignKey()
      source.activate(options: [])
      do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      let valid = await selectionEngine.validatesClipboardTarget(original)
      guard !Task.isCancelled else { return }
      guard valid, AXIsProcessTrusted(), NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier,
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
        self.isPasting = false
        self.clipboardMessage = "The field changed. Copy the entry instead."
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier { self.panel?.makeKeyAndOrderFront(nil) }
        else { self.dismiss(restoreFocus: false) }
        return
      }
      guard clipboardStore.copy(entry) else {
        self.isPasting = false; self.clipboardMessage = "Could not prepare the paste."
        self.panel?.makeKeyAndOrderFront(nil); return
      }
      down.flags = .maskCommand; up.flags = .maskCommand
      down.postToPid(source.processIdentifier); up.postToPid(source.processIdentifier)
      self.closing = true
      do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
      self.isPasting = false
      self.dismiss(restoreFocus: false)
    }
  }

  private func hideInvocationOpening() {
    guard invocationOpening else { return }
    invocationOpening = false
    fileContext = nil
    panel?.orderOut(nil)
    panel?.acceptsFocus = true
    panel?.ignoresMouseEvents = false
    appeared = false
  }

  private func cancelCapture() {
    hideInvocationOpening()
    captureTask?.cancel()
    captureTask = nil
    captureID = nil
    sourceApplication = nil
    selection = nil
    invocationContext = nil
  }

  private func show(opening: Bool = false) {
    TextHabitStore.shared.refreshOwner()
    state.hasTextHabits = selection?.hasSelection == true && fileContext == nil
      && TextHabitStore.shared.habits.contains(where: \.enabled)
    noticeDismissal?.cancel()
    noticeDismissal = nil
    let panel = existingPanel()
    let pointer = invocationPointer
    let screens = NSScreen.screens
    let primaryTop = screens.first?.frame.maxY ?? 0
    let bounds = selection?.hasSelection == true ? selection?.metadata?.anchorBounds : nil
    let target = bounds.flatMap {
      PanelPlacement.appKitRect(fromAX: $0, primaryScreenTop: primaryTop)
    }
    let targetScreen = target.flatMap {
      PanelPlacement.screenIndex(for: $0, screens: screens.map(\.frame))
    }
    let screen =
      targetScreen.map { screens[$0] }
      ?? screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
    if let screen {
      panel.setFrame(
        PanelPlacement.frame(
          panelSize: initialPanelSize(opening: opening),
          anchor: targetScreen == nil ? nil : target, pointer: pointer,
          visibleFrame: screen.visibleFrame), display: false)
    }
    if !opening { invocationOpening = false }
    panel.acceptsFocus = !opening
    panel.ignoresMouseEvents = opening
    if opening {
      panel.orderFrontRegardless()
    } else if !homeVisible && !clipboardVisible && !askVisible && shoppingSession == nil && selection?.isTransient == true {
      // A brief notice must not steal typing focus from the source application.
      // An empty capture also opens Home, but Ask is an interactive editor, not a notice.
      panel.orderFrontRegardless()
      noticeDismissal = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(2.5)) } catch { return }
        self?.dismiss(restoreFocus: false)
      }
    } else {
      panel.makeKeyAndOrderFront(nil)
    }
    withAnimation(.easeOut(duration: 0.14)) { appeared = true }
  }

  /// The first frame for the current presentation, before any mode-specific resize.
  private func initialPanelSize(opening: Bool) -> CGSize {
    if opening { return CGSize(width: max(440, presentedRowWidth + 2 * PanelPlacement.contentInset), height: 54) }
    if let shoppingSession { return Self.shoppingPanelSize(shoppingSession) }
    if clipboardVisible { return CGSize(width: 704, height: 464) }
    if askVisible { return askPanelSize }
    if fileContext != nil { return CGSize(width: actionRowPanelWidth, height: 54) }
    if homeVisible { return CGSize(width: max(480, homeRowWidth + 2 * PanelPlacement.contentInset), height: 54) }
    if selection?.hasSelection == true { return CGSize(width: actionRowPanelWidth, height: 54) }
    return CGSize(width: 330, height: selection?.status == .permissionRequired ? 100 : 58)
  }

  private func resizeAskEditor() {
    guard askVisible, let panel else { return }
    if refiningResult, let text = explanationText { resizeReadingCard(text); return }
    let total = askPanelSize.height
    guard abs(total - panel.frame.height) > 0.5 else { return }
    setPanelFrame(height: total)
  }

  private func existingPanel() -> TeroPanel {
    if let panel { return panel }
    let created = TeroPanel(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 54),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    created.title = "Tero Dev"
    created.isOpaque = false
    created.backgroundColor = .clear
    created.hasShadow = false
    created.level = .floating
    created.hidesOnDeactivate = false
    created.isReleasedWhenClosed = false
    created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    created.delegate = self
    let hostingView = NSHostingView(rootView: ActionBarView(controller: self))
    // AppKit owns this overlay's frame. SwiftUI must not negotiate window size
    // constraints as the content switches between a notice and the action row.
    hostingView.sizingOptions = []
    // Keep the hosting view below a plain AppKit content view. As the window's
    // root, NSHostingView still updates window size extrema in a SwiftUI App,
    // even with sizingOptions disabled, causing a constraint update loop.
    let container = NSView(frame: created.contentLayoutRect)
    hostingView.frame = container.bounds
    hostingView.autoresizingMask = [.width, .height]
    container.addSubview(hostingView)
    created.contentView = container
    created.handleKey = { [weak self] event in self?.handle(event) ?? false }
    panel = created
    return created
  }

  func actionAvailable(_ action: Action) -> Bool {
    guard action.definition?.usesAI == true else { return true }
    return aiAllowanceAvailable
  }

  /// AI runs with the person's own key, or with an active Tero Pro allowance.
  private var aiAllowanceAvailable: Bool {
    if GatewayAccess.usesOwnKey { return true }
    guard AccountStore.shared.user != nil else { return false }
    guard let usage = AccountStore.shared.usage,
          (usage.resetDate ?? .distantPast) > .now else { return true }
    return usage.canUseAI
  }

  func choose(_ action: Action) {
    guard selection?.hasSelection == true || fileContext != nil,
          state.actions.contains(action) else { return }
    state.select(action)
    activate()
  }

  private func activate() {
    guard selection?.hasSelection == true || fileContext != nil, state.executing == nil else { return }
    if ![Action.more, .back, .search].contains(state.selected) {
      let context = fileContext.map { RecommendationContext(fileContext: $0) }
        ?? selection.map { RecommendationContext(selection: $0, applicationID: nil) }
      guard let context, let definition = ActionCatalog.definition(for: state.selected),
            definition.accepts(context) else { return }
    }
    if !actionAvailable(state.selected) {
      showAllowanceReached()
      return
    }
    state.activate()
    if state.executing == nil {
      resizeActionRow()
      return
    }
    if state.isSearching {
      panel?.makeFirstResponder(nil)
      resizeActionRow()
    }
    guard let action = state.executing, let definition = ActionCatalog.definition(for: action) else { return }
    GatewayAccess.event("action_selected", mode: action.rawValue)
    if let kind = definition.workflowKind, let fileContext {
      fileWorkflow = FileWorkflowSession(kind: kind, context: fileContext,
        back: { [weak self] in self?.backFromFileWorkflow() },
        changed: { [weak self] in self?.updateFileWorkflowPresentation() })
      updateFileWorkflowPresentation()
      if [.rename, .batchRename].contains(kind) { fileWorkflow?.suggestName() }
      return
    }
    if definition.executor == .videoDownload, case .selected(let text) = selection?.status, let url = VideoLink.youtube(text) {
      videoDownload = VideoDownloadSession(url: url,
        back: { [weak self] in self?.backFromVideoDownload() },
        changed: { [weak self] in self?.updateVideoDownloadPresentation() })
      updateVideoDownloadPresentation()
      return
    }
    if definition.executor == .fileSummary, let context = fileContext {
      fileContext = nil
      startReading("Summarize the selected file.", action: "summarize_file", language: ResponseLanguage.load(), fileContext: context)
      return
    }
    guard case .selected(let text) = selection?.status else { return }
    switch definition.executor {
    case .shop:
      startShopping(text)
      return
    case .askSelection:
      beginSelectionAsk()
      return
    case .openMaps, .directions, .units, .currencies, .timeZones:
      startUtility(action, text: text)
      return
    case .checkClaim:
      startReading(text, action: "check_claim", context: ReplyContext(invocationContext))
      return
    case .fileWorkflow, .fileSummary, .videoDownload: return
    case .calculator:
      guard let value = QuickCalculation.number(text) else { state.returnFromOptions(); return }
      execution = Task { [weak self] in
        do { try await Task.sleep(for: .milliseconds(280)) } catch { return }
        guard let self else { return }
        if let panel = self.panel {
          // Grow upward for the shortcut hints, keeping the input in place.
          var frame = panel.frame
          frame.size.height += 24
          if let safe = panel.screen?.visibleFrame.insetBy(dx: 8, dy: 8) {
            frame.origin.y = min(max(frame.minY, safe.minY), safe.maxY - frame.height)
          }
          panel.setFrame(frame, display: false)
        }
        self.calculatorValue = value
      }
      return
    case .translate:
      translationTarget = ResponseLanguage.translationTarget()
      translationBackSelected = false
      translationMoreSelected = false
      translationPage = 0
      translationChoiceQuery = ""
      choosingTranslationLanguage = true
      return
    case .taskPlan, .eventPlan:
      startCommitmentPlan(text, destination: definition.executor == .taskPlan ? .reminders : .calendar)
      return
    case .explain:
      startExplanation(text)
      return
    case .reply:
      startReplyOptions(text)
      return
    case .rewrite, .tone, .changeCase:
      choosingTextOptions = true
      selectedTextOption = definition.executor == .changeCase ? LocalTextTransform.allCases.first?.rawValue : TextStyle.choices(for: action).first?.rawValue
      return
    case .correct, .simplify, .improvePrompt, .cleanFormatting, .keyPoints, .extractTasks:
      startCorrection(text)
      return
    }
  }

  /// Mode-specific adapters supply data and typed handlers; navigation stays generic.
  var modeChoices: ModeChoicePresentation? {
    if let session = fileWorkflow { return session.presentation }
    if let session = videoDownload { return session.presentation }
    if let utilitySession, utilitySession.message == nil { return utilitySession.presentation }
    if choosingTranslationLanguage {
      let languages = ResponseLanguage.translationChoices().filter {
        translationChoiceQuery.isEmpty || ($0.title+" "+$0.rawValue).localizedStandardContains(translationChoiceQuery)
      }
      let pageCount = max(1,(languages.count + 2) / 3)
      let visible = Array(languages.dropFirst(translationPage * 3).prefix(3))
      let options = visible.map {
        ModeChoice(id: $0.rawValue, title: $0.title, label: "Translate to \($0.title)")
      } + (languages.count>3 ? [ModeChoice(id: "more-languages", title: "More", label: "More languages")]:[])
      let selected = translationBackSelected ? nil : translationMoreSelected ? "more-languages" : translationTarget.rawValue
      return ModeChoicePresentation(step: .init(label: "Choose translation language", choices: options,
        selectedID: selected), searchQuery:translationChoiceQuery,search:{[weak self] query in
          guard let self else{return}
          translationChoiceQuery=String(query.prefix(80));translationPage=0
          translationBackSelected=false;translationMoreSelected=false
          if let first=ResponseLanguage.translationChoices().first(where:{query.isEmpty || ($0.title+" "+$0.rawValue).localizedStandardContains(query)}) {translationTarget=first}
        }, select: { [weak self] id in
          guard let self else { return }
          translationBackSelected = id == nil
          translationMoreSelected = id == "more-languages"
          if let id, let language = ResponseLanguage(rawValue: id) { translationTarget = language }
        }, perform: { [weak self] id in
          guard let self else { return }
          if id == "more-languages" {
            translationPage = (translationPage + 1) % pageCount
            translationMoreSelected = false
            translationTarget = languages[translationPage * 3]
          } else if let id, let language = ResponseLanguage(rawValue: id) { translateSelection(to: language) }
          else if id == nil { backFromTranslation() }
        })
    }
    if choosingTextOptions, let action = state.executing {
      let options = action == .changeCase
        ? LocalTextTransform.allCases.map { ModeChoice(id: $0.rawValue, title: $0.title, label: "Change to \($0.title)") }
        : TextStyle.choices(for: action).map { ModeChoice(id: $0.rawValue, title: $0.title, label: "\(action.title): \($0.title)") }
      return ModeChoicePresentation(step: .init(label: "Choose \(action.title.lowercased())", choices: options, selectedID: selectedTextOption),
        select: { [weak self] id in self?.selectedTextOption = id }, perform: { [weak self] id in
          guard let self else { return }
          if let id, options.contains(where: { $0.id == id }), case .selected(let text) = selection?.status {
            choosingTextOptions = false
            startCorrection(text, style: TextStyle(rawValue: id), letterCase: LocalTextTransform(rawValue: id))
          } else if id == nil {
            choosingTextOptions = false
            state.returnFromOptions()
            resizeActionRow()
          }
        })
    }
    if !replyIntents.isEmpty, explanationText == nil, correctionMessage == nil {
      let options = replyIntents.map { ModeChoice(id: $0.rawValue, title: $0.title, label: "Reply: \($0.title)") }
      let selected = replyIntents.indices.contains(replyIntentIndex) ? replyIntents[replyIntentIndex].rawValue : nil
      return ModeChoicePresentation(step: .init(label: "Choose how to reply", choices: options, selectedID: selected),
        activityTitle: replyDrafting ? "Reply" : nil, finished: correctionFinished,
        select: { [weak self] id in
          guard let self else { return }
          replyIntentIndex = id.flatMap { id in replyIntents.firstIndex { $0.rawValue == id } } ?? -1
        }, perform: { [weak self] id in
          guard let self else { return }
          if let id, let intent = ReplyIntent(rawValue: id) { chooseReplyIntent(intent) }
          else if id == nil { backFromReply() }
        })
    }
    return nil
  }

  func beginActionSearch(query: String = "") {
    guard selection?.hasSelection == true || fileContext != nil, state.executing == nil else { return }
    state.beginSearch(query: query)
    actionSelection = 0
    resizeActionRow()
    panel?.makeKeyAndOrderFront(nil)
  }

  func resizeModeChoiceRow() {
    if fileWorkflow != nil { updateFileWorkflowPresentation(); return }
    if videoDownload != nil { updateVideoDownloadPresentation(); return }
    if utilitySession != nil { updateUtilityPresentation(); return }
    guard let panel, let choices = modeChoices, choices.activityTitle == nil else { return }
    let width = max(440, choices.rowWidth + 2 * PanelPlacement.contentInset)
    let height: CGFloat = choices.searchQuery == nil ? panel.frame.height:92
    guard abs(panel.frame.width - width) > 0.5 || abs(panel.frame.height-height)>0.5 else { return }
    setPanelFrame(width: width, height: height, centered: true)
    if choices.searchQuery != nil {panel.makeKeyAndOrderFront(nil)}
  }

  func updateActionSearch(_ query: String) {
    state.updateSearch(query)
    actionSelection = 0
    resizeActionRow()
  }

  func endActionSearch() {
    guard state.isSearching, state.executing == nil else { return }
    panel?.makeFirstResponder(nil)
    state.endSearch()
    actionSelection = 1
    resizeActionRow()
  }

  private func resizeActionRow() {
    // Keep the original row's top edge; the search results unfold below it.
    setPanelFrame(width: actionRowPanelWidth, height: state.isSearching && state.executing == nil ? 92 : 54, centered: true)
  }

  private func handleClipboardMenuKey(_ event: NSEvent) -> Bool {
    if let editor = event.window?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
    switch event.keyCode {
    case 53: closeClipboardEntryMenu(); return true
    case 123,124,125,126,48:
      guard event.modifierFlags.intersection([.command,.option,.control]).isEmpty else { return false }
      clipboardModeSelectedID = clipboardModeStep.nextSelection(by: event.keyCode == 123 || event.keyCode == 126 || (event.keyCode == 48 && event.modifierFlags.contains(.shift)) ? -1 : 1)
      return true
    case 36,76: chooseClipboardMode(clipboardModeSelectedID); return true
    default: return false
    }
  }

  private func handle(_ event: NSEvent) -> Bool {
    if allowanceReached {
      if event.keyCode == 53 { dismiss(); return true }
      if [36, 76].contains(event.keyCode) { openAllowanceAccount(); return true }
      return false
    }
    if invocationOpening { return true }
    if closing || clipboardClosing || isPasting || closingTask != nil { return true }
    if event.keyCode == 53, clipboardActionEntryID != nil, state.executing == nil, !state.isSearching, state.page == .main { backToClipboardEntry(); return true }
    if let session = shoppingSession {
      if let editor = panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
      if event.keyCode == 53 { session.back(); return true }
      if [36, 76].contains(event.keyCode), !event.modifierFlags.contains(.shift) { session.search(); return true }
      return false
    }
    if let session = commitmentSession {
      if event.keyCode == 53 { dismiss(); return true }
      // Editing Return stays in the field; creation has an explicit focused button.
      if [36, 76].contains(event.keyCode), !(panel?.firstResponder is NSTextView), !(panel?.firstResponder is NSControl) {
        if session.containers.isEmpty {
          if session.needsSettings { openCommitmentSettings() }
          else { Task { await session.connect() } }
        } else { session.create() }
        return true
      }
      return false
    }
    if let session = utilitySession, session.message != nil {
      if [53,36,76].contains(event.keyCode) { backFromUtility(); return true }
      return false
    }
    if utilitySession?.choosingDate == true, panel?.firstResponder is NSTextView,
       ![53,36,76].contains(event.keyCode) { return false }
    if let session = videoDownload {
      // Escape steps back; while downloading it cancels the download.
      if event.keyCode == 53 {
        if session.busy { backFromVideoDownload() } else { session.presentation.perform(nil) }
        return true
      }
      if session.busy { return true }
      if [36, 76].contains(event.keyCode) { session.presentation.activate(session.selectedID); return true }
      if [123,124,125,126,48].contains(event.keyCode) {
        session.selectedID = session.presentation.step.nextSelection(by: event.keyCode == 123 || event.keyCode == 126 ? -1 : 1)
        return true
      }
      return false
    }
    if let session = fileWorkflow {
      if event.keyCode == 53 {
        if session.busy && [.rename, .batchRename, .move].contains(session.kind) { return true }
        backFromFileWorkflow(); return true
      }
      if session.suggesting { return true }
      if session.busy || session.succeeded { return true }
      if session.naming, event.keyCode == 15, event.modifierFlags.contains(.command) { session.suggestName(); return true }
      if [36, 76].contains(event.keyCode) { session.presentation.activate(session.selectedID); return true }
      if [123,124,125,126,48].contains(event.keyCode), !session.naming, !(panel?.firstResponder is NSTextView) {
        session.selectedID = session.presentation.step.nextSelection(by: event.keyCode == 123 || event.keyCode == 126 ? -1 : 1)
        return true
      }
      return false
    }
    if state.executing?.definition?.output == .review && utilitySession == nil {
      if event.keyCode == 53 { dismiss() }
      return true
    }
    if askVisible {
      if let editor = panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
      if event.keyCode == 15, event.modifierFlags.contains(.command),
         !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.option),
         !event.modifierFlags.contains(.control) {
        refineAskPrompt()
        return true
      }
      if event.keyCode == 6, event.modifierFlags.contains(.command),
         !event.modifierFlags.contains(.option), !event.modifierFlags.contains(.control),
         let editor = panel?.firstResponder as? NSTextView {
        if let revision = askPromptRevision, !event.modifierFlags.contains(.shift), askQuery == revision.refined {
          askQuery = revision.original
        } else if let revision = askPromptRevision, event.modifierFlags.contains(.shift), askQuery == revision.original {
          askQuery = revision.refined
        } else if event.modifierFlags.contains(.shift) { editor.undoManager?.redo() }
        else { editor.undoManager?.undo() }
        return true
      }
      switch event.keyCode {
      case 53: backFromAsk(); return true
      case 36, 76:
        if event.modifierFlags.contains(.shift) { return false }
        submitAsk(); return true
      default: return false
      }
    }
    if clipboardVisible {
      if clipboardActionMenuPresented { return handleClipboardMenuKey(event) }
      if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
        if event.keyCode == 40 { beginClipboardEntryActions(); return true }
        if event.keyCode == 35 { toggleClipboardPin(); return true }
      }
      switch event.keyCode {
      case 53: backFromClipboard(); return true
      case 125, 126:
        let entries = clipboardEntries
        if !entries.isEmpty {
          let current = entries.firstIndex { $0.id == clipboardSelectedID } ?? 0
          clipboardSelectedID = entries[(current + (event.keyCode == 125 ? 1 : entries.count - 1)) % entries.count].id
        }
        return true
      case 36, 76: performClipboardPrimary(); return true
      case 8 where event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command:
        useClipboardEntry(paste: false); return true
      default: return false
      }
    }
    if homeVisible {
      switch event.keyCode {
      case 53: if actionPage > 0 { changeActionPage(by: -1) } else { dismiss() }; return true
      case 123, 124, 125, 126, 48:
        let available = homeActions.indices.filter { homeActions[$0].isAvailable }
        if let position = available.firstIndex(of: homeSelectedIndex), !available.isEmpty {
          let backwards = event.keyCode == 123 || event.keyCode == 126 || (event.keyCode == 48 && event.modifierFlags.contains(.shift))
          homeSelectedIndex = available[(position + (backwards ? available.count - 1 : 1)) % available.count]
        }
        return true
      case 36, 76:
        if homeActions.indices.contains(homeSelectedIndex) { runHomeAction(homeActions[homeSelectedIndex]) }
        return true
      default: return false
      }
    }
    if let choices = modeChoices {
      if choices.activityTitle != nil {
        if event.keyCode == 53 { dismiss() }
        return true
      }
      switch event.keyCode {
      case 53:
        if let query=choices.searchQuery,!query.isEmpty {choices.search?("")}
        else {choices.activate(nil)}
      case 123, 124, 125, 126, 48:
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        let backwards = event.keyCode == 123 || event.keyCode == 126 || (event.keyCode == 48 && event.modifierFlags.contains(.shift))
        choices.select(choices.step.nextSelection(by: backwards ? -1 : 1))
      case 36, 76: choices.activate(choices.step.selectedID)
      default:
        if choices.searchQuery != nil,
           !(panel?.firstResponder is NSTextView),
           event.modifierFlags.intersection([.command,.control,.function]).isEmpty,
           let characters=event.characters,!characters.isEmpty,
           characters.unicodeScalars.allSatisfy({!CharacterSet.controlCharacters.contains($0)}) {
          choices.search?((choices.searchQuery ?? "")+characters)
        } else {return false}
      }
      return true
    }
    if state.executing?.definition?.output == .readingCard || explanationText != nil {
      if event.keyCode == 15,
        event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
        beginResultRefinement()
        return true
      }
      if event.keyCode == 53 { closeExplanation(); return true }
      if event.keyCode == 8,
        event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command {
        copyExplanation()
        return true
      }
      // Enter never pastes an explanation. Arrow keys remain available to scroll.
      if [36, 76].contains(event.keyCode) { return true }
      return false
    }
    if state.executing?.definition?.transformsText == true {
      if event.keyCode == 53 { dismiss(); return true }
      if event.keyCode == 8, event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
        let text = correctionText { copyCalculation(text); dismiss(); return true }
      if [36, 76].contains(event.keyCode), let text = correctionText, selection?.canPaste == true,
        pasteMessage == nil { pasteCalculation(text); return true }
      return true
    }
    if calculatorValue != nil {
      if event.keyCode == 8,
        event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command
      {
        if let editor = panel?.firstResponder as? NSTextView,
          let result = CalculationExpression.resultForDisplay(editor.string)
        {
          copyCalculation(result.text)
        }
        return true
      }
      if event.keyCode == 53 {
        closeCalculator()
        return true
      }
      return false  // Text editing, arrows, Tab and shortcuts belong to the calculator.
    }
    if selection?.status == .permissionRequired, [36, 76].contains(event.keyCode) {
      openAccessibilitySettings()
      return true
    }
    guard selection?.hasSelection == true || fileContext != nil else {
      if event.keyCode == 53 {
        dismiss()
        return true
      }
      return false
    }
    if event.keyCode == 3,
       event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
       state.executing == nil {
      if !state.isSearching { beginActionSearch() }
      return true
    }
    if state.executing == nil, !state.isSearching {
      let actions = presentedActions
      switch event.keyCode {
      case 53: if actionPage > 0 { changeActionPage(by: -1) } else { dismiss() }; return true
      case 123, 124, 125, 126, 48:
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        let backward = event.keyCode == 123 || event.keyCode == 126 || (event.keyCode == 48 && event.modifierFlags.contains(.shift))
        actionSelection = (actionSelection + (backward ? actions.count - 1 : 1)) % actions.count
        return true
      case 36, 76: choosePresented(actions[min(actionSelection, actions.count - 1)]); return true
      default:
        if event.modifierFlags.contains(.command), let number = Int(event.charactersIgnoringModifiers ?? ""), (1...min(3, actions.count)).contains(number) {
          let modes = actions.filter { $0 != .native(.back) && $0 != .native(.more) && $0 != .native(.allActions) && $0 != .native(.search) }
          guard number <= modes.count else { return false }
          choosePresented(modes[number - 1]); return true
        }
        if event.modifierFlags.intersection([.command, .control, .function]).isEmpty,
          let characters = event.characters, !characters.isEmpty,
          characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
          beginActionSearch(query: characters)
          return true
        }
        return false
      }
    }
    if state.isSearching, state.executing == nil {
      // Let IMEs validate marked text before interpreting Return or arrow keys.
      if let editor = panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
      switch event.keyCode {
      case 53: endActionSearch()
      case 123, 124, 125, 126:
        // Plain arrows navigate results; modified arrows keep native text editing.
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        let actions = presentedActions
        if !actions.isEmpty { actionSelection = (actionSelection + (event.keyCode == 123 || event.keyCode == 126 ? actions.count - 1 : 1)) % actions.count }
      case 48:
        let actions = presentedActions
        if !actions.isEmpty { actionSelection = (actionSelection + (event.modifierFlags.contains(.shift) ? actions.count - 1 : 1)) % actions.count }
      case 36, 76:
        let actions = presentedActions
        if !actions.isEmpty { choosePresented(actions[min(actionSelection, actions.count - 1)]) }
      default:
        // Preserve fast typing during the single run-loop before the field attaches.
        if !(panel?.firstResponder is NSTextView),
          event.modifierFlags.intersection([.command, .control, .function]).isEmpty,
          let characters = event.characters, !characters.isEmpty,
          characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
          updateActionSearch(state.searchQuery + characters)
        } else {
          return false // Text editing and ⌘A/C/V stay native.
        }
      }
      return true
    }
    switch event.keyCode {
    case 53:
      if state.escape() { dismiss() } else { resizeActionRow() }
    case 123: state.move(by: -1)
    case 124: state.move(by: 1)
    case 36, 76: activate()
    case 48:
      guard state.executing == nil else { return true }
      let target: Action = state.page == .more ? .back : state.actions.contains(.more) ? .more : .search
      choose(target)
    default:
      if event.modifierFlags.contains(.command),
        let value = Int(event.charactersIgnoringModifiers ?? ""),
        (1...min(3, state.actions.count)).contains(value)
      {
        choose(state.actions[value - 1])
      } else if state.executing == nil,
        event.modifierFlags.intersection([.command, .control, .function]).isEmpty,
        let characters = event.characters, !characters.isEmpty,
        characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
        beginActionSearch(query: characters)
      } else {
        return false
      }
    }
    return true
  }

  private func startUtility(_ action: Action, text: String) {
    utilitySession?.cancel()
    utilitySession = SelectionUtilitySession(action: action, text: text, result: { [weak self] result in
      guard let self, !self.closing, self.state.executing == action else { return }
      self.utilitySession = nil
      self.showExplanation(result)
    }, back: { [weak self] in self?.backFromUtility() }, opened: { [weak self] in self?.closeExplanation() })
    utilitySession?.start()
    updateUtilityPresentation()
  }

  func backFromUtility() {
    utilitySession?.cancel(); utilitySession = nil
    state.returnFromOptions(); resizeActionRow()
  }

  func updateUtilityPresentation() {
    guard let panel, let session = utilitySession else { return }
    let searching = session.presentation.searchQuery != nil
    let width: CGFloat = session.message != nil ? 340 : max(searching ? 280:180, session.presentation.rowWidth + (session.choosingDate ? 128 : 0))
    let height: CGFloat = session.message != nil ? 118 : session.busy ? 30 : (searching ? 68 : 30) + 6 + ModeHint.height(for: session.label, width: min(380, width))
    setPanelFrame(width: width + 2 * PanelPlacement.contentInset, height: height + 2 * PanelPlacement.contentInset, centered: true)
    if session.choosingDate || searching { panel.makeKeyAndOrderFront(nil) }
  }

  private func startExplanation(_ text: String) {
    guard let definition = state.executing?.definition, definition.output == .readingCard else { return }
    startReading(text, action: "explain", language: ResponseLanguage.load(), context: ReplyContext(invocationContext))
  }

  private func startReading(_ text: String, action: String, language: ResponseLanguage? = nil,
                            context: ReplyContext? = nil, intent: ReplyIntent? = nil, fileContext: InvocationContext? = nil, style: TextStyle? = nil, refinement: String? = nil) {
    let habitOwner = AccountStore.shared.user?.id
    correctionTask?.cancel()
    let id = intent != nil ? (correctionID ?? UUID()) : UUID()
    correctionID = id
    allowanceReached = false
    signInRequired = false
    correctionMessage = nil
    readingInProgress = true
    readingError = nil
    if action == "result_refine" { resizeReadingCard(explanationText ?? text) }
    else if askMode { showExplanation("") }
    else { explanationText = "" }
    correctionTask = Task { [weak self] in
      do {
        guard let self, self.correctionID == id else { return }
        guard let credential = await GatewayAccess.credential() else {
          throw CorrectionClient.Failure.unavailable
        }
        if action == "text_habit", habitOwner != AccountStore.shared.user?.id { self.dismiss(restoreFocus: false); return }
        var file: FileSummaryInput?
        if let fileContext, let url = fileContext.files.first?.url {
          let reader = FinderSelectionReader()
          guard try await reader.validates(fileContext),
                fileContext.fileOrigin != .finder || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            throw FileSummaryReader.Failure.unsupported
          }
          file = try await FileSummaryReader().prepare(url)
          try Task.checkCancellation()
          guard self.correctionID == id else { return }
        }
        let answer = try await CorrectionClient().reading(text, action: action, language: language,
          context: context, intent: intent, requestID: id, credential: credential, update: { [weak self] text in
            guard !Task.isCancelled, let self, self.correctionID == id, !self.closing else { return }
            if action == "text_habit", habitOwner != AccountStore.shared.user?.id { return }
            if self.explanationText?.isEmpty == true && !self.askMode { self.showExplanation(text) }
            else { self.explanationText = text }
            self.resizeReadingCard(text)
          }, file: file, style: style, refinement: refinement)
        guard !Task.isCancelled, self.correctionID == id else { return }
        if action == "text_habit", habitOwner != AccountStore.shared.user?.id { self.dismiss(restoreFocus: false); return }
        if self.explanationText?.isEmpty == true && !self.askMode { self.showExplanation(answer) }
        else { self.explanationText = answer }
        self.readingInProgress = false
        if action == "result_refine" { self.resultBeforeRefinement = nil }
        self.resizeReadingCard(answer)
      } catch {
        guard !Task.isCancelled, let self, self.correctionID == id else { return }
        if self.handleAllowanceFailure(error) { return }
        self.readingInProgress = false
        // Partial output remains visible, but can never be copied as a complete result.
        if self.explanationText?.isEmpty == true && !self.askMode { self.showExplanation("") }
        self.readingError = action == "ask" && (error as? CorrectionClient.Failure) == .tooLong
          ? "Ask a shorter question (up to 4,000 characters)."
          : (error as? CorrectionClient.Failure) == .invalid
            ? "Couldn't finish this answer. Try again."
            : (error as? CorrectionClient.Failure)?.errorDescription ?? (error as? FileSummaryReader.Failure)?.errorDescription ?? (error as? LocalFileIO.Failure)?.errorDescription ?? "The request failed. Try again in a moment."
        self.resizeReadingCard((self.explanationText ?? "") + "\n\n" + (self.readingError ?? ""))
      }
    }
  }

  private func startReplyOptions(_ text: String) {
    let id = UUID()
    correctionID = id
    replyContext = ReplyContext(invocationContext ?? selection?.context)
    let context = replyContext
    correctionTask?.cancel()
    correctionTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(280))
        guard let self, self.correctionID == id else { return }
        guard let credential = await GatewayAccess.credential() else { throw CorrectionClient.Failure.unavailable }
        let intents = try await CorrectionClient().replyOptions(text, context: context, requestID: id, credential: credential)
        guard !Task.isCancelled, self.correctionID == id else { return }
        self.replyIntentIndex = 0
        self.replyIntents = intents
      } catch {
        guard !Task.isCancelled, let self, self.correctionID == id else { return }
        if self.handleAllowanceFailure(error) { return }
        self.showCorrectionMessage((error as? CorrectionClient.Failure)?.errorDescription ?? "The request failed. Try again in a moment.")
      }
    }
  }

  func backFromReply() {
    guard !replyIntents.isEmpty, !replyDrafting else { return }
    correctionTask?.cancel()
    correctionID = nil
    replyIntents = []
    replyContext = nil
    state.returnFromOptions()
    resizeActionRow()
  }

  func chooseReplyIntent(_ intent: ReplyIntent) {
    guard !replyDrafting, replyIntents.contains(intent), case .selected(let text) = selection?.status else { return }
    replyIntentIndex = replyIntents.firstIndex(of: intent) ?? 0
    replyDrafting = true
    startCorrection(text, replyIntent: intent)
  }

  private func startCommitmentPlan(_ text: String, destination: CommitmentDestination) {
    correctionTask?.cancel()
    let id = UUID(); correctionID = id
    correctionTask = Task { [weak self] in
      do {
        guard let credential = await GatewayAccess.credential() else { throw CorrectionClient.Failure.unavailable }
        let drafts = try await CorrectionClient().plan(text, destination: destination, context: ReplyContext(self?.invocationContext), requestID: id, credential: credential)
        guard !Task.isCancelled, let self, self.correctionID == id, !self.closing else { return }
        let session = CommitmentSession(drafts, destination: destination)
        self.commitmentSession = session
        self.updateCommitmentPresentation()
      } catch {
        guard !Task.isCancelled, let self, self.correctionID == id, !self.closing else { return }
        if self.handleAllowanceFailure(error) { return }
        self.showCorrectionMessage((error as? CorrectionClient.Failure)?.errorDescription ?? "Couldn't prepare drafts. Try again.")
      }
    }
  }

  func closeCommitmentReview(_ session: CommitmentSession) {
    guard commitmentSession === session else { return }
    closeExplanation()
  }

  func openCommitmentSettings() {
    guard let session = commitmentSession, session.needsSettings, !closing else { return }
    session.beganSettingsVisit()
    if !NSWorkspace.shared.open(session.settingsURL) {
      NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?" + (session.destination == .reminders ? "Privacy_Reminders" : "Privacy_Calendars"))!)
    }
  }

  func updateCommitmentPresentation() {
    guard let panel, let session = commitmentSession else { return }
    let height: CGFloat = session.rows.isEmpty ? 110 : session.reviewHeight + 98 + 2 * PanelPlacement.contentInset + (session.message == nil ? 0 : 36) + (session.needsSettings ? 24 : 0)
    setPanelFrame(width: 380 + 2 * PanelPlacement.contentInset, height: height, centered: true)
    panel.makeKeyAndOrderFront(nil)
  }

  /// Last measured reading text. Streaming re-measures on every chunk, and the final
  /// answer is often measured twice; once the card reaches its height cap, a longer
  /// continuation of the same text cannot shrink it.
  @ObservationIgnored private var readingHeightCache: (text: String, height: CGFloat)?

  private func readingContentHeight(_ text: String) -> CGFloat {
    if let cache = readingHeightCache {
      if cache.text == text { return cache.height }
      if cache.height >= Self.readingContentMaxHeight, text.hasPrefix(cache.text) { return cache.height }
    }
    let height = Self.measureReadingContent(text)
    readingHeightCache = (text, height)
    return height
  }

  private static let readingContentMaxHeight: CGFloat = 200

  private static func measureReadingContent(_ text: String) -> CGFloat {
    let parsed = (try? AttributedString(markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    let value = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
    let style = NSMutableParagraphStyle()
    style.lineSpacing = 4
    value.addAttributes([.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: style],
      range: NSRange(location: 0, length: value.length))
    let storage = NSTextStorage(attributedString: value)
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: 332, height: CGFloat.greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    layout.ensureLayout(for: container)
    return min(readingContentMaxHeight, max(22, ceil(layout.usedRect(for: container).height) + 2))
  }

  private func readingCardContentHeight(_ text: String) -> CGFloat {
    let responseHeight = readingContentHeight(text)
    guard askMode, let preview = askQuestionPreview else { return responseHeight }
    // Match the two-line, 12-point request preview; it must not take space away
    // from the progressively appearing answer in the same scroll view.
    let previewHeight = (preview as NSString).boundingRect(
      with: CGSize(width: 332, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: NSFont.systemFont(ofSize: 12)]).height
    return responseHeight + min(32, ceil(previewHeight)) + 10
  }

  private func resizeReadingCard(_ text: String) {
    guard let panel, explanationText != nil else { return }
    let height = readingCardContentHeight(text)
    explanationContentHeight = height
    let extra = refiningResult ? askEditorHeight + AskInputView.refinementChrome : 0
    let total = height + ExplanationView.verticalChrome + extra + 2 * PanelPlacement.contentInset
    guard abs(total - panel.frame.height) > 0.5 else { return }
    setPanelFrame(height: total)
  }

  private func showExplanation(_ text: String) {
    guard panel != nil else { return }
    explanationText = text
    readingCardKeepsOpen = false
    explanationContentHeight = text.isEmpty && readingInProgress ? 42 : readingCardContentHeight(text)
    setPanelFrame(width: 360 + 2 * PanelPlacement.contentInset,
                  height: explanationContentHeight + ExplanationView.verticalChrome + 2 * PanelPlacement.contentInset,
                  centered: true, animate: false)
    // The card owns its reveal; an outer transition would move the loading row
    // while the panel grows and could animate later copy feedback.
  }

  func openExplanationLink(_ url: URL) {
    guard explanationText != nil, !closing,
          ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
          url.host != nil, url.user == nil, url.password == nil else { return }
    // Opening a source deliberately activates the browser. Keep this result
    // available until explicit close, rather than treating that activation as dismissal.
    readingCardKeepsOpen = true
    NSWorkspace.shared.open(url)
  }

  func copyExplanation() {
    guard let text = explanationText, !text.isEmpty, !readingInProgress, readingError == nil, !closing else { return }
    guard Self.writeToPasteboard(text) else { return }
    GatewayAccess.event("result_copied", mode: state.executing?.rawValue)
    flashShortcut("⌘C")
  }

  func closeExplanation() {
    guard closingTask == nil else { return }
    correctionTask?.cancel()
    correctionID = nil
    closing = true
    closingTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
      self?.dismiss()
    }
  }

  func backFromVideoDownload() {
    videoDownload?.cancel(); videoDownload = nil
    state.returnFromOptions(); resizeActionRow()
  }
  func updateVideoDownloadPresentation() {
    guard let session = videoDownload, panel != nil else { return }
    let choices = session.presentation
    let hint = session.message ?? session.hint
    let height: CGFloat = 54 + ModeHint.height(for: hint) + 8 + (session.busy ? 14 : 0)
    setPanelFrame(width: max(440, choices.rowWidth + 2 * PanelPlacement.contentInset), height: height, centered: true)
    if panel?.isKeyWindow == false { panel?.makeKeyAndOrderFront(nil) }
  }

  func backFromFileWorkflow() {
    fileWorkflow?.cancel(); fileWorkflow = nil
    state.returnFromOptions(); resizeActionRow()
  }
  func updateFileWorkflowPresentation() {
    if fileWorkflow?.requiresSignIn == true { showAllowanceReached(needsSignIn: true); return }
    if fileWorkflow?.requiresAccount == true { showAllowanceReached(); return }
    if allowanceReached { return }
    guard let session = fileWorkflow, let panel else { return }
    if session.succeeded {
      if closingTask == nil {
        closingTask = Task { [weak self, weak session] in
          do { try await Task.sleep(for: .milliseconds(650)) } catch { return }
          guard let self, self.fileWorkflow === session else { return }
          self.closing = true
          do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
          self.dismiss(restoreFocus: false)
        }
      }
      return
    }
    guard !session.busy else { return }
    var height: CGFloat = 54 + (session.detailsHeight > 0 ? session.detailsHeight + 8 : 0)
    if !session.hint.isEmpty && !session.suggesting { height += ModeHint.height(for: session.hint) + 8 }
    if let message = session.message { height += ModeHint.height(for: message) + 8 }
    setPanelFrame(width: 452, height: height)
    if !panel.isKeyWindow { panel.makeKeyAndOrderFront(nil) }
  }

  func backFromTranslation() {
    guard choosingTranslationLanguage else { return }
    choosingTranslationLanguage = false
    translationBackSelected = false
    state.returnFromOptions()
    resizeActionRow()
  }

  func translateSelection(to language: ResponseLanguage) {
    guard choosingTranslationLanguage, case .selected(let text) = selection?.status else { return }
    choosingTranslationLanguage = false
    translationTarget = language
    language.saveTranslationTarget()
    startCorrection(text, translation: language)
  }

  private func startCorrection(_ text: String, translation: ResponseLanguage? = nil, replyIntent: ReplyIntent? = nil, style: TextStyle? = nil, letterCase: LocalTextTransform? = nil, habit: TextHabit? = nil, instruction: String? = nil) {
    // A saved habit and a selection Ask share the gateway's selection + instruction contract.
    let instruction = habit?.instruction ?? instruction
    guard let action = state.executing, let definition = ActionCatalog.definition(for: action),
          definition.transformsText else { return }
    guard definition.executor != .reply || replyIntent != nil else { return }
    let localText = definition.executor == .cleanFormatting ? LocalTextTransform.clean(text)
      : definition.executor == .changeCase ? letterCase?.apply(text) : nil
    if let localText, localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      showCorrectionMessage("Nothing to format")
      return
    }
    if definition.delivery(canReplace: selection?.canPaste == true) == .readingCard {
      if let localText { showExplanation(localText) }
      else if let instruction { startReading(text, action: "text_habit", refinement: instruction) }
      else if let gatewayAction = definition.gatewayAction {
        startReading(text, action: gatewayAction, language: translation, context: replyContext, intent: replyIntent, style: style)
      }
      return
    }
    let id = replyIntent != nil ? (correctionID ?? UUID()) : UUID()
    correctionID = id
    correctionFinished = false
    correctionText = nil
    allowanceReached = false
    signInRequired = false
    correctionMessage = nil
    let habitOwner = AccountStore.shared.user?.id
    let context = replyContext
    correctionTask?.cancel()
    correctionTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .milliseconds(280))
        guard let self, self.correctionID == id else { return }
        let corrected: String
        if let localText { corrected = localText }
        else {
          guard let credential = await GatewayAccess.credential() else { throw CorrectionClient.Failure.unavailable }
          if let instruction {
            guard habitOwner == AccountStore.shared.user?.id else { self.dismiss(restoreFocus: false); return }
            corrected = try await CorrectionClient().reading(text, action: "text_habit", requestID: id, credential: credential, update: { _ in }, refinement: instruction)
            guard habitOwner == AccountStore.shared.user?.id else { self.dismiss(restoreFocus: false); return }
          } else if let replyIntent {
            corrected = try await CorrectionClient().reply(text, context: context, intent: replyIntent, requestID: id, credential: credential)
          } else if let translation {
            corrected = try await CorrectionClient().translate(text, language: translation, requestID: id, credential: credential)
          } else if definition.executor == .extractTasks {
            corrected = try await CorrectionClient().extractTasks(text, requestID: id, credential: credential)
          } else if definition.executor == .keyPoints {
            corrected = try await CorrectionClient().keyPoints(text, requestID: id, credential: credential)
          } else if [.rewrite, .tone, .simplify, .improvePrompt].contains(definition.executor), let gatewayAction = definition.gatewayAction {
            corrected = try await CorrectionClient().transform(text, action: gatewayAction, style: style, requestID: id, credential: credential)
          } else {
            corrected = try await CorrectionClient().correct(text, requestID: id, credential: credential)
          }
        }
        guard !Task.isCancelled, self.correctionID == id else { return }
        let delivery: ActionDefinition.Delivery = self.clipboardActionEntryID != nil ? .readingCard : definition.delivery(canReplace: self.selection?.canPaste == true)
        let shouldCopy = delivery == .clipboard
        // The gateway's fixed empty-state message is informational, never replacement text.
        let noTasks = definition.executor == .extractTasks && corrected == "No tasks found."
        if delivery == .readingCard || noTasks {
          // Reading context: show the result without writing the clipboard.
          // Copy is explicit through the result card, and Return never pastes it.
          self.showExplanation(corrected)
          return
        }
        if shouldCopy {
          self.correctionText = corrected
          // Read-only or unconfirmed editability: deliver the transformed text
          // to the clipboard, without sending any keystroke to the source app.
          guard Self.writeToPasteboard(corrected) else {
            self.showCorrectionMessage("Copy failed · ⌘C to try again")
            return
          }
        }
        if shouldCopy || corrected == text {
          // Also copy unchanged read-only text so it can be used elsewhere.
          self.correctionFinished = true
          try await Task.sleep(for: .milliseconds(320))
          guard self.correctionID == id else { return }
          self.closing = true
          try await Task.sleep(for: .milliseconds(180))
          guard self.correctionID == id else { return }
          self.dismiss()
          return
        }
        self.correctionText = corrected
        self.pasteCalculation(corrected)
      } catch {
        guard !Task.isCancelled, let self, self.correctionID == id else { return }
        if self.handleAllowanceFailure(error) { return }
        self.showCorrectionMessage((error as? CorrectionClient.Failure)?.errorDescription
          ?? "The request failed. Your text is unchanged.")
      }
    }
  }

  func openAllowanceAccount() {
    // Both cases lead to Settings → AI: connect a provider, or see the Tero Pro option there.
    dismiss(restoreFocus: false)
    NSApp.sendAction(Selector(("showAISettings")), to: NSApp.delegate, from: nil)
  }

  private func showAllowanceReached(needsSignIn: Bool = false) {
    // Without an own key or a Pro plan, the only useful next step is connecting a provider.
    signInRequired = needsSignIn || (!GatewayAccess.usesOwnKey && AccountStore.shared.usage?.plan != "pro")
    cancelAskRefinement()
    readingInProgress = false
    allowanceReached = true
    setPanelFrame(width: 388, height: 230)
  }

  private func showCorrectionMessage(_ message: String) {
    correctionMessage = message
    setPanelFrame(height: correctionText == nil ? 88 : 142)
  }

  // MARK: - Shared feedback helpers

  /// Briefly highlights a keyboard shortcut chip, replacing any pending highlight.
  private func flashShortcut(_ shortcut: String, for duration: Duration = .milliseconds(650),
                             clearingClipboardMessage: Bool = false) {
    activeShortcut = shortcut
    feedbackTask?.cancel()
    feedbackTask = Task { [weak self] in
      do { try await Task.sleep(for: duration) } catch { return }
      self?.activeShortcut = nil
      if clearingClipboardMessage { self?.clipboardMessage = nil }
    }
  }

  private static func writeToPasteboard(_ text: String) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
  }

  /// Presents the sign-in or allowance card for gateway access failures.
  /// Returns `true` when the error was handled.
  private func handleAllowanceFailure(_ error: Error) -> Bool {
    switch error as? CorrectionClient.Failure {
    case .unavailable: showAllowanceReached(needsSignIn: true); return true
    case .allowanceReached: showAllowanceReached(); return true
    default: return false
    }
  }

  /// Resizes the panel while keeping its top edge anchored, then keeps it inside the
  /// screen's visible area. A width change can also preserve the horizontal centre.
  private func setPanelFrame(width: CGFloat? = nil, height: CGFloat, centered: Bool = false,
                             display: Bool = false, animate: Bool? = nil) {
    guard let panel else { return }
    var frame = panel.frame
    if let width {
      if centered { frame.origin.x -= (width - frame.width) / 2 }
      frame.size.width = width
    }
    frame.origin.y -= height - frame.height
    frame.size.height = height
    if let safe = panel.screen?.visibleFrame.insetBy(dx: 8, dy: 8) {
      if width != nil { frame.origin.x = min(max(frame.minX, safe.minX), safe.maxX - frame.width) }
      frame.origin.y = min(max(frame.minY, safe.minY), safe.maxY - frame.height)
    }
    if let animate { panel.setFrame(frame, display: display, animate: animate) }
    else { panel.setFrame(frame, display: display) }
  }

  func closeCalculator() {
    guard calculatorValue != nil, closingTask == nil, !isPasting else { return }
    feedbackTask?.cancel()
    activeShortcut = "esc"
    closingTask = Task { [weak self] in
      do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      guard let self else { return }
      self.closing = true
      do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
      self.dismiss()
    }
  }

  func dismiss(restoreFocus: Bool = true) {
    if panel?.isVisible == true { GatewayAccess.event("panel_closed") }
    if invocationOpening { cancelCapture(); return }
    fileWorkflow?.cancel(); fileWorkflow = nil
    videoDownload?.cancel(); videoDownload = nil
    utilitySession?.cancel()
    utilitySession = nil
    commitmentSession?.cancel()
    commitmentSession = nil
    guard !clipboardDragging else { return }
    guard panel?.isVisible == true || isPasting || clipboardVisible else { return }
    closeClipboardEntryMenu()
    clipboardTransition?.cancel(); clipboardTransition = nil
    clipboardPresented = false; clipboardClosing = false
    clipboardActionEntryID = nil
    if let workspace = clipboardWorkspace { try? FileManager.default.removeItem(at: workspace) }
    clipboardWorkspace = nil
    clipboardStore?.browsing = false
    clipboardVisible = false
    clipboardQuery = ""
    clipboardSelectedID = nil
    clipboardMessage = nil
    homeVisible = false
    homeSelectedIndex = 0
    fileContext = nil
    correctionTask?.cancel()
    correctionTask = nil
    correctionID = nil
    correctionFinished = false
    choosingTranslationLanguage = false
    choosingTextOptions = false
    selectedTextOption = nil
    refiningResult = false
    resultBeforeRefinement = nil
    previousQuestionPreview = nil
    replyIntents = []
    replyIntentIndex = 0
    replyDrafting = false
    replyContext = nil
    explanationText = nil
    readingHeightCache = nil
    readingCardKeepsOpen = false
    explanationContentHeight = 80
    shoppingSession?.cancel(); shoppingSession = nil
    askVisible = false
    askMode = false
    selectionAskMode = nil
    askQuery = ""
    cancelAskRefinement()
    askQuestionPreview = nil
    askPromptRevision = nil
    readingInProgress = false
    readingError = nil
    correctionText = nil
    allowanceReached = false
    signInRequired = false
    correctionMessage = nil
    textHabitTitle = nil
    actionRecommendations = []; actionSelection = 0; actionPage = 0
    closingTask?.cancel()
    closingTask = nil
    feedbackTask?.cancel()
    feedbackTask = nil
    closing = false
    activeShortcut = nil
    noticeDismissal?.cancel()
    noticeDismissal = nil
    execution?.cancel()
    execution = nil
    pasteTask?.cancel()
    pasteTask = nil
    let targetID = selection?.targetID
    Task { [selectionEngine] in await selectionEngine.clearTarget(targetID) }
    let source = sourceApplication
    sourceApplication = nil
    panel?.orderOut(nil)
    appeared = false
    isPasting = false
    pasteMessage = nil
    state = ActionBarState()
    selection = nil
    invocationContext = nil
    calculatorValue = nil
    if restoreFocus, let source, !source.isTerminated,
      NSWorkspace.shared.frontmostApplication?.processIdentifier != source.processIdentifier
    {
      source.activate(options: [])
    }
  }

  func copyCalculation(_ text: String) {
    guard Self.writeToPasteboard(text), calculatorValue != nil, !isPasting, !closing else { return }
    flashShortcut("⌘C")
  }

  func pasteCalculation(_ text: String) {
    guard !isPasting, !closing, closingTask == nil, let original = selection, original.canPaste,
      let source = sourceApplication, !source.isTerminated
    else { return }
    isPasting = true
    pasteMessage = nil
    feedbackTask?.cancel()
    activeShortcut = "↵"
    pasteTask = Task { [weak self, selectionEngine] in
      do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
      guard let self else { return }
      let isCorrection = self.state.executing?.definition?.transformsText == true
      if !isCorrection {
        self.closing = true
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
      }
      let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
      guard frontPID == source.processIdentifier || frontPID == ProcessInfo.processInfo.processIdentifier else {
        self.dismiss(restoreFocus: false)
        return
      }
      if isCorrection {
        // Hand back keyboard focus without hiding the window: ordering it out
        // suspends the activity view while the source app is being validated.
        self.panel?.resignKey()
      } else {
        self.panel?.orderOut(nil)
      }
      source.activate(options: [])
      for _ in 0..<10 {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier {
          break
        }
        do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
      }
      guard !Task.isCancelled else { return }
      let valid = await selectionEngine.validatesPasteTarget(original)
      guard !Task.isCancelled else { return }
      guard valid, AXIsProcessTrusted(),
        NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier,
        let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
        let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false)
      else {
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == source.processIdentifier {
          self.isPasting = false
          self.closing = false
          self.activeShortcut = nil
          self.pasteMessage =
            "The selection changed or cannot be replaced. Copy the result."
          if self.state.executing?.definition?.transformsText == true {
            self.showCorrectionMessage("Selection changed · ⌘C to copy the result")
          }
          self.panel?.makeKeyAndOrderFront(nil)
        } else {
          self.dismiss(restoreFocus: false)
        }
        return
      }
      // Use the source app's native paste command so its normal undo mechanism applies.
      guard Self.writeToPasteboard(text) else {
        self.isPasting = false
        self.closing = false
        self.activeShortcut = nil
        self.pasteMessage = "Could not prepare the paste. Try copying the result."
        if self.state.executing?.definition?.transformsText == true { self.showCorrectionMessage(self.pasteMessage!) }
        self.panel?.makeKeyAndOrderFront(nil)
        return
      }
      down.flags = .maskCommand
      up.flags = .maskCommand
      down.postToPid(source.processIdentifier)
      up.postToPid(source.processIdentifier)
      if isCorrection {
        // Morph the still-visible ribbon; never swap or reopen the activity view.
        self.correctionFinished = true
        do { try await Task.sleep(for: .milliseconds(320)) } catch { return }
        self.closing = true
        do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
      }
      self.dismiss(restoreFocus: false)
    }
  }

  func openAccessibilitySettings() {
    dismiss(restoreFocus: false)
    let options =
      [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    AXIsProcessTrustedWithOptions(options)
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  func windowDidResignKey(_ notification: Notification) {
    guard !invocationOpening && !isPasting && !clipboardDragging else { return }
    guard commitmentSession?.busy != true, commitmentSession?.waitingForSettings != true else { return }
    guard fileWorkflow == nil, videoDownload == nil else { return }
    guard !(readingCardKeepsOpen && explanationText != nil) else { return }
    // Keep interactive windows and reading cards, regardless of the source surface.
    // The action bubbles (including Home and search) remain transient.
    guard !askVisible, shoppingSession == nil, !clipboardVisible,
          explanationText == nil, commitmentSession == nil else { return }
    dismiss(restoreFocus: false)
  }
}
