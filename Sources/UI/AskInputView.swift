import SwiftUI

struct AskInputView: View {
  static let width: CGFloat = 360
  static let verticalChrome: CGFloat = 104
  static let refinementChrome: CGFloat = 64
  let controller: PanelController
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false
  var body: some View {
    VStack(spacing: 0) {
      if (!controller.askVisible || controller.refiningResult), let text = controller.explanationText {
        ExplanationView(title: controller.readingTitle, questionPreview: controller.askMode ? controller.askQuestionPreview : nil,
          text: text, contentHeight: controller.explanationContentHeight,
          copied: controller.activeShortcut == "⌘C", copy: controller.copyExplanation,
          close: controller.closeExplanation, refine: controller.beginResultRefinement,
          restore: controller.restoreResult, canRestore: controller.canRestoreResult,
          openLink: controller.openExplanationLink, loading: controller.readingInProgress,
          error: controller.readingError, embedded: true)
        if controller.refiningResult { refinementInput }
      } else { editor }
    }
    .background { TeroReadingSurface() }
    .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
    .opacity(revealed ? 1 : 0)
    .scaleEffect(reduceMotion || revealed ? 1 : 0.98, anchor: .topLeading)
    .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.18), value: revealed)
    .onAppear { revealed = true }
  }

  private var refinementInput: some View {
    VStack(spacing: 10) {
      Rectangle().fill(.white.opacity(0.1)).frame(height: 1)
      AskPromptEditor(query: controller.askQuery, update: controller.updateAskQuery,
                      accessibilityLabel: "Changes to the result")
        .frame(height: controller.askEditorHeight)
        .overlay(alignment: .topLeading) {
          if controller.askQuery.isEmpty {
            Text("What would you like to change?").font(.system(size: 14)).foregroundStyle(.white.opacity(0.55))
              .allowsHitTesting(false).accessibilityHidden(true)
          }
        }
      HStack(spacing: 8) {
        if let error = controller.askRefineError { Text(error).font(.system(size: 10)).foregroundStyle(.secondary) }
        Spacer(minLength: 0)
        Button("Cancel", action: controller.backFromAsk).help("Keep this result · esc")
        Button(action: controller.submitAsk) { Image(systemName: "arrow.up").frame(width: 28, height: 28) }
          .accessibilityLabel("Apply changes · Return").help("Apply changes · Return")
          .disabled(controller.askQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }.font(.system(size: 11)).buttonStyle(TeroQuietButtonStyle()).frame(height: 28)
    }.padding(.horizontal, 14).padding(.bottom, 14)
      .frame(width: Self.width, height: controller.askEditorHeight + Self.refinementChrome)
  }

  private var editor: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        TeroModeTitle(title: "Ask", loading: controller.askRefining)
          .frame(maxWidth: .infinity, alignment: .leading)
          .overlay { WindowDragRegion().accessibilityHidden(true) }
        Button(action: controller.backFromAsk) {
          Image(systemName: controller.refiningResult ? "chevron.left" : "xmark").frame(width: 28, height: 28)
        }
        .accessibilityLabel(controller.refiningResult ? "Back" : "Close Tero")
        .help(controller.refiningResult ? "Back · esc" : "Close · esc")
        .buttonStyle(TeroQuietButtonStyle())
      }
      .frame(height: 28)

      AskPromptEditor(query: controller.askQuery, update: controller.updateAskQuery,
                      accessibilityLabel: controller.refiningResult ? "Changes to the result" : "Ask prompt",
                      accessibilityHelp: controller.askRefineError ?? "Return to send. Shift Return for a new line. Command R to refine your request.")
        .frame(height: controller.askEditorHeight)
        .overlay(alignment: .topLeading) {
          if controller.askQuery.isEmpty {
            Text(controller.refiningResult ? "What would you like to change?" : "Ask anything, or find a product…").font(.system(size: 14)).foregroundStyle(.white.opacity(0.55))
              .allowsHitTesting(false).accessibilityHidden(true)
          }
        }
      HStack(spacing: 12) {
        if let error = controller.askRefineError {
          Text(error).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            .help(error)
        }
        Spacer(minLength: 0)
        Button(action: controller.refineAskPrompt) {
          Image(systemName: "wand.and.stars")
            .frame(width: 28, height: 28)
          .overlay {
            if controller.askRefining {
              ModeActivityBorder(cornerRadius: 6)
                .transition(.opacity)
            }
          }
        }
        .help("Make your request clearer and more precise while keeping your intent and language. Review it before sending.\n⌘R to refine · ⌘Z to undo")
        .accessibilityLabel(controller.askRouting ? "Understanding your request" : controller.askRefining ? "Refining your request" : "Refine prompt · Command R. Improve wording without sending your request.")
        .disabled(controller.askRefining || controller.askQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        Button(action: controller.submitAsk) {
          Image(systemName: "arrow.up").frame(width: 28, height: 28)
            .foregroundStyle(.white.opacity(0.95))
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
          .accessibilityLabel(controller.refiningResult ? "Apply changes · Return" : "Ask · Return").help("Send · Return · New line with ⇧Return")
          .disabled(controller.askRefining || controller.askQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .font(.system(size: 11, weight: .medium)).buttonStyle(TeroQuietButtonStyle()).frame(height: 28)
      .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: controller.askRefining)
    }
    .padding(14)
    .frame(width: Self.width, height: controller.askEditorHeight + Self.verticalChrome)
    .transition(.opacity)
  }
}
