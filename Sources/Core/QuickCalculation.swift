import Foundation

/// Deliberately bounded decimal arithmetic. No expression evaluation or network.
enum QuickCalculation {
  enum Operation: String, CaseIterable, Identifiable {
    case add = "+", subtract = "−", multiply = "×", divide = "÷"
    var id: Self { self }
  }

  struct Output: Equatable {
    let text: String
    let approximate: Bool
  }

  static func number(_ text: String) -> Decimal? {
    let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "−", with: "-")
      .replacingOccurrences(of: "\u{00a0}", with: " ")
      .replacingOccurrences(of: "\u{202f}", with: " ")
    guard source.count <= 40,
      source.range(
        of: #"^[+-]?(?:[0-9]+|[0-9]{1,3}(?: [0-9]{3})+)(?:[.,][0-9]+)?$"#,
        options: .regularExpression) != nil
    else { return nil }
    // A single 1,234 / 1.234 can mean two different values. Do not guess.
    if source.range(
      of: #"^[+-]?[1-9][0-9]{0,2}[.,][0-9]{3}$"#,
      options: .regularExpression) != nil
    {
      return nil
    }
    let normalized = source.replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: ",", with: ".")
    guard normalized.filter(\.isNumber).count <= 28,
      let value = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
      !value.isNaN
    else { return nil }
    return value
  }

  static func evaluate(_ left: Decimal, _ operation: Operation, _ right: Decimal) -> Output? {
    guard !left.isNaN, !right.isNaN, !(operation == .divide && right == 0) else { return nil }
    var lhs = left
    var rhs = right
    var result = Decimal()
    let error: Decimal.CalculationError
    switch operation {
    case .add: error = NSDecimalAdd(&result, &lhs, &rhs, .plain)
    case .subtract: error = NSDecimalSubtract(&result, &lhs, &rhs, .plain)
    case .multiply: error = NSDecimalMultiply(&result, &lhs, &rhs, .plain)
    case .divide: error = NSDecimalDivide(&result, &lhs, &rhs, .plain)
    }
    guard error == .noError || error == .lossOfPrecision, !result.isNaN else { return nil }
    var rounded = Decimal()
    NSDecimalRound(&rounded, &result, 12, .plain)
    return Output(
      text: format(rounded), approximate: rounded != result || error == .lossOfPrecision)
  }

  static func format(_ value: Decimal) -> String {
    var copy = value
    return NSDecimalString(&copy, Locale(identifier: "en_US_POSIX"))
  }
}
