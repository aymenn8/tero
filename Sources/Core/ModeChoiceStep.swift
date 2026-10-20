/// A mode supplies data; the renderer and keyboard navigation do not know its executor.
struct ModeChoiceStep: Equatable, Sendable {
  let label: String
  let choices: [ModeChoice]
  var selectedID: String?
  var backLabel = "Back to actions"

  // nil is the shared Back item. Disabled choices are never keyboard targets.
  func nextSelection(by offset: Int) -> String? {
    let available: [String?] = [nil] + choices.filter(\.enabled).map { Optional($0.id) }
    let index = available.firstIndex(of: selectedID) ?? 0
    return available[((index + offset) % available.count + available.count) % available.count]
  }

  func allows(_ id: String?) -> Bool {
    id == nil || choices.contains { $0.id == id && $0.enabled }
  }
}
