import SwiftUI

struct ActionSearchHeader: View {
  let controller: PanelController

  var body: some View {
    HStack(spacing: 10) {
      Button("Back to suggestions", systemImage: "chevron.left", action: controller.endActionSearch)
        .labelStyle(.iconOnly)
        .buttonStyle(TeroQuietButtonStyle())
        .frame(width: 20, height: 20)
        .foregroundStyle(.secondary)
        .help("Back · Esc")
      ActionSearchInput(query: controller.state.searchQuery, update: controller.updateActionSearch)
        .id(controller.state.searchSession)
        .frame(height: 18)
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
    .font(.system(size: 13, weight: .medium))
    .padding(.horizontal, 12)
    .frame(width: 320, height: 30)
    .background { TeroReadingSurface(cornerRadius: 15) }
    .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
  }
}
