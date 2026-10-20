import SwiftUI

struct TeroHomeView: View {
    let controller: PanelController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        HStack(spacing: expanded ? ActionBubble.spacing : 0) {
            TeroLogoBubble()
            ForEach(Array(controller.homeActions.enumerated()), id: \.element.id) { index, action in
                ActionBubble(title: action.title, label: action.accessibilityLabel,
                             selected: controller.homeSelectedIndex == index, leadingSymbol: action.iconName) {
                    controller.runHomeAction(action)
                }
                .fixedSize()
                .opacity(expanded ? 1 : 0)
                .frame(width: expanded ? ActionBubble.width(title: action.title, leadingSymbol: action.iconName) : 0)
                .disabled(!action.isAvailable)
                .opacity(action.isAvailable ? 1 : 0.45)
            }
        }
        // Expand from the same compact brand bubble, without a stagger chain.
        .frame(width: max(480 - 2 * PanelPlacement.contentInset, controller.homeRowWidth))
        .frame(height: 30)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: expanded)
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            expanded = true
        }
    }
}
