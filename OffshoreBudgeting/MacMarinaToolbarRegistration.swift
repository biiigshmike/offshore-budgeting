#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Publishes the visible conversation's actions to the Marina toolbar segment.
struct MacMarinaToolbarRegistration: UIViewRepresentable {
    let controller: MacHomeToolbarController
    let menu: UIMenu
    let onDismiss: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        controller.updateMarina(menu: menu, onDismiss: onDismiss)
    }
}
#endif
