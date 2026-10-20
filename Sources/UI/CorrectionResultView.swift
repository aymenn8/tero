import SwiftUI

struct CorrectionResultView: View {
  let message: String
  let text: String?
  let copy: () -> Void
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let text {
        Button(action: copy) {
          Text(text).font(.system(size: 14)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("Copy result")
      }
      Text(message)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(width: 340, alignment: .leading)
    .background {
      RoundedRectangle(cornerRadius: 11).fill(
        reduceTransparency ? AnyShapeStyle(Color(white: 0.13)) : AnyShapeStyle(.regularMaterial))
    }
    .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.16)) }
  }
}
