import Foundation

enum SelectedAddress {
  // Created once: address detection runs during every recommendation pass.
  private static let addressDetector = try? NSDataDetector(types:NSTextCheckingResult.CheckingType.address.rawValue)
  static func query(_ text: String) -> String? {
    let trimmed=text.trimmingCharacters(in:.whitespacesAndNewlines)
    guard (3...240).contains(trimmed.count),trimmed.split(separator:"\n").count<=3,
          trimmed.range(of:#"https?://|[{}<>;]"#,options:.regularExpression)==nil,
          trimmed.rangeOfCharacter(from:.letters) != nil else{return nil}
    return trimmed
  }
  static func looksLikeAddress(_ text: String) -> Bool {
    guard let query=query(text),let detector=addressDetector else{return false}
    let range=NSRange(query.startIndex...,in:query)
    return detector.matches(in:query,range:range).contains { $0.resultType == .address }
  }
}
