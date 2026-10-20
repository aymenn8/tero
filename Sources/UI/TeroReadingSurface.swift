import SwiftUI

/// Shared quiet surface for prompt and reading cards; native material remains underneath.
struct TeroReadingSurface: View {
  var cornerRadius: CGFloat = 14
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    RoundedRectangle(cornerRadius: cornerRadius)
      .fill(reduceTransparency ? AnyShapeStyle(Color(white: 0.105)) : AnyShapeStyle(.regularMaterial))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(Color(white: 0.095).opacity(reduceTransparency ? 1 : 0.92))
      }
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.065)],
            startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
      }
  }
}
