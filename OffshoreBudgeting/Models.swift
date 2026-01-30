//  Models.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import Foundation
import SwiftData

// MARK: - Shared helpers

// MARK: - BudgetingPeriod

enum BudgetingPeriod: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .yearly: return "Yearly"
        }
    }

    var accessibilityLabel: String {
        displayTitle
    }

    func defaultRange(containing date: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let day = calendar.startOfDay(for: date)

        switch self {
        case .daily:
            return (start: day, end: day)

        case .weekly:
            let start = startOfWeekSunday(containing: day, calendar: calendar)
            let end = calendar.date(byAdding: DateComponents(day: 6), to: start) ?? day
            return (start: start, end: end)

        case .monthly:
            let start = startOfMonth(containing: day, calendar: calendar)
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? day
            return (start: start, end: end)

        case .quarterly:
            let start = startOfQuarter(containing: day, calendar: calendar)
            let end = calendar.date(byAdding: DateComponents(month: 3, day: -1), to: start) ?? day
            return (start: start, end: end)

        case .yearly:
            let start = startOfYear(containing: day, calendar: calendar)
            let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? day
            return (start: start, end: end)
        }
    }

    // MARK: - Period boundaries

    private func startOfWeekSunday(containing date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 1 // Sunday

        if let interval = cal.dateInterval(of: .weekOfYear, for: date) {
            return cal.startOfDay(for: interval.start)
        }

        // Fallback: if dateInterval fails, compute the last Sunday.
        let weekday = cal.component(.weekday, from: date) // Sunday = 1
        let daysToSubtract = (weekday - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -daysToSubtract, to: date) ?? date
        return cal.startOfDay(for: start)
    }

    private func startOfMonth(containing date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    private func startOfQuarter(containing date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? calendar.component(.year, from: date)
        let month = comps.month ?? calendar.component(.month, from: date)

        let quarterStartMonth: Int
        switch month {
        case 1...3: quarterStartMonth = 1
        case 4...6: quarterStartMonth = 4
        case 7...9: quarterStartMonth = 7
        default: quarterStartMonth = 10
        }

        return calendar.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1)) ?? calendar.startOfDay(for: date)
    }

    private func startOfYear(containing date: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: date)
        return calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? calendar.startOfDay(for: date)
    }
}

// MARK: - Budget name suggestion

enum BudgetNameSuggestion {
    static func suggestedName(start: Date, end: Date, calendar: Calendar = .current) -> String {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)

        if startDay == endDay {
            return formatSingleDay(startDay)
        }

        if isFullYear(start: startDay, end: endDay, calendar: calendar) {
            return yearString(for: startDay, calendar: calendar)
        }

        if let quarter = quarterStringIfFullQuarter(start: startDay, end: endDay, calendar: calendar) {
            return quarter
        }

        if let month = monthStringIfFullMonth(start: startDay, end: endDay, calendar: calendar) {
            return month
        }

        if isFullWeekSunday(start: startDay, end: endDay, calendar: calendar) {
            return formatRange(start: startDay, end: endDay, includeYear: false, calendar: calendar)
        }

        let includeYear = calendar.component(.year, from: startDay) != calendar.component(.year, from: endDay)
        return formatRange(start: startDay, end: endDay, includeYear: includeYear, calendar: calendar)
    }

    // MARK: - Period detection

    private static func isFullWeekSunday(start: Date, end: Date, calendar: Calendar) -> Bool {
        var cal = calendar
        cal.firstWeekday = 1 // Sunday

        guard let interval = cal.dateInterval(of: .weekOfYear, for: start) else { return false }
        let weekStart = cal.startOfDay(for: interval.start)
        let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        return start == weekStart && end == cal.startOfDay(for: weekEnd)
    }

    private static func isFullYear(start: Date, end: Date, calendar: Calendar) -> Bool {
        guard let interval = calendar.dateInterval(of: .year, for: start) else { return false }
        let yearStart = calendar.startOfDay(for: interval.start)
        let yearEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? yearStart
        return start == yearStart && end == calendar.startOfDay(for: yearEnd)
    }

    private static func quarterStringIfFullQuarter(start: Date, end: Date, calendar: Calendar) -> String? {
        guard let interval = calendar.dateInterval(of: .quarter, for: start) else { return nil }
        let quarterStart = calendar.startOfDay(for: interval.start)
        let quarterEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? quarterStart

        guard start == quarterStart && end == calendar.startOfDay(for: quarterEnd) else { return nil }

        let year = calendar.component(.year, from: start)
        let month = calendar.component(.month, from: start)
        let quarter: Int
        switch month {
        case 1...3: quarter = 1
        case 4...6: quarter = 2
        case 7...9: quarter = 3
        default: quarter = 4
        }
        return "Q\(quarter) \(year)"
    }

    private static func monthStringIfFullMonth(start: Date, end: Date, calendar: Calendar) -> String? {
        guard let interval = calendar.dateInterval(of: .month, for: start) else { return nil }
        let monthStart = calendar.startOfDay(for: interval.start)
        let monthEnd = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? monthStart

        guard start == monthStart && end == calendar.startOfDay(for: monthEnd) else { return nil }
        return formatMonthYear(start)
    }

    // MARK: - Formatting

    private static func yearString(for date: Date, calendar: Calendar) -> String {
        "\(calendar.component(.year, from: date))"
    }

    private static func formatMonthYear(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: date)
    }

    private static func formatSingleDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private static func formatRange(start: Date, end: Date, includeYear: Bool, calendar: Calendar) -> String {
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: end)
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)

        let startFormatter = DateFormatter()
        let endFormatter = DateFormatter()

        if sameMonth && sameYear {
            startFormatter.dateFormat = includeYear ? "MMM d, yyyy" : "MMM d"
            endFormatter.dateFormat = includeYear ? "d, yyyy" : "d"
        } else if sameYear {
            startFormatter.dateFormat = includeYear ? "MMM d, yyyy" : "MMM d"
            endFormatter.dateFormat = includeYear ? "MMM d, yyyy" : "MMM d"
        } else {
            startFormatter.dateFormat = "MMM d, yyyy"
            endFormatter.dateFormat = "MMM d, yyyy"
        }

        return "\(startFormatter.string(from: start)) – \(endFormatter.string(from: end))"
    }
}

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
    @Relationship(deleteRule: .cascade)
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

    // ✅ Keep this as a relationship, but do NOT specify inverse here.
    // The inverse is defined on ImportMerchantRule.preferredCategory.
    @Relationship
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

// MARK: - Preset

@Model
final class Preset {

    var id: UUID = UUID()
    var title: String = ""
    var plannedAmount: Double = 0

    // MARK: - Archiving
    // When true, this preset is hidden from normal selection/management flows.
    // Archiving never deletes any Planned Expenses that were already created from this preset.
    var isArchived: Bool = false
    var archivedAt: Date? = nil

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
        defaultCategory: Category? = nil,
        isArchived: Bool = false,
        archivedAt: Date? = nil
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

        self.isArchived = isArchived
        self.archivedAt = archivedAt
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

    var merchantKey: String = ""
    var preferredName: String? = nil

    @Relationship(inverse: \Workspace.importMerchantRules)
    var workspace: Workspace? = nil

    // ✅ Define the inverse on the to-one side only.
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
