import SwiftUI

struct ResolvedAppearanceTheme {
    let id: String
    let accent: Color
    let homeBackgroundPalette: (base: Color, highlight: Color, wash: Color)?

    static func resolve(id: String, customPalette: String, scheme: ColorScheme) -> Self {
        if id == CustomThemePalette.themeID,
           let palette = CustomThemePalette(storedValue: customPalette) {
            return palette.resolve(for: scheme)
        }
        return (AppearanceTheme(rawValue: id) ?? .offshoreDefault).resolved
    }
}
