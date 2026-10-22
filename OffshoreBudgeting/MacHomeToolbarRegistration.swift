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
    let editWidgets: () -> Void

    final class Coordinator {
        let registrationID = UUID()
        weak var controller: MacHomeToolbarController?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.controller = controller
        controller.update(
            menu: menu,
            isMarinaPresented: isMarinaPresented,
            openAssistant: openAssistant,
            editWidgets: editWidgets,
            registrationID: context.coordinator.registrationID
        )
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.controller?.clearHomeRegistration(id: coordinator.registrationID)
    }
}
#endif
