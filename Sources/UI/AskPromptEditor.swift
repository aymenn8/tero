import AppKit
import SwiftUI

struct AskPromptEditor: NSViewRepresentable {
  let query: String
  let update: (String) -> Void
  var submit: (() -> Void)? = nil
  var enabled = true
  var accessibilityLabel = "Ask prompt"
  var accessibilityHelp = "Return to send. Shift Return for a new line."

  func makeCoordinator() -> Coordinator { Coordinator(update: update, submit: submit) }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    let editor = NSTextView(frame: .zero)
    editor.drawsBackground = false
    editor.isRichText = false
    editor.allowsUndo = true
    editor.font = .systemFont(ofSize: 14)
    editor.textColor = .white.withAlphaComponent(0.9)
    editor.insertionPointColor = .white
    editor.textContainerInset = .zero
    editor.textContainer?.lineFragmentPadding = 0
    editor.textContainer?.widthTracksTextView = true
    editor.isHorizontallyResizable = false
    editor.isVerticallyResizable = true
    editor.autoresizingMask = [.width]
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.string = query
    editor.setAccessibilityLabel(accessibilityLabel)
    editor.setAccessibilityHelp(accessibilityHelp)
    editor.delegate = context.coordinator
    scroll.documentView = editor
    DispatchQueue.main.async { [weak editor] in
      guard let editor, let window = editor.window, window.isVisible, window.isKeyWindow else { return }
      window.makeFirstResponder(editor)
      editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
    }
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    context.coordinator.update = update
    context.coordinator.submit = submit
    (scroll.documentView as? NSTextView)?.isEditable = enabled
    (scroll.documentView as? NSTextView)?.setAccessibilityLabel(accessibilityLabel)
    (scroll.documentView as? NSTextView)?.setAccessibilityHelp(accessibilityHelp)
    guard let editor = scroll.documentView as? NSTextView,
          !editor.hasMarkedText(), editor.string != query else { return }
    // External replacements are atomic. The controller retains the last refinement
    // for Undo/Redo; discard native ranges tied to the previous document.
    editor.undoManager?.removeAllActions()
    editor.string = query
    editor.setSelectedRange(NSRange(location: query.utf16.count, length: 0))
  }

  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var update: (String) -> Void
    private let edits = UndoManager()
    var submit: (() -> Void)?
    init(update: @escaping (String) -> Void, submit: (() -> Void)?) { self.update = update; self.submit = submit }
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
      if selector == #selector(NSResponder.insertNewline(_:)),
         !textView.hasMarkedText(), NSApp.currentEvent?.modifierFlags.contains(.shift) != true,
         let submit { submit(); return true }
      return false
    }
    func undoManager(for view: NSTextView) -> UndoManager? { edits }
    func textDidChange(_ notification: Notification) {
      guard let editor = notification.object as? NSTextView else { return }
      update(editor.string)
    }
  }
}
