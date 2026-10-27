import Foundation

private final class LocalizationBundle: NSObject {}

enum L10n {
    static func text(_ key: String, language: InterfaceLanguage = .system) -> String {
        let resources = Bundle(for: LocalizationBundle.self)
        guard let path = resources.path(forResource: language.resolved, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
