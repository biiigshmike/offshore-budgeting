import SwiftUI

enum AppearanceTheme: String, CaseIterable, Identifiable {
    case offshoreDefault = "offshore-default"
    case harbor
    case slate
    case dune
    case heather

    static let storageKey = "appearance_theme"

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .offshoreDefault: "Default"
        case .harbor: "Moss"
        case .slate: "Slate"
        case .dune: "Dune"
        case .heather: "Botanical"
        }
    }

    var resolved: ResolvedAppearanceTheme {
        ResolvedAppearanceTheme(id: id, accent: accent, homeBackgroundPalette: homeBackgroundPalette)
    }

    var accent: Color {
        switch self {
        case .offshoreDefault: Color("AccentColor")
        case .harbor: Color("ThemeHarborAccent")
        case .slate: Color("ThemeSlateAccent")
        case .dune: Color("ThemeDuneAccent")
        case .heather: Color("ThemeHeatherAccent")
        }
    }

    var homeBackgroundPalette: (base: Color, highlight: Color, wash: Color)? {
        let assetPrefix: String
        switch self {
        case .offshoreDefault: return nil
        case .harbor: assetPrefix = "ThemeHarborHomeBackground"
        case .slate: assetPrefix = "ThemeSlateHomeBackground"
        case .dune: assetPrefix = "ThemeDuneHomeBackground"
        case .heather: assetPrefix = "ThemeHeatherHomeBackground"
        }
        return (
            base: Color(assetPrefix),
            highlight: Color(assetPrefix + "Highlight"),
            wash: Color(assetPrefix + "Wash")
        )
    }
}

extension EnvironmentValues {
    @Entry var appearanceTheme: ResolvedAppearanceTheme = AppearanceTheme.offshoreDefault.resolved
}

extension View {
    func offshoreAccentTint() -> some View {
        modifier(OffshoreAccentTint())
    }

    /// A muted theme accent for secondary actions alongside a primary action.
    func offshoreSecondaryAccentTint() -> some View {
        modifier(OffshoreAccentTint(opacity: 0.55))
    }
}

private struct OffshoreAccentTint: ViewModifier {
    @Environment(\.appearanceTheme) private var theme
    var opacity: Double = 1

    func body(content: Content) -> some View {
        content.tint(theme.accent.opacity(opacity))
    }
}
