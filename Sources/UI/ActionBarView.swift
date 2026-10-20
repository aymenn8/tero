import SwiftUI

struct ActionBarView: View {
  let controller: PanelController
  @Namespace private var askTransition
  @Environment(\.accessibilityReduceMotion) private var reduceMotion


  private var displaysMainRow: Bool {
    guard !controller.allowanceReached, controller.shoppingSession == nil,
          !controller.clipboardVisible, controller.utilitySession == nil,
          controller.commitmentSession == nil, controller.fileWorkflow == nil, controller.videoDownload == nil,
          controller.fileContext == nil,
          !controller.homeVisible, !controller.askVisible,
          controller.calculatorValue == nil, controller.modeChoices == nil else { return false }
    if let text = controller.explanationText {
      return text.isEmpty && controller.readingInProgress && !controller.askMode
    }
    return controller.correctionMessage == nil && controller.selection?.hasSelection == true
  }

  var body: some View {
    VStack(spacing: 0) {
      if controller.invocationOpening || displaysMainRow {
        FoldingActionRow(controller: controller)
      } else if controller.allowanceReached {
        AllowanceReachedView(needsSetup: controller.signInRequired, open: controller.openAllowanceAccount, close: { controller.dismiss() })
      } else if let session = controller.shoppingSession {
        ShoppingView(session: session)
      } else if controller.clipboardVisible, let store = controller.clipboardStore {
        ClipboardHistoryView(controller: controller, store: store)
      } else if let session = controller.utilitySession {
        SelectionUtilityView(session: session, close: controller.backFromUtility)
          .onChange(of: session.options) { _, _ in controller.updateUtilityPresentation() }
          .onChange(of: session.busy) { _, _ in controller.updateUtilityPresentation() }
          .onChange(of: session.message) { _, _ in controller.updateUtilityPresentation() }
          .onChange(of: session.choosingDate) { _, _ in controller.updateUtilityPresentation() }
      } else if let session = controller.commitmentSession {
        CommitmentReviewView(session: session, openSettings: controller.openCommitmentSettings) { controller.closeCommitmentReview(session) }
          .onChange(of: session.reviewHeight) { _, _ in controller.updateCommitmentPresentation() }
          .onChange(of: session.message) { _, _ in controller.updateCommitmentPresentation() }
          .onChange(of: session.needsSettings) { _, _ in controller.updateCommitmentPresentation() }
          .transition(.opacity)
      } else if let session = controller.videoDownload {
        VideoDownloadView(session: session)
      } else if let session = controller.fileWorkflow {
        FileWorkflowView(session: session)
          .onChange(of: session.destination) { _, _ in controller.updateFileWorkflowPresentation() }
      } else if controller.fileContext != nil {
        FoldingActionRow(controller: controller)
      } else if controller.homeVisible {
        TeroHomeView(controller: controller)
          .transition(.opacity)
      } else if controller.askVisible || (controller.askMode && controller.explanationText != nil) {
        AskInputView(controller: controller)

      } else if let value = controller.calculatorValue {
        CalculatorView(
          value: value, copyResult: controller.copyCalculation,
          pasteResult: controller.pasteCalculation,
          canPaste: controller.selection?.canPaste == true && !controller.isPasting,
          pasteMessage: controller.pasteMessage, activeShortcut: controller.activeShortcut)
      } else if let choices = controller.modeChoices {
        ModeChoiceRow(step: choices.step, activityTitle: choices.activityTitle,
                      finished: choices.finished, searchQuery:choices.searchQuery,search:choices.search,choose: choices.activate)
      } else if let text = controller.explanationText {
        if text.isEmpty && controller.readingInProgress && !controller.askMode {
          FoldingActionRow(controller: controller)
        } else {
        ExplanationView(title: controller.textHabitTitle ?? (controller.askMode ? "Ask" : controller.state.executing == .translate
                          ? "Translation · \(controller.translationTarget.title)" : (controller.state.executing?.title ?? "Result")),
                        questionPreview: controller.askMode ? controller.askQuestionPreview : nil,
                        text: text, contentHeight: controller.explanationContentHeight,
                        copied: controller.activeShortcut == "⌘C",
                        copy: controller.copyExplanation, close: controller.closeExplanation, refine: controller.beginResultRefinement,
                        restore: controller.restoreResult, canRestore: controller.canRestoreResult,
                        openLink: controller.openExplanationLink,
                        loading: controller.readingInProgress, error: controller.readingError)
          .matchedGeometryEffect(id: controller.askMode ? "ask-surface" : "reading-surface", in: askTransition, properties: reduceMotion ? [] : .frame)
          .transition(.opacity)
        }

      } else if let message = controller.correctionMessage {
        CorrectionResultView(message: message, text: controller.correctionText) {
          if let text = controller.correctionText { controller.copyCalculation(text) }
          controller.dismiss()
        }
      } else if controller.selection?.hasSelection == true {
        FoldingActionRow(controller: controller)
      } else if let selection = controller.selection {
        SelectionPreview(
          selection: selection, openPermissions: controller.openAccessibilitySettings)
      }
    }
    .foregroundStyle(.primary)
    .onChange(of: controller.modeChoices?.step) { _, _ in controller.resizeModeChoiceRow() }
    .animation(reduceMotion ? .easeOut(duration: 0.12)
               : .easeOut(duration: 0.18), value: controller.askVisible)
    .preferredColorScheme(.dark)
    .padding(PanelPlacement.contentInset)
    .frame(maxWidth: .infinity, maxHeight: .infinity,
           alignment: controller.askVisible || controller.homeVisible ? .topLeading : controller.explanationText == nil ? .center : .top)
    .allowsHitTesting(!controller.closing && !controller.isPasting && !controller.invocationOpening)
    .scaleEffect(x: reduceMotion || controller.clipboardVisible || controller.correctionFinished || !controller.closing ? 1 : 0.88,
                 y: reduceMotion || controller.clipboardVisible || controller.correctionFinished || !controller.closing ? 1 : 0.96)
    .opacity(controller.appeared && !controller.closing ? 1 : 0)
    .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.18), value: controller.closing)
    .offset(y: reduceMotion || controller.appeared ? 0 : 3)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Tero, contextual actions")
  }
}
