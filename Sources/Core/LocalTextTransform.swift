import Foundation

/// Deterministic transformations run on this Mac, without an AI request.
enum LocalTextTransform: String, CaseIterable, Sendable {
  case lowercase, uppercase, titleCase
  var title: String {
    switch self { case .lowercase: "lowercase"; case .uppercase: "UPPERCASE"; case .titleCase: "Title Case" }
  }
  func apply(_ text: String) -> String {
    switch self {
    case .lowercase: text.lowercased()
    case .uppercase: text.uppercased()
    case .titleCase: text.capitalized
    }
  }
  static func clean(_ text: String) -> String {
    // Preserve paragraphs, indentation and Markdown/code structure. Remove only
    // invisible artifacts, repeated prose spaces and excess empty lines. Fenced
    // code keeps its original spacing and contents.
    var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
    var lines: [String] = []
    var blanks = 0
    var fence: String?
    for line in normalized.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      let marker = trimmed.hasPrefix("```") ? "```" : trimmed.hasPrefix("~~~") ? "~~~" : nil
      if fence != nil || marker != nil {
        if let marker { fence = fence == marker ? nil : fence ?? marker }
        lines.append(line)
        blanks = 0
        continue
      }
      var clean = line.replacingOccurrences(of: "\u{FEFF}", with: "")
        .replacingOccurrences(of: "\u{200B}", with: "")
        .replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
      let indentation = clean.prefix { $0 == " " || $0 == "\t" }
      if marker == nil && fence == nil && indentation.count < 4 && !clean.contains("\t") && !trimmed.hasPrefix("|") {
        let body = String(clean.dropFirst(indentation.count)).replacingOccurrences(of: "\u{00A0}", with: " ")
          .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        clean = String(indentation) + body
      }
      if clean.isEmpty { blanks += 1 } else { blanks = 0 }
      if blanks <= 1 { lines.append(clean) }
    }
    while lines.first == "" { lines.removeFirst() }
    while lines.last == "" { lines.removeLast() }
    return lines.joined(separator: "\n")
  }
}
