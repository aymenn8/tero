import SwiftUI

struct TeroQuietButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var enabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hovered = false
  @Environment(\.isFocused) private var focused

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(.white.opacity(enabled ? (hovered ? 0.95 : 0.65) : 0.25))
      .background(.white.opacity(configuration.isPressed ? 0.11 : hovered ? 0.065 : 0.025),
                  in: RoundedRectangle(cornerRadius: 6))
      .overlay {
        RoundedRectangle(cornerRadius: 6)
          .strokeBorder(.white.opacity(focused ? 0.5 : 0), lineWidth: 1)
      }
      .scaleEffect(reduceMotion || !enabled || !configuration.isPressed ? 1 : 0.96)
      .contentShape(RoundedRectangle(cornerRadius: 6))
      .onHover { hovered = $0 }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
  }
}
