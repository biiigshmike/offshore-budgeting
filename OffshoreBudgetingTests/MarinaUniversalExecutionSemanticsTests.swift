import Foundation
import Testing
@testable import Offshore

struct MarinaUniversalExecutionSemanticsTests {
    private let bridge = MarinaSemanticUniversalPlanBridge()
    private let runner = MarinaUniversalQueryRunner()

    @Test func cardAndCategorySpendCanonicalizeToUnifiedRowsAndAggregateBeforeLimit() throws {
        let fixture = makeFixture()
        let cardPlan = try requirePlan(bridge.makePlan(from: MarinaSemanticRequest(
            entity: .card,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            targetName: fixture.cardA.name,
            resolvedTarget: reference(.card, fixture.cardA.id, fixture.cardA.name),
            resultLimit: 1,
            expectedAnswerShape: .metric
        )))
        let categoryPlan = try requirePlan(bridge.makePlan(from: MarinaSemanticRequest(
            entity: .category,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            targetName: fixture.primaryCategory.name,
            resolvedTarget: reference(.category, fixture.primaryCategory.id, fixture.primaryCategory.name),
            expectedAnswerShape: .metric
        )))

        #expect(cardPlan.surface == .unifiedExpenses)
        #expect(categoryPlan.surface == .unifiedExpenses)
        #expect(requireMetric(runner.run(plan: cardPlan, snapshot: fixture.snapshot)).value == .money(450))
        #expect(requireMetric(runner.run(plan: categoryPlan, snapshot: fixture.snapshot)).value == .money(470))
    }

    @Test func namedBudgetSummaryUsesFullRangeByDefaultAndExplicitIntersectionWhenRequested() throws {
        let fixture = makeFixture()
        let ambientRange = HomeQueryDateRange(startDate: fixture.rangeStart, endDate: fixture.firstHalfEnd)
        let context = MarinaUniversalPlanningContext(
            ambientDateRange: ambientRange,
            defaultBudgetingPeriod: .monthly,
            now: fixture.rangeStart,
            calendar: utcCalendar
        )
        let budgetReference = reference(.budget, fixture.budget.id, fixture.budget.name)
        let defaultedRequest = MarinaSemanticRequest(
            entity: .budget,
            operation: .sum,
            measure: .unifiedExpenseTotal,
            resolvedTarget: budgetReference,
            resolvedScope: .budget(fixture.budget.id),
            expectedAnswerShape: .metric
        )
        let explicitRequest = MarinaSemanticRequest(
            entity: .budget,
            operation: .sum,
            measure: .unifiedExpenseTotal,
            dateRangeSource: .explicit,
            resolvedTarget: budgetReference,
            resolvedScope: .budget(fixture.budget.id),
            expectedAnswerShape: .metric
        )

        let defaultedPlan = try requirePlan(bridge.makePlan(from: defaultedRequest, planningContext: context))
        let explicitPlan = try requirePlan(bridge.makePlan(from: explicitRequest, planningContext: context))

        #expect(defaultedPlan.projection == .summary)
        #expect(explicitPlan.projection == .summary)
        #expect(requireMetric(runner.run(plan: defaultedPlan, snapshot: fixture.snapshot)).value == .money(570))
        #expect(requireMetric(runner.run(plan: explicitPlan, snapshot: fixture.snapshot)).value == .money(340))
    }

    @Test func publicActivityOccurrenceAndMembershipProjectionsUseScopedRows() throws {
        let fixture = makeFixture()
        let activityPlan = try requirePlan(bridge.makePlan(from: MarinaSemanticRequest(
            entity: .savingsAccount,
            operation: .list,
            projection: .activity,
            targetName: fixture.savingsAccount.name,
            resolvedTarget: reference(
                .savingsAccount,
                fixture.savingsAccount.id,
                fixture.savingsAccount.name
            ),
            expectedAnswerShape: .list
        )))
        let occurrencePlan = try requirePlan(bridge.makePlan(from: MarinaSemanticRequest(
            entity: .incomeSeries,
            operation: .list,
            projection: .occurrences,
            targetName: fixture.incomeSeries.source,
            resolvedTarget: reference(
                .incomeSeries,
                fixture.incomeSeries.id,
                fixture.incomeSeries.source
            ),
            expectedAnswerShape: .list
        )))
        let membershipPlan = try requirePlan(bridge.makePlan(from: MarinaSemanticRequest(
            entity: .preset,
            operation: .list,
            projection: .linkedBudgets,
            targetName: fixture.preset.title,
            resolvedTarget: reference(.preset, fixture.preset.id, fixture.preset.title),
            expectedAnswerShape: .list
        )))

        #expect(activityPlan.surface == .savingsLedgerEntries)
        #expect(rowIDs(runner.run(plan: activityPlan, snapshot: fixture.snapshot)) == [fixture.savingsEntry.id])
        #expect(rowIDs(runner.run(plan: occurrencePlan, snapshot: fixture.snapshot)) == [fixture.occurrence.id])
        #expect(rowIDs(runner.run(plan: membershipPlan, snapshot: fixture.snapshot)) == [fixture.budget.id])
    }

    @Test func incomeSeriesOccurrencesUseIncomeDatesAndHonorRequestedRange() throws {
        let fixture = makeFixture()
        let later = Income(
            source: fixture.incomeSeries.source,
            amount: 2_000,
            date: fixture.firstHalfEnd.addingTimeInterval(86_400 * 3),
            isPlanned: true,
            workspace: fixture.workspace,
            series: fixture.incomeSeries
        )
        let base = fixture.snapshot
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: base.workspace,
            budgets: base.budgets,
            cards: base.cards,
            categories: base.categories,
            presets: base.presets,
            plannedExpenses: base.plannedExpenses,
            variableExpenses: base.variableExpenses,
            homePlannedExpenses: base.homePlannedExpenses,
            homeCalculationPlannedExpenses: base.homeCalculationPlannedExpenses,
            homeCalculationVariableExpenses: base.homeCalculationVariableExpenses,
            reconciliationAccounts: base.reconciliationAccounts,
            expenseAllocations: base.expenseAllocations,
            allocationSettlements: base.allocationSettlements,
            savingsAccounts: base.savingsAccounts,
            savingsEntries: base.savingsEntries,
            incomes: base.incomes + [later],
            incomeSeries: base.incomeSeries,
            importMerchantRules: base.importMerchantRules,
            assistantAliasRules: base.assistantAliasRules
        )
        let context = MarinaUniversalPlanningContext(
            ambientDateRange: HomeQueryDateRange(
                startDate: fixture.rangeStart,
                endDate: fixture.firstHalfEnd
            ),
            defaultBudgetingPeriod: .monthly,
            now: fixture.rangeStart,
            calendar: utcCalendar
        )
        let request = MarinaSemanticRequest(
            entity: .incomeSeries,
            operation: .list,
            measure: .incomeAmount,
            projection: .occurrences,
            dateRangeSource: .explicit,
            targetName: fixture.incomeSeries.source,
            resolvedTarget: reference(
                .incomeSeries,
                fixture.incomeSeries.id,
                fixture.incomeSeries.source
            ),
            expectedAnswerShape: .list
        )
        let plan = try requirePlan(bridge.makePlan(from: request, planningContext: context))

        #expect(plan.sorts.first?.target == .field(.date))
        #expect(rowIDs(runner.run(plan: plan, snapshot: snapshot)) == [fixture.occurrence.id])
    }

    @Test func multipleResolvedConstraintsCompileAsIndependentStableIDFilters() throws {
        let fixture = makeFixture()
        let request = MarinaSemanticRequest(
            entity: .category,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category, .card, .budget],
            constraints: [
                constraint(.category, fixture.primaryCategory.name, .category, fixture.primaryCategory.id),
                constraint(.card, fixture.cardA.name, .card, fixture.cardA.id),
                constraint(.budget, fixture.budget.name, .budget, fixture.budget.id)
            ],
            targetName: fixture.primaryCategory.name,
            resolvedTarget: reference(.category, fixture.primaryCategory.id, fixture.primaryCategory.name),
            resolvedScope: .budget(fixture.budget.id),
            expectedAnswerShape: .metric
        )
        let plan = try requirePlan(bridge.makePlan(from: request))

        #expect(plan.filters.count == 2)
        #expect(requireMetric(runner.run(plan: plan, snapshot: fixture.snapshot)).value == .money(350))
    }

    @Test func bridgeRejectsRawIdentityConstraintInsteadOfFilteringByDisplayName() {
        let request = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            constraints: [
                MarinaSemanticConstraint(dimension: .category, value: "Groceries", kindSource: .explicit)
            ],
            expectedAnswerShape: .metric
        )

        #expect(bridge.makePlan(from: request) == .unsupported(.unresolvedEntity))
    }

    @Test func directEntityTargetCompilesToIDFieldFilterInsteadOfSelfRelationship() throws {
        let fixture = makeFixture()
        let request = MarinaSemanticRequest(
            entity: .preset,
            operation: .list,
            projection: .records,
            dimensions: [.preset],
            targetName: fixture.preset.title,
            resolvedTarget: reference(.preset, fixture.preset.id, fixture.preset.title),
            expectedAnswerShape: .list
        )
        let plan = try requirePlan(bridge.makePlan(from: request))

        #expect(plan.filters == [
            MarinaRowFilter(
                target: .field(.id),
                operation: .equals,
                value: .text(fixture.preset.id.uuidString)
            )
        ])
        #expect(rowIDs(runner.run(plan: plan, snapshot: fixture.snapshot)) == [fixture.preset.id])
    }

    @Test func duplicateNamesUseResolvedIDRatherThanGuessing() throws {
        let fixture = makeFixture()
        let request = MarinaSemanticRequest(
            entity: .category,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            targetName: fixture.duplicateCategory.name,
            resolvedTarget: reference(
                .category,
                fixture.duplicateCategory.id,
                fixture.duplicateCategory.name
            ),
            expectedAnswerShape: .metric
        )
        let plan = try requirePlan(bridge.makePlan(from: request))

        #expect(requireMetric(runner.run(plan: plan, snapshot: fixture.snapshot)).value == .money(100))
    }

    @Test func comparisonSlotsResolveIndependentlyAndPreserveCommonConstraints() throws {
        let fixture = makeFixture()
        let primaryReference = reference(.card, fixture.cardA.id, fixture.cardA.name)
        let comparisonReference = reference(.card, fixture.cardB.id, fixture.cardB.name)
        let request = MarinaSemanticRequest(
            entity: .card,
            operation: .compare,
            measure: .budgetImpact,
            dimensions: [.card, .category],
            constraints: [
                MarinaSemanticConstraint(
                    dimension: .card,
                    value: fixture.cardA.name,
                    resolvedReference: primaryReference
                ),
                MarinaSemanticConstraint(
                    dimension: .category,
                    value: fixture.primaryCategory.name,
                    resolvedReference: reference(
                        .category,
                        fixture.primaryCategory.id,
                        fixture.primaryCategory.name
                    )
                )
            ],
            targetName: fixture.cardA.name,
            comparisonTargetName: fixture.cardB.name,
            resolvedTarget: primaryReference,
            resolvedComparisonTarget: comparisonReference,
            expectedAnswerShape: .comparison
        )
        let plan = try requirePlan(bridge.makePlan(from: request))
        let metric = requireMetric(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(metric.value == .money(230))
        #expect(metric.presentationRows.map(\.title) == [fixture.cardA.name, fixture.cardB.name])
        #expect(metric.presentationRows.map(\.primaryValue) == [.money(350), .money(120)])

        let ambiguousRequest = MarinaSemanticRequest(
            entity: .card,
            operation: .compare,
            measure: .budgetImpact,
            dimensions: [.card],
            targetName: fixture.cardA.name,
            comparisonTargetName: fixture.cardB.name,
            resolvedTarget: primaryReference,
            resolvedComparisonTarget: MarinaResolvedEntityReference(
                entity: .card,
                id: nil,
                displayName: fixture.cardB.name,
                provenance: .candidateResolver
            ),
            expectedAnswerShape: .comparison
        )
        let ambiguousPlan = try requirePlan(bridge.makePlan(from: ambiguousRequest))
        #expect(runner.run(plan: ambiguousPlan, snapshot: fixture.snapshot) == .unsupported(.ambiguousEntity))
    }

    @Test func unsupportedProjectionTupleIsRejectedBeforeExecution() {
        let request = MarinaSemanticRequest(
            entity: .category,
            operation: .list,
            projection: .activity,
            expectedAnswerShape: .list
        )
        #expect(bridge.makePlan(from: request) == .unsupported(.unsupportedCombination))
    }

    @MainActor
    @Test func staleAndCrossWorkspaceResolvedIDsFailBeforeRowOrFormulaExecution() throws {
        let fixture = makeFixture()
        let staleCategory = reference(.category, UUID(), fixture.primaryCategory.name)
        let rowPlan = try requirePlan(bridge.makePlan(from: MarinaSemanticRequest(
            entity: .category,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            resolvedTarget: staleCategory,
            expectedAnswerShape: .metric
        )))
        #expect(runner.run(plan: rowPlan, snapshot: fixture.snapshot) == .unsupported(.unresolvedEntity))

        let formulaRunner = MarinaUniversalQueryRunner(
            formulaRegistry: MarinaFormulaRegistry(now: fixture.rangeStart, calendar: utcCalendar)
        )
        let formulaPlan = MarinaUniversalQueryPlan(
            entity: .category,
            operation: .forecast,
            measure: .categoryAvailability,
            resolvedTarget: staleCategory
        )
        #expect(
            formulaRunner.runFormulaAware(plan: formulaPlan, snapshot: fixture.snapshot)
                == .unsupported(.unresolvedEntity)
        )

        let crossWorkspacePlan = MarinaUniversalQueryPlan(
            entity: .category,
            operation: .list,
            resolvedScope: .workspace(UUID())
        )
        #expect(
            runner.run(plan: crossWorkspacePlan, snapshot: fixture.snapshot)
                == .unsupported(.unresolvedEntity)
        )
    }

    @MainActor
    @Test func budgetFormulaIgnoresUnlinkedCardActivityInsideTheSameWorkspace() throws {
        let fixture = makeFixture()
        let outsideCard = Card(name: "Outside", workspace: fixture.workspace)
        let outsideExpense = VariableExpense(
            descriptionText: "Not in July budget",
            amount: 10_000,
            transactionDate: fixture.rangeStart.addingTimeInterval(86_400 * 10),
            workspace: fixture.workspace,
            card: outsideCard,
            category: fixture.primaryCategory
        )
        let base = fixture.snapshot
        let extendedSnapshot = MarinaWorkspaceSnapshot(
            workspace: base.workspace,
            budgets: base.budgets,
            cards: base.cards + [outsideCard],
            categories: base.categories,
            presets: base.presets,
            plannedExpenses: base.plannedExpenses,
            variableExpenses: base.variableExpenses + [outsideExpense],
            homePlannedExpenses: base.homePlannedExpenses,
            homeCalculationPlannedExpenses: base.homeCalculationPlannedExpenses,
            homeCalculationVariableExpenses: base.homeCalculationVariableExpenses + [outsideExpense],
            reconciliationAccounts: base.reconciliationAccounts,
            expenseAllocations: base.expenseAllocations,
            allocationSettlements: base.allocationSettlements,
            savingsAccounts: base.savingsAccounts,
            savingsEntries: base.savingsEntries,
            incomes: base.incomes,
            incomeSeries: base.incomeSeries,
            importMerchantRules: base.importMerchantRules,
            assistantAliasRules: base.assistantAliasRules
        )
        let request = MarinaSemanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .remainingRoom,
            dateRangeToken: .allTime,
            resolvedTarget: reference(.budget, fixture.budget.id, fixture.budget.name),
            resolvedScope: .budget(fixture.budget.id),
            expectedAnswerShape: .metric
        )
        let formulaRegistry = MarinaFormulaRegistry(now: fixture.rangeStart, calendar: utcCalendar)
        let bridge = MarinaSemanticUniversalPlanBridge(formulaRegistry: formulaRegistry)
        let plan = try requirePlan(bridge.makePlan(from: request))
        let formulaRunner = MarinaUniversalQueryRunner(
            formulaRegistry: formulaRegistry
        )

        let baseline = formulaRunner.runFormulaAware(plan: plan, snapshot: base)
        let extended = formulaRunner.runFormulaAware(plan: plan, snapshot: extendedSnapshot)
        #expect(extended == baseline)
        #expect(requireMetric(extended).value != .empty)
    }

    @MainActor
    @Test func formulaBackedCategoryListsReturnStableOffsetPagesAndFullTotals() throws {
        let workspace = Workspace(name: "Paging", hexColor: "#123456")
        let start = Date(timeIntervalSince1970: 1_783_036_800)
        let end = start.addingTimeInterval(86_400 * 30)
        let budget = Budget(name: "July", startDate: start, endDate: end, workspace: workspace)
        let card = Card(name: "Everyday", workspace: workspace)
        budget.cardLinks = [BudgetCardLink(budget: budget, card: card)]
        let categories = (0..<25).map {
            Offshore.Category(
                name: String(format: "Category %02d", $0),
                hexColor: "#111111",
                workspace: workspace
            )
        }
        budget.categoryLimits = categories.map {
            BudgetCategoryLimit(maxAmount: 100, budget: budget, category: $0)
        }
        let expenses = categories.enumerated().map { index, category in
            VariableExpense(
                descriptionText: "Expense \(index)",
                amount: 120,
                transactionDate: start.addingTimeInterval(86_400),
                workspace: workspace,
                card: card,
                category: category
            )
        }
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [card],
            categories: categories,
            presets: [],
            plannedExpenses: [],
            variableExpenses: expenses,
            homePlannedExpenses: [],
            homeCalculationPlannedExpenses: [],
            homeCalculationVariableExpenses: expenses,
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [],
            savingsEntries: [],
            incomes: []
        )
        let planningContext = MarinaUniversalPlanningContext(
            ambientDateRange: HomeQueryDateRange(startDate: start, endDate: end),
            defaultBudgetingPeriod: .monthly,
            now: start,
            calendar: utcCalendar
        )
        let formulaRegistry = MarinaFormulaRegistry(now: start, calendar: utcCalendar)
        let bridge = MarinaSemanticUniversalPlanBridge(formulaRegistry: formulaRegistry)
        let runner = MarinaUniversalQueryRunner(formulaRegistry: formulaRegistry)
        func page(offset: Int) throws -> MarinaUniversalRowsPage {
            let request = MarinaSemanticRequest(
                entity: .category,
                operation: .list,
                measure: .categoryAvailability,
                resultLimit: 20,
                resultOffset: offset,
                categoryAvailabilityFilter: .over,
                expectedAnswerShape: .list
            )
            let plan = try requirePlan(bridge.makePlan(from: request, planningContext: planningContext))
            guard case let .rowsPage(page) = runner.runFormulaAware(plan: plan, snapshot: snapshot) else {
                Issue.record("Expected formula-backed rows page.")
                throw ExecutionTestError.expectedPlan
            }
            return page
        }

        let first = try page(offset: 0)
        let second = try page(offset: 20)
        #expect(first.rows.count == 20)
        #expect(first.totalRowCount == 25)
        #expect(first.hasMore)
        #expect(first.nextOffset == 20)
        #expect(first.fullTotalAmount == 3_000)
        #expect(second.rows.count == 5)
        #expect(second.totalRowCount == 25)
        #expect(second.hasMore == false)
        #expect(second.nextOffset == nil)
        #expect(Set(first.rows.map(\.id)).isDisjoint(with: Set(second.rows.map(\.id))))
    }

    private func makeFixture() -> ExecutionFixture {
        let rangeStart = Date(timeIntervalSince1970: 1_783_036_800)
        let firstDate = rangeStart.addingTimeInterval(86400 * 4)
        let firstHalfEnd = rangeStart.addingTimeInterval(86400 * 14)
        let secondDate = rangeStart.addingTimeInterval(86400 * 19)
        let rangeEnd = rangeStart.addingTimeInterval(86400 * 30)

        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let budget = Budget(name: "July", startDate: rangeStart, endDate: rangeEnd, workspace: workspace)
        let cardA = Card(name: "Everyday", workspace: workspace)
        let cardB = Card(name: "Travel", workspace: workspace)
        let primaryCategory = Offshore.Category(name: "Groceries", hexColor: "#111111", workspace: workspace)
        let duplicateCategory = Offshore.Category(name: "Groceries", hexColor: "#222222", workspace: workspace)
        let cardLinkA = BudgetCardLink(budget: budget, card: cardA)
        let cardLinkB = BudgetCardLink(budget: budget, card: cardB)
        budget.cardLinks = [cardLinkA, cardLinkB]

        let preset = Preset(title: "Monthly bill", plannedAmount: 100, workspace: workspace, defaultCard: cardA)
        let presetLink = BudgetPresetLink(budget: budget, preset: preset)
        budget.presetLinks = [presetLink]
        preset.budgetPresetLinks = [presetLink]

        let plannedExpenses = [
            planned("First A", 100, firstDate, workspace, cardA, primaryCategory, budget),
            planned("Second A", 200, secondDate, workspace, cardA, primaryCategory, budget),
            planned("First B", 70, firstDate, workspace, cardB, primaryCategory, budget),
            planned("Duplicate", 40, firstDate, workspace, cardA, duplicateCategory, budget)
        ]
        let variableExpenses = [
            variable("Variable A first", 20, firstDate, workspace, cardA, primaryCategory),
            variable("Variable A second", 30, secondDate, workspace, cardA, primaryCategory),
            variable("Variable B", 50, firstDate, workspace, cardB, primaryCategory),
            variable("Variable duplicate", 60, firstDate, workspace, cardA, duplicateCategory)
        ]

        let savingsAccount = SavingsAccount(name: "Emergency", workspace: workspace)
        let savingsEntry = SavingsLedgerEntry(
            date: firstDate,
            amount: 25,
            note: "Deposit",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: savingsAccount
        )
        let incomeSeries = IncomeSeries(
            source: "Salary",
            amount: 2_000,
            isPlanned: true,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 5,
            monthlyIsLastDay: false,
            yearlyMonth: 1,
            yearlyDayOfMonth: 5,
            startDate: rangeStart,
            endDate: rangeEnd,
            workspace: workspace
        )
        let occurrence = Income(
            source: "Salary",
            amount: 2_000,
            date: firstDate,
            isPlanned: true,
            workspace: workspace,
            series: incomeSeries
        )

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [cardA, cardB],
            categories: [primaryCategory, duplicateCategory],
            presets: [preset],
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            homePlannedExpenses: plannedExpenses,
            homeCalculationPlannedExpenses: plannedExpenses,
            homeCalculationVariableExpenses: variableExpenses,
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [savingsAccount],
            savingsEntries: [savingsEntry],
            incomes: [occurrence],
            incomeSeries: [incomeSeries]
        )

        return ExecutionFixture(
            snapshot: snapshot,
            workspace: workspace,
            budget: budget,
            cardA: cardA,
            cardB: cardB,
            primaryCategory: primaryCategory,
            duplicateCategory: duplicateCategory,
            preset: preset,
            savingsAccount: savingsAccount,
            savingsEntry: savingsEntry,
            incomeSeries: incomeSeries,
            occurrence: occurrence,
            rangeStart: rangeStart,
            firstHalfEnd: firstHalfEnd
        )
    }

    private func planned(
        _ title: String,
        _ amount: Double,
        _ date: Date,
        _ workspace: Workspace,
        _ card: Card,
        _ category: Offshore.Category,
        _ budget: Budget
    ) -> PlannedExpense {
        PlannedExpense(
            title: title,
            plannedAmount: amount,
            expenseDate: date,
            workspace: workspace,
            card: card,
            category: category,
            sourceBudgetID: budget.id
        )
    }

    private func variable(
        _ title: String,
        _ amount: Double,
        _ date: Date,
        _ workspace: Workspace,
        _ card: Card,
        _ category: Offshore.Category
    ) -> VariableExpense {
        VariableExpense(
            descriptionText: title,
            amount: amount,
            transactionDate: date,
            workspace: workspace,
            card: card,
            category: category
        )
    }

    private func constraint(
        _ dimension: MarinaSemanticDimension,
        _ value: String,
        _ entity: MarinaSemanticEntity,
        _ id: UUID
    ) -> MarinaSemanticConstraint {
        MarinaSemanticConstraint(
            dimension: dimension,
            value: value,
            resolvedReference: reference(entity, id, value)
        )
    }

    private func reference(
        _ entity: MarinaSemanticEntity,
        _ id: UUID,
        _ name: String
    ) -> MarinaResolvedEntityReference {
        MarinaResolvedEntityReference(
            entity: entity,
            id: id,
            displayName: name,
            provenance: .candidateResolver
        )
    }

    private func requirePlan(
        _ result: MarinaSemanticUniversalPlanBridgeResult
    ) throws -> MarinaUniversalQueryPlan {
        guard case let .plan(plan) = result else {
            Issue.record("Expected plan, got \(result).")
            throw ExecutionTestError.expectedPlan
        }
        return plan
    }

    private func requireMetric(
        _ result: MarinaUniversalQueryResult
    ) -> MarinaUniversalMetricResult {
        guard case let .metric(metric) = result else {
            Issue.record("Expected metric, got \(result).")
            return MarinaUniversalMetricResult(value: .empty, evidenceRows: [])
        }
        return metric
    }

    private func rowIDs(
        _ result: MarinaUniversalQueryResult
    ) -> [UUID] {
        switch result {
        case let .rows(rows):
            return rows.map(\.id)
        case let .rowsPage(page):
            return page.rows.map(\.id)
        default:
            Issue.record("Expected rows, got \(result).")
            return []
        }
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }
}

private struct ExecutionFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let workspace: Workspace
    let budget: Budget
    let cardA: Card
    let cardB: Card
    let primaryCategory: Offshore.Category
    let duplicateCategory: Offshore.Category
    let preset: Preset
    let savingsAccount: SavingsAccount
    let savingsEntry: SavingsLedgerEntry
    let incomeSeries: IncomeSeries
    let occurrence: Income
    let rangeStart: Date
    let firstHalfEnd: Date
}

private enum ExecutionTestError: Error {
    case expectedPlan
}
