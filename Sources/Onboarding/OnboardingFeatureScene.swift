import SwiftUI
import AppKit

/// One persistent example teaches the same selection → shortcut → action gesture.
struct OnboardingFeatureScene: View {
    @Bindable var flow: OnboardingController
    var welcome = false
    var practice = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var demonstration = 0
    private var done: Bool { welcome ? demonstration == 4 : practice ? flow.exerciseSucceeded : flow.demoDone }
    private var invoked: Bool { welcome ? demonstration >= 2 : practice ? flow.exerciseInvoked : flow.demoInvoked }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "text.alignleft")
                Text(practice ? "A plan with Alex" : "A message to Alex")
                Spacer()
                Text("Demo")
            }.font(.system(size: 11)).foregroundStyle(OnboardingStyle.secondary)
                .padding(.bottom, 25)
            if practice {
                OnboardingExampleEditor(flow: flow).frame(height: 110)
            } else {
                VStack(alignment: .leading, spacing: 15) {
                    Text("Hey Alex,").foregroundStyle(OnboardingStyle.secondary)
                    Text(done ? (welcome ? "Thanks for your help yesterday!" : flow.demoResult) : "Thanks for you help yestarday!")
                        .font(.system(size: 22, weight: .medium)).tracking(-0.5)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .background(OnboardingStyle.accent.opacity(welcome && demonstration == 0 ? 0 : 0.19), in: RoundedRectangle(cornerRadius: 5))
                        .contentTransition(.opacity)
                }.frame(height: 110, alignment: .topLeading)
            }
            actionRow
        }.padding(28).frame(width: 526, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 19).fill(OnboardingStyle.surface) }
            .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(OnboardingStyle.line))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: done)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: invoked)
            .task { await playDemo() }
    }
    private var actionRow: some View {
            HStack(spacing: 10) {
                if (invoked || done) && !flow.working && !(welcome && demonstration == 3) {
                    TeroLogoBubble()
                    if !done {
                        if practice {
                            if flow.choosingLanguage {
                                ForEach(Array([ResponseLanguage.french, .english, .spanish].enumerated()), id: \.offset) { index, language in
                                    practiceButton(language.title, index: index) { flow.translate(to: language) }
                                }
                                practiceButton("Back", index: 3) { flow.choosingLanguage = false; flow.practiceIndex = 2 }
                            } else {
                                practiceButton("Add to Calendar", index: 0, action: flow.addToCalendar)
                                practiceButton("Correct", index: 1, action: flow.correct)
                                practiceButton("Translate", index: 2, action: flow.chooseTranslation)
                            }
                        } else {
                            ForEach(Array(["Correct", "Rewrite", "Translate"].enumerated()), id: \.offset) { index, title in
                                Button { flow.practiceIndex = index; flow.runDemo() } label: {
                                    Text(title).font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).frame(height: 30)
                                }.buttonStyle(.plain).background { TeroReadingSurface(cornerRadius: 15) }
                                    .overlay(Capsule().strokeBorder(.white.opacity(flow.practiceIndex == index ? 0.5 : 0), lineWidth: 1))
                                    .disabled(welcome)
                            }
                        }
                    } else {
                        Text(practice ? flow.successDetail : welcome ? "Same message. Mistakes gone." : "The example is updated.")
                            .font(.system(size: 12)).foregroundStyle(OnboardingStyle.secondary)
                    }
                } else if flow.working || (welcome && demonstration == 3) {
                    TeroLogoBubble(loading: true, activityTitle: practice ? flow.activityTitle : "Correcting")
                } else {
                    Text(practice ? "Select the text, then press your shortcut." : "Your actions appear right here.")
                        .font(.system(size: 12)).foregroundStyle(OnboardingStyle.secondary)
                }
                Spacer()
            }.frame(height: 36).padding(.top, 14)
    }
    private func practiceButton(_ title: String, index: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .medium)).padding(.horizontal, 12).frame(height: 30)
        }.buttonStyle(.plain).background { TeroReadingSurface(cornerRadius: 15) }
            .overlay(Capsule().strokeBorder(.white.opacity(flow.practiceIndex == index ? 0.5 : 0), lineWidth: 1))
    }
    private func playDemo() async {
        guard welcome else { return }
        for phase in 1...4 {
            do { try await Task.sleep(for: .milliseconds(phase == 3 ? 1100 : 650)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.35)) { demonstration = phase }
        }
    }
}

/// Native selection and undo, confined to the disposable onboarding example.
struct OnboardingExampleEditor: NSViewRepresentable {
    let flow: OnboardingController
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        let text = NSTextView()
        text.string = OnboardingController.practiceExample
        text.font = .systemFont(ofSize: 19, weight: .medium)
        text.textColor = NSColor(white: 0.96, alpha: 1)
        text.insertionPointColor = .white
        text.backgroundColor = .clear; text.drawsBackground = false
        text.isRichText = false; text.isEditable = false; text.isSelectable = true
        text.isAutomaticSpellingCorrectionEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.textContainerInset = NSSize(width: 4, height: 5)
        text.isVerticallyResizable = true; text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.setAccessibilityLabel("Practice text. Select the words you want to act on.")
        scroll.documentView = text
        flow.editor = text
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll.documentView as? NSTextView)?.isSelectable = !flow.working
    }
}


struct OnboardingKeyboardGuide: View {
    let firstKeys: [String]
    let firstLabel: String
    var secondKeys: [String] = []
    var secondLabel = ""
    var detail = ""
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 22) {
                gesture(firstKeys, label: firstLabel)
                if !secondKeys.isEmpty { gesture(secondKeys, label: secondLabel) }
            }
            if !detail.isEmpty {
                Text(detail).font(.system(size: 11)).foregroundStyle(OnboardingStyle.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    private func gesture(_ keys: [String], label: String) -> some View {
        HStack(spacing: 8) {
            Text(keys.joined(separator: " ")).font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(OnboardingStyle.line))
            Text(label).font(.system(size: 12)).foregroundStyle(OnboardingStyle.ink)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Read-only examples: both features are understandable without completing a task.
struct OnboardingCapabilitiesScene: View {
    private let askTint = Color(red: 0.76, green: 0.73, blue: 1)
    private let shopTint = Color(red: 0.59, green: 0.85, blue: 0.76)

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 18) {
                featureHeader("Ask", detail: "Get an answer. Keep your flow.", symbol: "text.bubble", tint: askTint)
                VStack(alignment: .leading, spacing: 16) {
                    Text("Why does bread rise?")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 16).padding(.vertical, 12)
                        .background(askTint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    HStack(alignment: .top, spacing: 10) {
                        TeroLogoMark().frame(width: 15, height: 15).padding(.top, 3).accessibilityHidden(true)
                        Text("Yeast makes tiny gas bubbles in the dough. The bubbles expand, making the bread rise.")
                            .font(.system(size: 14)).lineSpacing(5)
                            .foregroundStyle(OnboardingStyle.ink.opacity(0.88))
                    }.padding(.horizontal, 4)
                }.padding(18).frame(maxWidth: .infinity, minHeight: 210, alignment: .top)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(OnboardingStyle.line))
            }
            VStack(alignment: .leading, spacing: 18) {
                featureHeader("Ask", detail: "Find products that fit your needs, too.", symbol: "text.bubble", tint: shopTint)
                VStack(alignment: .leading, spacing: 15) {
                    Text("“A quiet keyboard for late nights”")
                        .font(.system(size: 15, weight: .medium)).lineSpacing(3)
                    HStack(spacing: 12) {
                        keyboardOption("Low profile", detail: "Slim & compact", tint: shopTint, compact: true)
                        keyboardOption("Silent switches", detail: "Soft & quiet", tint: shopTint, compact: false)
                    }
                    Text("Compare the options. Choose your fit.")
                        .font(.system(size: 12)).foregroundStyle(OnboardingStyle.secondary)
                }.padding(18).frame(maxWidth: .infinity, minHeight: 210, alignment: .top)
                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(OnboardingStyle.line))
            }
        }.frame(width: 680)
            .accessibilityElement(children: .contain)
    }

    private func featureHeader(_ title: String, detail: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.system(size: 23, weight: .semibold)).foregroundStyle(tint)
            Text(detail).font(.system(size: 13)).foregroundStyle(OnboardingStyle.secondary)
        }.padding(.horizontal, 4)
    }

    private func keyboardOption(_ title: String, detail: String, tint: Color, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "keyboard")
                .font(.system(size: compact ? 32 : 39, weight: .light))
                .foregroundStyle(tint.opacity(0.8))
                .rotationEffect(.degrees(compact ? -7 : 5))
                .frame(maxWidth: .infinity).frame(height: 58)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 12, weight: .medium))
            Text(detail).font(.system(size: 11)).foregroundStyle(OnboardingStyle.secondary)
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }
}
