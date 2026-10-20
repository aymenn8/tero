import Foundation
import Testing
@testable import TeroCore

@Test func replyIsSearchableBeyondSixSuggestionsAndUsesExistingDelivery() {
  var state = ActionBarState()
  #expect(!state.actions.contains(.reply))
  state.select(.more); state.activate()
  #expect(state.suggestions == [.rewrite, .keyPoints, .extractTasks])
  state.beginSearch(query: "répondre")
  #expect(state.suggestions == [.reply])
  state.activate()
  #expect(state.executing == .reply)
  #expect(Action.reply.definition?.delivery(canReplace: true) == .replacement)
  #expect(Action.reply.definition?.delivery(canReplace: false) == .readingCard)
  #expect(Action.reply.definition?.options == .replyIntent)
  state.returnFromOptions()
  #expect(state.isSearching && state.searchQuery == "répondre")
  #expect(!ActionBarState(calculationAvailable: true).suggestions.contains(.reply))
}

@Test func replyContextIsAllowlistedBoundedAndNotWholeSnapshot() throws {
  var context = InvocationContext(capturedAt: .now, applicationID: "private.bundle.id")
  context.capture = .observed
  context.applicationName = String(repeating: "a", count: 150)
  context.webHost = "example.test"
  context.nearbyText = String(repeating: "🙂", count: 1200)
  context.windowTitle = "PRIVATE TITLE"
  context.elementLabel = "PRIVATE LABEL"
  context.containers = [.init(role: "AXWindow", label: "PRIVATE CONTAINER")]
  let value = try #require(ReplyContext(context))
  #expect(value.applicationName?.count == 100)
  #expect(value.nearbyText?.unicodeScalars.count == 960)
  let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
  #expect(Set(object.keys) == ["applicationName", "webHost", "nearbyText", "surface"])
  context.capture = .protectedField
  #expect(ReplyContext(context) == nil)
  context.capture = .unavailable
  #expect(ReplyContext(context)?.nearbyText == nil)
  #expect(ReplyContext(nil) == nil)
}

@Test func replyIntentsOnlyDecodeKnownChoices() throws {
  #expect(try JSONDecoder().decode(ReplyIntent.self, from: Data("\"accept\"".utf8)) == .accept)
  #expect(throws: (any Error).self) { try JSONDecoder().decode(ReplyIntent.self, from: Data("\"delete_files\"".utf8)) }
  #expect(Set(ReplyIntent.allCases.map(\.title)).count == ReplyIntent.allCases.count)
}
