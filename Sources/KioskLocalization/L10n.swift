import Foundation

public enum L10n {
  public static func string(_ key: String, locale: Locale? = nil) -> String {
    let language = languageCode(for: locale)
    guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
      let localizedBundle = Bundle(path: path)
    else { return key }
    return localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
  }

  public static func languageCode(for locale: Locale? = nil) -> String {
    let requested = (locale?.identifier ?? Bundle.main.preferredLocalizations.first ?? "en")
      .lowercased().replacingOccurrences(of: "_", with: "-")
    switch requested {
    case let code
    where code == "zh" || code.hasPrefix("zh-hans") || code.hasPrefix("zh-cn")
      || code.hasPrefix("zh-sg"):
      return "zh-Hans"
    case let code where code.hasPrefix("ja"):
      return "ja"
    case let code where code.hasPrefix("ko"):
      return "ko"
    case let code where code.hasPrefix("en"):
      return "en"
    default:
      return "en"
    }
  }
}
