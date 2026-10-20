import AppKit

/// A typed mode adapter supplies its current choices and handlers to the shared UI.
@MainActor struct ModeChoicePresentation {
  let step: ModeChoiceStep
  var activityTitle: String? = nil
  var finished = false
  var searchQuery: String? = nil
  var search: ((String) -> Void)? = nil
  let select: (String?) -> Void
  let perform: (String?) -> Void

  var rowWidth: CGFloat {
    70 + CGFloat(step.choices.count) * ActionBubble.spacing + step.choices.reduce(0) {
      $0 + ActionBubble.width(title: $1.title, leadingSymbol: $1.iconName)
    }
  }

  func activate(_ id: String?) {
    guard activityTitle == nil, step.allows(id) else { return }
    perform(id)
  }
}
