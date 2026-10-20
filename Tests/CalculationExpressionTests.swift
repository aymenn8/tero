import Testing

@testable import TeroCore

@Test func expressionsRespectPrecedenceAndParentheses() {
  #expect(CalculationExpression.evaluate("120 / 4 + 10")?.text == "40")
  #expect(CalculationExpression.evaluate("2 + 3 * 4")?.text == "14")
  #expect(CalculationExpression.evaluate("(2 + 3) * 4")?.text == "20")
  #expect(CalculationExpression.evaluate("-2 * -3")?.text == "6")
  #expect(CalculationExpression.evaluate("0,1 + 0.2")?.text == "0.3")
  #expect(CalculationExpression.evaluate("10 / 2 / 5")?.text == "1")
  #expect(CalculationExpression.evaluate("1.234 + 1")?.text == "2.234")
}

@Test func incompleteOrInvalidCalculationsHaveNoResult() {
  for value in ["", "120 /", "1/0", "(2+3", "1..2", "2 3", "2**3", "1e2", "hello", "2(3)"] {
    #expect(CalculationExpression.evaluate(value) == nil)
  }
  #expect(CalculationExpression.evaluate(String(repeating: "(", count: 40) + "1") == nil)
  #expect(!CalculationExpression.accepts("120a"))
  #expect(!CalculationExpression.accepts("12 USD"))
  #expect(!CalculationExpression.accepts(String(repeating: "1", count: 257)))
  #expect(CalculationExpression.accepts("(120 + 3) / -2,5"))
}

@Test func resultIsHiddenUntilThereIsACompleteOperation() {
  for value in ["120", "-120", "+120", "(120)", "120 /", "120/0", ""] {
    #expect(CalculationExpression.resultForDisplay(value) == nil)
  }
  #expect(CalculationExpression.resultForDisplay("120 / 4")?.text == "30")
  #expect(CalculationExpression.resultForDisplay("-120 + 20")?.text == "-100")
  #expect(CalculationExpression.resultForDisplay("0,5 * 2")?.text == "1")
}
