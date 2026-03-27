import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct AddExpenseControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mb.offshore.control.add-expense") {
            ControlWidgetButton(action: WidgetOpenAddExpenseIntent()) {
                Label("Add Expense", systemImage: "creditcard")
            }
        }
        .displayName("Add Expense")
        .description("Open Offshore directly to quick add expense.")
    }
}

@available(iOS 18.0, *)
struct AddIncomeControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mb.offshore.control.add-income") {
            ControlWidgetButton(action: WidgetOpenAddIncomeIntent()) {
                Label("Add Income", systemImage: "banknote.fill")
            }
        }
        .displayName("Add Income")
        .description("Open Offshore directly to quick add income.")
    }
}

@available(iOS 18.0, *)
struct ReviewTodayControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mb.offshore.control.review-today") {
            ControlWidgetButton(action: WidgetReviewTodayIntent()) {
                Label("Review Today", systemImage: "list.bullet.clipboard")
            }
        }
        .displayName("Review Today")
        .description("Open Offshore to review today's spending.")
    }
}

@available(iOS 18.0, *)
struct ExcursionModeControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.mb.offshore.control.excursion-mode") {
            ControlWidgetButton(action: WidgetStartExcursionModeIntent()) {
                Label("Excursion Mode", systemImage: "sailboat.fill")
            }
        }
        .displayName("Excursion Mode")
        .description("Start a 2-hour Excursion Mode session.")
    }
}
