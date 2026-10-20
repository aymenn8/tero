import SwiftUI

struct ClipboardGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let charcoal = Color(.sRGB, red: 0.09, green: 0.09, blue: 0.09, opacity: 1)

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(charcoal.opacity(reduceTransparency ? 1 : 0.94))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            }
    }
}
