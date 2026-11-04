import SwiftUI

struct CustomThemePalette {
    static let themeID = "custom"
    static let storageKey = "appearance_customPalette"
    static let startingPalette = CustomThemePalette(
        accent: "#256D68",
        base: "#E9F4F0",
        highlight: "#CAE9E3",
        wash: "#E7D4B6"
    )

    var accent: String
    var base: String
    var highlight: String
    var wash: String

    private init(accent: String, base: String, highlight: String, wash: String) {
        self.accent = accent
        self.base = base
        self.highlight = highlight
        self.wash = wash
    }

    init?(storedValue: String) {
        let colors = storedValue.split(separator: ",", omittingEmptySubsequences: false)
        guard colors.count == 4,
              colors.allSatisfy({ color in
                  color.utf8.count == 7 && color.first == "#" && UInt32(color.dropFirst(), radix: 16) != nil
                    && color.dropFirst().allSatisfy { $0.isHexDigit }
              })
        else { return nil }

        self.init(accent: String(colors[0]), base: String(colors[1]),
                  highlight: String(colors[2]), wash: String(colors[3]))
    }

    var storedValue: String {
        [accent, base, highlight, wash].joined(separator: ",")
    }

    func resolve(for scheme: ColorScheme) -> ResolvedAppearanceTheme {
        let dark = scheme == .dark
        let backgroundAnchor: Color = dark ? .black : .white
        return ResolvedAppearanceTheme(
            id: Self.themeID,
            accent: color(at: \.accent).mix(with: dark ? .white : .black, by: dark ? 0.35 : 0.25),
            homeBackgroundPalette: (
                color(at: \.base).mix(with: backgroundAnchor, by: dark ? 0.65 : 0.60),
                color(at: \.highlight).mix(with: backgroundAnchor, by: 0.70),
                color(at: \.wash).mix(with: backgroundAnchor, by: dark ? 0.75 : 0.60)
            )
        )
    }

    func color(at field: KeyPath<Self, String>) -> Color {
        Color(hex: self[keyPath: field]) ?? .clear
    }

    mutating func setColor(_ color: Color, at field: WritableKeyPath<Self, String>, in environment: EnvironmentValues) {
        let rgb = color.resolve(in: environment)
        let bytes = [rgb.red, rgb.green, rgb.blue].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        self[keyPath: field] = String(format: "#%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }
}
