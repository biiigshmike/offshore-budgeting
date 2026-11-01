import SwiftUI

struct WorkspaceProgressHandoffView: View {
    let workspace: Workspace
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            WorkspaceProgressView(workspace: workspace, showsHandoffGuidance: true)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip", action: onContinue)
                            .accessibilityIdentifier("workspaceProgressSkip")
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
