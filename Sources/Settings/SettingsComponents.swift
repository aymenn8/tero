import SwiftUI
import AppKit

/// Settings use the same Inter resource and charcoal base as Tero's reading surface.
@MainActor enum SettingsStyle {
    static let background = Color(white: 0.095)
    static let secondary = Color.white.opacity(0.56)
    static func font(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        let native = NSFontManager.shared.convert(TeroModeTitle.nativeFont, toSize: size)
        return Font(native).weight(weight)
    }
    static func open(_ path: String) {
        guard let origin = AuthConfiguration.websiteOrigin else { return }
        NSWorkspace.shared.open(origin.appendingPathComponent(path))
    }
}

struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var body: some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white).frame(width: 23, height: 23)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !title.isEmpty { Text(title).font(SettingsStyle.font(12, weight: .semibold)).padding(.leading, 12) }
            VStack(spacing: 0) { content }
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.045)) }
        }
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: Control
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(SettingsStyle.font())
                if let detail { Text(detail).font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            control
        }.padding(.horizontal, 15).padding(.vertical, 13)
    }
}

struct SettingsDivider: View {
    var body: some View { Rectangle().fill(.white.opacity(0.055)).frame(height: 1).padding(.horizontal, 15) }
}

struct SettingsPill: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(SettingsStyle.font(11, weight: .medium))
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(.white.opacity(configuration.isPressed ? 0.14 : 0.075), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.06)) }
    }
}
