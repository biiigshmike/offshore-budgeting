//
//  HomeAssistantPresentationResolver.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import SwiftUI

// MARK: - Assistant Presentation

enum HomeAssistantPresentationMode: Equatable {
    case inspector
    case sheet
    case fullScreen
}

struct HomeAssistantPresentationPlan: Equatable {
    let mode: HomeAssistantPresentationMode
    let showsBottomLauncher: Bool
    let showsToolbarButton: Bool
    let detents: Set<PresentationDetent>
    let usesExpandedPanelSizing: Bool
    let prefersInlineInspectorWhenAvailable: Bool
}

enum HomeAssistantPresentationResolver {

    // MARK: - Resolve

    static func resolve(
        containerWidth: CGFloat,
        supportsInlineInspector: Bool,
        dynamicTypeSize: DynamicTypeSize,
        voiceOverEnabled: Bool
    ) -> HomeAssistantPresentationPlan {
        let width = max(0, containerWidth)
        let isAccessibilityLayout = voiceOverEnabled || dynamicTypeSize.isAccessibilitySize

        if isAccessibilityLayout || width < 540 {
            return HomeAssistantPresentationPlan(
                mode: .fullScreen,
                showsBottomLauncher: supportsInlineInspector == false,
                showsToolbarButton: supportsInlineInspector,
                detents: [.large],
                usesExpandedPanelSizing: false,
                prefersInlineInspectorWhenAvailable: false
            )
        }

        if width < 900 {
            return HomeAssistantPresentationPlan(
                mode: .sheet,
                showsBottomLauncher: supportsInlineInspector == false,
                showsToolbarButton: supportsInlineInspector,
                detents: [.medium, .large],
                usesExpandedPanelSizing: false,
                prefersInlineInspectorWhenAvailable: false
            )
        }

        if supportsInlineInspector {
            return HomeAssistantPresentationPlan(
                mode: .inspector,
                showsBottomLauncher: false,
                showsToolbarButton: true,
                detents: [.large],
                usesExpandedPanelSizing: false,
                prefersInlineInspectorWhenAvailable: true
            )
        }

        return HomeAssistantPresentationPlan(
            mode: .sheet,
            showsBottomLauncher: false,
            showsToolbarButton: true,
            detents: [.large],
            usesExpandedPanelSizing: true,
            prefersInlineInspectorWhenAvailable: true
        )
    }
}
