import SwiftUI
import UIKit

/// Native menus accept images rather than arbitrary SwiftUI artwork. Keep a
/// bounded cache of these small, decorative snapshots as forms redraw.
@MainActor
enum EntityMenuImageCache {
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 256
        return cache
    }()

    static func card(themeRaw: String, effectRaw: String, colorScheme: ColorScheme, scale: CGFloat) -> UIImage? {
        let theme = CardThemeOption(rawValue: themeRaw) ?? .ruby
        let effect = CardEffectOption(rawValue: effectRaw) ?? .plastic
        let key = "card:\(theme.rawValue):\(effect.rawValue):\(appearanceKey(colorScheme)):\(scale)" as NSString
        if let image = images.object(forKey: key) { return image }

        let artwork = CardVisualView(
            title: "",
            theme: theme,
            effect: effect,
            minHeight: nil,
            showsShadow: false,
            titlePadding: 0,
            titleOpacity: 0
        )
        .frame(width: 160, height: 160 / 1.586)
        .scaleEffect(0.2)
        .frame(width: 32, height: 32 / 1.586)
        .clipped()
        .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: artwork)
        renderer.scale = scale
        guard let image = renderer.uiImage?.withRenderingMode(.alwaysOriginal) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }

    static func category(hexColor: String?, colorScheme: ColorScheme, scale: CGFloat) -> UIImage? {
        let key = "category:\(hexColor?.uppercased() ?? "none"):\(appearanceKey(colorScheme)):\(scale)" as NSString
        if let image = images.object(forKey: key) { return image }

        let artwork = Circle()
            .fill(hexColor.flatMap(Color.init(hex:)) ?? .secondary)
            .frame(width: 12, height: 12)
            .padding(2)
            .environment(\.colorScheme, colorScheme)
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = scale
        guard let image = renderer.uiImage?.withRenderingMode(.alwaysOriginal) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }

    private static func appearanceKey(_ colorScheme: ColorScheme) -> String {
        colorScheme == .dark ? "dark" : "light"
    }
}
