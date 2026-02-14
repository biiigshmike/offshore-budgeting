import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Catalyst Titlebar

struct CatalystWindowTitlebarModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.background(CatalystWindowTitlebarConfigurator())
        #else
        content
        #endif
    }
}

extension View {
    func hideCatalystWindowTitlebarText() -> some View {
        modifier(CatalystWindowTitlebarModifier())
    }
}

#if targetEnvironment(macCatalyst)
private struct CatalystWindowTitlebarConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = TitlebarVisibilityView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let visibilityView = uiView as? TitlebarVisibilityView else { return }
        visibilityView.applyTitlebarVisibilityIfPossible()
    }
}

private final class TitlebarVisibilityView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyTitlebarVisibilityIfPossible()
    }

    func applyTitlebarVisibilityIfPossible() {
        window?.windowScene?.titlebar?.titleVisibility = .hidden
    }
}
#endif
