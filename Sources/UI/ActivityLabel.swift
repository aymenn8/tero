import SwiftUI

/// Shared loading shimmer: keep text and its baseline completely stationary.
struct ActivityLabel: View {
  let title: String
  var active = true
  var inactiveOpacity = 0.85
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var startedAt = Date()

  var body: some View {
    if active && !reduceMotion {
      TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
        let elapsed = context.date.timeIntervalSince(startedAt)
        let phase = elapsed.truncatingRemainder(dividingBy: 1.8) / 1.8
        Text(title)
          .foregroundStyle(.white.opacity(0.55))
          .overlay {
            GeometryReader { geometry in
              LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geometry.size.width)
                .offset(x: geometry.size.width * (CGFloat(phase) * 3 - 1.5))
            }.mask(Text(title)).accessibilityHidden(true)
          }
      }
    } else {
      Text(title).foregroundStyle(.white.opacity(inactiveOpacity))
    }
  }
}
