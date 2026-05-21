import Foundation
import Testing
@testable import Offshore

struct MarinaLiveDomainIntentMapperTests {
    @Test func mapper_repairsSmokePromptsIntoCanonicalReadRoutes() {
        let mapper = MarinaLiveDomainIntentMapper(nowProvider: { fixedNow })
        let context = routerContext()

        let activeBudget = mapper.map(
            payload: payload(route: "readQuery", intent: "sum", target: "active budget"),
            prompt: "What is my active budget?",
            context: context
        )
        #expect(activeBudget.canonicalRouteSummary == "budget.active")
        #expect(activeBudget.blockedWrongQuery == false)
        #expect(command(activeBudget)?.datasets == [.budgets])
        #expect(command(activeBudget)?.action == .lookupDetails)
        #expect(command(activeBudget)?.measure == .remainingBudget)
        #expect(command(activeBudget)?.includeFilters.isEmpty == true)

        let cardSpend = mapper.map(
            payload: payload(route: "readQuery", intent: "unsupported", target: "total spending"),
            prompt: "What did I spend on Apple Card this month?",
            context: context
        )
        #expect(cardSpend.canonicalRouteSummary == "spending.total.card")
        #expect(command(cardSpend)?.includeFilters.first?.rawText == "Apple Card")
        #expect(command(cardSpend)?.includeFilters.first?.allowedTypes == [.card])
        #expect(command(cardSpend)?.dateRange?.startDate == date(2026, 5, 1))
        #expect(cardSpend.dateSourceSummary == MarinaDateSource.promptExplicit.rawValue)
        #expect(cardSpend.effectiveDateRangeSummary == "2026-05-01..2026-05-31")

        let uncategorized = mapper.map(
            payload: payload(route: "readQuery", intent: "missingTarget", target: "uncategorized spending"),
            prompt: "How much uncategorized spending do I have?",
            context: context
        )
        #expect(uncategorized.canonicalRouteSummary == "spending.total.category")
        #expect(command(uncategorized)?.includeFilters.first?.rawText == "Uncategorized")
        #expect(command(uncategorized)?.includeFilters.first?.allowedTypes == [.category])

        let broadSpend = mapper.map(
            payload: payload(route: "readQuery", intent: "spendTotal", target: "this month", date: "May 2025"),
            prompt: "What did I spend this month?",
            context: context
        )
        #expect(broadSpend.canonicalRouteSummary == "spending.total.workspace")
        #expect(broadSpend.routeKeySummary == "spendTotal")
        #expect(broadSpend.droppedTargetSummary?.contains("target=this month") == true)
        #expect(broadSpend.datePolicySummary?.contains("dateRaw=this month") == true)
        #expect(broadSpend.datePolicySummary?.contains("aiDateDropped=May 2025") == true)
        #expect(broadSpend.dateSourceSummary == MarinaDateSource.promptExplicit.rawValue)
        #expect(broadSpend.effectiveDateRangeSummary == "2026-05-01..2026-05-31")
        #expect(command(broadSpend)?.includeFilters.isEmpty == true)
        #expect(command(broadSpend)?.dateRange?.startDate == date(2026, 5, 1))

        let merchantSpend = mapper.map(
            payload: payload(route: "readQuery", intent: "spendTotal", target: "Apple", date: "this month"),
            prompt: "What did I spend at Apple this month?",
            context: context
        )
        #expect(merchantSpend.canonicalRouteSummary == "spending.total.merchant")
        #expect(merchantSpend.routeKeySummary == "spendTotal")
        #expect(command(merchantSpend)?.includeFilters.first?.rawText == "Apple")
        #expect(command(merchantSpend)?.includeFilters.first?.allowedTypes == [.merchant])

        let topOne = mapper.map(
            payload: payload(route: "readQuery", intent: "topCategories", target: "categories", date: "this month"),
            prompt: "What is my top 1 category this month?",
            context: context
        )
        #expect(topOne.canonicalRouteSummary == "spending.topCategories")
        #expect(command(topOne)?.limit == 1)
        #expect(command(topOne)?.grouping == .category)
    }

    @Test func mapper_detectsRelationshipGrammarWithoutPhraseOrderDependency() {
        let mapper = MarinaLiveDomainIntentMapper(nowProvider: { fixedNow })
        let context = routerContext()

        let linkedCards = mapper.map(
            payload: payload(route: "lookup", intent: "linkedCards", target: "May Budget", relationship: "cards linked"),
            prompt: "Which cards are linked to May Budget?",
            context: context
        )
        #expect(linkedCards.canonicalRouteSummary == "budget.linkedCards")
        #expect(linkedCards.routeKeySummary == "budgetLinkedCards")
        #expect(command(linkedCards)?.includeFilters.first?.rawText == "May Budget")
        #expect(command(linkedCards)?.includeFilters.first?.allowedTypes == [.budget])
        #expect(command(linkedCards)?.requestedDetail == .linkedCards)

        let linkedPresets = mapper.map(
            payload: payload(route: "lookup", intent: "linkedPresets", target: "May Budget", relationship: "presets are linked"),
            prompt: "Which presets are linked to May Budget?",
            context: context
        )
        #expect(linkedPresets.canonicalRouteSummary == "budget.linkedPresets")
        #expect(linkedPresets.routeKeySummary == "budgetLinkedPresets")
        #expect(command(linkedPresets)?.includeFilters.first?.rawText == "May Budget")
        #expect(command(linkedPresets)?.includeFilters.first?.allowedTypes == [.budget])
        #expect(command(linkedPresets)?.requestedDetail == .linkedPresets)
    }

    @Test func mapper_usesHomeAppliedDateRangeForNoDateSpendAndIncomePrompts() {
        let mapper = MarinaLiveDomainIntentMapper(nowProvider: { fixedNow })
        let ambientRange = HomeQueryDateRange(
            startDate: date(2026, 5, 10),
            endDate: date(2026, 5, 16, endOfDay: true)
        )
        let context = routerContext(ambientDateRange: ambientRange)

        let uncategorized = mapper.map(
            payload: payload(route: "readQuery", intent: "missingTarget", target: "uncategorized spending"),
            prompt: "How much uncategorized spending do I have?",
            context: context
        )
        #expect(uncategorized.dateSourceSummary == MarinaDateSource.homeAppliedRange.rawValue)
        #expect(uncategorized.effectiveDateRangeSummary == "2026-05-10..2026-05-16")
        #expect(command(uncategorized)?.dateRange?.traceSummary == "2026-05-10..2026-05-16")

        let actualIncome = mapper.map(
            payload: payload(route: "readQuery", intent: "incomeActual", target: "income"),
            prompt: "What is my actual income?",
            context: context
        )
        #expect(actualIncome.dateSourceSummary == MarinaDateSource.homeAppliedRange.rawValue)
        #expect(command(actualIncome)?.dateRange?.traceSummary == "2026-05-10..2026-05-16")
    }

    @Test func mapper_fallsBackToDefaultBudgetingPeriodWhenNoHomeRangeExists() {
        let mapper = MarinaLiveDomainIntentMapper(nowProvider: { fixedNow })
        let context = routerContext(ambientDateRange: nil, defaultPeriodUnit: .week)

        let spend = mapper.map(
            payload: payload(route: "readQuery", intent: "spendTotal", target: nil),
            prompt: "What did I spend?",
            context: context
        )

        #expect(spend.dateSourceSummary == MarinaDateSource.defaultBudgetingPeriod.rawValue)
        #expect(command(spend)?.dateRange != nil)
        #expect(spend.effectiveDateRangeSummary?.contains("2026-05") == true)
    }

    @Test func mapper_keepsSpendGrammarAheadOfBadModelRelationshipOrRecentSignals() {
        let mapper = MarinaLiveDomainIntentMapper(nowProvider: { fixedNow })
        let context = routerContext()

        let rentSpend = mapper.map(
            payload: payload(route: "readQuery", intent: "linkedPresets", target: "Rent", relationship: "linked preset", date: "this month"),
            prompt: "What did I spend on Rent this month?",
            context: context
        )
        #expect(rentSpend.routeKeySummary == "spendTotal")
        #expect(rentSpend.canonicalRouteSummary != "budget.linkedPresets")

        let appleSpend = mapper.map(
            payload: payload(route: "readQuery", intent: "transactionRows", target: "Apple", date: "this month"),
            prompt: "What did I spend at Apple this month?",
            context: context
        )
        #expect(appleSpend.routeKeySummary == "spendTotal")
        #expect(appleSpend.canonicalRouteSummary == "spending.total.merchant")
    }

    @Test func mapper_repairsReconciliationAndRowSmokeFailures() {
        let mapper = MarinaLiveDomainIntentMapper(nowProvider: { fixedNow })
        let context = routerContext()

        let balance = mapper.map(
            payload: payload(route: "lookup", intent: "objectLookup", target: "Roommate's balance"),
            prompt: "What is Roommate's balance?",
            context: context
        )
        #expect(balance.canonicalRouteSummary == "reconciliation.balance")
        #expect(command(balance)?.datasets == [.reconciliation])
        #expect(command(balance)?.measure == .reconciliationBalance)
        #expect(command(balance)?.includeFilters.first?.rawText == "Roommate")
        #expect(command(balance)?.includeFilters.first?.allowedTypes == [.allocationAccount])

        let allocations = mapper.map(
            payload: payload(route: "readQuery", intent: "incomeRows", target: nil),
            prompt: "Show Roommate allocation rows.",
            context: context
        )
        #expect(allocations.canonicalRouteSummary == "reconciliation.allocationRows")
        #expect(command(allocations)?.datasets == [.expenseAllocations])
        #expect(command(allocations)?.action == .listRows)
        #expect(command(allocations)?.grouping == .allocationAccount)
        #expect(command(allocations)?.includeFilters.first?.rawText == "Roommate")

        let settlements = mapper.map(
            payload: payload(route: "unsupported", intent: "unsupported", target: "settlementRows"),
            prompt: "Show settlement rows.",
            context: context
        )
        #expect(settlements.canonicalRouteSummary == "reconciliation.settlementRows")
        #expect(settlements.droppedTargetSummary?.contains("target=settlementRows") == true)
        #expect(command(settlements)?.datasets == [.reconciliation])
        #expect(command(settlements)?.action == .listRows)
        #expect(command(settlements)?.grouping == .allocationAccount)
        #expect(command(settlements)?.includeFilters.isEmpty == true)
    }

    @Test func mapper_repairsIncomeSavingsAndScenarioSmokeFailures() {
        let mapper = MarinaLiveDomainIntentMapper(nowProvider: { fixedNow })
        let context = routerContext()

        let actualIncome = mapper.map(
            payload: payload(route: "readQuery", intent: "missingTarget", target: "actual income this month"),
            prompt: "What is my actual income this month?",
            context: context
        )
        #expect(actualIncome.canonicalRouteSummary == "income.actual")
        #expect(command(actualIncome)?.datasets == [.income])
        #expect(command(actualIncome)?.incomeStatusScope == .actual)
        #expect(command(actualIncome)?.includeFilters.isEmpty == true)

        let plannedVsActualIncome = mapper.map(
            payload: payload(route: "readQuery", intent: "categoryComparison", target: "Dining", date: "May 2024"),
            prompt: "Compare actual vs planned income this month.",
            context: context
        )
        #expect(plannedVsActualIncome.canonicalRouteSummary == "income.plannedVsActual")
        #expect(plannedVsActualIncome.routeKeySummary == "incomePlannedVsActual")
        #expect(command(plannedVsActualIncome)?.datasets == [.income])
        #expect(command(plannedVsActualIncome)?.incomeStatusScope == .all)
        #expect(command(plannedVsActualIncome)?.requestedDetail == .status)
        #expect(command(plannedVsActualIncome)?.includeFilters.isEmpty == true)
        #expect(command(plannedVsActualIncome)?.dateRange?.startDate == date(2026, 5, 1))
        #expect(plannedVsActualIncome.datePolicySummary?.contains("aiDateDropped=May 2024") == true)

        let savingsActivity = mapper.map(
            payload: payload(route: "readQuery", intent: "missingTarget", target: "savings activity"),
            prompt: "Show savings activity.",
            context: context
        )
        #expect(savingsActivity.canonicalRouteSummary == "savings.activity")
        #expect(command(savingsActivity)?.datasets == [.savingsLedger])
        #expect(command(savingsActivity)?.action == .listRows)
        #expect(command(savingsActivity)?.measure == .savingsMovement)

        let scenario = mapper.map(
            payload: payload(route: "unsupported", intent: "unsupported", target: "dining", amount: "200", direction: "less"),
            prompt: "What if I spend 200 less on dining?",
            context: context
        )
        #expect(scenario.canonicalRouteSummary == "scenario.budgetForecast")
        guard case .scenario(let scenarioIntent) = scenario.intent else {
            Issue.record("Expected scenario intent.")
            return
        }
        #expect(scenarioIntent.targetName == "Dining")
        #expect(scenarioIntent.targetTypeRaw == "category")
        #expect(scenarioIntent.amount == 200)
        #expect(scenarioIntent.valueModeRaw == "less")
    }

    @Test func mapper_blocksUnmappedLiveReadRoutesBeforeDataQuery() {
        let mapper = MarinaLiveDomainIntentMapper(nowProvider: { fixedNow })
        let result = mapper.map(
            payload: payload(route: "readQuery", intent: "creativeWriting", target: "budget poem"),
            prompt: "Write a poem about my budget.",
            context: routerContext()
        )

        #expect(result.blockedWrongQuery == true)
        #expect(result.canonicalRouteSummary == "blocked.unmappedLiveRoute")
        guard case .unsupported(let unsupported) = result.intent else {
            Issue.record("Expected unsupported guard intent.")
            return
        }
        #expect(unsupported.reasonRaw == "unmappedLiveRoute")
    }

    private var fixedNow: Date {
        date(2026, 5, 20)
    }

    private func routerContext(
        ambientDateRange: HomeQueryDateRange? = nil,
        defaultPeriodUnit: HomeQueryPeriodUnit = .month
    ) -> MarinaInterpretationContext {
        MarinaInterpretationContext(
            workspaceName: "Personal",
            defaultPeriodUnit: defaultPeriodUnit,
            ambientDateRange: ambientDateRange,
            sessionContext: HomeAssistantSessionContext(),
            priorQueryContext: .empty,
            cardNames: ["Apple Card", "Backup Card"],
            categoryNames: ["Groceries", "Dining"],
            incomeSourceNames: ["Salary"],
            presetTitles: ["Rent"],
            budgetNames: ["May Budget"],
            aliasSummaries: [],
            now: fixedNow
        )
    }

    private func payload(
        route: String,
        intent: String?,
        target: String?,
        secondary: String? = nil,
        relationship: String? = nil,
        date: String? = nil,
        comparison: String? = nil,
        amount: String? = nil,
        direction: String? = nil
    ) -> MarinaFoundationIntentEnvelopePayload {
        MarinaFoundationIntentEnvelopePayload(
            routeRaw: route,
            intentRaw: intent,
            targetText: target,
            secondaryTargetText: secondary,
            relationshipText: relationship,
            dateText: date,
            comparisonDateText: comparison,
            amountText: amount,
            valueDirectionRaw: direction,
            confidenceRaw: "high",
            unsupportedReasonRaw: nil
        )
    }

    private func command(_ mapping: MarinaLiveDomainIntentMapping) -> MarinaSemanticCommand? {
        guard case .semanticCommand(let command) = mapping.intent.structuredIntent else {
            return nil
        }
        return command
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, endOfDay: Bool = false) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        if endOfDay {
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? start
        }
        return start
    }
}
