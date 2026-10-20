import SwiftUI

/// The chosen mode keeps its compact bubble while the bubbles and label shimmer run.
struct CorrectionActivityView: View {
  let finished: Bool
  var activityLabel = "Correct"
  var allowsCancellation = true
  var compact = false

  var body: some View {
    HStack(spacing: 8) {
      ReadingActivityGlyph(finished: finished).accessibilityHidden(true)
      ActivityLabel(title: activityLabel, active: !finished)
    }
      .font(.system(size: compact ? 11 : 14, weight: .medium))
      .padding(.horizontal, compact ? 12 : 18)
      .frame(height: compact ? 20 : 30)
      .background { TeroReadingSurface(cornerRadius: compact ? 10 : 15) }
      .overlay {
        RoundedRectangle(cornerRadius: compact ? 10 : 15)
          .fill(.white.opacity(finished ? 0.1 : 0))
          .allowsHitTesting(false)
          .animation(.easeOut(duration: 0.18), value: finished)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(finished ? "\(activityLabel) complete" : "\(activityLabel) in progress.\(allowsCancellation ? " Escape to cancel." : "")")
  }
}
