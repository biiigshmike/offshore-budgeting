//
//  MarinaHost.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/17/26.
//

import SwiftUI

struct MarinaPanelHomeContext: Equatable, Sendable {
    let dateRange: HomeQueryDateRange?
    let excludeFuturePlannedExpensesFromCalculations: Bool
    let excludeFutureVariableExpensesFromCalculations: Bool

    init(
        dateRange: HomeQueryDateRange?,
        excludeFuturePlannedExpensesFromCalculations: Bool = false,
        excludeFutureVariableExpensesFromCalculations: Bool = false
    ) {
        self.dateRange = dateRange
        self.excludeFuturePlannedExpensesFromCalculations = excludeFuturePlannedExpensesFromCalculations
        self.excludeFutureVariableExpensesFromCalculations = excludeFutureVariableExpensesFromCalculations
    }
}

struct MarinaToolbarContext {
    var isToolbarButtonVisible: Bool = false
    var openAssistant: (MarinaPanelHomeContext?) -> Void = { _ in }
}

private struct MarinaToolbarContextKey: EnvironmentKey {
    static let defaultValue = MarinaToolbarContext()
}

extension EnvironmentValues {
    var marinaToolbarContext: MarinaToolbarContext {
        get { self[MarinaToolbarContextKey.self] }
        set { self[MarinaToolbarContextKey.self] = newValue }
    }
}

struct MarinaHostModifier: ViewModifier {

    let workspace: Workspace
    let isEnabled: Bool

    @State private var assistantRoute: AssistantPresentationRoute? = nil
    @State private var containerWidth: CGFloat = 0
    @State private var activeHomeContext: MarinaPanelHomeContext? = nil

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
                MarinaPanelView(
                    workspace: workspace,
                    onDismiss: dismissAssistant,
                    shouldUseLargeMinimumSize: assistantPresentationPlan.usesExpandedPanelSizing,
                    homeContext: activeHomeContext
                )
                .presentationDetents(assistantPresentationPlan.detents)
                .presentationDragIndicator(.visible)
            }
            .applyAssistantInspectorIfNeeded(
                isEnabled: shouldMountInspectorPresenter,
                isPresented: assistantInspectorPresentedBinding
            ) {
                MarinaPanelView(
                    workspace: workspace,
                    onDismiss: dismissAssistant,
                    shouldUseLargeMinimumSize: false,
                    homeContext: activeHomeContext
                )
                .inspectorColumnWidth(min: 340, ideal: 420, max: 520)
            }
            .fullScreenCover(
                isPresented: assistantFullScreenPresentedBinding,
                onDismiss: dismissAssistant
            ) {
                MarinaPanelView(
                    workspace: workspace,
                    onDismiss: dismissAssistant,
                    shouldUseLargeMinimumSize: false,
                    homeContext: activeHomeContext
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
            .environment(\.marinaToolbarContext, assistantToolbarContext)
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

    private func presentAssistant(homeContext: MarinaPanelHomeContext?) {
        guard isEnabled else { return }
        guard assistantRoute == nil else { return }
        activeHomeContext = homeContext
        assistantRoute = route(for: assistantPresentationPlan.mode)
    }

    private func dismissAssistant() {
        assistantRoute = nil
        activeHomeContext = nil
    }

    private func route(for mode: MarinaPanelPresentationMode) -> AssistantPresentationRoute {
        switch mode {
        case .inspector:
            return .inspector
        case .sheet:
            return .sheet
        case .fullScreen:
            return .fullScreen
        }
    }

    private var assistantPresentationPlan: MarinaPanelPresentationPlan {
        let basePlan = MarinaPanelPresentationResolver.resolve(
            containerWidth: containerWidth,
            supportsInlineInspector: supportsInlineInspector,
            dynamicTypeSize: dynamicTypeSize,
            voiceOverEnabled: voiceOverEnabled
        )

        guard isPhone == false else {
            return MarinaPanelPresentationPlan(
                mode: .fullScreen,
                showsBottomLauncher: false,
                showsToolbarButton: true,
                detents: [.large],
                usesExpandedPanelSizing: false,
                prefersInlineInspectorWhenAvailable: false
            )
        }

        guard usesCompactPhoneHeight == false else {
            return MarinaPanelPresentationPlan(
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

    private var assistantToolbarContext: MarinaToolbarContext {
        MarinaToolbarContext(
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
    func marinaHost(workspace: Workspace, isEnabled: Bool = true) -> some View {
        modifier(MarinaHostModifier(workspace: workspace, isEnabled: isEnabled))
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
