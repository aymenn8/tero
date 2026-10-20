import SwiftUI

/// Three translucent bubbles breathe together, then blend into one on completion.
struct ReadingActivityGlyph: View {
  var finished = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var startedAt = Date()
  @State private var finishedAt: Date?

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
      let elapsed = context.date.timeIntervalSince(startedAt)
      let completionElapsed = finishedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
      let progress = finished ? (reduceMotion ? 1 : min(1, completionElapsed / 0.4)) : 0
      let settle = progress * progress * (3 - 2 * progress)
      Canvas { canvas, _ in
        for index in 0..<3 {
          let phase = elapsed * 2 * .pi / 1.8 - Double(index) * 2 * .pi / 3
          let breath = reduceMotion ? 0.5 : (1 + sin(phase)) / 2
          // A small rocking motion keeps the bubbles floating without spinning.
          let rock = reduceMotion ? 0 : sin(elapsed * 2 * .pi / 3.6) * 0.16
          let angle = Double(index) * 2 * .pi / 3 - .pi / 2 + rock
          let radius = (3.2 + breath * 0.4) * (1 - settle)
          let size = (4.2 + breath * 0.7) * (1 - settle) + 7.5 * settle
          let rect = CGRect(x: 7 + cos(angle) * radius - size / 2,
                            y: 7 + sin(angle) * radius - size / 2, width: size, height: size)
          let bubble = Path(ellipseIn: rect)
          // Divide opacity as they merge, avoiding an abrupt white flash from overlap.
          let fillOpacity = (0.12 + breath * 0.12) * (1 - settle) + 0.16 * settle
          let rimOpacity = (0.3 + breath * 0.35) * (1 - settle) + 0.35 * settle
          canvas.fill(bubble, with: .color(.white.opacity(fillOpacity)))
          canvas.stroke(bubble, with: .linearGradient(
            Gradient(colors: [.white.opacity(rimOpacity), .white.opacity(rimOpacity * 0.35)]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY),
            endPoint: CGPoint(x: rect.maxX, y: rect.maxY)), lineWidth: 0.65)
        }
      }
    }
    .frame(width: 14, height: 14)
    .onAppear { if finished { finishedAt = Date() } }
    .onChange(of: finished) { _, complete in finishedAt = complete ? Date() : nil }
    .accessibilityLabel(finished ? "Complete" : "Generating response")
  }
}
