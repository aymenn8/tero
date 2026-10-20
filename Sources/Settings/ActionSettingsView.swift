import SwiftUI

struct ActionSettingsView: View {
    let habits: HabitEditorRouter
    @Bindable private var store = TextHabitStore.shared
    @State private var language = ResponseLanguage.load()
    @State private var translation = ResponseLanguage.translationTarget()
    @State private var search = ""
    @State private var editing: TextHabit?
    @State private var removing: TextHabit?
    private var targets: [ActionRecommendation.Target] {
        (ActionCatalog.definitions.map { .native($0.id) } + store.habits.map { .habit($0.id) })
            .filter { search.isEmpty || title($0).localizedStandardContains(search) }
            .sorted { title($0).localizedStandardCompare(title($1)) == .orderedAscending }
    }
    private func title(_ target: ActionRecommendation.Target) -> String {
        switch target { case .native(let action): action.title; case .habit(let id): store.habits.first { $0.id == id }?.name ?? "Personal action" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("All your actions").font(SettingsStyle.font(16, weight: .semibold)); Spacer()
                    Button("Create a habit", systemImage: "plus") { editing = TextHabit() }.buttonStyle(SettingsPill()).disabled(store.loadFailed || store.habits.count >= 50)
                }
                Text("Tero suggests the right actions for your selection. Create your own by describing what you need.").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).lineSpacing(3)
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(SettingsStyle.secondary); TextField("Find an action", text: $search).textFieldStyle(.plain) }
                    .padding(10).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                SettingsGroup(title: "Habits") {
                    let personal = targets.filter { if case .habit = $0 { return true }; return false }
                    ForEach(personal, id: \.self) { target in
                        row(target)
                        if target != personal.last { SettingsDivider() }
                    }
                    if personal.isEmpty {
                        Text(search.isEmpty ? "Create a habit by telling Tero what you need." : "No matching habits")
                            .font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).padding(15)
                    }
                }
                Text(store.syncDescription + " Select one to rename or refine it.")
                    .font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary)
                SettingsGroup(title: "Tero actions") {
                    let native = targets.filter { if case .native = $0 { return true }; return false }
                    ForEach(native, id: \.self) { target in
                        row(target)
                        if target != native.last { SettingsDivider() }
                    }
                    if native.isEmpty { Text("No matching actions").foregroundStyle(SettingsStyle.secondary).padding(15) }
                }
            }
            if let error = store.error { Text(error).font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary) }

            SettingsGroup(title: "Defaults") {
                SettingsRow(title: "AI response language", detail: "Used for explanations and Ask. Writing actions keep the source language.") {
                    Picker("AI response language", selection: $language) { ForEach(ResponseLanguage.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 120).onChange(of: language) { _, value in value.save() }
                }
                SettingsDivider()
                SettingsRow(title: "Translate to", detail: "The first language suggested when you translate.") {
                    Picker("Translate to", selection: $translation) { ForEach(ResponseLanguage.allCases, id: \.self) { Text($0.title).tag($0) } }.labelsHidden().frame(width: 120).onChange(of: translation) { _, value in value.saveTranslationTarget() }
                }
            }
        }
        .task { store.refreshOwner(); openRequestedEditor() }
        .onChange(of: habits.editorRequest) { _, _ in openRequestedEditor() }
        .onChange(of: AccountStore.shared.user?.id) { _, _ in editing = nil; removing = nil; store.refreshOwner() }
        .sheet(item: $editing) { TextHabitEditorView(store: store, habit: $0) }
        .alert("Delete this action?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Cancel", role: .cancel) { removing = nil }
            Button("Delete", role: .destructive) { if let habit = removing { store.remove(habit.id) }; removing = nil }
        } message: { Text("This removes your saved instructions. Your text is unchanged.") }
    }
    @ViewBuilder private func row(_ target: ActionRecommendation.Target) -> some View {
        switch target {
        case .native(let action):
            HStack(spacing: 12) {
                SettingsIcon(symbol: action.iconName, color: Color(white: 0.24))
                Text(action.title).font(SettingsStyle.font(12, weight: .medium)); Spacer()
            }.padding(15)
        case .habit(let id):
            if let habit = store.habits.first(where: { $0.id == id }) {
                HStack(spacing: 12) {
                    SettingsIcon(symbol: habit.resolvedIconName, color: Color(white: 0.24))
                    Button { editing = habit } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(habit.name).font(SettingsStyle.font(12, weight: .medium))
                            if habit.needsDestination { Text("Choose a destination folder on this Mac").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary) }
                            else if let summary = habit.summary { Text(summary).font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).lineLimit(2) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                    Button("Edit") { editing = habit }.buttonStyle(SettingsPill())
                        .accessibilityLabel("Edit " + habit.name)
                    Toggle("Enable \(habit.name)", isOn: Binding(get: { habit.enabled }, set: { store.setEnabled($0, id: id) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    Button("Delete \(habit.name)", systemImage: "trash") { removing = habit }.labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(SettingsStyle.secondary)
                }.padding(15)
            }
        }
    }
    private func openRequestedEditor() { if habits.editorRequest != nil { editing = TextHabit(); habits.editorRequest = nil } }
}
