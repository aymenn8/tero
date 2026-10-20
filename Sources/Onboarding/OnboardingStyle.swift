import SwiftUI

enum OnboardingStyle {
    static let background = Color(red: 0.055, green: 0.059, blue: 0.069)
    static let surface = Color(white: 0.095)
    static let ink = Color(white: 0.96)
    static let secondary = Color(white: 0.60)
    static let accent = Color(red: 0.60, green: 0.65, blue: 1)
    static let line = Color.white.opacity(0.13)
}

struct OnboardingButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 22).frame(height: 42)
            .foregroundStyle(prominent ? .black : OnboardingStyle.ink)
            .background(prominent ? OnboardingStyle.ink : .white.opacity(0.055), in: Capsule())
            .overlay(Capsule().strokeBorder(focused ? OnboardingStyle.accent : OnboardingStyle.line, lineWidth: focused ? 2 : 1))
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}

/// A single slim shortcut surface; individual symbols respond without toy keycaps.
struct OnboardingKeycaps: View {
    let keys: [String]
    var pressed: Set<String> = []
    var body: some View {
        HStack(spacing: 9) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key).font(.system(size: 22, weight: .medium))
                    .foregroundStyle(pressed.contains(key) ? OnboardingStyle.accent : OnboardingStyle.ink)
                    .frame(minWidth: 21, minHeight: 28)
                    .opacity(pressed.isEmpty || pressed.contains(key) ? 1 : 0.45)
            }
        }.padding(.horizontal, 21).padding(.vertical, 10)
            .background(.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(OnboardingStyle.line))
            .accessibilityElement(children: .ignore).accessibilityLabel(keys.joined(separator: " "))
    }
}

/// Directional graphite lighting: quiet depth, with no colored glow behind the content.
struct OnboardingBackdrop: View {
    var body: some View {
        ZStack {
            OnboardingStyle.background
            LinearGradient(colors: [Color(white: 0.16).opacity(0.7), .clear, .black.opacity(0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.045), .clear], center: .init(x: 0.5, y: 0),
                           startRadius: 0, endRadius: 560)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.025), .white.opacity(0.07)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .accessibilityHidden(true)
    }
}
