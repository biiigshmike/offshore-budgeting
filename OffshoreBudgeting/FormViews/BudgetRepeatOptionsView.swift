import SwiftUI

struct BudgetRepeatOptionsView: View {
    @Binding var periodRaw: String
    @Binding var interval: Int
    @Binding var count: Int
    var allowsNone = true
    var followingBudgets = false

    var body: some View {
        Section {
            Picker("Repeat", selection: $periodRaw) {
                if allowsNone { Text("None").tag("") }
                ForEach(BudgetingPeriod.allCases) { period in
                    Text(period.displayTitle).tag(period.rawValue)
                }
            }
            .accessibilityIdentifier("budget.repeat")
            if !periodRaw.isEmpty {
                Stepper("Every: \(interval)", value: $interval, in: 1...52)
                    .accessibilityIdentifier("budget.repeatInterval")
                Stepper("Number of budgets: \(count)", value: $count, in: 1...52)
                    .accessibilityIdentifier("budget.repeatCount")
            }
        } header: {
            Text("Repeat")
        } footer: {
            if !periodRaw.isEmpty {
                Text(followingBudgets
                     ? "Counts new budgets only. Each budget is independent; editing one will not change the others."
                     : "Includes the first budget. Each budget is independent; editing one will not change the others.")
            }
        }
    }
}
