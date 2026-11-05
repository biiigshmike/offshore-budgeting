import SwiftUI
import UIKit

/// Liquid Glass can render system navigation symbols in a neutral color even
/// when their SwiftUI container has a tint. Keep the native controls and supply
/// an explicitly colored symbol through UIKit's public appearance APIs.
struct NavigationAccentAppearance: UIViewControllerRepresentable {
    @Environment(\.appearanceTheme) private var theme

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.accent = UIColor(theme.accent)
        controller.applyAppearance()
    }

    final class Controller: UIViewController {
        var accent: UIColor = .tintColor
        private let appliedColors = NSMapTable<UIViewController, UIColor>.weakToStrongObjects()

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            applyAppearance()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            applyAppearance()
        }

        func applyAppearance() {
            guard let root = viewIfLoaded?.window?.rootViewController else { return }
            apply(to: root)
        }

        private func apply(to controller: UIViewController) {
            let color = accent.resolvedColor(with: controller.traitCollection)
            if let navigation = controller as? UINavigationController {
                let bar = navigation.navigationBar
                if appliedColors.object(forKey: navigation) != color
                    || bar.standardAppearance.backIndicatorImage.renderingMode != .alwaysOriginal {
                    func themed(_ original: UINavigationBarAppearance) -> UINavigationBarAppearance {
                        let appearance = UINavigationBarAppearance(barAppearance: original)
                        let image = original.backIndicatorImage.withTintColor(color, renderingMode: .alwaysOriginal)
                        appearance.setBackIndicatorImage(image, transitionMaskImage: original.backIndicatorTransitionMaskImage)
                        return appearance
                    }
                    bar.standardAppearance = themed(bar.standardAppearance)
                    if let appearance = bar.scrollEdgeAppearance { bar.scrollEdgeAppearance = themed(appearance) }
                    if let appearance = bar.compactAppearance { bar.compactAppearance = themed(appearance) }
                    if let appearance = bar.compactScrollEdgeAppearance { bar.compactScrollEdgeAppearance = themed(appearance) }
                    appliedColors.setObject(color, forKey: navigation)
                }
            }
            for child in controller.children { apply(to: child) }
            if let presented = controller.presentedViewController { apply(to: presented) }
        }
    }
}
