enum Action: String, CaseIterable, Identifiable, Sendable {
  case shop, askSelection, renameFile, batchRename, moveFiles, downloadVideo, openMaps, directions, convertUnits, convertCurrencies, convertTimeZones, checkClaim, tone, simplify, improvePrompt, cleanFormatting, changeCase, calculate, rewrite, explain, translate, more, keyPoints, extractTasks, fix, reply, summarizeFile, createTasks, createEvent, search, back, allActions

  var id: Self { self }
  var definition: ActionDefinition? { ActionCatalog.definition(for: self) }
  var title: String {
    if let definition = ActionCatalog.definition(for: self) { return definition.title }
    switch self {
    case .more: return "•••"
    case .search: return "Search"
    case .allActions: return "See more"
    case .back: return "←"
    case .rewrite: return "Rewrite"
    case .keyPoints: return "Key points"
    default: return rawValue
    }
  }
  var accessibilityLabel: String {
    switch self {
    case .more: "More actions"
    case .back: "Back to main actions"
    case .search: "Search actions"
    default: title
    }
  }
}

/// Shared native action contract. Descriptors are data; only registered executors run code.
struct ActionDefinition: Equatable, Sendable {
  enum Input: Sendable { case fileWorkflow, text, number, readableFile, videoLink, place, quantity, currency, zonedTime }
  enum Options: Sendable { case place, unit, currency, timeZone, none, expression, targetLanguage, replyIntent, textStyle, letterCase }
  enum Executor: Sendable { case shop, askSelection, fileWorkflow, openMaps, directions, units, currencies, timeZones, checkClaim, calculator, correct, explain, translate, rewrite, keyPoints, extractTasks, reply, fileSummary, videoDownload, taskPlan, eventPlan, tone, simplify, improvePrompt, cleanFormatting, changeCase }
  enum Output: Sendable { case calculator, readingCard, replaceOrCopy, replaceOrRead, review }
  enum Delivery: Sendable { case interactive, readingCard, replacement, clipboard }
  let id: Action
  let title: String
  let input: Input
  let options: Options
  let executor: Executor
  let output: Output
  let writingPriority: Int
  let readingPriority: Int
  let numericPriority: Int?

  func accepts(_ context: RecommendationContext) -> Bool {
    if input == .fileWorkflow {
      return context.source.map { $0.hasActionableFiles && !$0.isClipboardImage && workflowKind?.accepts($0.files) == true } == true
    }
    if input == .readableFile {
      return context.source.map { $0.hasActionableFiles && FileSummaryReader.accepts($0.files) } == true
    }
    guard case .text(let isNumber, _) = context.content else { return false }
    switch input {
    case .place: return context.selectionText.flatMap(SelectedAddress.query) != nil
    case .quantity: return context.selectionText.flatMap(UnitQuantity.parse) != nil
    case .currency: return context.selectionText.flatMap(CurrencyQuantity.parse) != nil
    case .zonedTime: return context.selectionText.flatMap(SelectedTime.parse) != nil
    case .videoLink: return context.selectionText.flatMap(VideoLink.youtube) != nil
    default: break
    }
    return input == .text || isNumber
  }

  func priority(in context: RecommendationContext) -> Int? {
    if input == .fileWorkflow || input == .readableFile { return accepts(context) ? readingPriority : nil }
    guard accepts(context), case .text(let isNumber, let editable) = context.content else { return nil }
    if input == .place { return context.selectionText.map(SelectedAddress.looksLikeAddress) == true ? 105 : 5 }
    if [.quantity, .currency, .zonedTime].contains(input) { return isNumber ? numericPriority : 110 }
    if input == .videoLink { return 120 }
    if isNumber { return numericPriority }
    return editable == true ? writingPriority : readingPriority
  }

  func delivery(canReplace: Bool) -> Delivery {
    switch output {
    case .calculator, .review: return .interactive
    case .readingCard: return .readingCard
    case .replaceOrCopy: return canReplace ? .replacement : .clipboard
    case .replaceOrRead: return canReplace ? .replacement : .readingCard
    }
  }

  var usesAI: Bool {
    switch executor {
    case .shop, .askSelection, .checkClaim, .correct, .explain, .translate, .rewrite, .keyPoints, .extractTasks, .reply, .fileSummary, .taskPlan, .eventPlan, .tone, .simplify, .improvePrompt: true
    case .fileWorkflow: [.rename, .batchRename].contains(workflowKind)
    case .openMaps, .directions, .units, .currencies, .timeZones, .calculator, .videoDownload, .cleanFormatting, .changeCase: false
    }
  }

  var searchTerms: [String] {
    switch executor {
    case .fileWorkflow: workflowKind?.searchTerms ?? [title]
    case .openMaps: ["map", "maps", "address", "location", "adresse", "carte"]
    case .directions: ["route", "directions", "navigate", "itineraire", "destination"]
    case .units: ["unit", "units", "distance", "temperature", "weight", "volume", "unites", "poids"]
    case .currencies: ["currency", "currencies", "exchange", "eur", "usd", "devise", "taux"]
    case .timeZones: ["time", "timezone", "time zones", "est", "utc", "fuseau", "heure"]
    case .shop: ["shop", "shopping", "buy", "product", "acheter", "achat", "produit", "clavier", "keyboard"]
    case .askSelection: ["ask", "question", "prompt", "custom", "write", "explain", "demander", "ecrire", "instruction"]
    case .checkClaim: ["fact check", "claim", "verify", "sources", "verifier", "affirmation"]
    case .taskPlan: ["reminders", "todo", "task", "rappels", "taches", "commitments"]
    case .eventPlan: ["calendar", "event", "meeting", "calendrier", "rendez-vous"]
    case .reply: ["respond", "answer", "repondre", "reponse"]
    case .calculator: ["calculator", "math", "calcul", "calculer"]
    case .videoDownload: ["youtube", "video", "download", "mp4", "mp3", "audio", "music", "telecharger", "musique"]
    case .fileSummary: ["summary", "summarize", "pdf", "image", "document", "resumer", "resume", "expliquer"]
    case .correct: ["fix", "spelling", "grammar", "typo", "corriger", "orthographe", "fautes"]
    case .explain: ["understand", "meaning", "expliquer", "comprendre"]
    case .translate: ["translation", "language", "traduire", "traduction", "langue"]
    case .rewrite: ["rephrase", "reformuler", "reecrire"]
    case .tone: ["warm", "direct", "diplomatic", "friendly", "ton", "diplomatique"]
    case .improvePrompt: ["prompt", "reprompt", "instructions", "prompt engineering", "ameliorer prompt"]
    case .simplify: ["simple", "plain language", "simplifier", "accessible"]
    case .cleanFormatting: ["clean", "format", "whitespace", "nettoyer", "espaces"]
    case .changeCase: ["uppercase", "lowercase", "title case", "majuscules", "minuscules", "casse"]
    case .keyPoints: ["summary", "summarize", "resumer", "resume", "synthese", "points cles"]
    case .extractTasks: ["tasks", "todo", "to do", "action items", "taches", "extraire"]
    }
  }

  var gatewayAction: String? {
    switch executor {
    case .correct: "fix"
    case .rewrite: "rewrite"
    case .tone: "tone"
    case .simplify: "simplify"
    case .improvePrompt: "improve_prompt"
    case .keyPoints: "key_points"
    case .extractTasks: "extract_tasks"
    case .translate: "translate"
    case .reply: "reply"
    default: nil
    }
  }

  var workflowKind: FileWorkflowKind? {
    switch id {
    case .renameFile: .rename
    case .batchRename: .batchRename
    case .moveFiles: .move
    default: nil
    }
  }
  /// The ranking service only scores actions it knows; local-only actions keep their local priority.
  var rankedOnServer: Bool { executor != .videoDownload && executor != .askSelection }
  /// Ask AI stays the third bubble whatever the semantic ranking says.
  var pinnedSlot: Int? { executor == .askSelection ? 2 : nil }
  var transformsText: Bool { output == .replaceOrCopy || output == .replaceOrRead }
}

enum ActionCatalog {
  static let definitions: [ActionDefinition] = [
    .init(id: .shop, title: "Ask", input: .text, options: .none, executor: .shop, output: .review, writingPriority: 15, readingPriority: 15, numericPriority: nil),
    .init(id: .askSelection, title: "Ask AI", input: .text, options: .none, executor: .askSelection, output: .replaceOrRead, writingPriority: 45, readingPriority: 45, numericPriority: nil),
    .init(id: .renameFile, title: "Rename", input: .fileWorkflow, options: .none, executor: .fileWorkflow, output: .review, writingPriority: 50, readingPriority: 50, numericPriority: nil),
    .init(id: .batchRename, title: "Batch rename", input: .fileWorkflow, options: .none, executor: .fileWorkflow, output: .review, writingPriority: 50, readingPriority: 50, numericPriority: nil),
    .init(id: .moveFiles, title: "Move files", input: .fileWorkflow, options: .none, executor: .fileWorkflow, output: .review, writingPriority: 50, readingPriority: 50, numericPriority: nil),
    .init(id: .downloadVideo, title: "Download video", input: .videoLink, options: .none, executor: .videoDownload, output: .review, writingPriority: 120, readingPriority: 120, numericPriority: nil),
    .init(id: .openMaps, title: "Open in Maps", input: .place, options: .place, executor: .openMaps, output: .review, writingPriority: 5, readingPriority: 5, numericPriority: nil),
    .init(id: .directions, title: "Get directions", input: .place, options: .place, executor: .directions, output: .review, writingPriority: 5, readingPriority: 5, numericPriority: nil),
    .init(id: .convertUnits, title: "Convert units", input: .quantity, options: .unit, executor: .units, output: .readingCard, writingPriority: 110, readingPriority: 110, numericPriority: nil),
    .init(id: .convertCurrencies, title: "Convert currencies", input: .currency, options: .currency, executor: .currencies, output: .readingCard, writingPriority: 110, readingPriority: 110, numericPriority: 60),
    .init(id: .convertTimeZones, title: "Convert time zones", input: .zonedTime, options: .timeZone, executor: .timeZones, output: .readingCard, writingPriority: 110, readingPriority: 110, numericPriority: nil),
    .init(id: .checkClaim, title: "Check a claim", input: .text, options: .none, executor: .checkClaim, output: .readingCard, writingPriority: 16, readingPriority: 16, numericPriority: nil),
    .init(id: .tone, title: "Adjust tone", input: .text, options: .textStyle, executor: .tone, output: .replaceOrRead, writingPriority: 20, readingPriority: 20, numericPriority: nil),
    .init(id: .improvePrompt, title: "Improve prompt", input: .text, options: .none, executor: .improvePrompt, output: .replaceOrRead, writingPriority: 18, readingPriority: 18, numericPriority: nil),
    .init(id: .simplify, title: "Simplify", input: .text, options: .none, executor: .simplify, output: .replaceOrRead, writingPriority: 19, readingPriority: 19, numericPriority: nil),
    .init(id: .cleanFormatting, title: "Clean formatting", input: .text, options: .none, executor: .cleanFormatting, output: .replaceOrRead, writingPriority: 18, readingPriority: 18, numericPriority: nil),
    .init(id: .changeCase, title: "Change case", input: .text, options: .letterCase, executor: .changeCase, output: .replaceOrRead, writingPriority: 17, readingPriority: 17, numericPriority: nil),
    .init(id: .createTasks, title: "Create tasks", input: .text, options: .none, executor: .taskPlan, output: .review, writingPriority: 22, readingPriority: 22, numericPriority: nil),
    .init(id: .createEvent, title: "Add to Calendar", input: .text, options: .none, executor: .eventPlan, output: .review, writingPriority: 21, readingPriority: 21, numericPriority: nil),
    .init(id: .summarizeFile, title: "Summarize", input: .readableFile, options: .none,
          executor: .fileSummary, output: .readingCard, writingPriority: 80, readingPriority: 80, numericPriority: nil),
    .init(id: .calculate, title: "Calculate", input: .number, options: .expression,
          executor: .calculator, output: .calculator, writingPriority: 100, readingPriority: 100, numericPriority: 100),
    .init(id: .fix, title: "Correct", input: .text, options: .none,
          executor: .correct, output: .replaceOrRead, writingPriority: 80, readingPriority: 40, numericPriority: nil),
    .init(id: .explain, title: "Explain", input: .text, options: .none,
          executor: .explain, output: .readingCard, writingPriority: 40, readingPriority: 80, numericPriority: nil),
    .init(id: .translate, title: "Translate", input: .text, options: .targetLanguage,
          executor: .translate, output: .replaceOrRead, writingPriority: 60, readingPriority: 60, numericPriority: nil),
    .init(id: .rewrite, title: "Rewrite", input: .text, options: .textStyle,
          executor: .rewrite, output: .replaceOrRead, writingPriority: 30, readingPriority: 30, numericPriority: nil),
    .init(id: .keyPoints, title: "Key points", input: .text, options: .none,
          executor: .keyPoints, output: .replaceOrRead, writingPriority: 25, readingPriority: 25, numericPriority: nil),
    .init(id: .extractTasks, title: "Extract tasks", input: .text, options: .none,
          executor: .extractTasks, output: .replaceOrRead, writingPriority: 24, readingPriority: 24, numericPriority: nil),
    .init(id: .reply, title: "Reply", input: .text, options: .replyIntent,
          executor: .reply, output: .replaceOrRead, writingPriority: 23, readingPriority: 23, numericPriority: nil)
  ]

  /// Indexed once: titles and definitions are looked up per bubble on every render.
  /// Keeps the first entry for an ID, matching the previous linear lookup.
  private static let definitionsByID = Dictionary(definitions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

  static func definition(for action: Action) -> ActionDefinition? {
    definitionsByID[action]
  }
}


extension Action {
  /// SF Symbols available on the app's macOS 14 baseline.
  var iconName: String {
    switch self {
    case .shop: "bubble.left"
    case .askSelection: "text.bubble"
    case .renameFile, .batchRename: "pencil.line"
    case .moveFiles: "folder"
    case .downloadVideo: "arrow.down.circle"
    case .openMaps: "map"
    case .directions: "location"
    case .convertUnits: "ruler"
    case .convertCurrencies: "dollarsign.arrow.circlepath"
    case .convertTimeZones: "clock"
    case .checkClaim: "checkmark.shield"
    case .tone: "slider.horizontal.3"
    case .simplify: "text.alignleft"
    case .improvePrompt: "sparkles"
    case .cleanFormatting: "textformat"
    case .changeCase: "textformat.size"
    case .calculate: "plus.forwardslash.minus"
    case .rewrite: "square.and.pencil"
    case .explain: "lightbulb"
    case .translate: "character.bubble"
    case .more: "ellipsis"
    case .keyPoints, .summarizeFile: "list.bullet"
    case .extractTasks, .createTasks: "checklist"
    case .fix: "checkmark"
    case .reply: "arrowshape.turn.up.left"
    case .createEvent: "calendar"
    case .search: "magnifyingglass"
    case .back: "chevron.left"
    case .allActions: "square.grid.2x2"
    }
  }
  var isNavigationIcon: Bool { self == .search || self == .back || self == .more }
}
