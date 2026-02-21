//
//  MacWindowSceneTitleHost.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/21/26.
//

import SwiftUI

#if targetEnvironment(macCatalyst)
import UIKit
#endif

struct MacWindowSceneTitleHost: View {

    let title: String

    var body: some View {
        #if targetEnvironment(macCatalyst)
        MacWindowSceneTitleRepresentable(title: title)
            .frame(width: 0, height: 0)
        #else
        EmptyView()
        #endif
    }
}

#if targetEnvironment(macCatalyst)
private struct MacWindowSceneTitleRepresentable: UIViewRepresentable {

    let title: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> SceneAttachmentView {
        let view = SceneAttachmentView()

        view.onWindowSceneChange = { [weak coordinator = context.coordinator] scene in
            coordinator?.attach(scene: scene)
        }

        context.coordinator.setDesiredTitle(title)
        return view
    }

    func updateUIView(_ uiView: SceneAttachmentView, context: Context) {
        context.coordinator.setDesiredTitle(title)

        if let scene = uiView.window?.windowScene {
            context.coordinator.attach(scene: scene)
        }
    }

    // MARK: - Coordinator

    final class Coordinator {

        private let notificationCenter = NotificationCenter.default

        private var desiredTitle: String = ""
        private weak var scene: UIWindowScene?
        private var isApplyingSceneTitle: Bool = false

        private var sceneDidActivateObserver: NSObjectProtocol?
        private var sceneWillEnterForegroundObserver: NSObjectProtocol?
        private var sceneTitleObservation: NSKeyValueObservation?

        deinit {
            removeObservers()
        }

        func setDesiredTitle(_ title: String) {
            desiredTitle = title
            applyTitleIfNeeded()
        }

        func attach(scene: UIWindowScene?) {
            guard let scene else { return }
            guard self.scene !== scene else {
                applyTitleIfNeeded()
                return
            }

            self.scene = scene
            installObservers(for: scene)
            installSceneTitleObservation(for: scene)
            applyTitleIfNeeded()
        }

        private func applyTitleIfNeeded() {
            guard let scene else { return }

            if scene.title != desiredTitle {
                isApplyingSceneTitle = true
                scene.title = desiredTitle
                isApplyingSceneTitle = false
            }

            if let titlebar = scene.titlebar, titlebar.titleVisibility != .visible {
                titlebar.titleVisibility = .visible
            }
        }

        private func installObservers(for scene: UIWindowScene) {
            removeObservers()

            sceneDidActivateObserver = notificationCenter.addObserver(
                forName: UIScene.didActivateNotification,
                object: scene,
                queue: .main
            ) { [weak self] _ in
                self?.applyTitleIfNeeded()
            }

            sceneWillEnterForegroundObserver = notificationCenter.addObserver(
                forName: UIScene.willEnterForegroundNotification,
                object: scene,
                queue: .main
            ) { [weak self] _ in
                self?.applyTitleIfNeeded()
            }
        }

        private func installSceneTitleObservation(for scene: UIWindowScene) {
            sceneTitleObservation?.invalidate()
            sceneTitleObservation = scene.observe(\.title, options: [.new]) { [weak self] _, change in
                guard let self else { return }
                guard self.isApplyingSceneTitle == false else { return }

                let sceneTitle = change.newValue ?? ""
                if sceneTitle != self.desiredTitle {
                    self.applyTitleIfNeeded()
                }
            }
        }

        private func removeObservers() {
            if let sceneDidActivateObserver {
                notificationCenter.removeObserver(sceneDidActivateObserver)
                self.sceneDidActivateObserver = nil
            }

            if let sceneWillEnterForegroundObserver {
                notificationCenter.removeObserver(sceneWillEnterForegroundObserver)
                self.sceneWillEnterForegroundObserver = nil
            }

            sceneTitleObservation?.invalidate()
            sceneTitleObservation = nil
        }
    }
}

private final class SceneAttachmentView: UIView {

    var onWindowSceneChange: ((UIWindowScene?) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowSceneChange?(window?.windowScene)
    }
}
#endif
