#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Presents a screen title and date range in the native Catalyst window title bar.
struct MacDateRangeWindowSubtitle: UIViewControllerRepresentable {
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
        controller.stopPresenting()
    }

    final class SubtitleController: UIViewController {
        private static let headings = NSMapTable<UIWindowScene, WindowHeading>(
            keyOptions: .weakMemory, valueOptions: .strongMemory
        )

        var subtitle = ""
        private weak var attachedScene: UIWindowScene?
        private var isVisible = false

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            isVisible = true
            applySubtitle()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            stopPresenting()
        }

        func applySubtitle() {
            guard isVisible, let scene = view.window?.windowScene else { return }
            if attachedScene !== scene {
                detachFromScene()
                attachedScene = scene
                let heading = Self.headings.object(forKey: scene) ?? WindowHeading(scene: scene)
                heading.owners.append(Owner(self))
                Self.headings.setObject(heading, forKey: scene)
            }

            guard Self.headings.object(forKey: scene)?.currentOwner === self else { return }
            showHeading(in: scene)
        }

        func stopPresenting() {
            isVisible = false
            detachFromScene()
        }

        private func detachFromScene() {
            guard let scene = attachedScene else { return }
            attachedScene = nil
            guard let heading = Self.headings.object(forKey: scene) else { return }
            let wasCurrentOwner = heading.currentOwner === self
            heading.owners.removeAll { $0.controller == nil || $0.controller === self }
            guard wasCurrentOwner else { return }

            if let nextOwner = heading.currentOwner {
                nextOwner.showHeading(in: scene)
            } else {
                Self.headings.removeObject(forKey: scene)
                heading.restore(in: scene)
            }
        }

        private func showHeading(in scene: UIWindowScene) {
            if let titlebar = scene.titlebar, titlebar.toolbarStyle != .unified {
                titlebar.toolbarStyle = .unified
            }
            if scene.subtitle != subtitle {
                scene.subtitle = subtitle
            }
            let headingTitle = title ?? ""
            if scene.title != headingTitle {
                scene.title = headingTitle
            }
        }

        private final class Owner {
            weak var controller: SubtitleController?

            init(_ controller: SubtitleController) {
                self.controller = controller
            }
        }

        /// Keep the original heading until the last visible screen leaves.
        private final class WindowHeading {
            var owners: [Owner] = []
            private let previousTitle: String?
            private let previousSubtitle: String
            private let previousToolbarStyle: UITitlebarToolbarStyle

            var currentOwner: SubtitleController? {
                owners.reversed().lazy.compactMap(\.controller).first
            }

            init(scene: UIWindowScene) {
                previousTitle = scene.title
                previousSubtitle = scene.subtitle
                previousToolbarStyle = scene.titlebar?.toolbarStyle ?? .automatic
            }

            func restore(in scene: UIWindowScene) {
                scene.titlebar?.toolbarStyle = previousToolbarStyle
                scene.subtitle = previousSubtitle
                scene.title = previousTitle
            }
        }
    }
}
#endif
