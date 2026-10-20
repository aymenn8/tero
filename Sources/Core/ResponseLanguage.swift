import Foundation

enum ResponseLanguage: String, CaseIterable, Sendable {
  case english = "en"
  case french = "fr"
  case spanish = "es", german = "de", italian = "it", portuguese = "pt"
  case dutch = "nl", arabic = "ar", chinese = "zh", japanese = "ja", korean = "ko", hindi = "hi"

  private static let preferenceKey = "aiResponseLanguage"

  var title: String {
    switch self {
    case .english: "English"
    case .french: "Français"
    case .spanish: "Spanish"
    case .german: "German"
    case .italian: "Italian"
    case .portuguese: "Portuguese"
    case .dutch: "Dutch"
    case .arabic: "Arabic"
    case .chinese: "Chinese"
    case .japanese: "Japanese"
    case .korean: "Korean"
    case .hindi: "Hindi"
    }
  }

  static func load(from defaults: UserDefaults = .standard) -> Self {
    defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .english
  }

  static func translationTarget(from defaults: UserDefaults = .standard) -> Self {
    defaults.string(forKey: "translationTargetLanguage").flatMap(Self.init(rawValue:)) ?? .english
  }

  func saveTranslationTarget(to defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: "translationTargetLanguage")
    let recent = [rawValue] + (defaults.stringArray(forKey: "recentTranslationLanguages") ?? []).filter { $0 != rawValue }
    defaults.set(Array(recent.prefix(3)), forKey: "recentTranslationLanguages")
  }

  static func translationChoices(from defaults: UserDefaults = .standard) -> [Self] {
    var seen = Set<Self>()
    let recent = (defaults.stringArray(forKey: "recentTranslationLanguages") ?? []).compactMap(Self.init(rawValue:))
    return ([translationTarget(from: defaults)] + recent + allCases).filter { seen.insert($0).inserted }
  }

  func save(to defaults: UserDefaults = .standard) {
    defaults.set(rawValue, forKey: Self.preferenceKey)
  }
}
