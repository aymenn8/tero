/// A free-form request about the selected text: answer a question about it, or write new text from it.
/// Both run through the existing `text_habit` gateway contract (selection + instruction).
enum SelectionAskMode: String, CaseIterable, Sendable {
  case explain, write

  var placeholder: String {
    switch self {
    case .explain: "Ask anything about this text…"
    case .write: "How should Tero rewrite it?"
    }
  }

  /// Not a choice: a confirmed editable selection is rewritten in place, anything else is explained.
  static func detected(canReplace: Bool) -> Self { canReplace ? .write : .explain }

  /// The gateway accepts 1,000 characters of instruction, framing included.
  static let requestLimit = 750

  /// Framing for the person's request. Nil when it is empty or too long.
  func instruction(for request: String) -> String? {
    let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !request.isEmpty, request.unicodeScalars.count <= Self.requestLimit else { return nil }
    switch self {
    case .explain:
      return "Answer the user's question about the selection. Reply in the language of the question, directly and concisely, in at most 200 words. Do not rewrite the selection unless the question asks for it.\nQuestion: " + request
    case .write:
      return "Write new text from the selection, following the user's request. Return only the text that replaces the selection, ready to paste, without quotes or commentary.\nRequest: " + request
    }
  }
}
