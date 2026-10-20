import SwiftUI

struct ClipboardSettingsView: View {
    var store: ClipboardStore?
    @State private var enabled = true
    @State private var confirmClear = false
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "History") {
                SettingsRow(title: "Capture clipboard history", detail: "Save new copies locally on this Mac.") {
                    Toggle("Capture clipboard history", isOn: $enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .disabled(store == nil || store?.error != nil)
                        .onChange(of: enabled) { _, value in store?.setEnabled(value); enabled = store?.enabled ?? false }
                }
                SettingsDivider()
                SettingsRow(title: "Keep entries for") { Text("7 days").foregroundStyle(SettingsStyle.secondary) }
                SettingsDivider()
                SettingsRow(title: "Pinned entries", detail: "Pinned copies stay until you remove them.") {
                    Text("\(store?.history.entries.filter(\.isPinned).count ?? 0)").foregroundStyle(SettingsStyle.secondary)
                }
            }
            SettingsGroup(title: "Storage") {
                SettingsRow(title: "Stored on this Mac", detail: "Your clipboard history is not synced to your Tero account.") { Image(systemName: "internaldrive").foregroundStyle(SettingsStyle.secondary) }
                SettingsDivider()
                SettingsRow(title: "Clear history", detail: "Remove saved entries, including pins. Your current clipboard stays intact.") {
                    Button("Clear…") { confirmClear = true }.buttonStyle(SettingsPill()).disabled(store == nil)
                }
            }
            if let error = store?.error { Text(error).font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary) }
        }.onAppear { enabled = store?.enabled ?? false }
        .alert("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear history", role: .destructive) { store?.clear(); enabled = store?.enabled ?? false }
        } message: { Text("All saved copies and pinned entries will be removed from this Mac.") }
    }
}
