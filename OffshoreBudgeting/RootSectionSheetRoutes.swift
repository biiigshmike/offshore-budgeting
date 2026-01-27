//
//  RootSectionSheetRoutes.swift
//  OffshoreBudgeting
//
//  Created by Codex on 1/27/26.
//

import Foundation

enum BudgetsSheetRoute: Identifiable {
    case addBudget
    case editBudget(Budget)
    case addExpense(budget: Budget)
    case manageCards(budget: Budget)
    case managePresets(budget: Budget)
    case editExpense(VariableExpense)
    case editPlannedExpense(PlannedExpense)
    case editPreset(Preset)
    case editCategoryLimit(budget: Budget, category: Category, plannedContribution: Double, variableContribution: Double)

    var id: String {
        switch self {
        case .addBudget:
            return "add-budget"
        case .editBudget(let budget):
            return "edit-budget-\(budget.id.uuidString)"
        case .addExpense(let budget):
            return "add-expense-\(budget.id.uuidString)"
        case .manageCards(let budget):
            return "manage-cards-\(budget.id.uuidString)"
        case .managePresets(let budget):
            return "manage-presets-\(budget.id.uuidString)"
        case .editExpense(let expense):
            return "edit-expense-\(expense.id.uuidString)"
        case .editPlannedExpense(let expense):
            return "edit-planned-expense-\(expense.id.uuidString)"
        case .editPreset(let preset):
            return "edit-preset-\(preset.id.uuidString)"
        case .editCategoryLimit(let budget, let category, _, _):
            return "edit-category-limit-\(budget.id.uuidString)-\(category.id.uuidString)"
        }
    }
}

enum CardsSheetRoute: Identifiable {
    case addCard
    case editCard(Card)
    case addExpense(defaultCard: Card)
    case importExpenses(card: Card)
    case editExpense(VariableExpense)
    case editPlannedExpense(PlannedExpense)
    case editPreset(Preset)

    var id: String {
        switch self {
        case .addCard:
            return "add-card"
        case .editCard(let card):
            return "edit-card-\(card.id.uuidString)"
        case .addExpense(let card):
            return "add-expense-\(card.id.uuidString)"
        case .importExpenses(let card):
            return "import-expenses-\(card.id.uuidString)"
        case .editExpense(let expense):
            return "edit-expense-\(expense.id.uuidString)"
        case .editPlannedExpense(let expense):
            return "edit-planned-expense-\(expense.id.uuidString)"
        case .editPreset(let preset):
            return "edit-preset-\(preset.id.uuidString)"
        }
    }
}

enum IncomeSheetRoute: Identifiable {
    case add(initialDate: Date)
    case edit(Income)

    var id: String {
        switch self {
        case .add(let initialDate):
            return "add-\(initialDate.timeIntervalSince1970)"
        case .edit(let income):
            return "edit-\(income.id.uuidString)"
        }
    }
}
