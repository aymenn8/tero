import AppKit
import SwiftUI

/// Native field editor keeps selection, shortcuts and input-method composition intact.
struct ActionSearchInput: NSViewRepresentable {
  let query: String
  let update: (String) -> Void
  var placeholder = "Search actions…"

  func makeCoordinator() -> Coordinator { Coordinator(update: update) }

  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField(string: query)
    field.placeholderString = placeholder
    field.font = .systemFont(ofSize: 14)
    field.textColor = .white
    field.usesSingleLineMode = true
    field.cell?.isScrollable = true
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.setAccessibilityLabel(placeholder)
    field.delegate = context.coordinator
    DispatchQueue.main.async { [weak field] in
      guard let field, let window = field.window, window.isVisible, window.isKeyWindow else { return }
      window.makeFirstResponder(field)
      if let editor = field.currentEditor() as? NSTextView {
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.selectedRange = NSRange(location: field.stringValue.utf16.count, length: 0)
      }
    }
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.update = update
    // The editor owns in-progress composition. Changes reach state through its delegate.
    if field.currentEditor() == nil, field.stringValue != query { field.stringValue = query }
    if let editor=field.currentEditor() as? NSTextView,!editor.hasMarkedText(),editor.string != query {
      editor.string=query
      editor.selectedRange=NSRange(location:query.utf16.count,length:0)
    }
  }

  @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
    var update: (String) -> Void
    init(update: @escaping (String) -> Void) { self.update = update }
    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      update(field.stringValue)
    }
  }
}
