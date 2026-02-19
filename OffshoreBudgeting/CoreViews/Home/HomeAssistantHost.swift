//
//  HomeAssistantHost.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/17/26.
//

import SwiftUI

struct HomeAssistantToolbarContext {
    var isToolbarButtonVisible: Bool = false
    var openAssistant: () -> Void = {}
}

private struct HomeAssistantToolbarContextKey: EnvironmentKey {
    static let defaultValue = HomeAssistantToolbarContext()
}

extension EnvironmentValues {
    var homeAssistantToolbarContext: HomeAssistantToolbarContext {
        get { self[HomeAssistantToolbarContextKey.self] }
        set { self[HomeAssistantToolbarContextKey.self] = newValue }
    }
}

struct HomeAssistantHostModifier: ViewModifier {

    let workspace: Workspace
    let isEnabled: Bool

    @State private var assistantRoute: AssistantPresentationRoute? = nil
    @State private var containerWidth: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private enum AssistantPresentationRoute: Equatable {
        case inspector
        case sheet
        case fullScreen
    }

    private var isPhone: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented: assistantSheetPresentedBinding,
                onDismiss: dismissAssistant
            ) {
                HomeAssistantPanelView(
                    workspace: workspace,
                    onDismiss: dismissAssistant,
                    shouldUseLargeMinimumSize: assistantPresentationPlan.usesExpandedPanelSizing
                )
                .presentationDetents(assistantPresentationPlan.detents)
                .presentationDragIndicator(.visible)
            }
            .applyAssistantInspectorIfNeeded(
                isEnabled: shouldMountInspectorPresenter,
                isPresented: assistantInspectorPresentedBinding
            ) {
                HomeAssistantPanelView(
                    workspace: workspace,
                    onDismiss: dismissAssistant,
                    shouldUseLargeMinimumSize: false
                )
                .inspectorColumnWidth(min: 340, ideal: 420, max: 520)
            }
            .fullScreenCover(
                isPresented: assistantFullScreenPresentedBinding,
                onDismiss: dismissAssistant
            ) {
                HomeAssistantPanelView(
                    workspace: workspace,
                    onDismiss: dismissAssistant,
                    shouldUseLargeMinimumSize: false
                )
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateContainerWidth(proxy.size.width)
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            updateContainerWidth(newWidth)
                        }
                }
            }
            .environment(\.homeAssistantToolbarContext, assistantToolbarContext)
            .onChange(of: isEnabled) { _, enabled in
                if enabled == false {
                    dismissAssistant()
                }
            }
            .onDisappear {
                dismissAssistant()
            }
    }

    private var assistantSheetPresentedBinding: Binding<Bool> {
        Binding(
            get: { isEnabled && assistantRoute == .sheet },
            set: { isPresented in
                assistantRoute = isPresented ? .sheet : nil
            }
        )
    }

    private var assistantInspectorPresentedBinding: Binding<Bool> {
        Binding(
            get: { isEnabled && assistantRoute == .inspector },
            set: { isPresented in
                assistantRoute = isPresented ? .inspector : nil
            }
        )
    }

    private var assistantFullScreenPresentedBinding: Binding<Bool> {
        Binding(
            get: { isEnabled && assistantRoute == .fullScreen },
            set: { isPresented in
                assistantRoute = isPresented ? .fullScreen : nil
            }
        )
    }

    private func presentAssistant() {
        guard isEnabled else { return }
        guard assistantRoute == nil else { return }
        assistantRoute = route(for: assistantPresentationPlan.mode)
    }

    private func dismissAssistant() {
        assistantRoute = nil
    }

    private func route(for mode: HomeAssistantPresentationMode) -> AssistantPresentationRoute {
        switch mode {
        case .inspector:
            return .inspector
        case .sheet:
            return .sheet
        case .fullScreen:
            return .fullScreen
        }
    }

    private var assistantPresentationPlan: HomeAssistantPresentationPlan {
        let basePlan = HomeAssistantPresentationResolver.resolve(
            containerWidth: containerWidth,
            supportsInlineInspector: supportsInlineInspector,
            dynamicTypeSize: dynamicTypeSize,
            voiceOverEnabled: voiceOverEnabled
        )

        guard isPhone == false else {
            return HomeAssistantPresentationPlan(
                mode: .fullScreen,
                showsBottomLauncher: false,
                showsToolbarButton: true,
                detents: [.large],
                usesExpandedPanelSizing: false,
                prefersInlineInspectorWhenAvailable: false
            )
        }

        guard usesCompactPhoneHeight == false else {
            return HomeAssistantPresentationPlan(
                mode: basePlan.mode,
                showsBottomLauncher: false,
                showsToolbarButton: true,
                detents: basePlan.detents,
                usesExpandedPanelSizing: basePlan.usesExpandedPanelSizing,
                prefersInlineInspectorWhenAvailable: basePlan.prefersInlineInspectorWhenAvailable
            )
        }

        return basePlan
    }

    private var supportsInlineInspector: Bool {
        isPhone == false && horizontalSizeClass != .compact
    }

    private var usesCompactPhoneHeight: Bool {
        #if os(iOS)
        isPhone && verticalSizeClass == .compact
        #else
        false
        #endif
    }

    private var shouldShowToolbarButton: Bool {
        guard isEnabled, assistantPresentationPlan.showsToolbarButton else {
            return false
        }

        if isPhone {
            return true
        }

        return assistantRoute == nil
    }

    private var assistantToolbarContext: HomeAssistantToolbarContext {
        HomeAssistantToolbarContext(
            isToolbarButtonVisible: shouldShowToolbarButton,
            openAssistant: presentAssistant
        )
    }

    private var shouldMountInspectorPresenter: Bool {
        isEnabled && supportsInlineInspector && assistantRoute == .inspector
    }

    private func updateContainerWidth(_ rawWidth: CGFloat) {
        let width = max(0, rawWidth)
        let previousBand = widthBand(for: containerWidth)
        let nextBand = widthBand(for: width)

        if containerWidth == 0 || previousBand != nextBand {
            containerWidth = width
        }
    }

    private func widthBand(for width: CGFloat) -> Int {
        if width < 540 { return 0 }
        if width < 900 { return 1 }
        return 2
    }
}

extension View {
    func homeAssistantHost(workspace: Workspace, isEnabled: Bool = true) -> some View {
        modifier(HomeAssistantHostModifier(workspace: workspace, isEnabled: isEnabled))
    }
}

private extension View {
    @ViewBuilder
    func applyAssistantInspectorIfNeeded<InspectorContent: View>(
        isEnabled: Bool,
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> InspectorContent
    ) -> some View {
        if isEnabled {
            self.inspector(isPresented: isPresented, content: content)
        } else {
            self
        }
    }
}
