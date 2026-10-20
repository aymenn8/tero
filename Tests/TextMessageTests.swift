import Foundation
import Testing
@testable import TeroCore

@Test func textMessageModesShareDeliveryAndEligibility() {
  let reading = RecommendationContext(applicationID: nil, content: .text(isNumber: false, editable: false))
  for action in [Action.fix, .rewrite, .translate, .keyPoints, .reply, .tone, .simplify, .cleanFormatting, .changeCase] {
    #expect(action.definition?.accepts(reading) == true)
    #expect(action.definition?.delivery(canReplace: false) == .readingCard)
    #expect(action.definition?.delivery(canReplace: true) == .replacement)
  }
  #expect(Action.cleanFormatting.definition?.usesAI == false)
  #expect(Action.changeCase.definition?.usesAI == false)
  #expect(TextStyle.choices(for: .tone) == [.warm, .direct, .diplomatic])
  #expect(TextStyle.choices(for: .rewrite) == [.natural, .professional, .casual])
}

@Test func textMessageCleaningPreservesStructure() {
  #expect(LocalTextTransform.clean("\u{FEFF}\nHello\u{200B}  \r\n\r\n\r\n  - world\t\n") == "Hello\n\n  - world")
  #expect(LocalTextTransform.clean("```\n    let x =  2\n```\n\nNext paragraph") == "```\n    let x =  2\n```\n\nNext paragraph")
  #expect(LocalTextTransform.clean("```\nlet space = \"\u{200B}\"  \n\n\n``` ") == "```\nlet space = \"\u{200B}\"  \n\n\n``` ")
  #expect(LocalTextTransform.clean("\n\t  ") == "")
  #expect(LocalTextTransform.clean("Hello   world\u{00A0}again") == "Hello world again")
  #expect(LocalTextTransform.clean("    let x =  2\n| A  | B |") == "    let x =  2\n| A  | B |")
  #expect(LocalTextTransform.uppercase.apply("café déjà 😄\nhello") == "CAFÉ DÉJÀ 😄\nHELLO")
}

@Test func textMessageLanguagesKeepRecentOrderWithoutContent() {
  let name = "tero-language-test-\(UUID())"
  let defaults = UserDefaults(suiteName: name)!
  defer { defaults.removePersistentDomain(forName: name) }
  ResponseLanguage.spanish.saveTranslationTarget(to: defaults)
  ResponseLanguage.french.saveTranslationTarget(to: defaults)
  ResponseLanguage.spanish.saveTranslationTarget(to: defaults)
  let languages = ResponseLanguage.translationChoices(from: defaults)
  #expect(Array(languages.prefix(3)) == [.spanish, .french, .english])
  #expect(Set(languages).count == ResponseLanguage.allCases.count)
  #expect(ResponseLanguage.load(from: defaults) == .english)
}

@Test func textMessageNewModesAreSearchableWithoutCrowdingSuggestions() {
  var state = ActionBarState()
  for (query, action) in [("tone", Action.tone), ("simplify", .simplify), ("clean formatting", .cleanFormatting), ("uppercase", .changeCase)] {
    state.beginSearch(query: query)
    #expect(state.suggestions.contains(action))
    #expect(state.suggestions.count <= 3)
    state.endSearch()
  }
}

@Test func improvePromptReplacesEditableSelectionsAndShowsReadOnlyResults() {
  let reading = RecommendationContext(applicationID: nil, content: .text(isNumber: false, editable: false))
  let writing = RecommendationContext(applicationID: nil, content: .text(isNumber: false, editable: true))
  let mode = Action.improvePrompt.definition!
  #expect(mode.accepts(reading) && mode.accepts(writing))
  #expect(mode.usesAI && mode.gatewayAction == "improve_prompt")
  #expect(mode.delivery(canReplace: true) == .replacement)
  #expect(mode.delivery(canReplace: false) == .readingCard)
  #expect(mode.transformsText)
  var state = ActionBarState()
  state.beginSearch(query: "reprompt")
  #expect(state.suggestions.contains(.improvePrompt))
}
