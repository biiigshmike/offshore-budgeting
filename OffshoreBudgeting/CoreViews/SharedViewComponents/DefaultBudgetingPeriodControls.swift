import SwiftUI

struct DefaultBudgetingPeriodControls: View {
    @Binding var rawValue: String

    static var footnote: Text {
        Text("Sets the default date range for Home, account views, and widgets, and the starting dates for new budgets. Monthly, for example, starts with the current month. This period also determines when completed periods are recorded in Offshore Savings. You can choose different dates for each budget.")
    }

    private var selection: Binding<BudgetingPeriod> {
        Binding {
            DefaultBudgetingPeriod(rawValue: rawValue).period
        } set: { period in
            guard period != DefaultBudgetingPeriod(rawValue: rawValue).period else { return }
            rawValue = period.rawValue
        }
    }

    private var weeklyInterval: Binding<Int> {
        Binding {
            DefaultBudgetingPeriod(rawValue: rawValue).weeklyInterval
        } set: { interval in
            rawValue = DefaultBudgetingPeriod(.weekly, weeklyInterval: interval).rawValue
        }
    }

    var body: some View {
        Picker("Default Budgeting Period", selection: selection) {
            ForEach(BudgetingPeriod.allCases) { period in
                Text(period.displayTitle).tag(period)
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("defaultBudgetingPeriod")

        if selection.wrappedValue == .weekly {
            let interval = weeklyInterval.wrappedValue
            Stepper(value: weeklyInterval, in: DefaultBudgetingPeriod.weeklyIntervalBounds) {
                if interval == 1 {
                    Text("Every 1 week")
                } else {
                    Text("Every \(interval.formatted()) weeks")
                }
            }
            .accessibilityIdentifier("defaultBudgetingPeriod.weeklyInterval")
        }
    }
}
