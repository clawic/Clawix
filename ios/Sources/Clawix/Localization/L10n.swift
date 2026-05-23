import Foundation

enum L10n {
    static func t(_ key: String.LocalizationValue) -> String {
        String(localized: key, bundle: .main)
    }

    static func format(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: t(key), locale: Locale.current, arguments: args)
    }
}
