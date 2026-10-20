import Foundation
import Testing
@testable import TeroCore

@Suite struct SemanticRankingTests {
  let local: [ActionRecommendation] = [
    .init(target: .native(.fix), priority: 100, reason: .writingContext),
    .init(target: .native(.translate), priority: 90, reason: .writingContext),
    .init(target: .native(.createEvent), priority: 80, reason: .writingContext)
  ]
  @Test func semanticsReorderOnlyRegisteredCandidates() {
    let scores = [SemanticScore(id:"fix",score:1,confidence:0.9),
                  .init(id:"translate",score:2,confidence:0.8),.init(id:"createEvent",score:3,confidence:0.95)]
    let ranked = SemanticRankingPolicy.apply(scores,to:local)!
    #expect(ranked.map(\.target) == [.native(.createEvent),.native(.translate),.native(.fix)])
    #expect(Set(ranked.map(\.target)) == Set(local.map(\.target)))
    // The executor and capability remain exactly the local objects.
    #expect(ranked[0] == local[2])
  }
  @Test func invalidOrIncompleteCoverageCannotChangeAnything() {
    let valid = local.map { item -> SemanticScore in
      guard case .native(let a) = item.target else { fatalError() }
      return .init(id:a.rawValue,score:2,confidence:0.9)
    }
    #expect(SemanticRankingPolicy.apply(Array(valid.dropLast()),to:local) == nil)
    #expect(SemanticRankingPolicy.apply(valid + [valid[0]],to:local) == nil)
    #expect(SemanticRankingPolicy.apply([.init(id:"deleteEverything",score:3,confidence:1)] + Array(valid.dropFirst()),to:local) == nil)
    #expect(SemanticRankingPolicy.apply([.init(id:"fix",score:.nan,confidence:1)] + Array(valid.dropFirst()),to:local) == nil)
    #expect(SemanticRankingPolicy.apply([.init(id:"fix",score:4,confidence:1)] + Array(valid.dropFirst()),to:local) == nil)
  }
  @Test func threeVisibleSuggestionsFollowExactJevScoresEvenWhenWeak() {
    let candidates = local + [ActionRecommendation(target:.native(.reply),priority:70,reason:.readingContext)]
    // Both old thresholds and the former 0.05 grouping would choose the wrong top three.
    let scores = [SemanticScore(id:"fix",score:0.10,confidence:1),
                  .init(id:"translate",score:0.11,confidence:0.01),
                  .init(id:"createEvent",score:0.12,confidence:0.02),
                  .init(id:"reply",score:0.13,confidence:0.03)]
    let ranked = SemanticRankingPolicy.apply(scores,to:candidates)!
    let bar = ActionBarState(recommendations:ranked)
    #expect(bar.suggestions == [.reply,.createEvent,.translate])
    #expect(bar.selected == .reply)
  }
  @Test func sixBestJevActionsPaginateThreeByThreeAndKeepSearch() throws {
    let actions: [Action] = [.fix,.translate,.createEvent,.reply,.rewrite,.explain,.keyPoints,.tone]
    let candidates = actions.enumerated().map { index, action in
      ActionRecommendation(target:.native(action),priority:100-index,reason:.generalText)
    }
    let scores = actions.enumerated().map { index, action in
      SemanticScore(id:action.rawValue,score:Double(index+1)/10,confidence:0.01)
    }
    let ranked = try #require(SemanticRankingPolicy.apply(scores,to:candidates))
    var bar = ActionBarState(recommendations:ranked)
    #expect(bar.suggestions == [.tone,.keyPoints,.explain])
    #expect(bar.selected == .tone)
    bar.select(.more); bar.activate()
    #expect(bar.suggestions == [.rewrite,.reply,.createEvent])
    #expect(bar.selected == .rewrite)
    // The seventh candidate is searchable, but never replaces a top-six recommendation.
    bar.beginSearch(query:"Translate")
    #expect(bar.suggestions == [.translate])
    bar.endSearch()
    #expect(bar.suggestions == [.rewrite,.reply,.createEvent])
    bar.select(.back); bar.activate()
    #expect(bar.suggestions == [.tone,.keyPoints,.explain])
    bar.select(.more); bar.activate()
    let shouldClose = bar.escape()
    #expect(!shouldClose)
    #expect(bar.suggestions == [.tone,.keyPoints,.explain])
    #expect(bar.selected == .tone)
  }
  @Test func onlyExactTiesPreserveLocalOrderAndExplicitHabits() {
    let scores = local.map { item -> SemanticScore in
      guard case .native(let action) = item.target else { fatalError() }
      return .init(id:action.rawValue,score:0.4,confidence:0.01)
    }
    #expect(SemanticRankingPolicy.apply(scores,to:local) == local)
    let habit = ActionRecommendation(target:.habit(UUID()),priority:100,reason:.explicitHabit)
    let mixed = [local[0],habit,local[1],local[2]]
    let strong = [SemanticScore(id:"fix",score:1,confidence:1),
                  .init(id:"translate",score:2,confidence:1),.init(id:"createEvent",score:3,confidence:1)]
    #expect(SemanticRankingPolicy.apply(strong,to:mixed) == nil)
    let personalScores = strong + [SemanticScore(id: habit.target.rankingID, score: 3, confidence: 1)]
    #expect(SemanticRankingPolicy.apply(personalScores,to:mixed)?.map(\.target) == [habit.target, local[2].target, local[1].target, local[0].target])
  }
  @Test func boundedStateOmitsPathsAndFileContent() throws {
    var source = InvocationContext(capturedAt:.now,applicationID:"com.apple.finder")
    source.files = [.init(url:URL(fileURLWithPath:"/Users/private/SecretFolder/photo.jpg"))]
    let state = try #require(RankingContext(.init(fileContext:source)))
    let json = String(decoding:try JSONEncoder().encode(state),as:UTF8.self)
    #expect(json.contains("photo.jpg"))
    #expect(!json.contains("SecretFolder"))
    #expect(!json.contains("/Users"))
    source.files = Array(repeating:source.files[0],count:21)
    #expect(RankingContext(.init(fileContext:source)) == nil)
  }
  @Test func composerEvidenceReachesBoundedRankingContext() throws {
    var source = InvocationContext(capturedAt: .now, applicationID: "company.thebrowser.dia")
    source.surface = .writing; source.capture = .observed; source.webHost = "x.com"
    source.elementDescription = "Post text"; source.elementPlaceholder = "What is happening?!"
    source.containers = [.init(role: "AXGroup", label: "Compose a post")]
    let readout = SelectionReadout(applicationName: "Dia", processIdentifier: 0, status: .selected("I shipped Tero"), context: source)
    let context = try #require(RankingContext(.init(selection: readout, applicationID: nil)))
    let json = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)
    #expect(json.contains("What is happening?!") && json.contains("Compose a post"))
    #expect(json.contains("writing") && json.contains("x.com"))
  }
  @Test func malformedDistributionCannotReorderModes() {
    var scores = local.map { SemanticScore(id: $0.target.rankingID, score: 1, confidence: 1, probabilities: ["0":0,"1":1,"2":0,"3":0]) }
    #expect(SemanticRankingPolicy.apply(scores, to: local) != nil)
    scores[0].probabilities = ["0":1,"1":1,"2":0,"3":0]
    #expect(SemanticRankingPolicy.apply(scores, to: local) == nil)
  }
  @Test func protectedAndEmptySelectionNeverSent() {
    let none = RecommendationContext(applicationID:"test",content:.none)
    #expect(RankingContext(none) == nil)
    let protected = RecommendationContext(selection:.init(applicationName:"test",processIdentifier:0,status:.protectedField),applicationID:"test")
    #expect(RankingContext(protected) == nil)
  }
}
