import SwiftUI

struct FoldingActionRow: View {
  let controller: PanelController
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var searchMorph
  @State private var modesAppeared = false

  var body: some View {
    let executing = controller.state.executing != nil
    let collapsed = controller.invocationOpening || executing || !modesAppeared
    let searching = controller.state.isSearching && !executing
    GeometryReader { row in
      ZStack {
        if searching {
          VStack(spacing: 8) {
            ActionSearchHeader(controller: controller)
              .matchedGeometryEffect(id: "search", in: searchMorph, properties: reduceMotion ? [] : .frame)
            HStack(spacing: ActionBubble.spacing) {
              TeroLogoBubble()
              if controller.presentedActions.isEmpty {
                Text("No matching actions")
                  .font(.system(size: 12))
                  .foregroundStyle(.secondary)
                  .frame(height: 30)
              } else {
                ForEach(Array(controller.presentedActions.enumerated()), id: \.element) { index, action in
                  ActionBubble(title: controller.title(for: action), label: controller.title(for: action), selected: controller.actionSelection == index, leadingSymbol: controller.icon(for: action)) {
                    controller.choosePresented(action)
                  }
                  .help(controller.title(for: action))
                  .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96)).combined(with: .offset(y: -5)))
                }
              }
            }
            .frame(height: 30)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.16), value: controller.presentedActions)
          }
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        } else {
          HStack(spacing: collapsed ? 0 : ActionBubble.spacing) {
            TeroLogoBubble(loading: controller.invocationOpening || executing,
              activityTitle: executing ? controller.textHabitTitle ?? controller.state.executing?.title : nil,
              finished: controller.correctionFinished)
            if controller.clipboardActionEntryID != nil && controller.state.page == .main {
              ActionBubble(title: "Back", label: "Back to clipboard · Escape", selected: false, symbol: "chevron.left", perform: controller.backToClipboardEntry)
                .opacity(collapsed ? 0 : 1)
                .frame(width: collapsed ? 0 : 30).accessibilityHidden(collapsed)
            }
            ForEach(Array(controller.presentedActions.enumerated()), id: \.element) { index, action in
              let symbol = action == .native(.search) ? "magnifyingglass" : action == .native(.back) ? "chevron.left" : action == .native(.more) ? "ellipsis" : nil
              ActionBubble(title: controller.title(for: action), label: controller.title(for: action), selected: controller.actionSelection == index, symbol: symbol, leadingSymbol: controller.icon(for: action)) {
                controller.choosePresented(action)
              }
              .fixedSize()
              .opacity(collapsed ? 0 : 1)
              .scaleEffect(reduceMotion || !collapsed ? 1 : 0.96)
              .blur(radius: reduceMotion || !collapsed ? 0 : 2)
              .animation(.easeOut(duration: 0.1), value: collapsed)
              // Animate allocation rather than shrinking/reflowing the label itself.
              .frame(width: collapsed ? 0 : symbol == nil ? ActionBubble.width(title: controller.title(for: action), leadingSymbol: controller.icon(for: action)) : 30)
              .accessibilityHidden(collapsed)
              .transition(.opacity)
            }
          }
          .allowsHitTesting(!collapsed)
          .accessibilityHidden(controller.invocationOpening)
          .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: collapsed)
          .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: controller.actionPage)
        }
      }
      .frame(width: row.size.width, height: searching ? 68 : 30)
      .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: searching)
    }
    .frame(height: searching ? 68 : 30)
    .task {
      // Stay mounted through ranking, then expand from the same logo surface.
      await Task.yield()
      guard !Task.isCancelled else { return }
      modesAppeared = true
    }
  }
}
