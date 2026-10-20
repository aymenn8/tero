import SwiftUI

struct CalculatorView: View {
  let pasteResult: (String) -> Void
  let canPaste: Bool
  let pasteMessage: String?
  let activeShortcut: String?
  let copyResult: (String) -> Void
  @State private var expression: String
  @State private var revealed = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(
    value: Decimal, copyResult: @escaping (String) -> Void, pasteResult: @escaping (String) -> Void,
    canPaste: Bool, pasteMessage: String?, activeShortcut: String?
  ) {
    self.copyResult = copyResult
    self.pasteResult = pasteResult
    self.canPaste = canPaste
    self.pasteMessage = pasteMessage
    self.activeShortcut = activeShortcut
    _expression = State(initialValue: QuickCalculation.format(value))
  }

  var body: some View {
    let result = CalculationExpression.resultForDisplay(expression)
    VStack(alignment: .trailing, spacing: 6) {
      HStack(spacing: 4) {
        shortcutHint("esc", explanation: "Close", available: true, index: 0)
        shortcutHint(
          "↵", explanation: pasteMessage ?? (canPaste ? "Paste result" : "Paste unavailable"),
          available: canPaste && pasteMessage == nil && result != nil, index: 1)
        shortcutHint("⌘C", explanation: "Copy result", available: result != nil, index: 2)
      }
      .padding(.trailing, 4)
      HStack(spacing: 10) {
        CalculationInput(text: $expression) {
          guard canPaste, pasteMessage == nil, let result else { return }
          pasteResult(result.text)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 18)
        if let result {
          Button {
            copyResult(result.text)
          } label: {
            Text("\(result.approximate ? "≈ " : "= ")\(result.text)")
              .font(.system(size: 14, weight: .medium).monospacedDigit())
              .lineLimit(1)
              .truncationMode(.middle)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .frame(maxWidth: 120, alignment: .trailing)
          .accessibilityLabel(
            "Result: \(result.text). Command C to copy. Return to paste when available."
          )
          .help(
            pasteMessage
              ?? (canPaste
                ? "⌘C Copy · ↵ Replace original selection"
                : "⌘C Copy · Paste unavailable for this selection")
          )
          .transition(.opacity)
        }
      }
      .padding(.horizontal, 12)
      .frame(width: 320, height: 30)
      .background {
        RoundedRectangle(cornerRadius: 11)
          .fill(
            reduceTransparency ? AnyShapeStyle(Color(white: 0.13)) : AnyShapeStyle(.regularMaterial))
      }
      .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.16)) }

    }
    .opacity(revealed ? 1 : 0)
    .scaleEffect(x: reduceMotion || revealed ? 1 : 0.82, y: 1, anchor: .center)
    .onAppear {
      withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22)) {
        revealed = true
      }
    }
    .animation(.easeOut(duration: 0.12), value: result != nil)
  }

  private func shortcutHint(_ key: String, explanation: String, available: Bool, index: Int) -> some View {
    let active = activeShortcut == key
    return Text(active && key == "⌘C" ? "✓" : key)
      .frame(width: key == "↵" ? 10 : 20)
      .contentTransition(.opacity)
      .font(.system(size: 10, weight: .medium))
      .foregroundStyle(.secondary)
      .opacity(available ? 1 : 0.4)
      .padding(.horizontal, 6)
      .frame(height: 18)
      .background {
        RoundedRectangle(cornerRadius: 5).fill(
          reduceTransparency ? AnyShapeStyle(Color(white: 0.13)) : AnyShapeStyle(.regularMaterial))
      }
      .overlay {
        RoundedRectangle(cornerRadius: 5)
          .fill(.white.opacity(active ? 0.18 : 0))
      }
      .scaleEffect(reduceMotion ? 1 : (active ? 0.9 : 1))
      .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.25, bounce: 0.25), value: active)
      .opacity(revealed ? 1 : 0)
      .offset(y: reduceMotion || revealed ? 0 : 5)
      .animation(
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0.2).delay(0.06 * Double(index)),
        value: revealed)
      .help(explanation)
      .accessibilityLabel("\(key) : \(explanation)")
      .accessibilityValue(available ? "Available" : "Unavailable")
  }

}
