import SwiftUI

/// Three independent bubbles converge, join into the exact brand silhouette, then fade in place.
struct OnboardingWelcomeScene: View {
    var animateEntrance = true
    var onReveal: () -> Void = {}
    var onComplete: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = [false, false, false]
    @State private var joined = false
    @State private var finished = false

    private let origins: [CGSize] = [CGSize(width: -130, height: -290), CGSize(width: -350, height: 170), CGSize(width: 340, height: 220)]
    private let destinations: [CGSize] = [CGSize(width: 0, height: -18), CGSize(width: -20, height: 18), CGSize(width: 20, height: 18)]

    var body: some View {
        ZStack {
            if !reduceMotion {
                ForEach(0..<3) { index in
                    Ellipse()
                        .strokeBorder(.white, lineWidth: 8)
                        .frame(width: 44, height: 47)
                        .rotationEffect(.degrees(arrived[index] ? (index == 0 ? 0 : index == 1 ? 35 : -35) : (index == 1 ? -45 : 45)))
                        .offset(arrived[index] ? destinations[index] : origins[index])
                        .opacity(arrived[index] && !joined ? 1 : 0)
                }
            }
            TeroLogoMark(size: 96)
                .opacity(joined ? 1 : 0)
        }
        .opacity(finished ? 0 : 1)
        .frame(width: 860, height: 720)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task { await reveal() }
    }

    private func reveal() async {
        guard !joined else { return }
        guard animateEntrance else { joined = true; onReveal(); onComplete(); return }
        do {
            if reduceMotion {
                withAnimation(.easeOut(duration: 0.2)) { joined = true }
                try await Task.sleep(for: .milliseconds(200))
            } else {
                for index in 0..<3 {
                    withAnimation(.spring(duration: 0.9, bounce: 0.12)) { arrived[index] = true }
                    try await Task.sleep(for: .milliseconds(110))
                }
                try await Task.sleep(for: .milliseconds(850))
                withAnimation(.easeInOut(duration: 0.25)) { joined = true }
                try await Task.sleep(for: .milliseconds(550))
            }
            try Task.checkCancellation()
            onReveal()
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.4)) { finished = true }
            try await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 400))
            try Task.checkCancellation()
            onComplete()
        } catch {
            // Closing or replaying the tour cancels its pending reveal callbacks.
        }
    }
}

/// The last screen becomes the texture of the departing bubbles; no desktop capture.
struct OnboardingFinishScene: View {
    let snapshot: NSImage
    let windowSize: CGSize
    let margin: CGFloat
    let onComplete: () -> Void
    @State private var phase: CGFloat = 0
    var body: some View {
        OnboardingBubbleFragments(snapshot: snapshot, windowSize: windowSize, margin: margin, phase: phase)
            .accessibilityHidden(true).allowsHitTesting(false)
            .task {
                withAnimation(.easeOut(duration: 1.05)) { phase = 1 } completion: { onComplete() }
            }
    }
}

nonisolated struct OnboardingBubbleFragments: View, Animatable {
    let snapshot: NSImage
    let windowSize: CGSize
    let margin: CGFloat
    var phase: CGFloat
    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }
    var body: some View {
        Canvas { context, _ in
            let image = context.resolve(Image(nsImage: snapshot))
            let columns = 18, rows = 14
            let width = windowSize.width / CGFloat(columns)
            let height = windowSize.height / CGFloat(rows)
            for row in 0..<rows {
                for column in 0..<columns {
                    let index = row * columns + column
                    let seed = CGFloat((index * 73 + 19) % 101) / 100
                    let x = (CGFloat(column) + 0.5) * width
                    let y = (CGFloat(row) + 0.5) * height
                    let dx = x - windowSize.width / 2
                    let dy = y - windowSize.height / 2
                    let distance = max(1, hypot(dx, dy))
                    let delay = min(0.18, distance / 3000) + seed * 0.08
                    let progress = min(1, max(0, phase * 1.3 - delay))
                    let travel = progress * (95 + seed * 145)
                    let scale = 1 - progress * 0.72
                    let opacity = max(0, 1 - max(0, progress - 0.18) / 0.72)
                    guard opacity > 0 else { continue }
                    var fragment = context
                    fragment.opacity = Double(opacity)
                    fragment.translateBy(x: margin + x + dx / distance * travel,
                                         y: margin + y + dy / distance * travel + progress * progress * 35)
                    fragment.scaleBy(x: scale, y: scale)
                    let rect = CGRect(x: -width / 2, y: -height / 2, width: width + 0.5, height: height + 0.5)
                    let radius = min(width, height) / 2 * min(1, progress * 7)
                    let bubble = Path(roundedRect: rect, cornerRadius: radius)
                    fragment.clip(to: bubble)
                    fragment.draw(image, in: CGRect(x: -x, y: -y, width: windowSize.width, height: windowSize.height))
                    if progress > 0.02 {
                        fragment.stroke(bubble, with: .color(.white.opacity(0.12)), lineWidth: 0.7)
                    }
                }
            }
        }
    }
}
