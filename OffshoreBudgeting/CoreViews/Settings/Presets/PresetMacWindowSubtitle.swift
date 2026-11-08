#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Presents the preset name and range in the native Catalyst window title bar,
/// restoring the previous heading and toolbar style when the destination leaves.
struct PresetMacWindowSubtitle: UIViewControllerRepresentable {
    let title: String
    let subtitle: String

    func makeUIViewController(context: Context) -> SubtitleController {
        let controller = SubtitleController()
        controller.title = title
        controller.subtitle = subtitle
        return controller
    }

    func updateUIViewController(_ controller: SubtitleController, context: Context) {
        controller.title = title
        controller.subtitle = subtitle
        controller.applySubtitle()
    }

    static func dismantleUIViewController(_ controller: SubtitleController, coordinator: ()) {
        controller.restoreSubtitle()
    }

    final class SubtitleController: UIViewController {
        var subtitle = ""
        private weak var attachedScene: UIWindowScene?
        private var previousTitle = ""
        private var previousSubtitle = ""
        private var previousToolbarStyle: UITitlebarToolbarStyle = .automatic
        private var isVisible = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isVisible = true
            applySubtitle()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            isVisible = false
            restoreSubtitle()
        }

        func applySubtitle() {
            guard isVisible, let scene = view.window?.windowScene else { return }
            if attachedScene !== scene {
                restoreSubtitle()
                attachedScene = scene
                previousTitle = scene.title ?? ""
                previousSubtitle = scene.subtitle
                previousToolbarStyle = scene.titlebar?.toolbarStyle ?? .automatic
            }
            scene.titlebar?.toolbarStyle = .unified
            scene.subtitle = subtitle
            scene.title = title ?? ""
        }

        func restoreSubtitle() {
            if let attachedScene, attachedScene.subtitle == subtitle {
                attachedScene.subtitle = previousSubtitle
                attachedScene.titlebar?.toolbarStyle = previousToolbarStyle
                attachedScene.title = previousTitle
            }
            attachedScene = nil
        }
    }
}
#endif
