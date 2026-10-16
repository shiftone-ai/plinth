import Foundation
import Observation

public enum InterfaceLanguage: String, CaseIterable, Identifiable, Sendable {
  case system
  case japanese = "ja"
  case english = "en"
  case korean = "ko"
  case simplifiedChinese = "zh-Hans"

  public var id: String { rawValue }

  public var nativeName: String {
    switch self {
    case .system: ""
    case .japanese: "日本語"
    case .english: "English"
    case .korean: "한국어"
    case .simplifiedChinese: "简体中文"
    }
  }
}

@MainActor @Observable
public final class LanguagePreference {
  private let key: String
  private let defaults: UserDefaults
  public private(set) var selection: InterfaceLanguage

  public init(storageNamespace: String = "Plinth", defaults: UserDefaults = .standard) {
    key = "ai.shiftone.plinth.interfaceLanguage.\(storageNamespace)"
    self.defaults = defaults
    selection = InterfaceLanguage(rawValue: defaults.string(forKey: key) ?? "") ?? .system
  }

  public var locale: Locale {
    Locale(
      identifier: selection == .system
        ? Bundle.main.preferredLocalizations.first ?? "en" : selection.rawValue)
  }

  public func select(_ language: InterfaceLanguage) {
    guard selection != language else { return }
    selection = language
    if language == .system {
      defaults.removeObject(forKey: key)
    } else {
      defaults.set(language.rawValue, forKey: key)
    }
  }
}
