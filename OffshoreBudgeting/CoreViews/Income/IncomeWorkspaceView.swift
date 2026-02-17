import SwiftUI

struct IncomeWorkspaceView: View {

    enum Segment: String, CaseIterable, Identifiable {
        case income = "Income"
        case savings = "Savings"

        var id: String { rawValue }
    }

    let workspace: Workspace

    @State private var selectedSegment: Segment = .income

    var body: some View {
        Group {
            if selectedSegment == .income {
                IncomeView(
                    workspace: workspace,
                    showSegmentControl: true,
                    selectedSegment: $selectedSegment
                )
            } else {
                SavingsAccountView(
                    workspace: workspace,
                    showSegmentControl: true,
                    selectedSegment: $selectedSegment
                )
            }
        }
        .navigationTitle(selectedSegment.rawValue)
        .navigationBarTitleDisplayMode(.automatic)
    }
}
