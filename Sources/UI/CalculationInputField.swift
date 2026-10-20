import AppKit

/// Focus once after SwiftUI has attached the calculator, including a transition from search.
final class CalculationInputField: NSTextField {
  private var initiallyFocused = false

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let attachedWindow = window else { return }
    DispatchQueue.main.async { [weak self, weak attachedWindow] in
      guard let self, let attachedWindow, self.window === attachedWindow,
            attachedWindow.isVisible, attachedWindow.isKeyWindow, !self.initiallyFocused else { return }
      if attachedWindow.makeFirstResponder(self) {
        self.initiallyFocused = true
        self.currentEditor()?.selectedRange = NSRange(location: self.stringValue.utf16.count, length: 0)
      }
    }
  }
}
