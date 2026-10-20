import Foundation

final class CalculationInputFormatter: Formatter {
  override func string(for obj: Any?) -> String? { obj as? String }
  override func getObjectValue(
    _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
    for string: String,
    errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
  ) -> Bool {
    guard CalculationExpression.accepts(string) else { return false }
    obj?.pointee = string as NSString
    return true
  }
  override func isPartialStringValid(
    _ partialString: String,
    newEditingString: AutoreleasingUnsafeMutablePointer<NSString?>?,
    errorDescription: AutoreleasingUnsafeMutablePointer<NSString?>?
  ) -> Bool {
    CalculationExpression.accepts(partialString)
  }
}
