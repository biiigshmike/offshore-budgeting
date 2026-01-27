//
//  SheetRouteEnvironment.swift
//  OffshoreBudgeting
//
//  Created by Codex on 1/27/26.
//

import SwiftUI

private struct BudgetsSheetRouteKey: EnvironmentKey {
    static let defaultValue: Binding<BudgetsSheetRoute?> = .constant(nil)
}

private struct CardsSheetRouteKey: EnvironmentKey {
    static let defaultValue: Binding<CardsSheetRoute?> = .constant(nil)
}

private struct IncomeSheetRouteKey: EnvironmentKey {
    static let defaultValue: Binding<IncomeSheetRoute?> = .constant(nil)
}

extension EnvironmentValues {
    var budgetsSheetRoute: Binding<BudgetsSheetRoute?> {
        get { self[BudgetsSheetRouteKey.self] }
        set { self[BudgetsSheetRouteKey.self] = newValue }
    }

    var cardsSheetRoute: Binding<CardsSheetRoute?> {
        get { self[CardsSheetRouteKey.self] }
        set { self[CardsSheetRouteKey.self] = newValue }
    }

    var incomeSheetRoute: Binding<IncomeSheetRoute?> {
        get { self[IncomeSheetRouteKey.self] }
        set { self[IncomeSheetRouteKey.self] = newValue }
    }
}

