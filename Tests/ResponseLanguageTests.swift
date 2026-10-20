import Foundation
import Testing
@testable import TeroCore

@Test func responseLanguageDefaultsToEnglishAndPersistsExplicitChoice() throws {
  let suite = "tero-language-test-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  #expect(ResponseLanguage.load(from: defaults) == .english)
  ResponseLanguage.french.save(to: defaults)
  let reloaded = try #require(UserDefaults(suiteName: suite))
  #expect(ResponseLanguage.load(from: reloaded) == .french)
  defaults.set("unknown", forKey: "aiResponseLanguage")
  #expect(ResponseLanguage.load(from: defaults) == .english)
}

@Test func translationTargetIsSeparateFromExplanationLanguage() throws {
  let suite = "tero-translation-test-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  #expect(ResponseLanguage.translationTarget(from: defaults) == .english)
  ResponseLanguage.french.saveTranslationTarget(to: defaults)
  #expect(ResponseLanguage.translationTarget(from: defaults) == .french)
  #expect(ResponseLanguage.load(from: defaults) == .english)
  ResponseLanguage.french.save(to: defaults)
  ResponseLanguage.english.saveTranslationTarget(to: defaults)
  #expect(ResponseLanguage.load(from: defaults) == .french)
}
