import AppKit
import SwiftUI

struct CalculationInput: NSViewRepresentable {
  @Binding var text: String
  var submit: () -> Void = {}

  func makeCoordinator() -> Coordinator { Coordinator(text: $text, submit: submit) }

  func makeNSView(context: Context) -> NSTextField {
    let field = CalculationInputField(string: text)
    field.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
    field.usesSingleLineMode = true
    field.cell?.isScrollable = true
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.formatter = CalculationInputFormatter()
    field.delegate = context.coordinator
    field.setAccessibilityLabel("Calculation")
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.text = $text
    context.coordinator.submit = submit
    if field.stringValue != text { field.stringValue = text }
  }

  @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
    var text: Binding<String>
    var submit: () -> Void
    init(text: Binding<String>, submit: @escaping () -> Void) {
      self.text = text
      self.submit = submit
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool
    {
      if selector == #selector(NSResponder.insertNewline(_:)) {
        submit()
        return true
      }
      return false
    }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      text.wrappedValue = field.stringValue
    }
  }
}
