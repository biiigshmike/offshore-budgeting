//
//  TabBarReselectHandler.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

#if canImport(UIKit)
import UIKit

/// Detects when the currently-selected tab bar item is tapped again.
struct TabBarReselectHandler: UIViewControllerRepresentable {

    var onReselect: (Int) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.attachIfNeeded(from: uiViewController)
        context.coordinator.onReselect = onReselect
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onReselect: onReselect)
    }

    final class Coordinator: NSObject, UITabBarControllerDelegate {

        fileprivate var onReselect: (Int) -> Void

        private weak var tabBarController: UITabBarController?
        private weak var previousDelegate: UITabBarControllerDelegate?
        private var lastSelectedIndex: Int?

        init(onReselect: @escaping (Int) -> Void) {
            self.onReselect = onReselect
        }

        fileprivate func attachIfNeeded(from viewController: UIViewController) {
            guard let tbc = findTabBarController(from: viewController) else { return }

            if tabBarController !== tbc {
                tabBarController = tbc
                lastSelectedIndex = tbc.selectedIndex
            }

            if tbc.delegate !== self {
                previousDelegate = tbc.delegate
                tbc.delegate = self
            }
        }

        private func findTabBarController(from viewController: UIViewController) -> UITabBarController? {
            var current: UIViewController? = viewController
            while let vc = current {
                if let tbc = vc as? UITabBarController { return tbc }
                current = vc.parent
            }
            return nil
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            let selectedIndex = tabBarController.selectedIndex
            if lastSelectedIndex == selectedIndex {
                onReselect(selectedIndex)
            }
            lastSelectedIndex = selectedIndex

            previousDelegate?.tabBarController?(tabBarController, didSelect: viewController)
        }

        override func responds(to aSelector: Selector!) -> Bool {
            if super.responds(to: aSelector) { return true }
            return previousDelegate?.responds(to: aSelector) ?? false
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if previousDelegate?.responds(to: aSelector) == true {
                return previousDelegate
            }
            return super.forwardingTarget(for: aSelector)
        }
    }
}
#endif
