import SwiftUI
import AppKit
import CoreText

/// Shared 11-point Inter heading, with a native system-font fallback.
struct TeroModeTitle: View {
  @MainActor static let nativeFont: NSFont = {
    if let url=Bundle.main.url(forResource:"InterVariable",withExtension:"ttf") {
      CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
    }
    return NSFont(name:"InterVariable",size:11)
      ?? NSFont(name:"Inter-Regular",size:11)
      ?? NSFont(name:"Inter",size:11)
      ?? NSFont.systemFont(ofSize:11,weight:.regular)
  }()
  let title: String
  var loading = false
  var body: some View {
    HStack(spacing: 8) {
      ZStack {
        TeroLogoMark().opacity(loading ? 0 : 1)
        if loading { ReadingActivityGlyph() }
      }.frame(width: 16, height: 16)
      ActivityLabel(title: title, active: loading)
        .font(Font(Self.nativeFont))
        .foregroundStyle(.white.opacity(0.8))
        .lineLimit(1)
    }
  }
}
