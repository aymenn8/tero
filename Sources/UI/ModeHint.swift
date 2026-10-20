import AppKit
import SwiftUI

/// Selection notes sit on their own quiet surface so they remain readable over any app.
struct ModeHint: View {
  let text: String
  var maxWidth: CGFloat = 380
  var body: some View {
    Text(text)
      .font(.system(size: 11))
      .foregroundStyle(.white.opacity(0.85))
      .multilineTextAlignment(.center)
      .lineLimit(3)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 10).padding(.vertical, 5)
      .frame(maxWidth: maxWidth)
      .background { TeroReadingSurface(cornerRadius: 8) }
      .help(text)
  }
  static func height(for text: String, width: CGFloat = 380) -> CGFloat {
    let font = NSFont.systemFont(ofSize: 11)
    let bounds = (text as NSString).boundingRect(
      with: CGSize(width: max(1, width - 20), height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
    let lineHeight = ceil(font.ascender - font.descender + font.leading)
    return ceil(min(bounds.height, lineHeight * 3)) + 10
  }
}
