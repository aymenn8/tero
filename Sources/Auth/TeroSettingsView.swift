import SwiftUI
import Observation

@MainActor @Observable final class SettingsNavigation {
    enum Page: String, CaseIterable, Identifiable {
        case general = "General", ai = "AI", shortcuts = "Shortcuts", actions = "Actions", clipboard = "Clipboard", connections = "Connections", privacy = "Privacy & Permissions", about = "About", account = "Account"
        var id: Self { self }
        var searchTerms: String {
            switch self {
            case .general: "login startup interface motion developer inspector"
            case .ai: "provider api key byok openai anthropic claude grok xai gemini openrouter mistral groq deepseek ollama lm studio model local pro"
            case .shortcuts: "keyboard hotkey bind ask clipboard modes"
            case .actions: "language translation modes AI defaults habits personal custom routines"
            case .clipboard: "history copies recording pin storage clear"
            case .connections: "calendar reminders destination integrations"
            case .privacy: "accessibility automation permissions data local"
            case .account: "profile plan billing credits usage subscription pro sign in"
            case .about: "version beta changelog updates manual docs contact feedback"
            }
        }
        var symbol: String {
            switch self {
            case .general: "gearshape.fill"
            case .ai: "cpu.fill"
            case .shortcuts: "command"
            case .actions: "sparkles"
            case .clipboard: "clipboard.fill"
            case .connections: "link"
            case .privacy: "hand.raised.fill"
            case .about: "info.circle.fill"
            case .account: "person.crop.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .general: .gray
            case .ai: .purple
            case .shortcuts: .pink
            case .actions: .blue
            case .clipboard: .orange
            case .connections: .green
            case .privacy: .indigo
            case .about: .gray
            case .account: .gray
            }
        }
    }
    var page: Page = .general
}

struct TeroSettingsView: View {
    @Bindable var navigation: SettingsNavigation
    let habits: HabitEditorRouter
    let account: AccountStore
    var clipboard: ClipboardStore?
    var setDeveloper: (Bool) -> Void
    @State private var search = ""
    // Observed so the AI sidebar subtitle follows provider changes.
    @AppStorage(AIConfiguration.Keys.provider) private var aiProvider = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var pages: [SettingsNavigation.Page] {
        // AI is pinned at the top. Account only appears once someone signs in to Tero Pro.
        SettingsNavigation.Page.allCases.filter { $0 != .ai && ($0 != .account || account.user != nil) && (search.isEmpty || ($0.rawValue + " " + $0.searchTerms).localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(SettingsStyle.secondary)
                    TextField("Search settings", text: $search).textFieldStyle(.plain).font(SettingsStyle.font(11))
                }.padding(9).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                sidebar(.ai, subtitle: aiSubtitle)
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(pages.filter { $0 != .about }) { page in sidebar(page) }
                        if pages.isEmpty { Text("No settings found").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).padding(.top, 12) }
                    }
                }.scrollIndicators(.hidden)
                if pages.contains(.about) { sidebar(.about) }
            }.padding(.horizontal, 12).padding(.top, 48).padding(.bottom, 14).frame(width: 202)
                .background(.white.opacity(0.023))
            Rectangle().fill(.white.opacity(0.06)).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(navigation.page.rawValue).font(SettingsStyle.font(13, weight: .semibold))
                    Spacer()
                    TeroLogoMark().opacity(0.65)
                }.padding(.horizontal, 28).frame(height: 53).background { WindowDragRegion() }
                Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                ScrollView {
                    content.padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
                        .id(navigation.page).transition(.opacity)
                }.defaultScrollAnchor(.top).scrollIndicators(.automatic)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .font(SettingsStyle.font()).foregroundStyle(.white.opacity(0.88))
        .background(SettingsStyle.background).preferredColorScheme(.dark)
        .frame(minWidth: 740, minHeight: 540)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.14), value: navigation.page)
        .onAppear { if account.user == nil { account.prepare() } }
    }
    private var aiSubtitle: String {
        if !aiProvider.isEmpty, let configuration = AIConfiguration.active { return configuration.provider.title + " · " + configuration.model }
        return account.usage?.plan == "pro" ? "Tero Pro" : "Add your AI key"
    }
    private func sidebar(_ page: SettingsNavigation.Page, subtitle: String? = nil) -> some View {
        Button { navigation.page = page } label: {
            HStack(spacing: 9) {
                SettingsIcon(symbol: page.symbol, color: page.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(page.rawValue).font(SettingsStyle.font(11, weight: .medium))
                    if let subtitle { Text(subtitle).font(SettingsStyle.font(9)).foregroundStyle(SettingsStyle.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).frame(height: subtitle == nil ? 34 : 48)
                .background(.white.opacity(navigation.page == page ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(navigation.page == page ? .isSelected : [])
    }
    @ViewBuilder private var content: some View {
        switch navigation.page {
        case .general: GeneralSettingsView(setDeveloper: setDeveloper)
        case .ai: AISettingsView()
        case .shortcuts: ShortcutsSettingsView()
        case .account: AccountView(account: account)
        case .clipboard: ClipboardSettingsView(store: clipboard)
        case .connections: PermissionSettingsView(connectionsOnly: true)
        case .privacy: PermissionSettingsView()
        case .actions: ActionSettingsView(habits: habits)
        case .about: AboutSettingsView()
        }
    }
}
