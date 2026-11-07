#if os(iOS) && !targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

extension View {
    func nativeDetailMenu(
        label: String,
        value: String?,
        identifier: String,
        isEnabled: Bool = true,
        refreshWhileOpen: Bool = false,
        menu: @escaping () -> UIMenu
    ) -> some View {
        accessibilityHidden(true)
            .overlay {
                TransparentDetailMenu(
                    label: label, value: value, identifier: identifier, isEnabled: isEnabled,
                    refreshWhileOpen: refreshWhileOpen, menu: menu
                )
            }
    }
}

private struct TransparentDetailMenu: UIViewRepresentable {
    let label: String
    let value: String?
    let identifier: String
    let isEnabled: Bool
    let refreshWhileOpen: Bool
    let menu: () -> UIMenu

    func makeUIView(context: Context) -> Trigger {
        let button = Trigger(type: .custom)
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        return button
    }

    func updateUIView(_ button: Trigger, context: Context) {
        let updatedMenu = menu()
        button.isEnabled = isEnabled
        button.accessibilityLabel = label
        button.accessibilityValue = value
        button.accessibilityIdentifier = identifier
        button.menu = updatedMenu
        if refreshWhileOpen {
            button.contextMenuInteraction?.updateVisibleMenu { _ in updatedMenu }
        }
    }

    final class Trigger: UIButton {
        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            transparentPreview()
        }

        override func contextMenuInteraction(
            _ interaction: UIContextMenuInteraction,
            previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
        ) -> UITargetedPreview? {
            transparentPreview()
        }

        private func transparentPreview() -> UITargetedPreview {
            // The SwiftUI label is behind this transparent button, outside the preview snapshot.
            let parameters = UIPreviewParameters()
            parameters.backgroundColor = .clear
            parameters.shadowPath = UIBezierPath()
            return UITargetedPreview(view: self, parameters: parameters)
        }
    }
}
#endif
