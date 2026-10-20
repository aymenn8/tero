import Foundation

/// Strict single-quantity parsing; never infer separators from the user's locale.
enum SelectionQuantity {
  // Compiled once: unit and currency actions parse every selection during recommendation.
  private static let quantityPattern = try? NSRegularExpression(pattern: #"^\s*([+-]?\d+(?:[.,]\d+)?)\s*(.*?)\s*$"#)
  static func parts(_ text: String) -> (amount: Double, suffix: String)? {
    guard text.count <= 120, let regex = quantityPattern,
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let numberRange = Range(match.range(at: 1), in: text), let suffixRange = Range(match.range(at: 2), in: text) else { return nil }
    let number = String(text[numberRange])
    // 1,234 could mean a decimal or thousands. Require an unambiguous spelling.
    if number.contains(","), number.split(separator: ",").last?.count == 3 { return nil }
    guard let amount = Double(number.replacingOccurrences(of: ",", with: ".")), amount.isFinite, abs(amount) <= 1e15 else { return nil }
    return (amount, String(text[suffixRange]).lowercased())
  }
  static func formatted(_ number: Double, digits: Int = 8) -> String {
    let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal; formatter.usesGroupingSeparator = false
    formatter.maximumFractionDigits = digits
    let result = formatter.string(from: NSNumber(value: number)) ?? String(number)
    return result == "0" && number != 0 ? String(format: "%.8g", number) : result
  }
}
