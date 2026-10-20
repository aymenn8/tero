import SwiftUI

/// Shown when an AI action can't run: no provider is set up yet, or a Tero Pro allowance is used up.
struct AllowanceReachedView: View {
    /// True when no AI provider is configured on this Mac.
    let needsSetup: Bool
    let open: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                TeroLogoMark()
                Text(needsSetup ? "Set up AI" : "Tero Pro").font(SettingsStyle.font(11, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(SettingsStyle.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Close")
            }
            Divider().overlay(.white.opacity(0.06))
            Text(needsSetup ? "Connect your AI provider." : "Your Pro allowance is used up.")
                .font(SettingsStyle.font(16, weight: .semibold))
            Text(needsSetup
                 ? "Add an API key from OpenAI, Anthropic, Grok, Gemini, OpenRouter and more, or use a local model. Your key stays on this Mac."
                 : "It renews with your next billing period. You can also add your own AI key in Settings.")
                .font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
            Button(action: open) {
                HStack { Text("Open AI settings"); Spacer(); Text("↩").opacity(0.55) }
                    .font(SettingsStyle.font(12, weight: .semibold)).foregroundStyle(Color(white: 0.1))
                    .padding(.horizontal, 12).frame(height: 32).background(.white, in: RoundedRectangle(cornerRadius: 7))
            }.buttonStyle(.plain)
        }.padding(16).frame(width: 360)
            .background(SettingsStyle.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.14)) }
    }
}
