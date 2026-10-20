import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    var setDeveloper: (Bool) -> Void
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var developer = UserDefaults.standard.bool(forKey: "developerContextInspector")
    @State private var message: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            SettingsGroup(title: "App") {
                SettingsRow(title: "Open at login", detail: "Keep Tero ready when you start your Mac.") {
                    Toggle("Open at login", isOn: $loginEnabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .onChange(of: loginEnabled) { _, value in updateLogin(value) }
                }
                SettingsDivider()
                SettingsRow(title: "Open Tero", detail: "Select something, then press your shortcut.") {
                    ShortcutRecorder(target: .open)
                }
            }
            SettingsGroup(title: "Getting started") {
                SettingsRow(title: "Meet Tero again", detail: "Replay the introduction and try your shortcut.") {
                    Button("Replay onboarding") { OnboardingController.shared.show() }.buttonStyle(SettingsPill())
                }
            }
            SettingsGroup(title: "Interface") {
                SettingsRow(title: "Language") { Text("English").foregroundStyle(SettingsStyle.secondary) }
                SettingsDivider()
                SettingsRow(title: "Motion", detail: "Tero respects Reduce Motion and Reduce Transparency in macOS.") {
                    Button("System Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess")!) }.buttonStyle(SettingsPill())
                }
            }
            if Bundle.main.isTeroDevBuild {
                SettingsGroup(title: "Developer") {
                    SettingsRow(title: "Context inspector", detail: "See captured context and recommendation scores when opening Tero.") {
                        Toggle("Context inspector", isOn: $developer).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            .onChange(of: developer) { _, value in setDeveloper(value) }
                    }
                }
            }
            if let message { Text(message).font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginEnabled = SMAppService.mainApp.status == .enabled
            developer = UserDefaults.standard.bool(forKey: "developerContextInspector")
        }
    }
    private func updateLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            message = SMAppService.mainApp.status == .requiresApproval ? "Allow Tero in System Settings → General → Login Items." : nil
        } catch { loginEnabled = SMAppService.mainApp.status == .enabled; message = "Couldn't change the login item. Check System Settings → General → Login Items." }
    }
}
