enum TextStyle: String, CaseIterable, Codable, Sendable {
  case natural, professional, casual, warm, direct, diplomatic

  var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
  static func choices(for action: Action) -> [Self] {
    action == .rewrite ? [.natural, .professional, .casual] : action == .tone ? [.warm, .direct, .diplomatic] : []
  }
}
