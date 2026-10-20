import SwiftUI

/// One continuous surface: branding expands into activity, then settles on completion.
struct TeroLogoBubble: View {
  var loading = false
  var activityTitle: String? = nil
  var finished = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var width: CGFloat {
    guard let activityTitle else { return 30 }
    return ceil((activityTitle as NSString).size(withAttributes: [.font: ActionBubble.titleFont]).width) + 58
  }

  var body: some View {
    HStack(spacing: 8) {
      ZStack {
        TeroLogoMark().opacity(loading ? 0 : 1)
        if loading { ReadingActivityGlyph(finished: finished) }
      }.frame(width: 14, height: 14).accessibilityHidden(true)
      if let activityTitle {
        ActivityLabel(title: activityTitle, active: loading && !finished)
          .font(.system(size: 14, weight: .medium))
          .fixedSize().transition(.opacity)
      }
    }
      .frame(width: width, height: 30)
      .background { TeroReadingSurface(cornerRadius: 15) }
      .overlay { Capsule().fill(.white.opacity(finished ? 0.08 : 0)).allowsHitTesting(false) }
      .clipShape(Capsule())
      .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
      .animation(.easeOut(duration: 0.12), value: loading)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(activityTitle.map { finished ? "\($0) complete" : "\($0) in progress. Escape to cancel." } ?? (loading ? "Preparing actions" : "Tero"))
      .allowsHitTesting(false)
  }
}
