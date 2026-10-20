import SwiftUI
import AppKit

struct OnboardingView: View {
    @Bindable var flow: OnboardingController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var keyboard = OnboardingKeyboard()
    private var keys: [String] { ShortcutRegistry.shared.bindings[ShortcutTarget.open.id]?.keycaps ?? ["?"] }
    private var stepName: String { ["Meet Tero", "Try the shortcut", "Beyond selections", "Allow access", "Your AI", "Make it yours"][flow.progress.step.rawValue] }
    var body: some View {
        ZStack {
            OnboardingBackdrop()
            if flow.introReady {
                VStack(spacing: 0) {
                    TeroLogoMark(size: 32)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .trailing) {
                            if flow.progress.step != .welcome {
                                Text(stepName).font(.system(size: 12)).foregroundStyle(OnboardingStyle.secondary)
                            }
                        }
                        .padding(.horizontal, 40).padding(.top, 42)
                    VStack(spacing: 23) { stage }
                        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 40)
                    footer
                }.transition(.opacity)
            }
            OnboardingKeyboardCapture(keyboard: keyboard).frame(width: 0, height: 0).id(flow.progress.isPresented)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(OnboardingStyle.ink).preferredColorScheme(.dark)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: flow.progress.step)
            .animation(.easeOut(duration: 0.45), value: flow.introReady)
            .onChange(of: flow.progress.step) { _, _ in keyboard.cancel() }
            .onChange(of: flow.accountConnected) { _, _ in flow.skipConnectedAccount() }
            .onChange(of: flow.progress.isPresented) { _, presented in if !presented { keyboard.stop() } }
            .onAppear {
                keyboard.onInvoke = { _ = flow.consume(.open) }
            }
            .onDisappear { keyboard.stop(); keyboard.onInvoke = nil; keyboard.onActionKey = nil }
            .onExitCommand { flow.escape() }
            .allowsHitTesting(!flow.finishing)
    }
    private var footer: some View {
        HStack {
            Group {
                if flow.progress.step != .welcome { Button("Back", action: flow.back).buttonStyle(OnboardingButtonStyle()) }
                else { Text("Made for your Mac.").font(.system(size: 11)).foregroundStyle(OnboardingStyle.secondary) }
            }.frame(width: 170, alignment: .leading)
            Spacer()
            HStack(spacing: 7) {
                ForEach(flow.visibleSteps, id: \.rawValue) { step in
                    Capsule().fill(.white.opacity(step == flow.progress.step ? 0.8 : 0.18))
                        .frame(width: step == flow.progress.step ? 22 : 5, height: 5)
                }
            }.accessibilityElement(children: .ignore).accessibilityLabel("Step \((flow.visibleSteps.firstIndex(of: flow.progress.step) ?? 0) + 1) of \(flow.visibleSteps.count)")
            Spacer()
            Group {
                if flow.progress.step == .account {
                    Button("Do it later", action: flow.deferAccount)
                        .buttonStyle(.plain).font(.system(size: 12))
                        .foregroundStyle(OnboardingStyle.secondary).padding(.vertical, 10)
                } else if flow.progress.step == .practice {
                    if flow.exerciseSucceeded {
                        Button("Start using Tero", action: flow.finish).buttonStyle(OnboardingButtonStyle(prominent: true))
                    } else {
                        Text("Try one demo to finish").font(.system(size: 11)).foregroundStyle(OnboardingStyle.secondary)
                    }
                } else {
                    Button(nextLabel, action: flow.next).buttonStyle(OnboardingButtonStyle(prominent: true))
                        .disabled(!canContinue)
                }
            }.frame(width: 170, alignment: .trailing)
        }.padding(.horizontal, 40).frame(height: 84)
    }
    private var nextLabel: String {
        flow.progress.step == .welcome ? "Try the shortcut" : flow.progress.step == .shortcut ? "Explore Tero" : "Continue"
    }
    private var canContinue: Bool {
        switch flow.progress.step {
        case .welcome: true
        case .capabilities: true
        case .shortcut: flow.demoDone && flow.shortcutReady
        case .permission: true
        case .account: true
        case .practice: flow.exerciseSucceeded
        }
    }
    @ViewBuilder private var stage: some View {
        switch flow.progress.step {
        case .welcome:
            heading("Select. Choose. Done.", "Tero brings useful actions beside the text you're working on.", size: 43)
            OnboardingFeatureScene(flow: flow, welcome: true)
            OnboardingKeyboardGuide(firstKeys: ["↩"], firstLabel: "Try it yourself", detail: "Every example in this tour is free and simulated.")
        case .shortcut:
            heading(flow.demoDone ? "One shortcut. Your choice." : "Try Tero with your keyboard.", flow.demoDone ? "You chose an action and changed the example." : "Press your Tero shortcut to bring up the action bubbles.")
            OnboardingKeycaps(keys: keys, pressed: keyboard.pressed)
            OnboardingFeatureScene(flow: flow)
            if flow.demoDone {
                OnboardingKeyboardGuide(firstKeys: ["↩"], firstLabel: "Explore Tero", detail: "Change your shortcut later in Settings → Shortcuts.")
            } else if flow.demoInvoked {
                OnboardingKeyboardGuide(firstKeys: ["←", "→"], firstLabel: "Choose an action", secondKeys: ["↩"], secondLabel: "Run the demo", detail: "You can also click any action bubble.")
            } else { note("The example is already selected. Press " + keys.joined(separator: " ") + " to start.") }
            if let message = ShortcutRegistry.shared.errors[ShortcutTarget.open.id] { note(message + " Change it in Settings → Shortcuts.") }
            if !ShortcutRegistry.shared.isEnabled(.open) {
                Button("Enable shortcut") { keyboard.message = ShortcutRegistry.shared.setEnabled(true, for: .open) }.buttonStyle(OnboardingButtonStyle())
            }
        case .capabilities:
            heading("More than selected text.", "Ask a question or find your next purchase, right from Tero.")
            OnboardingCapabilitiesScene()
            OnboardingKeyboardGuide(firstKeys: ["↩"], firstLabel: "Continue", detail: "Open Tero without selecting text to use Ask for questions and product recommendations. These are sample previews.")
        case .permission:
            heading("Bring Tero into your apps.", "After the tour, allow Accessibility access in Settings.")
            HStack(spacing: 22) {
                Text("Your selection").font(.system(size: 18)).padding(12)
                    .background(OnboardingStyle.accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 7))
                Image(systemName: "arrow.right").foregroundStyle(OnboardingStyle.secondary)
                TeroLogoBubble()
                Text("Your chosen action").font(.system(size: 14)).padding(.horizontal, 15).frame(height: 30)
                    .background { TeroReadingSurface(cornerRadius: 15) }
            }.frame(height: 110).accessibilityHidden(true)
            note("Accessibility lets Tero read selected text and apply the action you choose.\nThis tour uses its own examples, so you can keep exploring now.")
            OnboardingKeyboardGuide(firstKeys: ["↩"], firstLabel: "Continue", detail: "Set up access later in Settings → Privacy & Permissions.")
        case .account:
            heading("Bring your own AI.", "Use your OpenAI, Anthropic, Grok, Gemini or OpenRouter key, or a local model.")
            TeroLogoMark(size: 64).frame(height: 100).accessibilityHidden(true)
            note("Your key stays in your Mac's Keychain and requests go straight to your provider.\nNo Tero account needed. The examples in this tour don't use AI.")
            Button("Open AI settings", action: flow.signIn).buttonStyle(OnboardingButtonStyle(prominent: true))
            OnboardingKeyboardGuide(firstKeys: ["↩"], firstLabel: "Continue", detail: "Add your key now or later in Settings → AI.")
        case .practice:
            heading(flow.exerciseSucceeded ? "You've got the gesture." : "Try the full flow.", flow.exerciseSucceeded ? "Select text, open Tero, choose with the arrows, then press Return." : "Select the example, open Tero, then choose what to do.")
            if flow.calendarPreview {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Review the demo event", systemImage: "calendar").font(.system(size: 19, weight: .medium))
                    Text("Launch review").font(.system(size: 17))
                    Text("Tomorrow · 15:00–15:30\nDemo calendar").font(.system(size: 13)).foregroundStyle(OnboardingStyle.secondary)
                    Button("Add demo event", action: flow.createDemoEvent).buttonStyle(OnboardingButtonStyle(prominent: true))
                    Button("Back to the example") { flow.calendarPreview = false }.buttonStyle(.plain).font(.system(size: 12))
                    Text("This is a preview. Your calendar stays unchanged.").font(.system(size: 11)).foregroundStyle(OnboardingStyle.secondary)
                }.padding(28).frame(width: 526, alignment: .leading)
                    .background { RoundedRectangle(cornerRadius: 19).fill(OnboardingStyle.surface) }
                OnboardingKeyboardGuide(firstKeys: ["↩"], firstLabel: "Add the demo event")
            } else {
                OnboardingFeatureScene(flow: flow, practice: true)
                if flow.exerciseSucceeded {
                    OnboardingKeyboardGuide(firstKeys: ["↩"], firstLabel: "Start using Tero", detail: "You’re ready to try Tero with your own content.")
                } else if flow.working {
                    note("Running the prepared example. No AI request is sent.")
                } else if flow.exerciseInvoked {
                    OnboardingKeyboardGuide(firstKeys: ["←", "→"], firstLabel: flow.choosingLanguage ? "Choose a language" : "Choose an action", secondKeys: ["↩"], secondLabel: "Try your choice", detail: "Prepared demo. No AI request is sent and your calendar stays unchanged.")
                } else {
                    HStack(spacing: 16) {
                        Button("Select the example", action: flow.selectExample).buttonStyle(OnboardingButtonStyle())
                        OnboardingKeycaps(keys: keys, pressed: keyboard.pressed)
                    }
                    OnboardingKeyboardGuide(firstKeys: ["↩"], firstLabel: "Select the example", secondKeys: ["⌘", "A"], secondLabel: "Select all", detail: "Select the example, then press " + keys.joined(separator: " ") + " to open Tero.")
                }
            }
            if let message = flow.message { note(message) }
        }
    }
    private func heading(_ title: String, _ detail: String, size: CGFloat = 36) -> some View {
        VStack(spacing: 13) {
            Text(title).font(.system(size: size, weight: .semibold)).tracking(-1.3).multilineTextAlignment(.center)
            Text(detail).font(.system(size: 14)).foregroundStyle(OnboardingStyle.secondary).multilineTextAlignment(.center).lineSpacing(4)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(OnboardingStyle.secondary)
            .multilineTextAlignment(.center).frame(maxWidth: 550).fixedSize(horizontal: false, vertical: true)
    }
}
