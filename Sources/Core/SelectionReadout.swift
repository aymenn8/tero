import Foundation

/// Ephemeral selection data. Never encoded, logged or persisted.
struct SelectionReadout: Equatable, Sendable {
  enum Status: Equatable, Sendable {
    case selected(String)
    case noSelection
    case permissionRequired
    case unsupported
    case protectedField
    case unavailable
  }

  let applicationName: String
  let processIdentifier: Int32
  let status: Status
  var context: InvocationContext? = nil
  var targetID: UUID? = nil
  var metadata: SelectionMetadata? = nil

  var canInsertClipboard: Bool {
    canPaste || (status == .noSelection && targetID != nil && metadata?.isEditable == true && metadata?.range?.length == 0)
  }

  /// Capture failures and protected fields are not evidence of an empty selection.
  var opensHome: Bool { status == .noSelection }

  var canPaste: Bool {
    hasSelection && targetID != nil && metadata?.isEditable == true
      && (metadata?.range?.length ?? 0) > 0
  }

  var hasSelection: Bool {
    if case .selected(let text) = status { return !text.isEmpty }
    return false
  }

  var isTransient: Bool {
    !hasSelection && status != .permissionRequired
  }

  var preview: String? {
    guard case .selected(let text) = status else { return nil }
    let prefix = String(text.prefix(240))
    return text.count > 240 ? prefix + "…" : prefix
  }

  var characterCount: Int? {
    guard case .selected(let text) = status else { return nil }
    return text.count
  }

  static func status(for text: String) -> Status {
    // Whitespace can be an intentional selection. Preserve it exactly.
    text.isEmpty ? .noSelection : .selected(text)
  }
}
