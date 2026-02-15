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
            if hasAnyWorkspace(context: context) {
                applyPinnedHomeOrderForExistingWorkspaceIfPossible(context: context)
                return
            }
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

    // MARK: - Home Pins

    private static func applyPinnedHomeOrderForExistingWorkspaceIfPossible(context: ModelContext) {
        do {
            let workspaces = try context.fetch(FetchDescriptor<Workspace>())
            guard let workspace = pickPinnedWorkspace(from: workspaces) else {
                assertionFailure("DebugSeeder could not find a workspace for pinned widget seeding.")
                return
            }

            let cards = try context.fetch(FetchDescriptor<Card>())
                .filter { $0.workspace?.id == workspace.id }

            guard
                let checkingCardID = cardID(named: "checking", in: cards),
                let appleCardID = cardID(named: "applecard", in: cards),
                let amexCardID = cardID(named: "amex", in: cards)
            else {
                assertionFailure("DebugSeeder could not resolve Checking/Apple Card/AmEx for pinned widget seeding.")
                return
            }

            applyPinnedHomeOrder(
                workspaceID: workspace.id,
                checkingCardID: checkingCardID,
                appleCardID: appleCardID,
                amexCardID: amexCardID
            )
        } catch {
            assertionFailure("DebugSeeder failed to apply pinned widget order: \(error)")
        }
    }

    private static func applyPinnedHomeOrder(
        workspaceID: UUID,
        checkingCardID: UUID,
        appleCardID: UUID,
        amexCardID: UUID
    ) {
        HomePinnedItemsStore(workspaceID: workspaceID).save([
            .widget(.income, .small),
            .widget(.categoryAvailability, .small),
            .widget(.spendTrends, .small),
            .card(checkingCardID, .small),
            .card(appleCardID, .small),
            .widget(.nextPlannedExpense, .small),
            .widget(.categorySpotlight, .small),
            .widget(.savingsOutlook, .small),
            .widget(.whatIf, .small),
            .card(amexCardID, .small)
        ])

        HomePinnedWidgetsStore(workspaceID: workspaceID).save([
            .income,
            .categoryAvailability,
            .spendTrends,
            .nextPlannedExpense,
            .categorySpotlight,
            .savingsOutlook,
            .whatIf
        ])

        HomePinnedCardsStore(workspaceID: workspaceID).save([
            checkingCardID,
            appleCardID,
            amexCardID
        ])
    }

    private static func pickPinnedWorkspace(from workspaces: [Workspace]) -> Workspace? {
        if let screenshotsWorkspace = workspaces.first(where: { $0.name.caseInsensitiveCompare("Screenshots") == .orderedSame }) {
            return screenshotsWorkspace
        }
        return workspaces.first
    }

    private static func cardID(named normalizedName: String, in cards: [Card]) -> UUID? {
        cards.first(where: { normalizedCardName($0.name) == normalizedName })?.id
    }

    private static func normalizedCardName(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "").lowercased()
    }

    // MARK: - Wipe

    private static func wipeAllData(context: ModelContext) {
        SpendingSessionStore.end()

        deleteAll(Income.self, context: context)
        deleteAll(IncomeSeries.self, context: context)

        deleteAll(ExpenseAllocation.self, context: context)
        deleteAll(AllocationSettlement.self, context: context)
        deleteAll(AllocationAccount.self, context: context)

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
        deleteAll(AssistantAliasRule.self, context: context)
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
        let cardVisa = Card(name: "Apple Card", theme: "periwinkle", effect: "glass", workspace: workspace)
        let cardAmex = Card(name: "AmEx", theme: "aster", effect: "holographic", workspace: workspace)
        [cardChecking, cardVisa, cardAmex].forEach { context.insert($0) }

        applyPinnedHomeOrder(
            workspaceID: workspace.id,
            checkingCardID: cardChecking.id,
            appleCardID: cardVisa.id,
            amexCardID: cardAmex.id
        )

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

        // Category limits (Double literals)
        applyCategoryLimits(
            context: context,
            budget: currentBudget,
            limits: [
                (catGroceries, 520.0),
                (catDining, 320.0),
                (catServices, 260.0),
                (catTransport, 220.0),
                (catEntertainment, 180.0),
                (catShopping, 260.0),
                (catHealth, 220.0),
                (catUtilities, 220.0)
            ]
        )

        applyCategoryLimits(
            context: context,
            budget: futureMonthlyBudget,
            limits: [
                (catGroceries, 540.0),
                (catDining, 330.0),
                (catServices, 260.0),
                (catTransport, 220.0),
                (catEntertainment, 180.0),
                (catShopping, 260.0),
                (catHealth, 220.0),
                (catUtilities, 220.0)
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

        // Yearly budget: enough to make charts interesting
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

        // Income for visible range (realistic planned vs actual with cents)
        seedIncomeForRange(
            context: context,
            workspace: workspace,
            rangeStart: pastBudget2.startDate,
            rangeEnd: futureQuarterlyBudget.endDate,
            cardChecking: cardChecking,
            calendar: cal
        )

        seedSharedBalances(
            context: context,
            workspace: workspace,
            cardChecking: cardChecking,
            cardVisa: cardVisa,
            categories: (
                groceries: catGroceries,
                dining: catDining,
                transport: catTransport,
                entertainment: catEntertainment
            ),
            calendar: cal
        )

        seedMarinaConversation(workspaceID: workspace.id, now: now)
        seedExcursionModeActive(now: now)
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

        addPlanned(title: "Rent", planned: 1500, actual: 1500, day: 1, category: categories.housing, card: cardChecking, presetID: presets.rent.id)
        addPlanned(title: "Internet", planned: 80, actual: 80, day: 3, category: categories.utilities, card: cardChecking, presetID: presets.internet.id)

        let electricActual = actualsMatchPlanned ? 128 : 128
        addPlanned(title: "Electric", planned: 130, actual: Double(electricActual), day: 6, category: categories.utilities, card: cardChecking, presetID: nil)

        let waterActual = actualsMatchPlanned ? 55 : 55
        addPlanned(title: "Water", planned: 55, actual: Double(waterActual), day: 8, category: categories.utilities, card: cardChecking, presetID: nil)

        let carPaymentActual = actualsMatchPlanned ? 345 : 345
        addPlanned(title: "Car Payment", planned: 345, actual: Double(carPaymentActual), day: 10, category: categories.health, card: cardChecking, presetID: nil)

        let gymActual = actualsMatchPlanned ? 45 : 0
        addPlanned(title: "Gym", planned: 45, actual: Double(gymActual), day: 12, category: categories.health, card: cardVisa, presetID: presets.gym.id)

        let insuranceActual = actualsMatchPlanned ? 132 : 132
        addPlanned(title: "Insurance", planned: 132, actual: Double(insuranceActual), day: 15, category: categories.health, card: cardChecking, presetID: presets.insurance.id)

        let streamingActual = actualsMatchPlanned ? 25 : 0
        addPlanned(title: "Streaming", planned: 25, actual: Double(streamingActual), day: 19, category: categories.entertainment, card: cardVisa, presetID: presets.streaming.id)

        let loanActual = actualsMatchPlanned ? 210 : 210
        addPlanned(title: "Student Loan", planned: 210, actual: Double(loanActual), day: 22, category: categories.health, card: cardChecking, presetID: nil)

        let phoneActual = actualsMatchPlanned ? 78 : 78
        addPlanned(title: "Phone", planned: 78, actual: Double(phoneActual), day: 24, category: categories.utilities, card: cardChecking, presetID: nil)
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

        addPlanned(title: "Electric", planned: 130, day: 6, category: categories.utilities, card: cardChecking, presetID: nil)
        addPlanned(title: "Water", planned: 55, day: 8, category: categories.utilities, card: cardChecking, presetID: nil)
        addPlanned(title: "Car Payment", planned: 345, day: 10, category: categories.health, card: cardChecking, presetID: nil)

        addPlanned(title: "Gym", planned: 45, day: 12, category: categories.health, card: cardVisa, presetID: presets.gym.id)
        addPlanned(title: "Insurance", planned: 132, day: 15, category: categories.health, card: cardChecking, presetID: presets.insurance.id)
        addPlanned(title: "Streaming", planned: 25, day: 19, category: categories.entertainment, card: cardVisa, presetID: presets.streaming.id)

        addPlanned(title: "Student Loan", planned: 210, day: 22, category: categories.health, card: cardChecking, presetID: nil)
        addPlanned(title: "Phone", planned: 78, day: 24, category: categories.utilities, card: cardChecking, presetID: nil)
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

        // Groceries (5)
        add("Trader Joe's", 124.65, day(3), cardVisa, categories.groceries)
        add("Safeway", 92.40, day(8), cardVisa, categories.groceries)
        add("Costco", 214.90, day(14), cardAmex, categories.groceries)
        add("Grocery Run", 89.15, day(20), cardVisa, categories.groceries)
        add("Quick Groceries", 34.22, day(26), cardVisa, categories.groceries)

        // Dining (5)
        add("Coffee", 9.85, day(4), cardVisa, categories.dining)
        add("Lunch", 22.60, day(7), cardVisa, categories.dining)
        add("Dinner", 58.40, day(11), cardAmex, categories.dining)
        add("Takeout", 31.20, day(18), cardVisa, categories.dining)
        add("Brunch", 44.10, day(23), cardAmex, categories.dining)

        // Transport (4)
        add("Uber", 28.40, day(6), cardVisa, categories.transport)
        add("Gas", 68.25, day(10), cardChecking, categories.transport)
        add("Parking", 14.00, day(15), cardVisa, categories.transport)
        add("Gas", 64.10, day(25), cardChecking, categories.transport)

        // Utilities type stuff (2)
        add("Household Supplies", 42.18, day(9), cardAmex, categories.utilities)
        add("Mobile Add-On", 18.99, day(16), cardChecking, categories.utilities)

        // Services (2)
        add("Haircut", 85.00, day(12), cardChecking, categories.services)
        add("Car Wash", 18.00, day(21), cardChecking, categories.services)

        // Shopping (3)
        add("Target", 88.30, day(5), cardAmex, categories.shopping)
        add("Amazon", 62.49, day(17), cardVisa, categories.shopping)
        add("Home Stuff", 54.99, day(28), cardAmex, categories.shopping)

        // Entertainment (2)
        add("Movie", 26.00, day(13), cardVisa, categories.entertainment)
        add("Concert / Event", 74.00, day(24), cardAmex, categories.entertainment)

        // Health (2)
        add("Pharmacy", 32.40, day(19), cardChecking, categories.health)
        add("Copay", 45.00, day(27), cardChecking, categories.health)

        // Deterministic "life hits" so some months go negative
        if month % 2 == 0 {
            add("Car Repair", 520.00, day(22), cardChecking, categories.services)
        }

        if month % 3 == 0 {
            add("Medical", 260.00, day(29), cardChecking, categories.health)
        }

        if month % 4 == 0 {
            add("Weekend Trip", 420.00, day(30), cardVisa, categories.entertainment)
        }

        if month % 5 == 0 {
            add("Vet / Pet", 185.00, day(2), cardChecking, categories.health)
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
        // Planned: 1500.00 and 1500.00 each month
        // Actual: slightly off with cents, month-to-month wobble
        // One month: second paycheck is delayed/missing

        var cursor = startOfMonth(containing: rangeStart, calendar: calendar)

        let nowMonthStart = startOfMonth(containing: Date(), calendar: calendar)
        let missingSecondPaycheckMonthStart = calendar.date(byAdding: .month, value: -2, to: nowMonthStart) ?? nowMonthStart

        while cursor <= rangeEnd {
            let monthStart = startOfMonth(containing: cursor, calendar: calendar)
            let monthEnd = endOfMonth(containing: cursor, calendar: calendar)

            if monthEnd < rangeStart {
                cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor
                continue
            }
            if monthStart > rangeEnd { break }

            let month = calendar.component(.month, from: monthStart)
            let year = calendar.component(.year, from: monthStart)

            // Deterministic cents wobble so screenshots are consistent.
            // derive cents from month/year so it "feels" random but never changes per run.
            func actualForPlanned(_ planned: Double, paycheckIndex: Int) -> Double {
                let seed = (year * 100) + (month * 10) + paycheckIndex
                let dollarsBump = Double((seed % 7) - 3) // -3 ... +3
                let centsBump = Double((seed * 37) % 97) / 100.0 // 0.00 ... 0.96

                // Slight underpayment bias most months, occasional tiny over.
                // Example: 1500 -> 1476.94 style results appear naturally.
                let baseDelta: Double
                switch seed % 5 {
                case 0: baseDelta = -22.00
                case 1: baseDelta = -13.00
                case 2: baseDelta = -7.00
                case 3: baseDelta = -28.00
                default: baseDelta = -10.00
                }

                let result = planned + baseDelta + dollarsBump + centsBump
                // Keep it sane
                return max(1200.00, min(1550.99, round(result * 100) / 100))
            }

            // Paycheck #1
            let p1Planned = 1500.00
            let p1Actual = actualForPlanned(p1Planned, paycheckIndex: 1)

            let p1PlannedDate = monthStart
            let p1ActualDate = monthStart

            context.insert(Income(
                source: "Paycheck",
                amount: p1Planned,
                date: p1PlannedDate,
                isPlanned: true,
                workspace: workspace,
                series: nil,
                card: cardChecking
            ))

            context.insert(Income(
                source: "Paycheck",
                amount: p1Actual,
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

            let p2Planned = 1500.00
            let p2Actual = actualForPlanned(p2Planned, paycheckIndex: 2)

            // Optional: one month missing second paycheck, but not catastrophic because expenses are already tight
            let shouldSkipSecondPaycheck = (monthStart == missingSecondPaycheckMonthStart)

            if !shouldSkipSecondPaycheck {
                context.insert(Income(
                    source: "Paycheck",
                    amount: p2Planned,
                    date: p2PlannedDate,
                    isPlanned: true,
                    workspace: workspace,
                    series: nil,
                    card: cardChecking
                ))

                context.insert(Income(
                    source: "Paycheck",
                    amount: p2Actual,
                    date: p2ActualDate,
                    isPlanned: false,
                    workspace: workspace,
                    series: nil,
                    card: cardChecking
                ))
            }

            // Side income every other month, small and believable
            if month % 2 == 1 {
                context.insert(Income(
                    source: "Side Hustle",
                    amount: 165.32,
                    date: calendar.date(byAdding: .day, value: 20, to: monthStart) ?? monthStart,
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

    // MARK: - Shared Balances

    private static func seedSharedBalances(
        context: ModelContext,
        workspace: Workspace,
        cardChecking: Card,
        cardVisa: Card,
        categories: (groceries: Category, dining: Category, transport: Category, entertainment: Category),
        calendar: Calendar
    ) {
        let now = Date()

        let alex = AllocationAccount(name: "Alex", hexColor: "#60A5FA", workspace: workspace)
        let jordan = AllocationAccount(name: "Jordan", hexColor: "#F97316", workspace: workspace)
        let casey = AllocationAccount(name: "Casey", hexColor: "#34D399", workspace: workspace)

        context.insert(alex)
        context.insert(jordan)
        context.insert(casey)

        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: now) ?? now
        let threeDaysAgo = calendar.date(byAdding: .day, value: -3, to: now) ?? now
        let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: now) ?? now
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let nineDaysAgo = calendar.date(byAdding: .day, value: -9, to: now) ?? now
        let twelveDaysAgo = calendar.date(byAdding: .day, value: -12, to: now) ?? now
        let fourteenDaysAgo = calendar.date(byAdding: .day, value: -14, to: now) ?? now

        let dinnerExpense = VariableExpense(
            descriptionText: "Dinner Split",
            amount: 84.00,
            transactionDate: twelveDaysAgo,
            workspace: workspace,
            card: cardVisa,
            category: categories.dining
        )
        context.insert(dinnerExpense)

        let dinnerAllocation = ExpenseAllocation(
            allocatedAmount: 42.00,
            createdAt: twelveDaysAgo,
            updatedAt: twelveDaysAgo,
            workspace: workspace,
            account: alex,
            expense: dinnerExpense
        )
        context.insert(dinnerAllocation)
        dinnerExpense.allocation = dinnerAllocation

        context.insert(
            AllocationSettlement(
                date: fiveDaysAgo,
                note: "Paid me back via Zelle",
                amount: 30.00,
                workspace: workspace,
                account: alex
            )
        )

        let groceriesExpense = VariableExpense(
            descriptionText: "Groceries Run",
            amount: 96.00,
            transactionDate: fourteenDaysAgo,
            workspace: workspace,
            card: cardChecking,
            category: categories.groceries
        )
        context.insert(groceriesExpense)

        let groceriesAllocation = ExpenseAllocation(
            allocatedAmount: 48.00,
            createdAt: fourteenDaysAgo,
            updatedAt: fourteenDaysAgo,
            workspace: workspace,
            account: jordan,
            expense: groceriesExpense
        )
        context.insert(groceriesAllocation)
        groceriesExpense.allocation = groceriesAllocation

        let concertExpense = VariableExpense(
            descriptionText: "Concert Tickets",
            amount: 100.00,
            transactionDate: sevenDaysAgo,
            workspace: workspace,
            card: cardVisa,
            category: categories.entertainment
        )
        context.insert(concertExpense)

        let concertAllocation = ExpenseAllocation(
            allocatedAmount: 60.00,
            createdAt: sevenDaysAgo,
            updatedAt: sevenDaysAgo,
            workspace: workspace,
            account: jordan,
            expense: concertExpense
        )
        context.insert(concertAllocation)
        concertExpense.allocation = concertAllocation

        let concertOffset = AllocationSettlement(
            date: sevenDaysAgo,
            note: "Offset applied to Concert Tickets",
            amount: -20.00,
            workspace: workspace,
            account: jordan,
            expense: concertExpense
        )
        context.insert(concertOffset)
        concertExpense.offsetSettlement = concertOffset

        context.insert(
            AllocationSettlement(
                date: threeDaysAgo,
                note: "I paid Jordan cash",
                amount: -25.00,
                workspace: workspace,
                account: jordan
            )
        )

        let tripExpense = VariableExpense(
            descriptionText: "Road Trip Gas",
            amount: 70.00,
            transactionDate: nineDaysAgo,
            workspace: workspace,
            card: cardChecking,
            category: categories.transport
        )
        context.insert(tripExpense)

        let tripAllocation = ExpenseAllocation(
            allocatedAmount: 35.00,
            createdAt: nineDaysAgo,
            updatedAt: nineDaysAgo,
            workspace: workspace,
            account: casey,
            expense: tripExpense
        )
        context.insert(tripAllocation)
        tripExpense.allocation = tripAllocation

        context.insert(
            AllocationSettlement(
                date: twoDaysAgo,
                note: "I covered parking",
                amount: -50.00,
                workspace: workspace,
                account: casey
            )
        )
    }

    // MARK: - Marina

    private static func seedMarinaConversation(workspaceID: UUID, now: Date) {
        let store = HomeAssistantConversationStore()

        let answers: [HomeAnswer] = [
            HomeAnswer(
                queryID: UUID(),
                kind: .metric,
                userPrompt: "How am I doing this month?",
                title: "This month at a glance",
                subtitle: "Income is covering spending so far.",
                primaryValue: "$412.85 projected savings",
                rows: [
                    HomeAnswerRow(title: "Total spend", value: "$2,486.14"),
                    HomeAnswerRow(title: "Total income", value: "$2,899.00"),
                    HomeAnswerRow(title: "Status", value: "On track")
                ],
                generatedAt: now.addingTimeInterval(-1_200)
            ),
            HomeAnswer(
                queryID: UUID(),
                kind: .comparison,
                userPrompt: "Compare this month to last month.",
                title: "Spending change",
                subtitle: "You spent less than last month.",
                primaryValue: "-$183.40",
                rows: [
                    HomeAnswerRow(title: "Current month", value: "$2,486.14"),
                    HomeAnswerRow(title: "Previous month", value: "$2,669.54")
                ],
                generatedAt: now.addingTimeInterval(-900)
            ),
            HomeAnswer(
                queryID: UUID(),
                kind: .list,
                userPrompt: "Where can I trim spending?",
                title: "Top categories to review",
                subtitle: "These categories had the highest variable spend.",
                rows: [
                    HomeAnswerRow(title: "Dining", value: "$276.15"),
                    HomeAnswerRow(title: "Shopping", value: "$205.78"),
                    HomeAnswerRow(title: "Entertainment", value: "$178.00")
                ],
                generatedAt: now.addingTimeInterval(-600)
            ),
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                userPrompt: "Add planned income $450 for freelance next Friday.",
                title: "Ready to add that income",
                subtitle: "I can prefill this as planned income so you can confirm it.",
                rows: [
                    HomeAnswerRow(title: "Amount", value: "$450.00"),
                    HomeAnswerRow(title: "Source", value: "Freelance"),
                    HomeAnswerRow(title: "Type", value: "Planned")
                ],
                generatedAt: now.addingTimeInterval(-300)
            )
        ]

        store.saveAnswers(answers, workspaceID: workspaceID)
    }

    // MARK: - Excursion

    private static func seedExcursionModeActive(now: Date) {
        SpendingSessionStore.activate(hours: 2, now: now)

        Task { @MainActor in
            ShoppingModeManager.shared.refreshIfExpired(now: now)
        }
    }
}
#endif
