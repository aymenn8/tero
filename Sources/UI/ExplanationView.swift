import SwiftUI

struct ExplanationView: View {
  static let verticalChrome: CGFloat = 66
  var title = "Explain"
  var questionPreview: String?
  let text: String
  let contentHeight: CGFloat
  let copied: Bool
  let copy: () -> Void
  let close: () -> Void
  var refine: (() -> Void)? = nil
  var restore: (() -> Void)? = nil
  var canRestore = false
  let openLink: (URL) -> Void
  var loading = false
  var error: String?
  var embedded = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false

  private var renderedText: AttributedString {
    var value = (try? AttributedString(markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    let visible = String(value.characters)
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
      for match in detector.matches(in: visible, range: NSRange(visible.startIndex..., in: visible)) {
        guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let range = Range(match.range, in: visible),
              let start = AttributedString.Index(range.lowerBound, within: value),
              let end = AttributedString.Index(range.upperBound, within: value) else { continue }
        value[start..<end].link = url
      }
    }
    for run in value.runs where run.link != nil { value[run.range].underlineStyle = .single }
    return value
  }

  var body: some View {
    let cardHeight = contentHeight + Self.verticalChrome
    ZStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 8) {
          TeroModeTitle(title: title, loading: loading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .overlay { WindowDragRegion().accessibilityHidden(true) }
            .help("Drag to move")
          if canRestore, let restore {
            Button(action: restore) { Image(systemName: "chevron.left").frame(width: 28, height: 28) }
              .help("Return to the previous result").accessibilityLabel("Restore previous result")
          }
          if !loading, let refine {
            Button(action: refine) { Image(systemName: "square.and.pencil").frame(width: 28, height: 28) }
              .help("Refine result · ⌘R").accessibilityLabel("Refine result · Command R")
              .disabled(loading || error != nil || text.isEmpty)
          }
          if !loading && !text.isEmpty {
          Button(action: copy) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
              .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
              .frame(width: 28, height: 28)
          }
          .help("Copy result · ⌘C")
          .accessibilityLabel(copied ? "Result copied" : "Copy result")
          .disabled(loading || error != nil || text.isEmpty)
          }
          Button(action: close) {
            Image(systemName: "xmark").frame(width: 28, height: 28)
          }
          .help("Close · esc")
          .accessibilityLabel("Close result")
        }
        .frame(height: 28)
        .font(.system(size: 11, weight: .medium))
        .buttonStyle(TeroQuietButtonStyle())

        ScrollView {
          VStack(alignment: .leading, spacing: 10) {
            if let questionPreview {
              ActivityLabel(title: questionPreview, active: loading, inactiveOpacity: 0.55).font(.system(size: 12)).lineLimit(2)
            }
            ReadingTextView(text: renderedText, openLink: openLink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(text.isEmpty ? 0 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: text.isEmpty)
            if let error {
              Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: contentHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: text.isEmpty)
        .scrollBounceBehavior(.basedOnSize)
      }
      .padding(14)
      .frame(width: 360, height: cardHeight, alignment: .top)
    }
    .frame(width: 360, height: cardHeight, alignment: .top)
    .background { if !embedded { TeroReadingSurface() } }
    .opacity(embedded || revealed ? 1 : 0)
    // Keep the native text view at its final size: reveal without a resizing mask.
    .scaleEffect(embedded || reduceMotion || revealed ? 1 : 0.98, anchor: .topLeading)
    .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18), value: revealed)
    .shadow(color: .black.opacity(embedded ? 0 : 0.24), radius: 3, y: 2)
    .onAppear { revealed = true }
  }
}
