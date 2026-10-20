import Foundation
import Testing

@testable import TeroCore

@Test func numericSelectionMustBeEntirelyNumeric() {
  #expect(QuickCalculation.number(" 1\u{202f}250,50 ") == Decimal(string: "1250.50"))
  #expect(QuickCalculation.number("−42") == -42)
  #expect(QuickCalculation.number("0,125") == Decimal(string: "0.125"))
  for text in ["120 EUR", "12 pommes", "1,234", "1.234", "1 2", "1e3", "1/2", "", "nan", "12.3.4"] {
    #expect(QuickCalculation.number(text) == nil)
  }
}

@Test func decimalArithmeticAvoidsBinaryRoundingArtifacts() {
  let result = QuickCalculation.evaluate(Decimal(string: "0.1")!, .add, Decimal(string: "0.2")!)
  #expect(result?.text == "0.3")
  #expect(result?.approximate == false)
  #expect(QuickCalculation.evaluate(120, .divide, 4)?.text == "30")
  #expect(QuickCalculation.evaluate(12, .subtract, 20)?.text == "-8")
  #expect(QuickCalculation.evaluate(-5, .multiply, 4)?.text == "-20")
  #expect(QuickCalculation.evaluate(1, .divide, 3)?.approximate == true)
  #expect(QuickCalculation.evaluate(1, .divide, 0) == nil)
}

@Test func numericActionsStayNumericAfterSearchAndEscape() {
  var state = ActionBarState(calculationAvailable: true)
  #expect(state.selected == .calculate)
  #expect(state.actions == [.calculate, .search])
  state.select(.search)
  state.activate()
  let closes = state.escape()
  #expect(!closes)
  #expect(state.selected == .calculate)
  state.activate()
  #expect(state.executing == .calculate)
  state.move(by: 1)
  #expect(state.selected == .calculate)
}
