//
//  Models.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import Foundation
import SwiftData

// MARK: - Shared helpers

enum TransactionType: String, CaseIterable, Identifiable {
    case expense = "Expense"
    case income = "Income"
    var id: String { rawValue }
}

enum ExpenseScope: String, Identifiable {
    case planned
    case variable
    case unified
    var id: String { rawValue }
}

enum RecurrenceFrequency: String, CaseIterable, Identifiable {
    case none
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }
}

// MARK: - Workspace

@Model
final class Workspace {

    var id: UUID = UUID()
    var name: String = ""
    var hexColor: String = "#3B82F6"

    @Relationship(deleteRule: .cascade)
    var budgets: [Budget]? = nil

    @Relationship(deleteRule: .cascade)
    var cards: [Card]? = nil

    @Relationship(deleteRule: .cascade)
    var categories: [Category]? = nil

    @Relationship(deleteRule: .cascade)
    var presets: [Preset]? = nil

    @Relationship(deleteRule: .cascade)
    var incomes: [Income]? = nil

    @Relationship(deleteRule: .cascade)
    var incomeSeries: [IncomeSeries]? = nil

    @Relationship(deleteRule: .cascade)
    var plannedExpenses: [PlannedExpense]? = nil

    @Relationship(deleteRule: .cascade)
    var variableExpenses: [VariableExpense]? = nil
    
    @Relationship(deleteRule: .cascade)
    var importMerchantRules: [ImportMerchantRule]? = nil

    init(id: UUID = UUID(), name: String, hexColor: String) {
        self.id = id
        self.name = name
        self.hexColor = hexColor
    }
}

// MARK: - Budget

@Model
final class Budget {

    var id: UUID = UUID()
    var name: String = ""

    var startDate: Date = Date.now
    var endDate: Date = Date.now

    @Relationship(inverse: \Workspace.budgets)
    var workspace: Workspace? = nil

    @Relationship(deleteRule: .cascade)
    var cardLinks: [BudgetCardLink]? = nil

    @Relationship(deleteRule: .cascade)
    var presetLinks: [BudgetPresetLink]? = nil

    @Relationship(deleteRule: .cascade)
    var categoryLimits: [BudgetCategoryLimit]? = nil

    init(
        id: UUID = UUID(),
        name: String,
        startDate: Date,
        endDate: Date,
        workspace: Workspace? = nil
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.workspace = workspace
    }
}

// MARK: - Card

@Model
final class Card {

    var id: UUID = UUID()
    var name: String = ""

    var theme: String = "default"
    var effect: String = "none"

    @Relationship(inverse: \Workspace.cards)
    var workspace: Workspace? = nil

    @Relationship(deleteRule: .cascade)
    var budgetLinks: [BudgetCardLink]? = nil

    @Relationship(deleteRule: .cascade)
    var plannedExpenses: [PlannedExpense]? = nil

    @Relationship(deleteRule: .cascade)
    var variableExpenses: [VariableExpense]? = nil

    // IMPORTANT:
    // Do NOT annotate these with @Relationship(inverse:) on this toolchain.
    // The inverse is declared on Preset.defaultCard / Income.card instead.
    var defaultForPresets: [Preset]? = nil
    var incomes: [Income]? = nil

    init(
        id: UUID = UUID(),
        name: String,
        theme: String = "default",
        effect: String = "none",
        workspace: Workspace? = nil
    ) {
        self.id = id
        self.name = name
        self.theme = theme
        self.effect = effect
        self.workspace = workspace
    }
}

// MARK: - BudgetCardLink (Join model)

@Model
final class BudgetCardLink {

    var id: UUID = UUID()

    @Relationship(inverse: \Budget.cardLinks)
    var budget: Budget? = nil

    @Relationship(inverse: \Card.budgetLinks)
    var card: Card? = nil

    init(id: UUID = UUID(), budget: Budget? = nil, card: Card? = nil) {
        self.id = id
        self.budget = budget
        self.card = card
    }
}

// MARK: - Category

@Model
final class Category {

    var id: UUID = UUID()
    var name: String = ""
    var hexColor: String = "#3B82F6"
    
    var importMerchantRules: [ImportMerchantRule]? = nil

    @Relationship(inverse: \Workspace.categories)
    var workspace: Workspace? = nil

    @Relationship var budgetCategoryLimits: [BudgetCategoryLimit]? = nil
    @Relationship var plannedExpenses: [PlannedExpense]? = nil
    @Relationship var variableExpenses: [VariableExpense]? = nil

    // IMPORTANT:
    // Do NOT annotate with @Relationship(inverse:) here.
    // The inverse is declared on Preset.defaultCategory instead.
    var defaultForPresets: [Preset]? = nil

    init(id: UUID = UUID(), name: String, hexColor: String, workspace: Workspace? = nil) {
        self.id = id
        self.name = name
        self.hexColor = hexColor
        self.workspace = workspace
    }
}

// MARK: - Preset

@Model
final class Preset {

    var id: UUID = UUID()
    var title: String = ""
    var plannedAmount: Double = 0

    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    var interval: Int = 1
    var weeklyWeekday: Int = 6
    var monthlyDayOfMonth: Int = 15
    var monthlyIsLastDay: Bool = false
    var yearlyMonth: Int = 1
    var yearlyDayOfMonth: Int = 15

    @Relationship(inverse: \Workspace.presets)
    var workspace: Workspace? = nil

    // Inverse is defined here (to-one side). Card.defaultForPresets stays un-annotated.
    @Relationship(inverse: \Card.defaultForPresets)
    var defaultCard: Card? = nil

    // Inverse is defined here (to-one side). Category.defaultForPresets stays un-annotated.
    @Relationship(inverse: \Category.defaultForPresets)
    var defaultCategory: Category? = nil

    @Relationship var budgetPresetLinks: [BudgetPresetLink]? = nil

    init(
        id: UUID = UUID(),
        title: String,
        plannedAmount: Double,
        frequencyRaw: String = RecurrenceFrequency.monthly.rawValue,
        interval: Int = 1,
        weeklyWeekday: Int = 6,
        monthlyDayOfMonth: Int = 15,
        monthlyIsLastDay: Bool = false,
        yearlyMonth: Int = 1,
        yearlyDayOfMonth: Int = 15,
        workspace: Workspace? = nil,
        defaultCard: Card? = nil,
        defaultCategory: Category? = nil
    ) {
        self.id = id
        self.title = title
        self.plannedAmount = plannedAmount

        self.frequencyRaw = frequencyRaw
        self.interval = max(1, interval)
        self.weeklyWeekday = min(7, max(1, weeklyWeekday))

        // ✅ fixed typo: weeklyDayOfMonth -> monthlyDayOfMonth
        self.monthlyDayOfMonth = min(31, max(1, monthlyDayOfMonth))

        self.monthlyIsLastDay = monthlyIsLastDay
        self.yearlyMonth = min(12, max(1, yearlyMonth))
        self.yearlyDayOfMonth = min(31, max(1, yearlyDayOfMonth))

        self.workspace = workspace
        self.defaultCard = defaultCard
        self.defaultCategory = defaultCategory
    }
}

extension Preset {
    var frequency: RecurrenceFrequency {
        RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly
    }
}

// MARK: - BudgetPresetLink

@Model
final class BudgetPresetLink {

    var id: UUID = UUID()

    @Relationship(inverse: \Budget.presetLinks)
    var budget: Budget? = nil

    @Relationship(inverse: \Preset.budgetPresetLinks)
    var preset: Preset? = nil

    init(id: UUID = UUID(), budget: Budget? = nil, preset: Preset? = nil) {
        self.id = id
        self.budget = budget
        self.preset = preset
    }
}

// MARK: - BudgetCategoryLimit

@Model
final class BudgetCategoryLimit {

    var id: UUID = UUID()

    var minAmount: Double? = nil
    var maxAmount: Double? = nil

    @Relationship(inverse: \Budget.categoryLimits)
    var budget: Budget? = nil

    @Relationship(inverse: \Category.budgetCategoryLimits)
    var category: Category? = nil

    init(
        id: UUID = UUID(),
        minAmount: Double? = nil,
        maxAmount: Double? = nil,
        budget: Budget? = nil,
        category: Category? = nil
    ) {
        self.id = id
        self.minAmount = minAmount
        self.maxAmount = maxAmount
        self.budget = budget
        self.category = category
    }
}

// MARK: - PlannedExpense

@Model
final class PlannedExpense {

    var id: UUID = UUID()
    var title: String = ""
    var plannedAmount: Double = 0
    var actualAmount: Double = 0
    var expenseDate: Date = Date.now

    @Relationship(inverse: \Workspace.plannedExpenses)
    var workspace: Workspace? = nil

    @Relationship(inverse: \Card.plannedExpenses)
    var card: Card? = nil

    @Relationship(inverse: \Category.plannedExpenses)
    var category: Category? = nil

    var sourcePresetID: UUID? = nil
    var sourceBudgetID: UUID? = nil

    init(
        id: UUID = UUID(),
        title: String,
        plannedAmount: Double,
        actualAmount: Double = 0,
        expenseDate: Date,
        workspace: Workspace? = nil,
        card: Card? = nil,
        category: Category? = nil,
        sourcePresetID: UUID? = nil,
        sourceBudgetID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.plannedAmount = plannedAmount
        self.actualAmount = actualAmount
        self.expenseDate = expenseDate
        self.workspace = workspace
        self.card = card
        self.category = category
        self.sourcePresetID = sourcePresetID
        self.sourceBudgetID = sourceBudgetID
    }
}

// MARK: - VariableExpense

@Model
final class VariableExpense {

    var id: UUID = UUID()
    var descriptionText: String = ""
    var amount: Double = 0
    var transactionDate: Date = Date.now

    @Relationship(inverse: \Workspace.variableExpenses)
    var workspace: Workspace? = nil

    @Relationship(inverse: \Card.variableExpenses)
    var card: Card? = nil

    @Relationship(inverse: \Category.variableExpenses)
    var category: Category? = nil

    init(
        id: UUID = UUID(),
        descriptionText: String,
        amount: Double,
        transactionDate: Date,
        workspace: Workspace? = nil,
        card: Card? = nil,
        category: Category? = nil
    ) {
        self.id = id
        self.descriptionText = descriptionText
        self.amount = amount
        self.transactionDate = transactionDate
        self.workspace = workspace
        self.card = card
        self.category = category
    }
}

// MARK: - IncomeSeries

@Model
final class IncomeSeries {

    var id: UUID = UUID()

    var source: String = ""
    var amount: Double = 0
    var isPlanned: Bool = false

    var frequencyRaw: String = RecurrenceFrequency.none.rawValue
    var interval: Int = 1
    var weeklyWeekday: Int = 6
    var monthlyDayOfMonth: Int = 15
    var monthlyIsLastDay: Bool = false
    var yearlyMonth: Int = 1
    var yearlyDayOfMonth: Int = 15

    var startDate: Date = Date.now
    var endDate: Date = Date.now

    @Relationship(inverse: \Workspace.incomeSeries)
    var workspace: Workspace? = nil

    @Relationship(deleteRule: .cascade)
    var incomes: [Income]? = nil

    init(
        id: UUID = UUID(),
        source: String,
        amount: Double,
        isPlanned: Bool,
        frequencyRaw: String,
        interval: Int,
        weeklyWeekday: Int,
        monthlyDayOfMonth: Int,
        monthlyIsLastDay: Bool,
        yearlyMonth: Int,
        yearlyDayOfMonth: Int,
        startDate: Date,
        endDate: Date,
        workspace: Workspace? = nil
    ) {
        self.id = id
        self.source = source
        self.amount = amount
        self.isPlanned = isPlanned

        self.frequencyRaw = frequencyRaw
        self.interval = max(1, interval)
        self.weeklyWeekday = min(7, max(1, weeklyWeekday))
        self.monthlyDayOfMonth = min(31, max(1, monthlyDayOfMonth))
        self.monthlyIsLastDay = monthlyIsLastDay
        self.yearlyMonth = min(12, max(1, yearlyMonth))
        self.yearlyDayOfMonth = min(31, max(1, yearlyDayOfMonth))

        self.startDate = startDate
        self.endDate = endDate
        self.workspace = workspace
    }
}

extension IncomeSeries {
    var frequency: RecurrenceFrequency {
        RecurrenceFrequency(rawValue: frequencyRaw) ?? .none
    }
}

// MARK : - Merchant Rule

@Model
final class ImportMerchantRule {

    var id: UUID = UUID()

    /// Normalized merchant identifier used for Option 1 memory.
    /// Example: "STARBUCKS" or "CHEVRON" after your MerchantNormalizer.
    var merchantKey: String = ""

    /// Optional preferred display name to import as.
    /// Example: "MCDONALDS" instead of "xxxxxxxx1234 MCDONALDS 1 HIGHWAY CA".
    var preferredName: String? = nil

    /// Belongs to a workspace.
    @Relationship(inverse: \Workspace.importMerchantRules)
    var workspace: Workspace? = nil
    
    @Relationship(inverse: \Category.importMerchantRules)
    var preferredCategory: Category? = nil

    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        merchantKey: String,
        preferredName: String? = nil,
        preferredCategory: Category? = nil,
        workspace: Workspace? = nil,
        createdAt: Date = Date.now,
        updatedAt: Date = Date.now
    ) {
        self.id = id
        self.merchantKey = merchantKey
        self.preferredName = preferredName
        self.preferredCategory = preferredCategory
        self.workspace = workspace
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Income

@Model
final class Income {

    var id: UUID = UUID()
    var source: String = ""
    var amount: Double = 0
    var date: Date = Date.now
    var isPlanned: Bool = false
    var isException: Bool = false

    @Relationship(inverse: \Workspace.incomes)
    var workspace: Workspace? = nil

    @Relationship(inverse: \IncomeSeries.incomes)
    var series: IncomeSeries? = nil

    // Inverse is defined here (to-one side). Card.incomes stays un-annotated.
    @Relationship(inverse: \Card.incomes)
    var card: Card? = nil

    init(
        id: UUID = UUID(),
        source: String,
        amount: Double,
        date: Date,
        isPlanned: Bool,
        isException: Bool = false,
        workspace: Workspace? = nil,
        series: IncomeSeries? = nil,
        card: Card? = nil
    ) {
        self.id = id
        self.source = source
        self.amount = amount
        self.date = date
        self.isPlanned = isPlanned
        self.isException = isException
        self.workspace = workspace
        self.series = series
        self.card = card
    }
}
