import Foundation
import Security

/// How a provider is called. Every supported service speaks one of these three dialects.
enum AIWireProtocol: Sendable {
  case openAIResponses, anthropicMessages, openAICompatible
}

/// Bring-your-own-key providers. Requests go straight from this Mac to the provider;
/// keys stay in the Keychain and never reach Tero's servers.
enum AIProvider: String, CaseIterable, Codable, Identifiable, Sendable {
  case openAI, anthropic, xAI, gemini, openRouter, mistral, groq, deepSeek, ollama, lmStudio, custom

  var id: String { rawValue }
  var title: String {
    switch self {
    case .openAI: "OpenAI"
    case .anthropic: "Anthropic"
    case .xAI: "Grok (xAI)"
    case .gemini: "Google Gemini"
    case .openRouter: "OpenRouter"
    case .mistral: "Mistral"
    case .groq: "Groq"
    case .deepSeek: "DeepSeek"
    case .ollama: "Ollama"
    case .lmStudio: "LM Studio"
    case .custom: "Custom"
    }
  }
  var subtitle: String {
    switch self {
    case .ollama, .lmStudio: "Local models on this Mac"
    case .openRouter: "Hundreds of models, one key"
    case .anthropic: "Claude models"
    case .custom: "Any OpenAI-compatible endpoint"
    default: "Your API key"
    }
  }
  var symbol: String {
    switch self {
    case .ollama, .lmStudio: "desktopcomputer"
    case .openRouter: "arrow.triangle.branch"
    case .custom: "slider.horizontal.3"
    default: "key"
    }
  }
  /// Official mark from Lobe Icons (MIT, Resources/LobeIcons-LICENSE.txt); nil for a custom endpoint.
  var logoAsset: String? { self == .custom ? nil : "Provider-" + rawValue }

  var wire: AIWireProtocol {
    switch self {
    case .openAI: .openAIResponses
    case .anthropic: .anthropicMessages
    default: .openAICompatible
    }
  }
  var defaultBaseURL: String {
    switch self {
    case .openAI: "https://api.openai.com/v1"
    case .anthropic: "https://api.anthropic.com/v1"
    case .xAI: "https://api.x.ai/v1"
    case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai"
    case .openRouter: "https://openrouter.ai/api/v1"
    case .mistral: "https://api.mistral.ai/v1"
    case .groq: "https://api.groq.com/openai/v1"
    case .deepSeek: "https://api.deepseek.com/v1"
    case .ollama: "http://localhost:11434/v1"
    case .lmStudio: "http://localhost:1234/v1"
    case .custom: ""
    }
  }
  /// Suggested starting model. The model list can also be loaded from the provider.
  var defaultModel: String {
    switch self {
    case .openAI: "gpt-6-luna"
    case .anthropic: "claude-haiku-5-5"
    default: ""
    }
  }
  var needsKey: Bool { ![.ollama, .lmStudio].contains(self) }
  var editableBaseURL: Bool { [.ollama, .lmStudio, .custom].contains(self) }
  /// Ask can cite the web; Check a claim and product search require it.
  var supportsWebSearch: Bool { [.openAI, .anthropic, .openRouter].contains(self) }
  /// Native PDF input. Other providers receive the PDF's extracted text instead.
  var supportsPDF: Bool { [.openAI, .anthropic, .openRouter].contains(self) }
  var keyPage: URL? {
    switch self {
    case .openAI: URL(string: "https://platform.openai.com/api-keys")
    case .anthropic: URL(string: "https://console.anthropic.com/settings/keys")
    case .xAI: URL(string: "https://console.x.ai")
    case .gemini: URL(string: "https://aistudio.google.com/apikey")
    case .openRouter: URL(string: "https://openrouter.ai/settings/keys")
    case .mistral: URL(string: "https://console.mistral.ai/api-keys")
    case .groq: URL(string: "https://console.groq.com/keys")
    case .deepSeek: URL(string: "https://platform.deepseek.com/api_keys")
    case .ollama: URL(string: "https://ollama.com/download")
    case .lmStudio: URL(string: "https://lmstudio.ai")
    case .custom: nil
    }
  }
}

/// A complete, ready-to-use provider configuration.
struct AIConfiguration: Sendable, Equatable {
  let provider: AIProvider
  let baseURL: URL
  let model: String
  let key: String?

  /// The configuration used for AI actions, or nil when the user hasn't set one up.
  static var active: AIConfiguration? {
    let defaults = UserDefaults.standard
    guard let raw = defaults.string(forKey: Keys.provider), let provider = AIProvider(rawValue: raw) else { return nil }
    return load(provider)
  }

  static func load(_ provider: AIProvider) -> AIConfiguration? {
    let defaults = UserDefaults.standard
    let base = defaults.string(forKey: Keys.baseURL(provider)) ?? provider.defaultBaseURL
    let model = (defaults.string(forKey: Keys.model(provider)) ?? provider.defaultModel).trimmingCharacters(in: .whitespaces)
    let key = AIKeyVault.read(provider)
    guard let url = validBaseURL(base), !model.isEmpty, !provider.needsKey || key != nil else { return nil }
    return AIConfiguration(provider: provider, baseURL: url, model: model, key: key)
  }

  /// HTTPS everywhere, plain HTTP only for a server on this Mac.
  static func validBaseURL(_ raw: String) -> URL? {
    guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), let host = url.host?.lowercased(),
          url.user == nil, url.password == nil else { return nil }
    if url.scheme == "https" { return url }
    return url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host) ? url : nil
  }

  enum Keys {
    static let provider = "ai.provider"
    static func model(_ provider: AIProvider) -> String { "ai.model." + provider.rawValue }
    static func baseURL(_ provider: AIProvider) -> String { "ai.baseURL." + provider.rawValue }
  }
}

/// One Keychain item per provider, readable only on this Mac while unlocked.
enum AIKeyVault {
  private static func query(_ provider: AIProvider) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: "\(Bundle.main.bundleIdentifier ?? "com.aymenkadri.tero").ai-key",
     kSecAttrAccount as String: provider.rawValue]
  }

  static func read(_ provider: AIProvider) -> String? {
    var attributes = query(provider)
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(attributes as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
    return key
  }

  @discardableResult
  static func save(_ key: String, for provider: AIProvider) -> Bool {
    let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty, key.count <= 512, !key.contains(where: \.isNewline) else { return false }
    let value = [kSecValueData as String: Data(key.utf8)]
    let status = SecItemUpdate(query(provider) as CFDictionary, value as CFDictionary)
    if status == errSecSuccess { return true }
    guard status == errSecItemNotFound else { return false }
    var attributes = query(provider).merging(value) { _, new in new }
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
  }

  static func delete(_ provider: AIProvider) {
    SecItemDelete(query(provider) as CFDictionary)
  }
}
