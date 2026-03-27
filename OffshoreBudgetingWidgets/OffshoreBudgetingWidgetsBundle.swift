//
//  OffshoreBudgetingWidgetsBundle.swift
//  OffshoreBudgetingWidgets
//
//  Created by Michael Brown on 1/27/26.
//

import WidgetKit
import SwiftUI

@main
struct OffshoreBudgetingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        IncomeWidget()
        CardWidget()
        NextPlannedExpenseWidget()
        SpendTrendsWidget()
        SafeSpendTodayWidget()
        ForecastSavingsWidget()
        if #available(iOS 18.0, *) {
            AddExpenseControlWidget()
            AddIncomeControlWidget()
            ReviewTodayControlWidget()
            ExcursionModeControlWidget()
        }
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        ShoppingModeLiveActivity()
        #endif
    }
}
