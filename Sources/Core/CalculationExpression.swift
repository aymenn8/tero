import Foundation

/// Bounded recursive descent; never executes code or evaluates arbitrary expressions.
enum CalculationExpression {
  static func accepts(_ text: String) -> Bool {
    text.count <= 256 && text.allSatisfy { "0123456789.,+-*/() ×÷−".contains($0) }
  }

  /// A lone value (including a signed value) is input, not a calculation result.
  static func resultForDisplay(_ text: String) -> QuickCalculation.Output? {
    let normalized = text.replacingOccurrences(of: "−", with: "-")
    var hasLeftOperand = false
    var hasOperation = false
    for character in normalized {
      if character.isNumber || character == ")" { hasLeftOperand = true }
      if "*/×÷".contains(character) || ("+-".contains(character) && hasLeftOperand) {
        hasOperation = true
      }
    }
    return hasOperation ? evaluate(text) : nil
  }

  static func evaluate(_ text: String) -> QuickCalculation.Output? {
    guard accepts(text) else { return nil }
    var parser = Parser(
      characters: Array(
        text.replacingOccurrences(of: ",", with: ".")
          .replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "÷", with: "/")
          .replacingOccurrences(of: "−", with: "-")))
    guard var result = parser.expression(), parser.finished else { return nil }
    var rounded = Decimal()
    NSDecimalRound(&rounded, &result, 12, .plain)
    return .init(
      text: QuickCalculation.format(rounded),
      approximate: parser.approximate || result != rounded)
  }

  private struct Parser {
    let characters: [Character]
    var index = 0
    var approximate = false
    var depth = 0

    mutating func spaces() {
      while index < characters.count && characters[index] == " " { index += 1 }
    }
    var finished: Bool {
      mutating get {
        spaces()
        return index == characters.count
      }
    }
    mutating func take(_ token: Character) -> Bool {
      spaces()
      guard index < characters.count, characters[index] == token else { return false }
      index += 1
      return true
    }
    mutating func expression() -> Decimal? {
      guard var result = term() else { return nil }
      while true {
        let op: QuickCalculation.Operation
        if take("+") { op = .add } else if take("-") { op = .subtract } else { break }
        guard let right = term(), let next = apply(result, op, right) else { return nil }
        result = next
      }
      return result
    }
    mutating func term() -> Decimal? {
      guard var result = factor() else { return nil }
      while true {
        let op: QuickCalculation.Operation
        if take("*") { op = .multiply } else if take("/") { op = .divide } else { break }
        guard let right = factor(), let next = apply(result, op, right) else { return nil }
        result = next
      }
      return result
    }
    mutating func factor() -> Decimal? {
      guard depth < 32 else { return nil }
      depth += 1
      defer { depth -= 1 }
      if take("+") { return factor() }
      if take("-") { return factor().map { -$0 } }
      if take("(") {
        guard let value = expression(), take(")") else { return nil }
        return value
      }
      spaces()
      let start = index
      while index < characters.count, "0123456789.".contains(characters[index]) { index += 1 }
      let number = String(characters[start..<index])
      guard number.filter(\.isNumber).count <= 28,
        number.range(of: #"^(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression)
          != nil,
        let value = Decimal(string: number, locale: Locale(identifier: "en_US_POSIX")),
        !value.isNaN
      else { return nil }
      return value
    }
    mutating func apply(_ left: Decimal, _ operation: QuickCalculation.Operation, _ right: Decimal)
      -> Decimal?
    {
      guard !(operation == .divide && right == 0) else { return nil }
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
      approximate = approximate || error == .lossOfPrecision
      return result
    }
  }
}
