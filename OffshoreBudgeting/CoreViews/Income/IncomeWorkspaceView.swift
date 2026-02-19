import SwiftUI

struct IncomeWorkspaceView: View {

    let workspace: Workspace

    var body: some View {
        IncomeView(workspace: workspace)
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
