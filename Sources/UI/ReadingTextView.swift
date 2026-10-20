import AppKit
import SwiftUI

/// AppKit provides native link hit testing, cursor feedback and text selection.
struct ReadingTextView: NSViewRepresentable {
  let text: AttributedString
  let openLink: (URL) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(openLink: openLink) }

  func makeNSView(context: Context) -> NSTextView {
    let view = NSTextView()
    view.isEditable = false
    view.isSelectable = true
    view.drawsBackground = false
    view.textContainerInset = .zero
    view.textContainer?.lineFragmentPadding = 0
    view.textContainer?.widthTracksTextView = true
    view.isHorizontallyResizable = false
    view.isVerticallyResizable = true
    view.linkTextAttributes = [
      .foregroundColor: NSColor.white.withAlphaComponent(0.95),
      .underlineStyle: NSUnderlineStyle.single.rawValue,
      .cursor: NSCursor.pointingHand
    ]
    view.delegate = context.coordinator
    return view
  }

  func updateNSView(_ view: NSTextView, context: Context) {
    context.coordinator.openLink = openLink
    let value = NSMutableAttributedString(attributedString: NSAttributedString(text))
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4
    value.addAttributes([.font: NSFont.systemFont(ofSize: 13),
      .foregroundColor: NSColor.white.withAlphaComponent(0.9), .paragraphStyle: paragraph],
      range: NSRange(location: 0, length: value.length))
    if view.textStorage?.isEqual(to: value) != true {
      view.textStorage?.setAttributedString(value)
    }
  }

  func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
    guard let width = proposal.width, let container = view.textContainer,
          let layout = view.layoutManager else { return nil }
    container.containerSize = CGSize(width: width, height: .greatestFiniteMagnitude)
    layout.ensureLayout(for: container)
    return CGSize(width: width, height: max(1, ceil(layout.usedRect(for: container).height)))
  }

  @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
    var openLink: (URL) -> Void
    init(openLink: @escaping (URL) -> Void) { self.openLink = openLink }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
      guard let url = link as? URL ?? (link as? String).flatMap(URL.init(string:)) else { return true }
      openLink(url)
      return true
    }
  }
}
