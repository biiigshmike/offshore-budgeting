#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

private struct MacHomeToolbarControllerKey: EnvironmentKey {
    static let defaultValue: MacHomeToolbarController? = nil
}

extension EnvironmentValues {
    var macHomeToolbarController: MacHomeToolbarController? {
        get { self[MacHomeToolbarControllerKey.self] }
        set { self[MacHomeToolbarControllerKey.self] = newValue }
    }
}

/// Publishes Home's current actions to its owned window toolbar without changing
/// SwiftUI state during view updates. The native actions retain Home's bindings.
struct MacHomeToolbarRegistration: UIViewRepresentable {
    let controller: MacHomeToolbarController
    let menu: UIMenu
    let isMarinaPresented: Bool
    let openAssistant: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        controller.update(
            menu: menu,
            isMarinaPresented: isMarinaPresented,
            openAssistant: openAssistant
        )
    }
}
#endif
