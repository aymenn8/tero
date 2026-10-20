import AppKit
import Observation

@MainActor @Observable
final class FileWorkflowSession {
  let kind: FileWorkflowKind
  let context: InvocationContext
  private let habit: TextHabit?
  private let owner: UUID?
  var urls: [URL]
  var names: [String] = []
  var naming: Bool { [.rename, .batchRename].contains(kind) }
  private(set) var suggesting = false
  var destination: URL?
  var selectedID: String? = "run"
  private(set) var busy = false
  private(set) var succeeded = false
  private(set) var requiresAccount = false
  private(set) var requiresSignIn = false
  private(set) var message: String?
  private(set) var outputs: [URL] = []
  private let snapshots: [URL: LocalFileIO.Snapshot]
  @ObservationIgnored private let engine = FileWorkflowEngine()
  @ObservationIgnored private var work: Task<Void, Never>?
  @ObservationIgnored private let changed: () -> Void
  @ObservationIgnored private let back: () -> Void
  init(kind: FileWorkflowKind, context: InvocationContext, back: @escaping () -> Void,
       changed: @escaping () -> Void, habit: TextHabit? = nil) {
    self.habit = habit; owner = AccountStore.shared.user?.id
    self.kind = kind; self.context = context; urls = context.files.map(\.url)
    self.back = back; self.changed = changed
    snapshots = Dictionary(uniqueKeysWithValues: context.files.compactMap { file in
      (try? LocalFileIO.Snapshot(file.url)).map { (file.url, $0) }
    })
    if kind == .move { selectedID = "browse" }
    if let bookmark = habit?.destinationBookmark {
      var stale = false
      destination = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
      if stale { destination = nil; message = "Choose the destination again in your habit settings." }
      if destination != nil { selectedID = "run" }
    }
    names = urls.map { $0.deletingPathExtension().lastPathComponent }
  }
  func suggestName() {
    guard naming, !busy, !suggesting, !succeeded else { return }
    suggesting = true; message = nil; changed()
    work = Task { [weak self] in
      guard let self else { return }
      defer { suggesting = false; changed() }
      do {
        guard let credential = await GatewayAccess.credential() else { throw CorrectionClient.Failure.unavailable }
        var inputs: [FileNamingInput]
        if let habit, habit.filePlan?.usesContents != true {
          inputs = urls.enumerated().map { .init(id: "file-\($0.offset)", text: "Original filename: " + $0.element.lastPathComponent, file: nil) }
        } else {
          inputs = try await FileSummaryReader().namingInputs(urls, snapshots: urls.compactMap { snapshots[$0] })
        }
        if habit != nil { for index in inputs.indices { inputs[index].name = urls[index].lastPathComponent } }
        let proposed = try await CorrectionClient().renameFiles(inputs, requestID: UUID(), credential: credential, refinement: habit?.instruction)
        try Task.checkCancellation()
        guard try zip(urls, urls.compactMap { snapshots[$0] }).allSatisfy({ try LocalFileIO.Snapshot($0.0) == $0.1 }) else { throw LocalFileIO.Failure.changed }
        guard validHabit else { throw LocalFileIO.Failure.changed }
        names = habit == nil ? proposed.map(FileNameProposal.formatted) : proposed
      } catch { if !Task.isCancelled {
        if (error as? CorrectionClient.Failure) == .unavailable { requiresSignIn = true; return }
        if (error as? CorrectionClient.Failure) == .allowanceReached { requiresAccount = true; return }
        message = error is FileSummaryReader.Failure ? "Couldn't analyze these files. Use images, PDFs, documents or readable text." : error.localizedDescription
      } }
    }
  }
  var detailsHeight: CGFloat {
    if suggesting || succeeded { return 0 }
    if naming { return 30 + min(200, CGFloat(urls.count * 48)) }
    return kind == .move ? 106 : 0
  }
  var targets: [URL] { (try? FileNameProposal.targets(urls, stems: names, format: habit == nil)) ?? [] }
  private var validHabit: Bool {
    guard let habit else { return true }
    TextHabitStore.shared.refreshOwner()
    return owner == AccountStore.shared.user?.id && habit.enabled
      && TextHabitStore.shared.habits.contains(habit)
      && habit.filePlan?.accepts(context.files) == true
  }
  var canRun: Bool {
    guard validHabit else { return false }
    guard !busy, !suggesting, !succeeded, snapshots.count == urls.count else { return false }
    switch kind {
    case .rename, .batchRename: return targets.count == urls.count && targets != urls && Set(targets.map { $0.path.lowercased() }).count == targets.count
    case .move: return destination != nil
    }
  }
  var hint: String {
    if naming && !suggesting {
      if !names.allSatisfy(FileWorkflowEngine.validStem) { return "Use a filename without /, : or a leading dot." }
      if Set(targets.map { $0.path.lowercased() }).count != targets.count { return "Give each file a different name." }
    }
    return ""
  }
  var recentFolders: [URL] {
    (UserDefaults.standard.stringArray(forKey: "tero.recentMoveFolders") ?? []).map { URL(fileURLWithPath: $0) }
      .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map { $0.isDirectory == true && $0.isSymbolicLink == false } == true }
  }
  func pickFolder() {
    let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
    picker.allowsMultipleSelection = false; picker.prompt = "Choose"
    if picker.runModal() == .OK, let folder = picker.url { destination = folder; changed() }
  }
  var presentation: ModeChoicePresentation {
    let options: [ModeChoice]
    if kind == .move {
      if destination == nil {
        options = Array(recentFolders.prefix(2).enumerated()).map { index, folder in
          .init(id: "folder-\(index)", title: folder.lastPathComponent.count > 12 ? String(folder.lastPathComponent.prefix(11)) + "…" : folder.lastPathComponent, label: folder.path)
        } + [.init(id: "browse", title: "Choose folder…", label: "Choose destination")]
      } else {
        options = [.init(id: "run", title: "Move ↵", label: "Move selected files", enabled: canRun),
          .init(id: "browse", title: "Change…", label: "Change destination")]
      }
    } else {
      options = [.init(id: "run", title: naming ? "Rename ↵" : kind.title + " ↵", label: kind.title, enabled: canRun)]
    }
    return .init(step: .init(label: kind.title, choices: options, selectedID: selectedID, backLabel: "Back to actions"),
      activityTitle: busy || succeeded || suggesting ? kind.title : nil, finished: succeeded,
      select: { [weak self] in self?.selectedID = $0 }, perform: { [weak self] id in
        guard let self else { return }
        guard let id else { back(); return }
        if kind == .move {
          if id == "browse" { pickFolder(); selectedID = destination == nil ? "browse" : "run"; changed(); return }
          if id.hasPrefix("folder-"), let index = Int(id.dropFirst(7)), recentFolders.indices.contains(index) {
            destination = recentFolders[index]; selectedID = "run"; changed(); return
          }
        }
        run()
      })
  }
  func run() {
    if naming && habit == nil { names = names.map(FileNameProposal.formatted) }
    guard canRun else { return }
    busy = true; message = nil; changed()
    let current = urls, frozen = current.compactMap { snapshots[$0] }, target = destination, proposedTargets = targets
    work = Task { [weak self] in
      guard let self else { return }
      defer { busy = false; changed() }
      do {
        guard validHabit else { throw LocalFileIO.Failure.changed }
        let scoped = target?.startAccessingSecurityScopedResource() == true
        defer { if scoped { target?.stopAccessingSecurityScopedResource() } }
        guard try await FinderSelectionReader().validates(context) else { throw LocalFileIO.Failure.changed }
        switch kind {
        case .rename, .batchRename:
          outputs = try await engine.relocate(current, targets: proposedTargets, snapshots: frozen)
        case .move:
          guard let target, try target.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory == true,
            try target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false else { throw LocalFileIO.Failure.unavailable }
          outputs = try await engine.relocate(current, targets: current.map { target.appendingPathComponent($0.lastPathComponent) }, snapshots: frozen)
          let recent = [target.path] + (UserDefaults.standard.stringArray(forKey: "tero.recentMoveFolders") ?? []).filter { $0 != target.path }
          UserDefaults.standard.set(Array(recent.prefix(5)), forKey: "tero.recentMoveFolders")
        }
        guard !Task.isCancelled else { return }
        succeeded = true
      } catch { if !Task.isCancelled {
        message = (error as? LocalFileIO.Failure) == .conversionFailed
          ? "Couldn't complete this action. Check that the destination is writable." : error.localizedDescription
      } }
    }
  }
  func cancel() { work?.cancel() }
}
