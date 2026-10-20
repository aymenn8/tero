import SwiftUI

/// A moving stroke that follows a control’s contour without changing its layout.
struct ModeActivityBorder: View {
  var cornerRadius: CGFloat = 11
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var startedAt = Date()

  var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion)) { context in
          let phase = reduceMotion ? 0.1 : context.date.timeIntervalSince(startedAt).truncatingRemainder(dividingBy: 1.8) / 1.8
          ZStack {
            ForEach(0..<6) { segment in
              let start = (phase + Double(segment) * 0.025).truncatingRemainder(dividingBy: 1)
              let end = start + 0.027
              let color = Color.white.opacity(0.12 + Double(segment) * 0.15)
              RoundedRectangle(cornerRadius: cornerRadius)
                .trim(from: start, to: min(1, end))
                .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
              if end > 1 {
                RoundedRectangle(cornerRadius: cornerRadius)
                  .trim(from: 0, to: end - 1)
                  .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
              }
            }
          }.padding(0.7)
        }.allowsHitTesting(false).accessibilityHidden(true)
  }
}
