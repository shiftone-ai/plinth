import Foundation

public enum L10n {
  public static func string(_ key: String, locale: Locale? = nil) -> String {
    let requested = (locale?.identifier ?? Bundle.main.preferredLocalizations.first ?? "en")
      .lowercased().replacingOccurrences(of: "_", with: "-")
    let language: String
    switch requested {
    case let code
    where code == "zh" || code.hasPrefix("zh-hans") || code.hasPrefix("zh-cn")
      || code.hasPrefix("zh-sg"):
      language = "zh-Hans"
    case let code where code.hasPrefix("ja"):
      language = "ja"
    case let code where code.hasPrefix("ko"):
      language = "ko"
    case let code where code.hasPrefix("en"):
      language = "en"
    default:
      language = "en"
    }
    guard let path = Bundle.module.path(forResource: language, ofType: "lproj"),
      let localizedBundle = Bundle(path: path)
    else { return key }
    return localizedBundle.localizedString(forKey: key, value: key, table: "Localizable")
  }
}
