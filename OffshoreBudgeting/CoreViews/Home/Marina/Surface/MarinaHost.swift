//
//  MarinaHost.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/17/26.
//

import SwiftUI

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
    @State private var activeHomeContext: MarinaPanelHomeContext? = nil

    private enum AssistantPresentationRoute: Equatable {
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
                    shouldUseLargeMinimumSize: false,
                    homeContext: activeHomeContext
                )
                .id(workspace.id)
                .frame(idealWidth: 700, idealHeight: 650)
                .presentationSizing(.fitted)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
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
            .environment(\.marinaToolbarContext, assistantToolbarContext)
            .onChange(of: workspace.id) { _, _ in
                dismissAssistant()
            }
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

    private var assistantFullScreenPresentedBinding: Binding<Bool> {
        Binding(
            get: { isEnabled && assistantRoute == .fullScreen },
            set: { isPresented in
                assistantRoute = isPresented ? .fullScreen : nil
            }
        )
    }

    private func presentAssistant(homeContext: MarinaPanelHomeContext?) {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        guard isEnabled else { return }
        guard assistantRoute == nil else { return }
        activeHomeContext = homeContext
        assistantRoute = isPhone ? .fullScreen : .sheet
    }

    private func dismissAssistant() {
        assistantRoute = nil
        activeHomeContext = nil
    }

    private var shouldShowToolbarButton: Bool {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return false }
        guard isEnabled else {
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
}

extension View {
    func marinaHost(workspace: Workspace, isEnabled: Bool = true) -> some View {
        modifier(MarinaHostModifier(workspace: workspace, isEnabled: isEnabled))
    }
}
