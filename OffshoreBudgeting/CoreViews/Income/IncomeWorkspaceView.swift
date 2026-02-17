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
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedSegment) {
                ForEach(Segment.allCases) { segment in
                    Text(segment.rawValue).tag(segment)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if selectedSegment == .income {
                IncomeView(workspace: workspace)
            } else {
                SavingsAccountView(workspace: workspace)
            }
        }
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.inline)
    }
}
