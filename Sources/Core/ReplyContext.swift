import Foundation

/// Explicit, bounded AI payload for contextual AI modes; never serialize the whole AX snapshot.
struct ReplyContext: Codable, Equatable, Sendable {
  let applicationName: String?
  let webHost: String?
  let surface: String
  let nearbyText: String?

  init?(_ snapshot: InvocationContext?) {
    guard let snapshot, snapshot.capture != .protectedField else { return nil }
    applicationName = Self.bounded(snapshot.applicationName, limit: 100)
    webHost = Self.bounded(snapshot.webHost, limit: 253)
    surface = snapshot.surface.rawValue
    nearbyText = [.observed, .partial].contains(snapshot.capture)
      ? Self.bounded(snapshot.nearbyText, limit: 960) : nil
  }

  private static func bounded(_ value: String?, limit: Int) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return String(String.UnicodeScalarView(value.unicodeScalars.prefix(limit)))
  }
}
