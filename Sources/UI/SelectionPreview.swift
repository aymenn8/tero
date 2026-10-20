import SwiftUI

/// Compact status only; selected text is never duplicated in the overlay.
struct SelectionPreview: View {
  let selection: SelectionReadout
  let openPermissions: () -> Void
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    VStack(spacing: 8) {
      switch selection.status {
      case .selected:
        EmptyView()
      case .noSelection:
        Text("Select some text")
      case .permissionRequired:
        Text("Allow Tero in System Settings")
        Button("Open System Settings ↵", action: openPermissions)
          .buttonStyle(.bordered)
      case .unsupported:
        Text("Selection not accessible in this app")
      case .protectedField:
        Text("Protected field")
      case .unavailable:
        Text("Selection unavailable · Try again")
      }
    }
    .font(.system(size: 13, weight: .medium))
    .fixedSize()
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background {
      RoundedRectangle(cornerRadius: 11)
        .fill(
          reduceTransparency ? AnyShapeStyle(Color(white: 0.13)) : AnyShapeStyle(.regularMaterial))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.14))
    }
  }
}
