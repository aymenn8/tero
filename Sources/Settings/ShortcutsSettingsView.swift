import SwiftUI

struct ShortcutsSettingsView: View {
    @State private var search = ""
    private var modes: [ActionDefinition] { ActionCatalog.definitions.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: "Tero") {
                SettingsRow(title: "Open Tero", detail: "Suggest actions for your current selection.") { ShortcutRecorder(target: .open) }
                SettingsDivider()
                SettingsRow(title: "Clipboard", detail: "Open your clipboard history directly.") { ShortcutRecorder(target: .clipboard) }
                SettingsDivider()
                SettingsRow(title: "Ask", detail: "Open Ask, ready to type.") { ShortcutRecorder(target: .ask) }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("Modes").font(SettingsStyle.font(12, weight: .semibold)).padding(.leading, 12)
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(SettingsStyle.secondary); TextField("Find a mode", text: $search).textFieldStyle(.plain) }
                    .padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                SettingsGroup(title: "") {
                    ForEach(modes, id: \.id) { mode in
                        SettingsRow(title: mode.title) { ShortcutRecorder(target: .mode(mode.id)) }
                        if mode.id != modes.last?.id { SettingsDivider() }
                    }
                    if modes.isEmpty { Text("No matching modes").foregroundStyle(SettingsStyle.secondary).padding(16) }
                }
            }
            Text("Select text or files before using a mode shortcut. Click a shortcut to change it. Uncheck to disable without deleting. Use × to remove a shortcut. Escape cancels recording; Delete also removes it.")
                .font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).lineSpacing(4)
        }
    }
}
