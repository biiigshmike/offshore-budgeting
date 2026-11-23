import SwiftUI

struct WorkspaceProgressHandoffView: View {
    let workspace: Workspace
    let onBudgetCreated: ((UUID) -> Void)?
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            WorkspaceProgressView(workspace: workspace, showsHandoffGuidance: true, onBudgetCreated: onBudgetCreated)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: onContinue) {
                            if WorkspaceProgressService.canHideProgress(in: workspace) {
                                Text("Done")
                            } else {
                                Text("Skip")
                            }
                        }
                        .accessibilityIdentifier("workspaceProgressSkip")
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
