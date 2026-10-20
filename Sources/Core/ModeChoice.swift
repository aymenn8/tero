struct ModeChoice: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let label: String
  var iconName: String? = nil
  var help: String = ""
  var enabled = true
}
