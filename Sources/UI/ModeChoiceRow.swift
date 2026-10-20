import SwiftUI

/// Shared option bubbles, Back and fold/loading transition for every choice step.
/// An optional native input slot supports parameter entry without duplicating the row.
struct ModeChoiceRow<Accessory: View>: View {
  let step: ModeChoiceStep
  let activityTitle: String?
  let finished: Bool
  let choose: (String?) -> Void
  let accessory: Accessory
  var searchQuery: String? = nil
  var search: ((String) -> Void)? = nil
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false

  init(step: ModeChoiceStep, activityTitle: String? = nil, finished: Bool = false,
       searchQuery: String? = nil, search: ((String) -> Void)? = nil,
       choose: @escaping (String?) -> Void, @ViewBuilder accessory: () -> Accessory) {
    self.step = step; self.activityTitle = activityTitle; self.finished = finished
    self.choose = choose; self.accessory = accessory()
    self.searchQuery=searchQuery; self.search=search
  }

  var body: some View {
    let busy = activityTitle != nil
    VStack(alignment:.leading,spacing:8) {
    if let searchQuery,let search,!busy {
      HStack(spacing:8) {
        Image(systemName:"magnifyingglass").font(.system(size:11)).foregroundStyle(.secondary)
        ActionSearchInput(query:searchQuery,update:search,placeholder:"Search choices…")
      }.padding(.horizontal,10).frame(height:30).background{TeroReadingSurface()}
    }
    GeometryReader { row in
      HStack(spacing: busy ? 0 : ActionBubble.spacing) {
        TeroLogoBubble(loading: busy, activityTitle: activityTitle, finished: finished)
        ActionBubble(title: "Back", label: step.backLabel, selected: step.selectedID == nil,
                     symbol: "chevron.left") { choose(nil) }
          .fixedSize().opacity(busy ? 0 : 1)
          .frame(width: busy ? 0 : 30).accessibilityHidden(busy)
        accessory.fixedSize().opacity(busy ? 0 : 1)
          .frame(width: busy ? 0 : nil).accessibilityHidden(busy)
        ForEach(step.choices) { option in
          ActionBubble(title: option.title, label: option.label, selected: step.selectedID == option.id, leadingSymbol: option.iconName) {
            choose(option.id)
          }
          .disabled(!option.enabled || busy)
          .help(option.help.isEmpty ? option.label : option.help)
          .fixedSize().opacity(busy ? 0 : 1)
          .scaleEffect(reduceMotion || !busy ? 1 : 0.96)
          .blur(radius: reduceMotion || !busy ? 0 : 2)
          .animation(.easeOut(duration: 0.1), value: busy)
          .frame(width: busy ? 0 : ActionBubble.width(title: option.title, leadingSymbol: option.iconName))
          .accessibilityHidden(busy)
        }
      }
      .allowsHitTesting(!busy)
      .frame(width: row.size.width, height: 30)
      .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.28, dampingFraction: 0.88), value: busy)
    }
    .frame(height: 30)
    }
    .opacity(revealed ? 1 : 0)
    .onAppear { withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.2)) { revealed = true } }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(step.label)
  }
}

extension ModeChoiceRow where Accessory == EmptyView {
  init(step: ModeChoiceStep, activityTitle: String? = nil, finished: Bool = false,
       searchQuery: String? = nil, search: ((String) -> Void)? = nil,
       choose: @escaping (String?) -> Void) {
    self.init(step: step, activityTitle: activityTitle, finished: finished, searchQuery:searchQuery,search:search,choose: choose) { EmptyView() }
  }
}
