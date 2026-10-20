import SwiftUI

struct ActionBubble: View {
    static let horizontalPadding: CGFloat = 17
    static let spacing: CGFloat = 10

    /// Shared by every bubble measurement (and `TeroLogoBubble`); widths are computed per render.
    static let titleFont = NSFont.systemFont(ofSize: 14, weight: .medium)

    static func width(title: String, leadingSymbol: String? = nil) -> CGFloat {
        ceil((title as NSString).size(withAttributes: [.font: titleFont]).width) + 2 * horizontalPadding + (leadingSymbol == nil ? 0 : 20)
    }

    static func rowWidth(for actions: [Action]) -> CGFloat {
        return actions.reduce(40 + CGFloat(max(0, actions.count - 1)) * spacing) { width, action in
            width + (action.isNavigationIcon ? 30 : Self.width(title: action.title, leadingSymbol: action.iconName))
        }
    }

    let title: String
    let label: String
    let selected: Bool
    let symbol: String?
    let leadingSymbol: String?
    let perform: () -> Void
    init(action: Action, selected: Bool, perform: @escaping () -> Void) {
        self.init(title: action.title, label: action.accessibilityLabel, selected: selected,
                  symbol: action == .search ? "magnifyingglass" : action == .back ? "chevron.left" : action == .more ? "ellipsis" : nil,
                  leadingSymbol: action.isNavigationIcon ? nil : action.iconName, perform: perform)
    }

    init(title: String, label: String, selected: Bool, symbol: String? = nil, leadingSymbol: String? = nil, perform: @escaping () -> Void) {
        self.title = title
        self.label = label
        self.selected = selected
        self.symbol = symbol
        self.leadingSymbol = leadingSymbol
        self.perform = perform
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovered = false

    var body: some View {
        Button(action: perform) {
            Group {
                if let symbol {
                    Label(title, systemImage: symbol).labelStyle(.iconOnly).frame(width: 30)
                } else {
                    HStack(spacing: 6) {
                        if let leadingSymbol {
                            Image(systemName: leadingSymbol)
                                .symbolRenderingMode(.monochrome)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white).frame(width: 14)
                                .accessibilityHidden(true)
                        }
                        Text(title)
                    }.padding(.horizontal, Self.horizontalPadding)
                }
            }
                .lineLimit(1)
                .font(.system(size: 14, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? .white : .white.opacity(0.85))
                .frame(height: 30)
                .background {
                    TeroReadingSurface(cornerRadius: 15)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .fill(.white.opacity(selected ? 0.09 : hovered ? 0.05 : 0))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(.white.opacity(contrast == .increased ? 0.7 : selected ? 0.25 : hovered ? 0.16 : 0))
                }
                .shadow(color: .black.opacity(0.24), radius: 3, y: 2)
        }
        .buttonStyle(TeroBubblePressStyle())
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
        .animation(nil, value: selected)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(symbol == "magnifyingglass" ? "Search actions · ⌘F · or start typing" : label)
    }
}

private struct TeroBubblePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion || !enabled || !configuration.isPressed ? 1 : 0.96)
            .opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
