import Foundation
import Testing
@testable import TeroCore

@Test func recommendationsDistinguishWritingReadingAndNumbers() {
    let writing = RecommendationEngine.rank(context: .init(applicationID: "com.example.editor", content: .text(isNumber: false, editable: true)))
    let reading = RecommendationEngine.rank(context: .init(applicationID: "com.example.editor", content: .text(isNumber: false, editable: false)))
    #expect(writing.first?.target == .native(.fix))
    #expect(reading.first?.target == .native(.explain))
    #expect(writing.first?.reason == .writingContext)
    let number = RecommendationEngine.rank(context: .init(applicationID: nil, content: .text(isNumber: true, editable: true)))
    #expect(number.map(\.target) == [.native(.calculate)])
    #expect(writing.contains { $0.target == .native(.keyPoints) })
}

@Test func recommendationsNeverTreatUnknownContextAsWritingOrReadProtectedContent() {
    let unknown = RecommendationEngine.rank(context: .init(applicationID: "com.whatsapp", content: .text(isNumber: false, editable: nil)))
    #expect(unknown.first?.reason == .generalText)
    #expect(unknown.first?.target != .native(.fix))
    for status in [SelectionReadout.Status.protectedField, .noSelection, .permissionRequired, .unavailable] {
        let context = RecommendationContext(selection: .init(applicationName: "Test", processIdentifier: 0, status: status), applicationID: nil)
        #expect(RecommendationEngine.rank(context: context).isEmpty)
    }
}

@Test func fileContextsWithoutObservedFilesRecommendNothing() {
    for context in [
        RecommendationContext(applicationID: "com.apple.finder", content: .files(count: 3, allAudio: true)),
        .init(applicationID: "other", content: .files(count: 1, allAudio: false)),
        .init(applicationID: nil, content: .none)
    ] { #expect(RecommendationEngine.rank(context: context).isEmpty) }
    #expect(HomeAction.clipboard.isAvailable && HomeAction.habits.isAvailable)
}

@Test func rankedPrimarySurvivesMoreBackAndEmptyResultsCannotExecute() {
    let ranked = RecommendationEngine.rank(context: .init(applicationID: nil, content: .text(isNumber: false, editable: true)))
    var state = ActionBarState(recommendations: ranked)
    #expect(state.actions == [.fix, .translate, .explain, .more, .search])
    state.select(.more); state.activate()
    #expect(state.actions == [.rewrite, .keyPoints, .extractTasks, .back, .search])
    state.select(.back); state.activate()
    #expect(state.selected == .fix)
    state.select(.more); state.activate()
    let closes = state.escape()
    #expect(!closes)
    #expect(state.selected == .fix)
    state.activate()
    #expect(state.executing == .fix)
    var empty = ActionBarState(recommendations: [])
    empty.activate(); empty.move(by: 1)
    #expect(empty.actions.isEmpty && empty.executing == nil)
}

@Test func barRejectsSimulatedAndDuplicateCandidates() {
    let state = ActionBarState(recommendations: [
        .init(target: .native(.more), priority: 999, reason: .generalText),
        .init(target: .native(.fix), priority: 80, reason: .writingContext),
        .init(target: .native(.fix), priority: 80, reason: .writingContext)
    ])
    #expect(state.actions == [.fix, .search])
}

@Test func actionRegistryRejectsUnsupportedInputsAndUnimplementedActions() {
    #expect(Set(ActionCatalog.definitions.map(\.id)).count == ActionCatalog.definitions.count)
    for action in [Action.more, .back, .search] {
        #expect(action.definition == nil)
    }
    let files = RecommendationContext(applicationID: "com.apple.finder", content: .files(count: 2, allAudio: false))
    let none = RecommendationContext(applicationID: nil, content: .none)
    for definition in ActionCatalog.definitions {
        #expect(!definition.accepts(files))
        #expect(!definition.accepts(none))
    }
    let text = RecommendationContext(applicationID: nil, content: .text(isNumber: false, editable: true))
    #expect(Action.calculate.definition?.accepts(text) == false)
    #expect(Action.fix.definition?.accepts(text) == true)
}

@Test func actionDeliveryPreservesExistingReadOnlyAndEditableBehavior() {
    for canReplace in [true, false] {
        #expect(Action.explain.definition?.delivery(canReplace: canReplace) == .readingCard)
        #expect(Action.calculate.definition?.delivery(canReplace: canReplace) == .interactive)
    }
    #expect(Action.fix.definition?.delivery(canReplace: true) == .replacement)
    #expect(Action.fix.definition?.delivery(canReplace: false) == .readingCard)
    #expect(Action.translate.definition?.delivery(canReplace: true) == .replacement)
    #expect(Action.translate.definition?.delivery(canReplace: false) == .readingCard)
    #expect(Action.translate.definition?.options == .targetLanguage)
    #expect(Action.calculate.definition?.options == .expression)
}

@Test func returningFromOptionsKeepsFrozenWritingRecommendationsAndSelection() {
    let ranked = RecommendationEngine.rank(context: .init(applicationID: nil, content: .text(isNumber: false, editable: true)))
    var state = ActionBarState(recommendations: ranked)
    let initial = state.actions
    state.select(.translate)
    state.activate()
    state.returnFromOptions()
    #expect(state.actions == initial)
    #expect(state.selected == .translate)
    #expect(state.executing == nil)
    state.activate()
    #expect(state.executing == .translate)
}

@Test func rewriteIsSecondaryForTextAndNeverSuggestedForNumbersOrFiles() {
    for editable in [true, false] {
        let context = RecommendationContext(applicationID: nil, content: .text(isNumber: false, editable: editable))
        let suggestions = RecommendationEngine.rank(context: context)
        #expect(suggestions.contains { $0.target == .native(.rewrite) })
        var state = ActionBarState(recommendations: suggestions)
        #expect(!state.actions.contains(.rewrite))
        state.select(.more); state.activate()
        #expect(state.actions.contains(.rewrite))
        #expect(Action.rewrite.definition?.delivery(canReplace: editable) == (editable ? .replacement : .readingCard))
    }
    let numbers = RecommendationEngine.rank(context: .init(applicationID: nil, content: .text(isNumber: true, editable: true)))
    #expect(!numbers.contains { $0.target == .native(.rewrite) })
}

@Test func keyPointsReplacesEditableSelectionAndReadsOtherwise() {
    let context = RecommendationContext(applicationID: nil, content: .text(isNumber: false, editable: true))
    var state = ActionBarState(recommendations: RecommendationEngine.rank(context: context))
    #expect(!state.actions.contains(.keyPoints))
    state.select(.more); state.activate()
    #expect(state.actions == [.rewrite, .keyPoints, .extractTasks, .back, .search])
    state.select(.keyPoints); state.activate()
    #expect(state.executing == .keyPoints)
    #expect(Action.keyPoints.definition?.delivery(canReplace: true) == .replacement)
    #expect(Action.keyPoints.definition?.delivery(canReplace: false) == .readingCard)
    #expect(Action.keyPoints.definition?.usesAI == true)
    let numbers = RecommendationContext(applicationID: nil, content: .text(isNumber: true, editable: nil))
    #expect(Action.keyPoints.definition?.priority(in: numbers) == nil)
}

@Test func retiredShortenHasNoNativeAction() {
    #expect(Action(rawValue: "shorten") == nil)
    #expect(Action.keyPoints.definition?.transformsText == true)
}

@Test func extractTasksIsSecondaryAndFollowsEditability() {
    for editable in [true, false] {
        let context = RecommendationContext(applicationID: nil, content: .text(isNumber: false, editable: editable))
        var state = ActionBarState(recommendations: RecommendationEngine.rank(context: context))
        #expect(!state.actions.contains(.extractTasks))
        state.select(.more); state.activate()
        #expect(state.actions.contains(.extractTasks))
        state.select(.extractTasks); state.activate()
        #expect(state.executing == .extractTasks)
        #expect(Action.extractTasks.definition?.delivery(canReplace: editable) == (editable ? .replacement : .readingCard))
    }
    #expect(Action.extractTasks.definition?.usesAI == true)
    #expect(Action.extractTasks.definition?.transformsText == true)
    for context in [
        RecommendationContext(applicationID: nil, content: .text(isNumber: true, editable: true)),
        .init(applicationID: nil, content: .files(count: 1, allAudio: false)),
        .init(applicationID: nil, content: .none)
    ] {
        #expect(!RecommendationEngine.rank(context: context).contains { $0.target == .native(.extractTasks) })
    }
}

@Test func keyPointsDoesNotTreatAnEditabilityHintAsPermissionToReplace() {
    var selection = SelectionReadout(applicationName: "Test", processIdentifier: 0, status: .selected("A passage"))
    selection.metadata = SelectionMetadata(range: NSRange(location: 0, length: 9), controlBounds: nil, selectionBounds: nil, isEditable: true)
    #expect(!selection.canPaste) // No captured target token.
    #expect(Action.keyPoints.definition?.delivery(canReplace: selection.canPaste) == .readingCard)
    selection.targetID = UUID()
    #expect(selection.canPaste)
    #expect(Action.keyPoints.definition?.delivery(canReplace: selection.canPaste) == .replacement)
}
