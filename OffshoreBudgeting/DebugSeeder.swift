//
//  DebugSeeder.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/31/26.
//

import Foundation
import SwiftData

#if DEBUG
enum DebugSeeder {

    // MARK: - Run control

    private static var didRunThisLaunch: Bool = false

    static func runIfNeeded(container: ModelContainer, forceReset: Bool) {
        guard !didRunThisLaunch else { return }
        didRunThisLaunch = true

        let context = ModelContext(container)

        if forceReset {
            wipeAllData(context: context)
        } else {
            if hasAnyWorkspace(context: context) { return }
        }

        seedSampleData(context: context)

        do {
            try context.save()
        } catch {
            assertionFailure("DebugSeeder failed to save seed data: \(error)")
        }
    }

    // MARK: - Checks

    private static func hasAnyWorkspace(context: ModelContext) -> Bool {
        do {
            let existing = try context.fetch(FetchDescriptor<Workspace>())
            return !existing.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Wipe

    private static func wipeAllData(context: ModelContext) {
        deleteAll(Income.self, context: context)
        deleteAll(IncomeSeries.self, context: context)

        deleteAll(VariableExpense.self, context: context)
        deleteAll(PlannedExpense.self, context: context)

        deleteAll(BudgetCategoryLimit.self, context: context)
        deleteAll(BudgetPresetLink.self, context: context)
        deleteAll(BudgetCardLink.self, context: context)

        deleteAll(Preset.self, context: context)
        deleteAll(Category.self, context: context)
        deleteAll(Card.self, context: context)
        deleteAll(Budget.self, context: context)

        deleteAll(ImportMerchantRule.self, context: context)
        deleteAll(Workspace.self, context: context)
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) {
        do {
            let items = try context.fetch(FetchDescriptor<T>())
            for item in items {
                context.delete(item)
            }
        } catch {
            // Swallow in DEBUG
        }
    }

    // MARK: - Seed Data

    private static func seedSampleData(context: ModelContext) {
        let cal = Calendar.current
        let now = Date()

        // Workspace
        let workspace = Workspace(name: "Screenshots", hexColor: "#3B82F6")
        context.insert(workspace)

        // Categories
        let catHousing = Category(name: "Housing", hexColor: "#6366F1", workspace: workspace)
        let catUtilities = Category(name: "Utilities", hexColor: "#14B8A6", workspace: workspace)
        let catGroceries = Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let catDining = Category(name: "Dining", hexColor: "#F97316", workspace: workspace)
        let catServices = Category(name: "Services", hexColor: "#A855F7", workspace: workspace)
        let catTransport = Category(name: "Transport", hexColor: "#0EA5E9", workspace: workspace)
        let catEntertainment = Category(name: "Entertainment", hexColor: "#E11D48", workspace: workspace)
        let catShopping = Category(name: "Shopping", hexColor: "#F59E0B", workspace: workspace)
        let catHealth = Category(name: "Health", hexColor: "#10B981", workspace: workspace)

        let categories: [Category] = [
            catHousing, catUtilities, catGroceries, catDining, catServices,
            catTransport, catEntertainment, catShopping, catHealth
        ]
        categories.forEach { context.insert($0) }

        // Cards
        let cardChecking = Card(name: "Checking", theme: "sunset", effect: "plastic", workspace: workspace)
        let cardVisa = Card(name: "Apple Card", theme: "lavender", effect: "glass", workspace: workspace)
        let cardAmex = Card(name: "AmEx", theme: "nebula", effect: "holographic", workspace: workspace)
        [cardChecking, cardVisa, cardAmex].forEach { context.insert($0) }

        // Presets
        let presetRent = Preset(title: "Rent", plannedAmount: 1500, workspace: workspace)
        let presetInternet = Preset(title: "Internet", plannedAmount: 80, workspace: workspace)
        let presetGym = Preset(title: "Gym", plannedAmount: 45, workspace: workspace)
        let presetInsurance = Preset(title: "Insurance", plannedAmount: 120, workspace: workspace)
        let presetStreaming = Preset(title: "Streaming", plannedAmount: 25, workspace: workspace)

        let presets: [Preset] = [presetRent, presetInternet, presetGym, presetInsurance, presetStreaming]
        presets.forEach { context.insert($0) }

        // Budgets
        let currentMonthStart = startOfMonth(containing: now, calendar: cal)
        let currentMonthEnd = endOfMonth(containing: now, calendar: cal)

        let currentBudget = Budget(
            name: BudgetNameSuggestion.suggestedName(start: currentMonthStart, end: currentMonthEnd, calendar: cal),
            startDate: currentMonthStart,
            endDate: currentMonthEnd,
            workspace: workspace
        )
        context.insert(currentBudget)

        let pastMonth1Date = cal.date(byAdding: .month, value: -1, to: now) ?? now
        let pastMonth2Date = cal.date(byAdding: .month, value: -2, to: now) ?? now

        let pastBudget1 = makeMonthlyBudget(containing: pastMonth1Date, workspace: workspace, calendar: cal)
        let pastBudget2 = makeMonthlyBudget(containing: pastMonth2Date, workspace: workspace, calendar: cal)

        context.insert(pastBudget1)
        context.insert(pastBudget2)

        let prevYearDate = cal.date(byAdding: .year, value: -1, to: now) ?? now
        let prevYearStart = startOfYear(containing: prevYearDate, calendar: cal)
        let prevYearEnd = endOfYear(containing: prevYearDate, calendar: cal)

        let yearlyBudget = Budget(
            name: BudgetNameSuggestion.suggestedName(start: prevYearStart, end: prevYearEnd, calendar: cal),
            startDate: prevYearStart,
            endDate: prevYearEnd,
            workspace: workspace
        )
        context.insert(yearlyBudget)

        let nextMonthDate = cal.date(byAdding: .month, value: 1, to: now) ?? now
        let futureMonthlyBudget = makeMonthlyBudget(containing: nextMonthDate, workspace: workspace, calendar: cal)
        context.insert(futureMonthlyBudget)

        let nextQuarterStart = startOfNextQuarter(after: now, calendar: cal)
        let nextQuarterEnd = cal.date(byAdding: DateComponents(month: 3, day: -1), to: nextQuarterStart) ?? nextQuarterStart

        let futureQuarterlyBudget = Budget(
            name: BudgetNameSuggestion.suggestedName(start: nextQuarterStart, end: nextQuarterEnd, calendar: cal),
            startDate: nextQuarterStart,
            endDate: nextQuarterEnd,
            workspace: workspace
        )
        context.insert(futureQuarterlyBudget)

        let allBudgets: [Budget] = [
            currentBudget, pastBudget1, pastBudget2, yearlyBudget, futureMonthlyBudget, futureQuarterlyBudget
        ]

        // Link cards to all budgets
        for budget in allBudgets {
            context.insert(BudgetCardLink(budget: budget, card: cardChecking))
            context.insert(BudgetCardLink(budget: budget, card: cardVisa))
            context.insert(BudgetCardLink(budget: budget, card: cardAmex))
        }

        // Assign presets to monthly + quarterly (skip yearly)
        let presetBudgets: [Budget] = [currentBudget, pastBudget1, pastBudget2, futureMonthlyBudget, futureQuarterlyBudget]
        for budget in presetBudgets {
            context.insert(BudgetPresetLink(budget: budget, preset: presetRent))
            context.insert(BudgetPresetLink(budget: budget, preset: presetInternet))
            context.insert(BudgetPresetLink(budget: budget, preset: presetGym))
            context.insert(BudgetPresetLink(budget: budget, preset: presetInsurance))
            context.insert(BudgetPresetLink(budget: budget, preset: presetStreaming))
        }

        // Category limits (Double literals so Swift stays happy)
        applyCategoryLimits(
            context: context,
            budget: currentBudget,
            limits: [
                (catGroceries, 500.0),
                (catDining, 250.0),
                (catServices, 220.0),
                (catTransport, 180.0),
                (catEntertainment, 120.0),
                (catShopping, 200.0),
                (catHealth, 150.0),
                (catUtilities, 180.0)
            ]
        )

        applyCategoryLimits(
            context: context,
            budget: futureMonthlyBudget,
            limits: [
                (catGroceries, 520.0),
                (catDining, 260.0),
                (catServices, 220.0),
                (catTransport, 180.0),
                (catEntertainment, 120.0),
                (catShopping, 200.0),
                (catHealth, 150.0),
                (catUtilities, 180.0)
            ]
        )

        // Planned expenses per budget
        seedMonthlyPlannedExpenses(
            context: context,
            budget: pastBudget2,
            monthStart: pastBudget2.startDate,
            workspace: workspace,
            cardChecking: cardChecking,
            cardVisa: cardVisa,
            presets: (presetRent, presetInternet, presetGym, presetInsurance, presetStreaming),
            categories: (catHousing, catUtilities, catHealth, catEntertainment),
            actualsMatchPlanned: true
        )

        seedMonthlyPlannedExpenses(
            context: context,
            budget: pastBudget1,
            monthStart: pastBudget1.startDate,
            workspace: workspace,
            cardChecking: cardChecking,
            cardVisa: cardVisa,
            presets: (presetRent, presetInternet, presetGym, presetInsurance, presetStreaming),
            categories: (catHousing, catUtilities, catHealth, catEntertainment),
            actualsMatchPlanned: true
        )

        // Current month: a couple planned items not paid yet
        seedMonthlyPlannedExpenses(
            context: context,
            budget: currentBudget,
            monthStart: currentBudget.startDate,
            workspace: workspace,
            cardChecking: cardChecking,
            cardVisa: cardVisa,
            presets: (presetRent, presetInternet, presetGym, presetInsurance, presetStreaming),
            categories: (catHousing, catUtilities, catHealth, catEntertainment),
            actualsMatchPlanned: false
        )

        // Future month: planned only
        seedMonthlyPlannedExpensesFuture(
            context: context,
            budget: futureMonthlyBudget,
            monthStart: futureMonthlyBudget.startDate,
            workspace: workspace,
            cardChecking: cardChecking,
            cardVisa: cardVisa,
            presets: (presetRent, presetInternet, presetGym, presetInsurance, presetStreaming),
            categories: (catHousing, catUtilities, catHealth, catEntertainment)
        )

        // Quarterly: planned only for each month
        seedQuarterlyPlannedExpensesFuture(
            context: context,
            budget: futureQuarterlyBudget,
            quarterStart: futureQuarterlyBudget.startDate,
            workspace: workspace,
            cardChecking: cardChecking,
            cardVisa: cardVisa,
            presets: (presetRent, presetInternet, presetGym, presetInsurance, presetStreaming),
            categories: (catHousing, catUtilities, catHealth, catEntertainment),
            calendar: cal
        )

        // Variable expenses across ranges
        let variableRanges: [(start: Date, end: Date)] = [
            (pastBudget2.startDate, pastBudget2.endDate),
            (pastBudget1.startDate, pastBudget1.endDate),
            (currentBudget.startDate, currentBudget.endDate),
            (futureMonthlyBudget.startDate, futureMonthlyBudget.endDate),
            (futureQuarterlyBudget.startDate, futureQuarterlyBudget.endDate)
        ]

        for range in variableRanges {
            seedVariableExpenses(
                context: context,
                workspace: workspace,
                rangeStart: range.start,
                rangeEnd: range.end,
                cardChecking: cardChecking,
                cardVisa: cardVisa,
                cardAmex: cardAmex,
                categories: (catGroceries, catDining, catServices, catTransport, catEntertainment, catShopping, catHealth, catUtilities),
                calendar: cal
            )
        }

        // Yearly budget: enough to make charts interesting, not thousands of rows
        seedYearlyIncomeAndSpending(
            context: context,
            workspace: workspace,
            yearStart: yearlyBudget.startDate,
            yearEnd: yearlyBudget.endDate,
            cardChecking: cardChecking,
            cardVisa: cardVisa,
            categories: (catGroceries, catDining, catServices, catTransport, catEntertainment, catShopping, catHealth, catUtilities),
            calendar: cal
        )

        // Income for visible range (more realistic amounts and a little variability)
        seedIncomeForRange(
            context: context,
            workspace: workspace,
            rangeStart: pastBudget2.startDate,
            rangeEnd: futureQuarterlyBudget.endDate,
            cardChecking: cardChecking,
            calendar: cal
        )
    }

    // MARK: - Budgets helpers

    private static func makeMonthlyBudget(containing date: Date, workspace: Workspace, calendar: Calendar) -> Budget {
        let start = startOfMonth(containing: date, calendar: calendar)
        let end = endOfMonth(containing: date, calendar: calendar)
        return Budget(
            name: BudgetNameSuggestion.suggestedName(start: start, end: end, calendar: calendar),
            startDate: start,
            endDate: end,
            workspace: workspace
        )
    }

    // MARK: - Date helpers

    private static func startOfMonth(containing date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private static func endOfMonth(containing date: Date, calendar: Calendar) -> Date {
        let start = startOfMonth(containing: date, calendar: calendar)
        return calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
    }

    private static func startOfYear(containing date: Date, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: date)
        return calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? date
    }

    private static func endOfYear(containing date: Date, calendar: Calendar) -> Date {
        let start = startOfYear(containing: date, calendar: calendar)
        return calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? start
    }

    private static func startOfNextQuarter(after date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? calendar.component(.year, from: date)
        let month = comps.month ?? calendar.component(.month, from: date)

        let currentQuarterStartMonth: Int
        switch month {
        case 1...3: currentQuarterStartMonth = 1
        case 4...6: currentQuarterStartMonth = 4
        case 7...9: currentQuarterStartMonth = 7
        default: currentQuarterStartMonth = 10
        }

        let nextQuarterStartMonth = currentQuarterStartMonth + 3
        if nextQuarterStartMonth <= 12 {
            return calendar.date(from: DateComponents(year: year, month: nextQuarterStartMonth, day: 1)) ?? date
        } else {
            return calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? date
        }
    }

    private static func safeDate(year: Int, month: Int, day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    // MARK: - Limits

    private static func applyCategoryLimits(
        context: ModelContext,
        budget: Budget,
        limits: [(Category, Double)]
    ) {
        for (category, max) in limits {
            context.insert(BudgetCategoryLimit(minAmount: nil, maxAmount: max, budget: budget, category: category))
        }
    }

    // MARK: - Planned expenses (monthly)

    private static func seedMonthlyPlannedExpenses(
        context: ModelContext,
        budget: Budget,
        monthStart: Date,
        workspace: Workspace,
        cardChecking: Card,
        cardVisa: Card,
        presets: (rent: Preset, internet: Preset, gym: Preset, insurance: Preset, streaming: Preset),
        categories: (housing: Category, utilities: Category, health: Category, entertainment: Category),
        actualsMatchPlanned: Bool
    ) {
        let cal = Calendar.current

        func addPlanned(title: String, planned: Double, actual: Double, day: Int, category: Category, card: Card, presetID: UUID?) {
            let date = cal.date(byAdding: .day, value: max(0, day - 1), to: monthStart) ?? monthStart
            context.insert(PlannedExpense(
                title: title,
                plannedAmount: planned,
                actualAmount: actual,
                expenseDate: date,
                workspace: workspace,
                card: card,
                category: category,
                sourcePresetID: presetID,
                sourceBudgetID: budget.id
            ))
        }

        // Core fixed bills
        addPlanned(title: "Rent", planned: 1500, actual: 1500, day: 1, category: categories.housing, card: cardChecking, presetID: presets.rent.id)
        addPlanned(title: "Internet", planned: 80, actual: 80, day: 3, category: categories.utilities, card: cardChecking, presetID: presets.internet.id)

        // A couple "non-preset" fixed-ish bills that help reduce magical savings
        let electricActual = actualsMatchPlanned ? 112 : 112
        addPlanned(title: "Electric", planned: 115, actual: Double(electricActual), day: 6, category: categories.utilities, card: cardChecking, presetID: nil)

        let waterActual = actualsMatchPlanned ? 45 : 45
        addPlanned(title: "Water", planned: 45, actual: Double(waterActual), day: 8, category: categories.utilities, card: cardChecking, presetID: nil)

        let carPaymentActual = actualsMatchPlanned ? 325 : 325
        addPlanned(title: "Car Payment", planned: 325, actual: Double(carPaymentActual), day: 10, category: categories.health, card: cardChecking, presetID: nil)

        // Gym + streaming: sometimes pending in current month
        let gymActual = actualsMatchPlanned ? 45 : 0
        addPlanned(title: "Gym", planned: 45, actual: Double(gymActual), day: 12, category: categories.health, card: cardVisa, presetID: presets.gym.id)

        let insuranceActual = actualsMatchPlanned ? 120 : 120
        addPlanned(title: "Insurance", planned: 120, actual: Double(insuranceActual), day: 15, category: categories.health, card: cardChecking, presetID: presets.insurance.id)

        let streamingActual = actualsMatchPlanned ? 25 : 0
        addPlanned(title: "Streaming", planned: 25, actual: Double(streamingActual), day: 19, category: categories.entertainment, card: cardVisa, presetID: presets.streaming.id)

        // One more realistic monthly obligation
        let loanActual = actualsMatchPlanned ? 180 : 180
        addPlanned(title: "Student Loan", planned: 180, actual: Double(loanActual), day: 22, category: categories.health, card: cardChecking, presetID: nil)
    }

    private static func seedMonthlyPlannedExpensesFuture(
        context: ModelContext,
        budget: Budget,
        monthStart: Date,
        workspace: Workspace,
        cardChecking: Card,
        cardVisa: Card,
        presets: (rent: Preset, internet: Preset, gym: Preset, insurance: Preset, streaming: Preset),
        categories: (housing: Category, utilities: Category, health: Category, entertainment: Category)
    ) {
        let cal = Calendar.current

        func addPlanned(title: String, planned: Double, day: Int, category: Category, card: Card, presetID: UUID?) {
            let date = cal.date(byAdding: .day, value: max(0, day - 1), to: monthStart) ?? monthStart
            context.insert(PlannedExpense(
                title: title,
                plannedAmount: planned,
                actualAmount: 0,
                expenseDate: date,
                workspace: workspace,
                card: card,
                category: category,
                sourcePresetID: presetID,
                sourceBudgetID: budget.id
            ))
        }

        addPlanned(title: "Rent", planned: 1500, day: 1, category: categories.housing, card: cardChecking, presetID: presets.rent.id)
        addPlanned(title: "Internet", planned: 80, day: 3, category: categories.utilities, card: cardChecking, presetID: presets.internet.id)

        addPlanned(title: "Electric", planned: 115, day: 6, category: categories.utilities, card: cardChecking, presetID: nil)
        addPlanned(title: "Water", planned: 45, day: 8, category: categories.utilities, card: cardChecking, presetID: nil)
        addPlanned(title: "Car Payment", planned: 325, day: 10, category: categories.health, card: cardChecking, presetID: nil)

        addPlanned(title: "Gym", planned: 45, day: 12, category: categories.health, card: cardVisa, presetID: presets.gym.id)
        addPlanned(title: "Insurance", planned: 120, day: 15, category: categories.health, card: cardChecking, presetID: presets.insurance.id)
        addPlanned(title: "Streaming", planned: 25, day: 19, category: categories.entertainment, card: cardVisa, presetID: presets.streaming.id)

        addPlanned(title: "Student Loan", planned: 180, day: 22, category: categories.health, card: cardChecking, presetID: nil)
    }

    private static func seedQuarterlyPlannedExpensesFuture(
        context: ModelContext,
        budget: Budget,
        quarterStart: Date,
        workspace: Workspace,
        cardChecking: Card,
        cardVisa: Card,
        presets: (rent: Preset, internet: Preset, gym: Preset, insurance: Preset, streaming: Preset),
        categories: (housing: Category, utilities: Category, health: Category, entertainment: Category),
        calendar: Calendar
    ) {
        for monthOffset in 0..<3 {
            let monthDate = calendar.date(byAdding: .month, value: monthOffset, to: quarterStart) ?? quarterStart
            let monthStart = startOfMonth(containing: monthDate, calendar: calendar)

            seedMonthlyPlannedExpensesFuture(
                context: context,
                budget: budget,
                monthStart: monthStart,
                workspace: workspace,
                cardChecking: cardChecking,
                cardVisa: cardVisa,
                presets: presets,
                categories: categories
            )
        }
    }

    // MARK: - Variable expenses

    private static func seedVariableExpenses(
        context: ModelContext,
        workspace: Workspace,
        rangeStart: Date,
        rangeEnd: Date,
        cardChecking: Card,
        cardVisa: Card,
        cardAmex: Card,
        categories: (groceries: Category, dining: Category, services: Category, transport: Category, entertainment: Category, shopping: Category, health: Category, utilities: Category),
        calendar: Calendar
    ) {
        let days = max(1, calendar.dateComponents([.day], from: rangeStart, to: rangeEnd).day ?? 28)
        let month = calendar.component(.month, from: rangeStart)

        func day(_ d: Int) -> Date {
            let clamped = min(max(1, d), days)
            return calendar.date(byAdding: .day, value: clamped - 1, to: rangeStart) ?? rangeStart
        }

        func add(_ desc: String, _ amount: Double, _ date: Date, _ card: Card, _ category: Category) {
            context.insert(VariableExpense(
                descriptionText: desc,
                amount: amount,
                transactionDate: date,
                workspace: workspace,
                card: card,
                category: category
            ))
        }

        // Baseline month spending (a bit higher than before so savings stops looking fake)
        add("Trader Joe's", 104.65, day(3), cardVisa, categories.groceries)
        add("Safeway", 72.40, day(9), cardVisa, categories.groceries)
        add("Costco", 168.90, day(16), cardAmex, categories.groceries)
        add("Grocery Run", 79.15, day(24), cardVisa, categories.groceries)

        add("Coffee", 9.10, day(5), cardVisa, categories.dining)
        add("Lunch", 19.75, day(12), cardVisa, categories.dining)
        add("Dinner", 48.60, day(21), cardAmex, categories.dining)

        add("Uber", 24.80, day(7), cardVisa, categories.transport)
        add("Gas", 58.25, day(15), cardChecking, categories.transport)
        add("Parking", 12.00, day(20), cardVisa, categories.transport)

        add("Haircut", 75.00, day(13), cardChecking, categories.services)
        add("Car Wash", 16.00, day(26), cardChecking, categories.services)

        add("Target", 62.30, day(10), cardAmex, categories.shopping)
        add("Amazon", 49.99, day(19), cardVisa, categories.shopping)

        add("Movie", 22.00, day(17), cardVisa, categories.entertainment)
        add("Pharmacy", 28.40, day(22), cardChecking, categories.health)

        add("Mobile Phone", 65.00, day(8), cardChecking, categories.utilities)

        // Month-to-month realism "hits"
        // I keep these deterministic so screenshots are consistent.
        if month % 2 == 0 {
            add("Car Repair", 480.00, day(18), cardChecking, categories.services)
        }

        if month % 3 == 0 {
            add("Medical", 220.00, day(23), cardChecking, categories.health)
        }

        if month % 5 == 0 {
            add("Weekend Trip", 350.00, day(27), cardVisa, categories.entertainment)
        }
    }

    // MARK: - Income

    private static func seedIncomeForRange(
        context: ModelContext,
        workspace: Workspace,
        rangeStart: Date,
        rangeEnd: Date,
        cardChecking: Card,
        calendar: Calendar
    ) {
        // Realistic paychecks:
        // - lower amounts than before
        // - small month-to-month variability
        // - one month missing a second paycheck (life happens)

        var cursor = startOfMonth(containing: rangeStart, calendar: calendar)
        let nowMonthStart = startOfMonth(containing: Date(), calendar: calendar)
        let missingSecondPaycheckMonthStart = calendar.date(byAdding: .month, value: -1, to: nowMonthStart) ?? nowMonthStart

        while cursor <= rangeEnd {
            let monthStart = startOfMonth(containing: cursor, calendar: calendar)
            let monthEnd = endOfMonth(containing: cursor, calendar: calendar)

            if monthEnd < rangeStart {
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor
                continue
            }
            if monthStart > rangeEnd { break }

            let month = calendar.component(.month, from: monthStart)

            // Base: ~3400–3600/month grossed across two checks
            var p1Amount: Double = 1700
            var p2Amount: Double = 1650

            // Deterministic small wobble
            if month % 2 == 0 { p1Amount -= 75 }
            if month % 3 == 0 { p2Amount -= 100 }
            if month % 5 == 0 { p2Amount += 60 } // tiny "bonus" month

            // Paycheck #1
            let p1PlannedDate = monthStart
            let p1ActualDate = monthStart

            context.insert(Income(
                source: "Paycheck",
                amount: p1Amount,
                date: p1PlannedDate,
                isPlanned: true,
                workspace: workspace,
                series: nil,
                card: cardChecking
            ))

            context.insert(Income(
                source: "Paycheck",
                amount: p1Amount,
                date: p1ActualDate,
                isPlanned: false,
                workspace: workspace,
                series: nil,
                card: cardChecking
            ))

            // Paycheck #2 (15th-ish)
            let midDay = min(15, calendar.component(.day, from: monthEnd))
            let p2PlannedDate = calendar.date(byAdding: .day, value: midDay - 1, to: monthStart) ?? monthStart
            let p2ActualDate = p2PlannedDate

            // One month: second paycheck missing (makes at least one budget clearly negative)
            let shouldSkipSecondPaycheck = (monthStart == missingSecondPaycheckMonthStart)

            if !shouldSkipSecondPaycheck {
                context.insert(Income(
                    source: "Paycheck",
                    amount: p2Amount,
                    date: p2PlannedDate,
                    isPlanned: true,
                    workspace: workspace,
                    series: nil,
                    card: cardChecking
                ))

                context.insert(Income(
                    source: "Paycheck",
                    amount: p2Amount,
                    date: p2ActualDate,
                    isPlanned: false,
                    workspace: workspace,
                    series: nil,
                    card: cardChecking
                ))
            }

            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor
        }
    }

    private static func seedYearlyIncomeAndSpending(
        context: ModelContext,
        workspace: Workspace,
        yearStart: Date,
        yearEnd: Date,
        cardChecking: Card,
        cardVisa: Card,
        categories: (groceries: Category, dining: Category, services: Category, transport: Category, entertainment: Category, shopping: Category, health: Category, utilities: Category),
        calendar: Calendar
    ) {
        seedIncomeForRange(
            context: context,
            workspace: workspace,
            rangeStart: yearStart,
            rangeEnd: yearEnd,
            cardChecking: cardChecking,
            calendar: calendar
        )

        // Representative months per quarter
        let monthsToSeed = [1, 4, 7, 10]
        let year = calendar.component(.year, from: yearStart)

        for month in monthsToSeed {
            let monthDate = safeDate(year: year, month: month, day: 1, calendar: calendar)
            let mStart = startOfMonth(containing: monthDate, calendar: calendar)
            let mEnd = endOfMonth(containing: monthDate, calendar: calendar)

            seedVariableExpenses(
                context: context,
                workspace: workspace,
                rangeStart: mStart,
                rangeEnd: mEnd,
                cardChecking: cardChecking,
                cardVisa: cardVisa,
                cardAmex: cardVisa,
                categories: categories,
                calendar: calendar
            )
        }
    }
}
#endif
