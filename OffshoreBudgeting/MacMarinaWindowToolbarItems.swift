#if targetEnvironment(macCatalyst)
import SwiftUI

/// Participates in the active SwiftUI navigation toolbar; never replaces the
/// system toolbar or sidebar toggle.
struct MacMarinaWindowToolbarItems: ToolbarContent {
    @Environment(\.macMarinaToolbarState) private var state
    @Environment(\.marinaToolbarContext) private var presentation

    var body: some ToolbarContent {
        if presentation.isInspectorPresented {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(state?.creation ?? []) { action in
                        actionButton(action)
                    }
                    Divider()
                    ForEach(state?.management ?? []) { action in
                        actionButton(action)
                    }
                } label: {
                    Label(String(localized: "marina.chat.actions", defaultValue: "Chat Actions"), systemImage: "ellipsis")
                }
                .accessibilityIdentifier("marina.chatActionsMenu")
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: presentation.closeAssistant) {
                    Label(String(localized: "assistant.close", defaultValue: "Close Assistant"), systemImage: "xmark")
                }
                .accessibilityIdentifier("marina.closeButton")
            }
        }
    }

    private func actionButton(_ action: MarinaToolbarAction) -> some View {
        Button(role: action.isDestructive ? .destructive : nil, action: action.perform) {
            Label(action.title, systemImage: action.systemImage)
        }
        .disabled(!action.isEnabled)
    }
}
#endif
