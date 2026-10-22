import Testing
@testable import TeroCore

@Test func selectionAskIsAThirdBubbleForTextAndNeverForNumbers() {
  for editable in [true, false] {
    let context = RecommendationContext(applicationID: nil, content: .text(isNumber: false, editable: editable))
    let state = ActionBarState(recommendations: RecommendationEngine.rank(context: context))
    #expect(state.actions[2] == .askSelection)
    #expect(Action.askSelection.definition?.delivery(canReplace: editable) == (editable ? .replacement : .readingCard))
  }
  let number = RecommendationContext(applicationID: nil, content: .text(isNumber: true, editable: true))
  #expect(Action.askSelection.definition?.priority(in: number) == nil)
  #expect(Action.askSelection.definition?.usesAI == true)
  #expect(Action.askSelection.definition?.rankedOnServer == false)
}

@Test func selectionAskKeepsItsSlotAfterSemanticRanking() {
  let ask = ActionRecommendation(target: .native(.askSelection), priority: 45, reason: .writingContext)
  let video = ActionRecommendation(target: .native(.downloadVideo), priority: 120, reason: .writingContext)
  let ranked = [Action.explain, .fix, .translate, .rewrite].map { ActionRecommendation(target: .native($0), priority: 0, reason: .writingContext) }
  #expect(SemanticRankingPolicy.merge(localOnly: [ask], ranked: ranked).map(\.target)
    == [.native(.explain), .native(.fix), .native(.askSelection), .native(.translate), .native(.rewrite)])
  #expect(SemanticRankingPolicy.merge(localOnly: [ask, video], ranked: ranked).map(\.target).prefix(3)
    == [.native(.downloadVideo), .native(.explain), .native(.askSelection)])
  #expect(SemanticRankingPolicy.merge(localOnly: [ask], ranked: []).map(\.target) == [.native(.askSelection)])
}

@Test func selectionAskInstructionFitsTheGatewayLimit() {
  #expect(SelectionAskMode.detected(canReplace: true) == .write)
  #expect(SelectionAskMode.detected(canReplace: false) == .explain)
  for mode in SelectionAskMode.allCases {
    #expect(mode.instruction(for: "  \n ") == nil)
    #expect(mode.instruction(for: String(repeating: "é", count: SelectionAskMode.requestLimit + 1)) == nil)
    let longest = mode.instruction(for: String(repeating: "é", count: SelectionAskMode.requestLimit))
    #expect(longest.map { $0.unicodeScalars.count <= 1000 } == true)
    #expect(mode.instruction(for: " Make it formal ")?.hasSuffix(": Make it formal") == true)
  }
  #expect(SelectionAskMode.explain.instruction(for: "Why?")?.contains("language of the question") == true)
}
