import Foundation

func widgetLocalized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func widgetLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: widgetLocalized(key), locale: Locale.current, arguments)
}
