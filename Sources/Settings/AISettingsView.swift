import SwiftUI

/// Bring your own AI: pick a provider, paste a key, choose a model.
/// Keys go to the Keychain; requests go straight from this Mac to the provider.
struct AISettingsView: View {
  @State private var selected: AIProvider = AIConfiguration.active?.provider ?? .openAI
  @State private var active: AIProvider? = AIConfiguration.active?.provider
  @State private var key = ""
  @State private var hasSavedKey = false
  @State private var model = ""
  @State private var baseURL = ""
  @State private var models: [String] = []
  @State private var status: Status?
  @State private var busy = false

  private enum Status: Equatable { case success(String), failure(String) }
  private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      Text("Tero uses your own AI account. Requests go straight from this Mac to your provider, and your key stays in the Keychain.")
        .font(SettingsStyle.font(12)).foregroundStyle(SettingsStyle.secondary).fixedSize(horizontal: false, vertical: true)
      SettingsGroup(title: "Provider") {
        LazyVGrid(columns: columns, spacing: 8) {
          ForEach(AIProvider.allCases) { provider in providerTile(provider) }
        }.padding(10)
      }
      SettingsGroup(title: selected.title) {
        if selected.needsKey {
          SettingsRow(title: "API key", detail: hasSavedKey ? "Saved in your Keychain" : "Stored only on this Mac") {
            HStack(spacing: 8) {
              SecureField(hasSavedKey ? "••••••••  Replace key" : "Paste your key", text: $key)
                .textFieldStyle(.roundedBorder).frame(width: 200)
              if let page = selected.keyPage { Link("Get a key", destination: page).font(SettingsStyle.font(11)).fixedSize() }
            }
          }
          SettingsDivider()
        }
        if selected.editableBaseURL {
          SettingsRow(title: "Server URL", detail: selected == .custom ? "OpenAI-compatible, ending in /v1" : "Local server address") {
            TextField(selected.defaultBaseURL.isEmpty ? "https://…/v1" : selected.defaultBaseURL, text: $baseURL)
              .textFieldStyle(.roundedBorder).frame(width: 260)
          }
          SettingsDivider()
        }
        SettingsRow(title: "Model", detail: models.isEmpty ? "Type a model name or load the list" : "\(models.count) models available") {
          HStack(spacing: 6) {
            TextField("Model", text: $model).textFieldStyle(.roundedBorder).frame(width: 180)
            Menu {
              ForEach(models, id: \.self) { name in Button(name) { model = name } }
            } label: { Image(systemName: "chevron.down") }
              .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(models.isEmpty)
              .accessibilityLabel("Choose a model")
            Button("Load", action: loadModels).buttonStyle(SettingsPill()).fixedSize().disabled(busy || draft(requireModel: false) == nil)
          }
        }
        SettingsDivider()
        HStack(spacing: 10) {
          statusView
          Spacer()
          if hasSavedKey || active == selected {
            Button("Remove", role: .destructive, action: remove).buttonStyle(SettingsPill()).disabled(busy)
          }
          Button(active == selected ? "Save & test" : "Use \(selected.title)", action: saveAndTest)
            .buttonStyle(SettingsPill()).keyboardShortcut(.defaultAction).disabled(busy || draft(requireModel: true) == nil)
        }.padding(.horizontal, 15).padding(.vertical, 12)
      }
      capabilities
      JevKeySettings()
      SettingsGroup(title: "") {
        SettingsRow(title: "Prefer not to manage keys?", detail: "Tero Pro includes AI with a Tero account.") {
          HStack(spacing: 12) {
            if AccountStore.shared.user == nil {
              Button("Sign in") { AccountStore.shared.signIn() }.buttonStyle(.link)
            }
            Button("Learn more") { AccountStore.shared.openBilling() }.buttonStyle(.link)
          }.font(SettingsStyle.font(11))
        }
      }.opacity(0.75)
    }
    // Clicking empty space ends text editing, like elsewhere in macOS.
    .contentShape(Rectangle())
    .onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
    .onAppear { load(selected) }
    .onChange(of: selected) { _, provider in load(provider) }
  }

  private func providerTile(_ provider: AIProvider) -> some View {
    Button { selected = provider } label: {
      HStack(spacing: 10) {
        ProviderLogo(provider: provider).frame(width: 18, height: 18)
        VStack(alignment: .leading, spacing: 2) {
          Text(provider.title).font(SettingsStyle.font(12, weight: .semibold))
          Text(provider.subtitle).font(SettingsStyle.font(10)).foregroundStyle(SettingsStyle.secondary).lineLimit(1)
        }
        Spacer(minLength: 4)
        if active == provider {
          Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("In use")
        }
      }
      .padding(.horizontal, 10).frame(height: 44).contentShape(Rectangle())
      .background(selected == provider ? Color.white.opacity(0.09) : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
      .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(selected == provider ? 0.22 : 0.06)) }
    }.buttonStyle(.plain)
  }

  @ViewBuilder private var statusView: some View {
    switch status {
    case .success(let text): Label(text, systemImage: "checkmark.circle").foregroundStyle(.green)
        .font(SettingsStyle.font(11)).lineLimit(2)
    case .failure(let text): Label(text, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        .font(SettingsStyle.font(11)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
    case nil:
      if busy { ProgressView().controlSize(.small) }
      else if active == selected { Text("In use for AI actions").font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary) }
    }
  }

  private var capabilities: some View {
    Text(selected.supportsWebSearch
      ? "\(selected.title) supports every Tero action, including web answers, claim checks and product search."
      : "\(selected.title) supports writing, reading, planning and file actions. Web answers stay offline; Check a claim and product search need OpenAI, Anthropic or OpenRouter.")
      .font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary).fixedSize(horizontal: false, vertical: true)
  }

  // MARK: - Actions

  private func load(_ provider: AIProvider) {
    let defaults = UserDefaults.standard
    key = ""
    hasSavedKey = AIKeyVault.read(provider) != nil
    model = defaults.string(forKey: AIConfiguration.Keys.model(provider)) ?? provider.defaultModel
    baseURL = defaults.string(forKey: AIConfiguration.Keys.baseURL(provider)) ?? provider.defaultBaseURL
    models = []
    status = nil
  }

  /// The configuration being edited, using the saved key when no new key was typed.
  private func draft(requireModel: Bool) -> AIConfiguration? {
    let typed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    let secret = typed.isEmpty ? AIKeyVault.read(selected) : typed
    let name = model.trimmingCharacters(in: .whitespaces)
    guard let url = AIConfiguration.validBaseURL(baseURL.isEmpty ? selected.defaultBaseURL : baseURL),
          !selected.needsKey || secret != nil, !requireModel || !name.isEmpty else { return nil }
    return AIConfiguration(provider: selected, baseURL: url, model: name, key: secret)
  }

  private func loadModels() {
    guard let configuration = draft(requireModel: false) else { return }
    busy = true; status = nil
    Task {
      defer { busy = false }
      do {
        models = try await AIProviderClient(configuration: configuration, timeout: 15).models()
        if model.isEmpty, let first = models.first { model = first }
        status = models.isEmpty ? .failure("No models returned. Type a model name.") : nil
      } catch { status = .failure(message(error)) }
    }
  }

  private func saveAndTest() {
    guard let configuration = draft(requireModel: true) else { return }
    busy = true; status = nil
    Task {
      defer { busy = false }
      do {
        // A tiny correction proves the key, model and structured output all work.
        let body = try JSONSerialization.data(withJSONObject: ["requestID": UUID().uuidString, "action": "fix",
                                                                "selection": "Thsi is a quick tset."])
        _ = try await LocalGateway(configuration: configuration).respond(body)
        let typed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty, !AIKeyVault.save(typed, for: selected) { status = .failure("Couldn’t save the key to your Keychain."); return }
        let defaults = UserDefaults.standard
        defaults.set(configuration.model, forKey: AIConfiguration.Keys.model(selected))
        defaults.set(configuration.baseURL.absoluteString, forKey: AIConfiguration.Keys.baseURL(selected))
        defaults.set(selected.rawValue, forKey: AIConfiguration.Keys.provider)
        key = ""; hasSavedKey = AIKeyVault.read(selected) != nil; active = selected
        status = .success("Connected. Tero now uses \(selected.title).")
      } catch { status = .failure(message(error)) }
    }
  }

  private func remove() {
    AIKeyVault.delete(selected)
    if active == selected {
      UserDefaults.standard.removeObject(forKey: AIConfiguration.Keys.provider)
      active = nil
    }
    load(selected)
  }

  private func message(_ error: Error) -> String {
    if let failure = error as? CorrectionClient.Failure, failure != .invalid { return failure.localizedDescription }
    if error is URLError { return "Couldn’t reach \(selected.title). Check the address and your connection." }
    return "The model didn’t return a usable answer. Try another model."
  }
}

/// Optional Typesafe key: Jev orders the action bubbles, called straight from this Mac.
/// Without it, recommendations use Tero's local rules.
private struct JevKeySettings: View {
  @State private var key = ""
  @State private var saved = AIKeyVault.read(account: AIKeyVault.jevAccount) != nil
  @State private var status: String?
  @State private var failed = false
  @State private var busy = false

  var body: some View {
    SettingsGroup(title: "Recommendations") {
      SettingsRow(title: "Jev key", detail: saved ? "Saved in your Keychain" : "Optional · smarter suggestions") {
        HStack(spacing: 8) {
          SecureField(saved ? "••••••••  Replace key" : "Paste your Typesafe key", text: $key)
            .textFieldStyle(.roundedBorder).frame(width: 200)
          Link("Get a key", destination: JevClient.keyPage).font(SettingsStyle.font(11)).fixedSize()
        }
      }
      SettingsDivider()
      HStack(spacing: 10) {
        if busy { ProgressView().controlSize(.small) }
        else if let status {
          Label(status, systemImage: failed ? "exclamationmark.triangle" : "checkmark.circle")
            .foregroundStyle(failed ? .orange : .green).font(SettingsStyle.font(11)).lineLimit(2)
        } else {
          Text(saved ? "Used with your own AI provider" : "Without a key, Tero ranks actions with local rules")
            .font(SettingsStyle.font(11)).foregroundStyle(SettingsStyle.secondary)
        }
        Spacer()
        if saved { Button("Remove", role: .destructive, action: remove).buttonStyle(SettingsPill()).disabled(busy) }
        Button("Save & test", action: save).buttonStyle(SettingsPill())
          .disabled(busy || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }.padding(.horizontal, 15).padding(.vertical, 12)
    }
  }

  private func save() {
    let typed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typed.isEmpty else { return }
    busy = true; status = nil
    Task {
      defer { busy = false }
      do {
        // A synthetic two-action score proves the key works before it is kept.
        try await JevClient(deadline: .seconds(10), key: typed).verify()
        guard AIKeyVault.save(typed, account: AIKeyVault.jevAccount) else { failed = true; status = "Couldn’t save the key to your Keychain."; return }
        key = ""; saved = true; failed = false; status = "Connected. Jev now orders your actions."
      } catch {
        failed = true
        status = switch error as? JevClient.Failure {
          case .rejected: "Typesafe rejected this key."
          case .timeout: "Typesafe didn’t answer in time. Try again."
          case .invalid: "Jev returned an unexpected answer."
          default: "Couldn’t reach Typesafe. Check your connection."
        }
      }
    }
  }

  private func remove() {
    AIKeyVault.delete(account: AIKeyVault.jevAccount)
    saved = false; key = ""; status = nil
  }
}

/// The provider's official mark. Monochrome marks follow the text colour; brand-coloured ones keep their colours.
struct ProviderLogo: View {
  let provider: AIProvider
  var body: some View {
    if provider == .gemini, let asset = provider.logoAsset {
      // macOS can't render the official SVG gradient, so the brand colours are applied to the mark here.
      Image(asset).resizable().scaledToFit().foregroundStyle(AngularGradient(
        colors: [Color(red: 0.19, green: 0.53, blue: 1), Color(red: 0.98, green: 0.27, blue: 0.26),
                 Color(red: 0.98, green: 0.74, blue: 0.07), Color(red: 0.03, green: 0.73, blue: 0.38),
                 Color(red: 0.19, green: 0.53, blue: 1)], center: .center)).accessibilityHidden(true)
    } else if let asset = provider.logoAsset {
      Image(asset).resizable().scaledToFit().foregroundStyle(.white.opacity(0.9)).accessibilityHidden(true)
    } else {
      Image(systemName: provider.symbol).font(.system(size: 13)).foregroundStyle(.white.opacity(0.8)).accessibilityHidden(true)
    }
  }
}
