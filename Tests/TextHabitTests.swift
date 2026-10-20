import Foundation
import Testing
@testable import TeroCore

@Test func textHabitChoiceKeepsNativeModesAndSupportsKeyboardNavigation() {
    var state = ActionBarState()
    let original = state.actions
    state.hasTextHabits = true
    #expect(state.actions == original)
    state.beginTextHabit()
    #expect(state.executing == .rewrite)
    state.move(by: -1)
    #expect(state.executing == .rewrite)
}

@Test func textHabitCannotExecuteWhenUnavailable() {
    var state = ActionBarState()
    state.beginTextHabit()
    #expect(state.executing == nil)
    #expect(!state.actions.contains(.allActions))
}

@Test func personalActionsUseTheSameRankingOrderAndRequireExactCoverage() {
    let id = UUID()
    let actions = [ActionRecommendation(target: .native(.fix), priority: 100, reason: .writingContext), ActionRecommendation(target: .habit(id), priority: 20, reason: .explicitHabit)]
    let scores = [SemanticScore(id: "fix", score: 1, confidence: 1), SemanticScore(id: actions[1].target.rankingID, score: 3, confidence: 1)]
    #expect(SemanticRankingPolicy.apply(scores, to: actions)?.first?.target == .habit(id))
    #expect(SemanticRankingPolicy.apply(Array(scores.prefix(1)), to: actions) == nil)
}

@Test func generatedDraftRequiresAUsableSampleAndBoundedInstructions() {
    let valid = HabitDesign(name: "Warm emails", instruction: "Make the email warmer.", summary: "Keep it friendly.", sample: "Please send the draft by Friday.", question: nil)
    #expect(valid.isValid)
    #expect(!HabitDesign(name: valid.name, instruction: valid.instruction, summary: valid.summary, sample: "", question: nil).isValid)
    #expect(HabitDesign(name: "", instruction: "", summary: "", sample: "", question: "What kind of text?").isValid)
}

@Test func recommendationPagesShowNineModesInThreeRows() {
    let recommendations = (0..<10).map { _ in ActionRecommendation(target: .habit(UUID()), priority: 1, reason: .explicitHabit) }
    let first = ActionRecommendationPages.targets(recommendations, page: 0)
    let second = ActionRecommendationPages.targets(recommendations, page: 1)
    let third = ActionRecommendationPages.targets(recommendations, page: 2)
    #expect(first == [.native(.search)] + Array(recommendations.prefix(3)).map(\.target) + [.native(.more)])
    #expect(second == [.native(.back)] + Array(recommendations.dropFirst(3).prefix(3)).map(\.target) + [.native(.more)])
    #expect(third == [.native(.back)] + Array(recommendations.dropFirst(6).prefix(3)).map(\.target) + [.native(.allActions)])
    #expect(!first.contains(.native(.allActions)))
    #expect(!second.contains(.native(.allActions)))
    #expect(!second.contains(.native(.search)))
    #expect(!third.contains(.native(.search)))
    #expect(!third.contains(recommendations[9].target))
}

@Test func shortRecommendationListDoesNotInventModes() {
    let recommendations = [ActionRecommendation(target: .native(.fix), priority: 1, reason: .generalText)]
    #expect(ActionRecommendationPages.targets(recommendations, page: 0) == [.native(.search), .native(.fix), .native(.allActions)])
}

@Test func thirdPageModeUsesTheExistingExecutor() {
    let modes = ActionCatalog.definitions.filter { $0.input == .text }.prefix(9).map { $0.id }
    var state = ActionBarState(recommendations: modes.map { .init(target: .native($0), priority: 1, reason: .generalText) })
    let last = Array(modes).last!
    state.selectRecommended(last)
    state.activate()
    #expect(state.executing == last)
}

@Test func fileHabitsRequireTypedPlansAndExplicitMoveDestination() throws {
    let rename = FileHabitPlan(operation: .rename, extensions: ["pdf"], nameContains: [])
    var habit = TextHabit(name: "Invoices", instruction: "Rename invoices by date.", filePlan: rename)
    #expect(habit.isValid)
    habit.filePlan = FileHabitPlan(operation: .move, extensions: ["pdf"], nameContains: [])
    #expect(!habit.isValid)
    habit.destinationBookmark = Data([1])
    #expect(habit.isValid)
    let old = try JSONDecoder().decode(TextHabit.self, from: Data(#"{"id":"a29e3710-4438-41bf-beb6-c1d6d20d366d","name":"Text","instruction":"Rewrite.","output":"replace","enabled":true}"#.utf8))
    #expect(old.isValid && old.filePlan == nil)
}
@Test func fileHabitMatchesOnlyCompleteCompatibleSelections() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pdf = directory.appendingPathComponent("invoice.pdf"), png = directory.appendingPathComponent("photo.png")
    try Data("test".utf8).write(to: pdf); try Data("test".utf8).write(to: png)
    let plan = FileHabitPlan(operation: .move, extensions: ["pdf"], nameContains: ["invoice"])
    #expect(plan.accepts([.read(pdf)]))
    #expect(!plan.accepts([.read(pdf), .read(png)]))
    #expect(!plan.accepts([.read(directory)]))
    let link = directory.appendingPathComponent("invoice-link.pdf")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: pdf)
    #expect(!plan.accepts([.read(link)]))
}
@Test func fileHabitTestRelocatesDisposableCopiesAndRefusesOverwrite() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("invoice.pdf"), renamed = root.appendingPathComponent("2026-03-12-invoice.pdf")
    try Data("fictional invoice".utf8).write(to: source)
    let engine = FileWorkflowEngine()
    _ = try await engine.relocate([source], targets: [renamed], snapshots: [try LocalFileIO.Snapshot(source)])
    #expect(try Data(contentsOf: renamed) == Data("fictional invoice".utf8))
    let destination = root.appendingPathComponent("destination")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let moved = destination.appendingPathComponent(renamed.lastPathComponent)
    _ = try await engine.relocate([renamed], targets: [moved], snapshots: [try LocalFileIO.Snapshot(renamed)])
    try Data("untouched".utf8).write(to: renamed)
    do { _ = try await engine.relocate([renamed], targets: [moved], snapshots: [try LocalFileIO.Snapshot(renamed)]); Issue.record("Overwrote an existing file") } catch { }
    #expect(try Data(contentsOf: renamed) == Data("untouched".utf8))
    #expect(try Data(contentsOf: moved) == Data("fictional invoice".utf8))
}

@Test func searchFindsPersonalModesBeyondTheNineRecommendations() {
    let habits = (0..<10).map { TextHabit(name: "Personal \($0)", instruction: "Rewrite email", summary: "Email rewrite") }
    let recommendations = habits.map { ActionRecommendation(target: .habit($0.id), priority: 1, reason: .explicitHabit) }
    #expect(ActionSearch.results(for: "personal 9", recommendations: recommendations, habits: habits) == [.habit(habits[9].id)])
    var disabled = habits; disabled[9].enabled = false
    #expect(ActionSearch.results(for: "personal 9", recommendations: recommendations, habits: disabled).isEmpty)
    #expect(ActionSearch.results(for: "email", recommendations: recommendations, habits: habits).count == 3)
}

@Test func filenameCaseHabitRequiresAFilePlanButTextCaseHabitDoesNot() {
    let incorrect = HabitDesign(name: "camelCase", instruction: "Réécris les noms de fichiers en camelCase. Préserve les extensions.", summary: "Rename files", sample: "rapport annuel.pdf", question: nil)
    #expect(incorrect.needsFileRenamePlan)
    let text = HabitDesign(name: "camelCase", instruction: "Convert the selected text to camelCase.", summary: "Convert text", sample: "annual report", question: nil)
    #expect(!text.needsFileRenamePlan)
    let file = HabitDesign(name: "camelCase", instruction: incorrect.instruction, summary: "Rename files", sample: "", question: nil,
        filePlan: .init(operation: .rename, extensions: [], nameContains: [], usesContents: false),
        fileSamples: [.init(name: "rapport annuel.pdf", content: "")])
    #expect(file.isValid && !file.needsFileRenamePlan)
}

@Test func personalFileModesRemainVisibleAndShareSemanticRankingWithNativeModes() {
    var source = InvocationContext(capturedAt: .now, applicationID: "com.apple.finder")
    source.fileCapture = .observed
    source.files = ["notes.txt", "invoice.pdf"].map {
        .init(url: URL(fileURLWithPath: "/tmp/" + $0), isDirectory: false, isSymbolicLink: false, metadataAvailable: true)
    }
    let context = RecommendationContext(fileContext: source)
    let habit = TextHabit(name: "Archive", instruction: "Move selected files to the saved folder.", summary: "Archive my files.",
        filePlan: .init(operation: .move, extensions: [], nameContains: [], usesContents: false), destinationBookmark: Data([1]))
    #expect(habit.rankingDescription == "Archive my files.")
    let local = RecommendationEngine.rank(context: context, personalActions: [habit])
    #expect(ActionRecommendationPages.targets(local, page: 0).contains(.habit(habit.id)))
    let scores = local.map { SemanticScore(id: $0.target.rankingID, score: $0.target == .habit(habit.id) ? 3 : 1, confidence: 1) }
    #expect(SemanticRankingPolicy.apply(scores, to: local)?.first?.target == .habit(habit.id))
    let nativeScores = local.map { SemanticScore(id: $0.target.rankingID, score: $0.target == .native(.moveFiles) ? 3 : 1, confidence: 1) }
    #expect(SemanticRankingPolicy.apply(nativeScores, to: local)?.first?.target == .native(.moveFiles))
    var disabled = habit; disabled.enabled = false
    #expect(!RecommendationEngine.rank(context: context, personalActions: [disabled]).contains { $0.target == .habit(habit.id) })
    #expect(!habit.isEligible(in: .init(applicationID: nil, content: .text(isNumber: false, editable: true))))
    var old = habit; old.summary = " "
    #expect(old.rankingDescription == old.instruction)
}

@Test func personalRenamePreviewPreservesStyleAndAddsTheExtensionOnlyOnce() throws {
    let urls = [URL(fileURLWithPath: "/tmp/annual report.PDF"), URL(fileURLWithPath: "/tmp/notes.txt")]
    let targets = try FileNameProposal.targets(urls, stems: ["annualReport.pdf", "my_custom_notes"], format: false)
    #expect(targets.map(\.lastPathComponent) == ["annualReport.PDF", "my_custom_notes.txt"])
    #expect(throws: (any Error).self) {
        try FileNameProposal.targets([urls[0]], stems: [".PDF"], format: false)
    }
}

@Test func cloudHabitsNeverUploadLocalFolderPermissions() throws {
    let owner = UUID()
    let plan = FileHabitPlan(operation: .move, extensions: ["pdf"], nameContains: [])
    let original = TextHabit(name: "Archive PDFs", instruction: "Move PDFs to my archive", filePlan: plan, destinationBookmark: Data([1, 2, 3]))
    let cloud = CloudHabit(original, owner: owner)
    let json = String(decoding: try JSONEncoder().encode(cloud), as: UTF8.self)
    #expect(!json.contains("destinationBookmark"))
    #expect(!json.contains("AQID"))
    let restored = try cloud.habit(local: nil)
    #expect(restored.isSyncable && !restored.isValid)
    #expect(restored.needsDestination)
    #expect(try cloud.habit(local: original).destinationBookmark == original.destinationBookmark)
}

@Test func cloudHabitMergeKeepsPendingEditsAndDoesNotResurrectDeletedHabits() throws {
    let owner = UUID()
    let original = TextHabit(name: "Tone", instruction: "Make it friendly")
    var edited = original; edited.name = "Warm tone"
    let removed = TextHabit(name: "Remove me", instruction: "Shorten")
    var state = HabitSyncState(); state.save(edited.id); state.remove(removed.id)
    let result = try HabitSyncMerge.merge(local: [edited], remote: [CloudHabit(original, owner: owner), CloudHabit(removed, owner: owner)], state: state, owner: owner)
    #expect(result == [edited])
    #expect(try HabitSyncMerge.merge(local: [original], remote: [], state: HabitSyncState(), owner: owner).isEmpty)
    #expect(throws: TextHabitRepository.Failure.self) {
        try HabitSyncMerge.merge(local: [], remote: [CloudHabit(original, owner: UUID())], state: state, owner: owner)
    }
}

@Test func habitOutboxSurvivesRestartAtomicallyAndSupportsLegacyArchives() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = TextHabitRepository(url: directory.appendingPathComponent("habits.json"))
    let habit = TextHabit(name: "Rewrite", instruction: "Rewrite clearly")
    try repository.save([habit])
    #expect(try repository.loadArchive().sync == nil)
    var state = HabitSyncState(); state.save(habit.id)
    let oldVersion = state.pending[habit.id]
    state.save(habit.id)
    #expect(state.pending[habit.id] != oldVersion)
    try repository.save([habit], sync: state)
    #expect(try repository.loadArchive().sync == state)
    state.remove(habit.id)
    try repository.save([], sync: state)
    #expect(try repository.load().isEmpty)
    #expect(try repository.loadArchive().sync?.deleted[habit.id] != nil)
}


@Test func modeIconPersistenceAndAutomaticFallback() throws {
    var habit = TextHabit(name: "Translate notes", instruction: "Translate the selected text.")
    #expect(habit.resolvedIconName == "character.bubble")
    habit.iconName = "heart"
    habit.name = "Email summary"
    #expect(habit.resolvedIconName == "heart")
    let decoded = try JSONDecoder().decode(TextHabit.self, from: JSONEncoder().encode(habit))
    #expect(decoded.iconName == "heart")
    let cloud = try JSONDecoder().decode(CloudHabit.self, from: JSONEncoder().encode(CloudHabit(habit, owner: UUID())))
    #expect(try cloud.habit(local: nil).resolvedIconName == "heart")
    var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(habit)) as? [String: Any])
    legacy.removeValue(forKey: "iconName")
    let old = try JSONDecoder().decode(TextHabit.self, from: JSONSerialization.data(withJSONObject: legacy))
    #expect(old.iconName == nil)
    #expect(old.resolvedIconName == "envelope")
    habit.iconName = "unknown.symbol"
    #expect(habit.resolvedIconName == "envelope")
    habit.iconName = nil
    habit.name = "My action"
    #expect(habit.resolvedIconName == "sparkles")
}
