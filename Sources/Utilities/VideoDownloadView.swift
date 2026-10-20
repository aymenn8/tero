import SwiftUI

/// Shared action bubbles for the YouTube download choices, with download progress below.
struct VideoDownloadView: View {
  let session: VideoDownloadSession
  var body: some View {
    VStack(spacing: 8) {
      let choices = session.presentation
      ModeChoiceRow(step: choices.step, activityTitle: choices.activityTitle, finished: choices.finished, choose: choices.activate)
      if session.busy {
        ProgressView(value: session.progress).progressViewStyle(.linear).tint(.white.opacity(0.85))
          .frame(width: 320).accessibilityLabel("Download progress")
      }
      ModeHint(text: session.message ?? session.hint)
    }
  }
}
