import SwiftUI

struct TeroHeaderDivider: View {
  var body: some View {
    Rectangle().fill(.white.opacity(0.08)).frame(height: 1).accessibilityHidden(true)
  }
}
