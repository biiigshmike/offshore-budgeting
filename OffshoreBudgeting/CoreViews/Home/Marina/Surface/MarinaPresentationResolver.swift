//
//  MarinaPanelPresentationResolver.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import SwiftUI

// MARK: - Assistant Presentation

enum MarinaPanelPresentationMode: Equatable {
    case inspector
    case sheet
    case fullScreen
}

struct MarinaPanelPresentationPlan: Equatable {
    let mode: MarinaPanelPresentationMode
    let showsBottomLauncher: Bool
    let showsToolbarButton: Bool
    let detents: Set<PresentationDetent>
    let usesExpandedPanelSizing: Bool
    let prefersInlineInspectorWhenAvailable: Bool
}

enum MarinaPanelPresentationResolver {

    // MARK: - Resolve

    static func resolve(
        containerWidth: CGFloat,
        supportsInlineInspector: Bool,
        dynamicTypeSize: DynamicTypeSize,
        voiceOverEnabled: Bool
    ) -> MarinaPanelPresentationPlan {
        let width = max(0, containerWidth)
        let isAccessibilityLayout = voiceOverEnabled || dynamicTypeSize.isAccessibilitySize

        if isAccessibilityLayout || width < 540 {
            return MarinaPanelPresentationPlan(
                mode: .fullScreen,
                showsBottomLauncher: supportsInlineInspector == false,
                showsToolbarButton: supportsInlineInspector,
                detents: [.large],
                usesExpandedPanelSizing: false,
                prefersInlineInspectorWhenAvailable: false
            )
        }

        if width < 900 {
            return MarinaPanelPresentationPlan(
                mode: .sheet,
                showsBottomLauncher: supportsInlineInspector == false,
                showsToolbarButton: supportsInlineInspector,
                detents: [.medium, .large],
                usesExpandedPanelSizing: false,
                prefersInlineInspectorWhenAvailable: false
            )
        }

        if supportsInlineInspector {
            return MarinaPanelPresentationPlan(
                mode: .inspector,
                showsBottomLauncher: false,
                showsToolbarButton: true,
                detents: [.large],
                usesExpandedPanelSizing: false,
                prefersInlineInspectorWhenAvailable: true
            )
        }

        return MarinaPanelPresentationPlan(
            mode: .sheet,
            showsBottomLauncher: false,
            showsToolbarButton: true,
            detents: [.large],
            usesExpandedPanelSizing: true,
            prefersInlineInspectorWhenAvailable: true
        )
    }
}
