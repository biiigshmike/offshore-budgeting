import Foundation
import SwiftData
import Testing
@testable import Offshore

@Suite(.serialized)
@MainActor
struct MarinaSemanticPromptSuiteTests {
    private struct PromptCase {
        let prompt: String
        let entity: MarinaSemanticEntity
        let operation: MarinaSemanticOperation
        let measure: MarinaSemanticMeasure?
        let shape: MarinaSemanticAnswerShape
        let categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter?
        let source: MarinaSemanticSource
        let confidence: MarinaSemanticConfidence

        init(
            prompt: String,
            entity: MarinaSemanticEntity,
            operation: MarinaSemanticOperation,
            measure: MarinaSemanticMeasure?,
            shape: MarinaSemanticAnswerShape,
            categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
            source: MarinaSemanticSource = .ruleBased,
            confidence: MarinaSemanticConfidence = .high
        ) {
            self.prompt = prompt
            self.entity = entity
            self.operation = operation
            self.measure = measure
            self.shape = shape
            self.categoryAvailabilityFilter = categoryAvailabilityFilter
            self.source = source
            self.confidence = confidence
        }
    }

    private struct AnswerCase {
        let prompt: String
        let kind: HomeAnswerKind
    }

    private struct Fixture {
        let context: ModelContext
        let workspace: Workspace
        let currentRange: HomeQueryDateRange
        let now: Date
    }

    @Test func promptSuite_parsesIntoUniversalSemanticRequests() throws {
        let interpreter = MarinaRuleBasedInterpreter()
        let planner = MarinaQueryPlanner()
        let cases: [PromptCase] = [
            .init(prompt: "What workspace am I in?", entity: .workspace, operation: .list, measure: .name, shape: .metric),
            .init(prompt: "What is the name of this workspace?", entity: .workspace, operation: .list, measure: .name, shape: .metric),
            .init(prompt: "What is this workspace's color?", entity: .workspace, operation: .list, measure: .color, shape: .metric),
            .init(prompt: "What is my top category this month?", entity: .category, operation: .group, measure: .budgetImpact, shape: .list),
            .init(prompt: "What preset is due next?", entity: .preset, operation: .next, measure: .plannedAmount, shape: .metric),
            .init(prompt: "What presets have an actual amount greater than 0 this month?", entity: .preset, operation: .list, measure: .actualAmount, shape: .list),
            .init(prompt: "Which category has the most presets assigned to it?", entity: .preset, operation: .group, measure: .plannedAmount, shape: .list),
            .init(prompt: "How many cards do I have?", entity: .card, operation: .count, measure: nil, shape: .metric),
            .init(prompt: "What is my Apple Card spend this month?", entity: .card, operation: .sum, measure: .budgetImpact, shape: .metric),
            .init(prompt: "Compare Apple Card spend to Chase spend", entity: .card, operation: .compare, measure: .budgetImpact, shape: .comparison),
            .init(prompt: "What is my Target spend this month?", entity: .variableExpense, operation: .sum, measure: .budgetImpact, shape: .metric),
            .init(prompt: "When did I last go shopping at Target?", entity: .variableExpense, operation: .last, measure: .budgetImpact, shape: .metric),
            .init(prompt: "List my most recent 5 expenses on Apple Card", entity: .variableExpense, operation: .list, measure: .budgetImpact, shape: .list),
            .init(prompt: "What is Alejandro's balance for the current period?", entity: .reconciliationAccount, operation: .sum, measure: .reconciliationBalance, shape: .metric),
            .init(prompt: "How much did Alejandro spend on Groceries for the current period?", entity: .reconciliationAccount, operation: .sum, measure: .reconciliationBalance, shape: .metric),
            .init(prompt: "What is my current Savings Account balance?", entity: .savingsAccount, operation: .sum, measure: .savingsTotal, shape: .metric),
            .init(prompt: "What is my projected savings for the current period?", entity: .savingsAccount, operation: .forecast, measure: .savingsTotal, shape: .metric),
            .init(prompt: "What is my actual income for this month?", entity: .income, operation: .sum, measure: .incomeAmount, shape: .metric),
            .init(prompt: "Compare my actual income this month to last month. Am I up or down?", entity: .income, operation: .compare, measure: .incomeAmount, shape: .comparison),
            .init(prompt: "What is my Actual Income to Planned Income percentage?", entity: .income, operation: .share, measure: .incomeAmount, shape: .metric),
            .init(prompt: "How is my income progress?", entity: .income, operation: .share, measure: .incomeAmount, shape: .metric),
            .init(prompt: "How is my budget for this period?", entity: .budget, operation: .forecast, measure: .budgetImpact, shape: .metric),
            .init(prompt: "What is my safe spend today?", entity: .budget, operation: .forecast, measure: .remainingRoom, shape: .metric),
            .init(prompt: "What is my burn rate?", entity: .budget, operation: .average, measure: .burnRate, shape: .metric),
            .init(prompt: "Where will I end up on projected spend?", entity: .budget, operation: .forecast, measure: .projectedSpend, shape: .metric),
            .init(prompt: "What can I spend per day?", entity: .budget, operation: .forecast, measure: .safeDailySpend, shape: .metric),
            .init(prompt: "Am I spending too fast?", entity: .budget, operation: .compare, measure: .paceDifference, shape: .comparison),
            .init(prompt: "Does my income cover planned expenses?", entity: .income, operation: .share, measure: .coverageRatio, shape: .metric),
            .init(prompt: "What is my recurring burden?", entity: .preset, operation: .sum, measure: .recurringBurden, shape: .metric),
            .init(prompt: "What is eating my budget?", entity: .category, operation: .share, measure: .concentration, shape: .metric),
            .init(prompt: "See the expenses driving my spend trends.", entity: .variableExpense, operation: .list, measure: .budgetImpact, shape: .list),
            .init(prompt: "Compare this budget period to last period.", entity: .budget, operation: .compare, measure: .budgetImpact, shape: .comparison),
            .init(prompt: "If I spend $50 at Target, what happens to my safe spend?", entity: .budget, operation: .whatIf, measure: .remainingRoom, shape: .comparison),
            .init(prompt: "If I spend $200 on Groceries, what happens to projected savings?", entity: .budget, operation: .whatIf, measure: .savingsTotal, shape: .comparison),
            .init(prompt: "Show my savings outlook.", entity: .savingsAccount, operation: .forecast, measure: .savingsTotal, shape: .metric),
            .init(prompt: "Show category availability.", entity: .category, operation: .forecast, measure: .categoryAvailability, shape: .metric),
            .init(prompt: "Which 5 categories are over limit?", entity: .category, operation: .list, measure: .categoryAvailability, shape: .list, categoryAvailabilityFilter: .over),
            .init(prompt: "Which categories are near limit?", entity: .category, operation: .list, measure: .categoryAvailability, shape: .list, categoryAvailabilityFilter: .near),
            .init(prompt: "List categories under limit.", entity: .category, operation: .list, measure: .categoryAvailability, shape: .list, categoryAvailabilityFilter: .underLimit),
            .init(prompt: "Show category spotlight.", entity: .category, operation: .group, measure: .budgetImpact, shape: .list),
            .init(prompt: "What are my spend trends?", entity: .category, operation: .group, measure: .budgetImpact, shape: .list),
            .init(prompt: "What is my next planned expense?", entity: .plannedExpense, operation: .next, measure: .effectiveAmount, shape: .metric),
            .init(prompt: "Summarize my Apple Card.", entity: .card, operation: .sum, measure: .budgetImpact, shape: .metric)
        ]

        for testCase in cases {
            let interpreted = interpreter.interpretWithConfidence(testCase.prompt)
            let request = interpreted.request
            let plan = planner.plan(
                request: request,
                ambientDateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
                defaultBudgetingPeriod: .monthly,
                now: date(2026, 4, 20)
            )
            #expect(interpreted.source == testCase.source, "Source mismatch for \(testCase.prompt)")
            #expect(interpreted.confidence == testCase.confidence, "Confidence mismatch for \(testCase.prompt)")
            #expect(request.entity == testCase.entity, "Entity mismatch for \(testCase.prompt)")
            #expect(request.operation == testCase.operation, "Operation mismatch for \(testCase.prompt)")
            #expect(request.measure == testCase.measure, "Measure mismatch for \(testCase.prompt)")
            #expect(request.expectedAnswerShape == testCase.shape, "Shape mismatch for \(testCase.prompt)")
            #expect(request.categoryAvailabilityFilter == testCase.categoryAvailabilityFilter, "Category availability filter mismatch for \(testCase.prompt)")
            #expect(plan.entity == testCase.entity, "Plan entity mismatch for \(testCase.prompt)")
            #expect(plan.operation == testCase.operation, "Plan operation mismatch for \(testCase.prompt)")
        }
    }

    @Test func queryPlanner_currentMonthUsesAmbientRangeForComparisonsAndFormulas() throws {
        let planner = MarinaQueryPlanner()
        let ambientRange = HomeQueryDateRange(
            startDate: date(2026, 6, 1),
            endDate: date(2026, 6, 30)
        )
        let now = date(2026, 4, 20)

        let comparisonPlan = planner.plan(
            request: MarinaSemanticRequest(
                entity: .income,
                operation: .compare,
                measure: .incomeAmount,
                dateRangeToken: .currentMonth,
                expectedAnswerShape: .comparison
            ),
            ambientDateRange: ambientRange,
            defaultBudgetingPeriod: .monthly,
            now: now
        )

        #expect(comparisonPlan.dateRange?.startDate == date(2026, 6, 1))
        #expect(comparisonPlan.dateRange?.endDate == date(2026, 6, 30))
        #expect(comparisonPlan.comparisonDateRange?.startDate == date(2026, 5, 2))
        #expect(comparisonPlan.comparisonDateRange?.endDate == date(2026, 5, 31))

        let formulaPlan = planner.plan(
            request: MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .safeDailySpend,
                dateRangeToken: .currentMonth,
                expectedAnswerShape: .metric
            ),
            ambientDateRange: ambientRange,
            defaultBudgetingPeriod: .monthly,
            now: now
        )

        #expect(formulaPlan.dateRange?.startDate == date(2026, 6, 1))
        #expect(formulaPlan.dateRange?.endDate == date(2026, 6, 30))
        #expect(formulaPlan.comparisonDateRange == nil)
    }

    @Test func queryPlanner_yearToDateUsesCalendarYearThroughToday() throws {
        let planner = MarinaQueryPlanner(calendar: Calendar(identifier: .gregorian))
        let now = date(2026, 4, 20)

        let plan = planner.plan(
            request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                dateRangeToken: .yearToDate,
                expectedAnswerShape: .metric
            ),
            ambientDateRange: HomeQueryDateRange(
                startDate: date(2026, 4, 1),
                endDate: date(2026, 4, 30)
            ),
            defaultBudgetingPeriod: .monthly,
            now: now
        )

        #expect(plan.dateRange?.startDate == date(2026, 1, 1))
        #expect(plan.dateRange?.endDate == date(2026, 4, 20))
    }

    @Test func promptSuite_executesEveryInAppQuestionPhrase() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let cases: [AnswerCase] = [
            .init(prompt: "What workspace am I in?", kind: .metric),
            .init(prompt: "What is the name of this workspace?", kind: .metric),
            .init(prompt: "What is this workspace's color?", kind: .metric),
            .init(prompt: "What is my top category this month?", kind: .list),
            .init(prompt: "What preset is due next?", kind: .metric),
            .init(prompt: "What presets have an actual amount greater than 0 this month?", kind: .list),
            .init(prompt: "Which category has the most presets assigned to it?", kind: .list),
            .init(prompt: "How many cards do I have?", kind: .metric),
            .init(prompt: "What is my Apple Card spend this month?", kind: .metric),
            .init(prompt: "Compare Apple Card spend to Chase spend", kind: .comparison),
            .init(prompt: "What is my Target spend this month?", kind: .metric),
            .init(prompt: "When did I last go shopping at Target?", kind: .metric),
            .init(prompt: "List my most recent 5 expenses on Apple Card", kind: .list),
            .init(prompt: "What is Alejandro's balance for the current period?", kind: .metric),
            .init(prompt: "How much did Alejandro spend on Groceries for the current period?", kind: .metric),
            .init(prompt: "What is my current Savings Account balance?", kind: .metric),
            .init(prompt: "What is my projected savings for the current period?", kind: .metric),
            .init(prompt: "What is my actual income for this month?", kind: .metric),
            .init(prompt: "Compare my actual income this month to last month. Am I up or down?", kind: .comparison),
            .init(prompt: "What is my Actual Income to Planned Income percentage?", kind: .metric),
            .init(prompt: "How is my income progress?", kind: .metric),
            .init(prompt: "How is my budget for this period?", kind: .list),
            .init(prompt: "What is my safe spend today?", kind: .metric),
            .init(prompt: "What is my burn rate?", kind: .metric),
            .init(prompt: "Where will I end up on projected spend?", kind: .metric),
            .init(prompt: "What can I spend per day?", kind: .metric),
            .init(prompt: "Am I spending too fast?", kind: .comparison),
            .init(prompt: "Does my income cover planned expenses?", kind: .metric),
            .init(prompt: "What is my recurring burden?", kind: .metric),
            .init(prompt: "What is eating my budget?", kind: .metric),
            .init(prompt: "See the expenses driving my spend trends.", kind: .list),
            .init(prompt: "Compare this budget period to last period.", kind: .comparison),
            .init(prompt: "If I spend $50 at Target, what happens to my safe spend?", kind: .comparison),
            .init(prompt: "If I spend $200 on Groceries, what happens to projected savings?", kind: .comparison),
            .init(prompt: "Show my savings outlook.", kind: .metric),
            .init(prompt: "Show category availability.", kind: .metric),
            .init(prompt: "Show category spotlight.", kind: .list),
            .init(prompt: "What are my spend trends?", kind: .list),
            .init(prompt: "What is my next planned expense?", kind: .metric),
            .init(prompt: "Summarize my Apple Card.", kind: .metric)
        ]

        for testCase in cases {
            let answer = await answer(testCase.prompt, using: brain, fixture: fixture)
            #expect(answer.kind == testCase.kind, "Answer kind mismatch for \(testCase.prompt): \(answer.title)")
            #expect(answer.title.isEmpty == false, "Missing title for \(testCase.prompt)")
        }
    }

    @Test func promptSuite_formulaPhraseVariantsMapToDeterministicMeasures() throws {
        let interpreter = MarinaRuleBasedInterpreter()
        let cases: [(prompt: String, entity: MarinaSemanticEntity, operation: MarinaSemanticOperation, measure: MarinaSemanticMeasure)] = [
            ("What is my daily spend?", .budget, .average, .burnRate),
            ("Show my spending rate.", .budget, .average, .burnRate),
            ("Where will I end up?", .budget, .forecast, .projectedSpend),
            ("Am I on track to spend too much?", .budget, .forecast, .projectedSpend),
            ("What's my daily allowance?", .budget, .forecast, .safeDailySpend),
            ("Show my safe per day.", .budget, .forecast, .safeDailySpend),
            ("Am I ahead?", .budget, .compare, .paceDifference),
            ("Am I behind?", .budget, .compare, .paceDifference),
            ("Are expenses covered by income?", .income, .share, .coverageRatio),
            ("Show fixed expenses.", .preset, .sum, .recurringBurden),
            ("Show preset burden.", .preset, .sum, .recurringBurden),
            ("Which category has the biggest share?", .category, .share, .concentration)
        ]

        for testCase in cases {
            let request = interpreter.interpret(testCase.prompt)
            #expect(request.entity == testCase.entity, "Entity mismatch for \(testCase.prompt)")
            #expect(request.operation == testCase.operation, "Operation mismatch for \(testCase.prompt)")
            #expect(request.measure == testCase.measure, "Measure mismatch for \(testCase.prompt)")
        }
    }

    @Test func promptSuite_plansAndExecutesRepresentativeAnswers() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()

        let cardCount = await answer("How many cards do I have?", using: brain, fixture: fixture)
        #expect(cardCount.kind == .metric)
        #expect(cardCount.primaryValue == "2")

        let appleSpend = await answer("What is my Apple Card spend this month?", using: brain, fixture: fixture)
        #expect(appleSpend.kind == .metric)
        #expect((appleSpend.primaryValue ?? "").contains("1,370") || (appleSpend.primaryValue ?? "").contains("1370"))
        #expect(appleSpend.rows.contains(where: { $0.title == "Planned" }))
        #expect(appleSpend.rows.contains(where: { $0.title == "Variable" }))

        let targetLast = await answer("When did I last go shopping at Target?", using: brain, fixture: fixture)
        #expect(targetLast.kind == .metric)
        #expect(targetLast.rows.contains(where: { $0.title.contains("Target") }))

        let reconciliation = await answer("What is Alejandro's balance for the current period?", using: brain, fixture: fixture)
        #expect(reconciliation.kind == .metric)
        #expect((reconciliation.primaryValue ?? "").contains("40"))

        let monthlyReconciliation = await answer("What is Alejandro's balance for the current month?", using: brain, fixture: fixture)
        #expect(monthlyReconciliation.kind == .metric)
        #expect((monthlyReconciliation.primaryValue ?? "").contains("40"))

        let allTimeReconciliation = await answer("What is Alejandro's balance?", using: brain, fixture: fixture)
        #expect(allTimeReconciliation.kind == .metric)
        #expect((allTimeReconciliation.primaryValue ?? "").contains("50"))

        let reconciliationSpend = await answer("How much did Alejandro spend on Groceries for the current period?", using: brain, fixture: fixture)
        #expect(reconciliationSpend.kind == .metric)
        #expect((reconciliationSpend.primaryValue ?? "").contains("40"))

        let presetCategory = await answer("What presets are tied to Groceries?", using: brain, fixture: fixture)
        #expect(presetCategory.kind == .list)
        #expect(presetCategory.rows.contains(where: { $0.title == "Grocery Envelope" }))

        let savingsMonth = await answer("What is my Savings Account balance this month?", using: brain, fixture: fixture)
        #expect(savingsMonth.kind == .metric)
        #expect(savingsMonth.title == "Savings Status")

        let incomeShare = await answer("What is my Actual Income to Planned Income percentage?", using: brain, fixture: fixture)
        #expect(incomeShare.kind == .metric)
        #expect((incomeShare.primaryValue ?? "").contains("93"))

        let whatIf = await answer("If I spend $50 at Target, what happens to my safe spend?", using: brain, fixture: fixture)
        #expect(whatIf.kind == .comparison)
        #expect((whatIf.primaryValue ?? "").contains("113.18"))
        #expect(whatIf.rows.contains(where: { $0.title == "Current safe spend today" }))
        #expect(whatIf.rows.contains(where: { $0.title == "Virtual spend" }))
        let safeSpendAfter = whatIf.rows.first(where: { $0.title == "Safe spend after" })?.amount ?? -1
        let periodRoomAfter = whatIf.rows.first(where: { $0.title == "Period room after" })?.amount
        #expect(abs(safeSpendAfter - 113.18181818181819) < 0.0001)
        #expect(periodRoomAfter == 1_245)

        let categoryAvailability = await answer("Show category availability.", using: brain, fixture: fixture)
        #expect(categoryAvailability.kind == .metric)
        #expect(categoryAvailability.title == "Category Availability")
        let categoryAvailabilityHasOverRow = categoryAvailability.rows.contains { row in
            row.title == "Over" && row.value == "0"
        }
        #expect(categoryAvailabilityHasOverRow)

        let nextPlanned = await answer("What is my next planned expense?", using: brain, fixture: fixture)
        #expect(nextPlanned.kind == .metric)
        let nextPlannedHasExpenseRow = nextPlanned.rows.contains { row in
            row.title == "Expense" && row.value == "Phone"
        }
        #expect(nextPlannedHasExpenseRow)
    }

    @Test func budgetFormulaCalculator_returnsExpectedValuesAndNilForInvalidInputs() throws {
        #expect(MarinaBudgetFormulaCalculator.burnRate(actualSpend: 1_715, elapsedDays: 20) == 85.75)
        #expect(MarinaBudgetFormulaCalculator.burnRate(actualSpend: 1_715, elapsedDays: 0) == nil)

        #expect(MarinaBudgetFormulaCalculator.projectedSpend(burnRate: 85.75, totalDays: 30) == 2_572.5)
        #expect(MarinaBudgetFormulaCalculator.projectedSpend(burnRate: 85.75, totalDays: 0) == nil)

        let safeDailySpend = try #require(MarinaBudgetFormulaCalculator.safeDailySpend(remainingRoom: 1_295, remainingDays: 11))
        #expect(abs(safeDailySpend - 117.72727272727273) < 0.0001)
        #expect(MarinaBudgetFormulaCalculator.safeDailySpend(remainingRoom: 1_295, remainingDays: 0) == nil)

        let paceDifference = try #require(MarinaBudgetFormulaCalculator.paceDifference(actualSpend: 1_715, plannedSpend: 1_490, elapsedPercent: 20.0 / 30.0))
        #expect(abs(paceDifference - 721.6666666666667) < 0.0001)
        #expect(MarinaBudgetFormulaCalculator.paceDifference(actualSpend: 1_715, plannedSpend: 1_490, elapsedPercent: -0.1) == nil)

        let coverageRatio = try #require(MarinaBudgetFormulaCalculator.coverageRatio(income: 3_000, plannedExpenses: 1_490))
        #expect(abs(coverageRatio - 2.0134228187919465) < 0.0001)
        #expect(MarinaBudgetFormulaCalculator.coverageRatio(income: 3_000, plannedExpenses: 0) == nil)

        #expect(MarinaBudgetFormulaCalculator.recurringBurden(recurringTotal: 1_490, plannedExpenseTotal: 1_490) == 1)
        #expect(MarinaBudgetFormulaCalculator.recurringBurden(recurringTotal: 1_490, plannedExpenseTotal: 0) == nil)

        let concentration = try #require(MarinaBudgetFormulaCalculator.concentration(partTotal: 1_590, wholeTotal: 1_805))
        #expect(abs(concentration - 0.8808864265927978) < 0.0001)
        #expect(MarinaBudgetFormulaCalculator.concentration(partTotal: 1_590, wholeTotal: 0) == nil)
    }

    @Test func formulaAnswers_explainDeterministicBudgetMath() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()

        let burnRate = await answer("What is my burn rate?", using: brain, fixture: fixture)
        #expect(burnRate.kind == .metric)
        #expect(burnRate.title == "Budget Pace")
        #expect(burnRate.primaryValue == CurrencyFormatter.string(from: 85.75))
        #expect(burnRate.rows.first(where: { $0.title == "Spent so far" })?.amount == 1_715)
        #expect(burnRate.rows.first(where: { $0.title == "Elapsed days" })?.amount == 20)
        #expect(burnRate.rows.first(where: { $0.title == "Average per day" })?.amount == 85.75)

        let projectedSpend = await answer("Where will I end up on projected spend?", using: brain, fixture: fixture)
        #expect(projectedSpend.kind == .metric)
        #expect(projectedSpend.title == "Projected Spend")
        #expect(projectedSpend.primaryValue == CurrencyFormatter.string(from: 2_572.5))
        #expect(projectedSpend.rows.first(where: { $0.title == "Spent so far" })?.amount == 1_715)
        #expect(projectedSpend.rows.first(where: { $0.title == "Average per day" })?.amount == 85.75)
        #expect(projectedSpend.rows.first(where: { $0.title == "Projected total" })?.amount == 2_572.5)

        let safeDailySpend = await answer("What can I spend per day?", using: brain, fixture: fixture)
        #expect(safeDailySpend.kind == .metric)
        #expect(safeDailySpend.title == "Safe Daily Spend")
        #expect(safeDailySpend.rows.first(where: { $0.title == "Remaining room" })?.amount == 1_295)
        #expect(safeDailySpend.rows.first(where: { $0.title == "Remaining days" })?.amount == 11)
        let safePerDay = try #require(safeDailySpend.rows.first(where: { $0.title == "Safe per day" })?.amount)
        #expect(abs(safePerDay - 117.72727272727273) < 0.0001)

        let pace = await answer("Am I spending too fast?", using: brain, fixture: fixture)
        #expect(pace.kind == .comparison)
        #expect(pace.title == "Pace Difference")
        #expect((pace.primaryValue ?? "").contains("721.67"))
        #expect(pace.rows.first(where: { $0.title == "Spent so far" })?.amount == 1_715)
        let expectedByNow = try #require(pace.rows.first(where: { $0.title == "Expected by now" })?.amount)
        #expect(abs(expectedByNow - 993.3333333333333) < 0.0001)
        let paceDifference = try #require(pace.rows.first(where: { $0.title == "Pace difference" })?.amount)
        #expect(abs(paceDifference - 721.6666666666667) < 0.0001)

        let coverage = await answer("Does my income cover planned expenses?", using: brain, fixture: fixture)
        #expect(coverage.kind == .metric)
        #expect(coverage.title == "Income Coverage")
        #expect(coverage.primaryValue == (3_000.0 / 1_490.0).formatted(.percent.precision(.fractionLength(1))))
        #expect(coverage.rows.first(where: { $0.title == "Income" })?.amount == 3_000)
        #expect(coverage.rows.first(where: { $0.title == "Planned expenses" })?.amount == 1_490)
        let coveragePercent = try #require(coverage.rows.first(where: { $0.title == "Coverage percent" })?.amount)
        #expect(abs(coveragePercent - (3_000.0 / 1_490.0)) < 0.0001)
        #expect(coverage.rows.first(where: { $0.title == "Difference" })?.amount == 1_510)

        let recurringBurden = await answer("What is my recurring burden?", using: brain, fixture: fixture)
        #expect(recurringBurden.kind == .metric)
        #expect(recurringBurden.title == "Recurring Burden")
        #expect(recurringBurden.primaryValue == 1.0.formatted(.percent.precision(.fractionLength(1))))
        #expect(recurringBurden.rows.first(where: { $0.title == "Recurring total" })?.amount == 1_490)
        #expect(recurringBurden.rows.first(where: { $0.title == "Planned expenses" })?.amount == 1_490)
        #expect(recurringBurden.rows.first(where: { $0.title == "Recurring burden" })?.amount == 1)

        let concentration = await answer("What is eating my budget?", using: brain, fixture: fixture)
        #expect(concentration.kind == .metric)
        #expect(concentration.title == "Category Spend Share")
        #expect(concentration.primaryValue == (1_590.0 / 1_805.0).formatted(.percent.precision(.fractionLength(1))))
        #expect(concentration.rows.first(where: { $0.title == "Category" })?.value == "Bills")
        #expect(concentration.rows.first(where: { $0.title == "Category spend" })?.amount == 1_590)
        #expect(concentration.rows.first(where: { $0.title == "Total spend" })?.amount == 1_805)
        let concentrationRatio = try #require(concentration.rows.first(where: { $0.title == "Concentration" })?.amount)
        #expect(abs(concentrationRatio - (1_590.0 / 1_805.0)) < 0.0001)
    }

    @Test func incomeSavingsWhatIfFollowUpPreservesAmountAndReturnsTypedUnsupported() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()

        let baseline = await seed("What is the amount of income I need to break even on my savings this month?", using: brain, fixture: fixture)
        let followUp = await seed(
            "What if I saved 4,000 this month?",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [baseline.answer])
        )

        #expect(followUp.debugTrace?.promptTreatment == .standalone)
        #expect(followUp.debugTrace?.validatorOutput.operation == .whatIf)
        #expect(followUp.debugTrace?.validatorOutput.whatIfAmount == 4_000)
        #expect(followUp.debugTrace?.validatorOutput.unsupportedReason == .incomeSavingsWhatIfUnsupported)
        #expect(followUp.answer.kind == .message)
        #expect(followUp.answer.title == "I can't answer that yet")
        #expect(followUp.answer.title != "Income Coverage")
        #expect(followUp.answer.primaryValue == nil)
    }

    @Test func incomeSavingsWhatIfAuditedPhrasesPreserveScenarioAmount() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let cases: [(String, MarinaSemanticEntity, Double)] = [
            ("What if I earned 5,000?", .income, 5_000),
            ("What if I only earned $4,250.50?", .income, 4_250.50),
            ("What if income was 3200?", .income, 3_200),
            ("What if I saved 4,000?", .savingsAccount, 4_000),
            ("What if I only saved $750?", .savingsAccount, 750),
            ("What if savings were 1,250.25?", .savingsAccount, 1_250.25)
        ]

        for (prompt, entity, amount) in cases {
            let result = await seed(prompt, using: brain, fixture: fixture)
            #expect(result.debugTrace?.validatorOutput.entity == entity, "\(prompt)")
            #expect(result.debugTrace?.validatorOutput.operation == .whatIf, "\(prompt)")
            #expect(result.debugTrace?.validatorOutput.whatIfAmount == amount, "\(prompt)")
            #expect(result.debugTrace?.validatorOutput.unsupportedReason == .incomeSavingsWhatIfUnsupported, "\(prompt)")
            #expect(result.answer.kind == .message, "\(prompt)")
        }
    }

    @Test func resolver_cardSummaryPhrasesResolveSameWorkspaceCardTarget() async throws {
        let fixture = try makeFixture(includeDebitCard: true)
        let brain = legacyRuleBasedBrain()

        let prompts = [
            "Summarize my Debit Card.",
            "Debit Card spend",
            "What is my Debit Card spend this period?"
        ]

        for prompt in prompts {
            let cardAnswer = await answer(prompt, using: brain, fixture: fixture)
            #expect(cardAnswer.kind == .metric, "Expected metric for \(prompt), got \(cardAnswer.kind)")
            #expect(cardAnswer.title == "Debit Card Spend", "Wrong title for \(prompt): \(cardAnswer.title)")
            #expect(cardAnswer.primaryValue == CurrencyFormatter.string(from: 100), "Wrong value for \(prompt): \(cardAnswer.primaryValue ?? "nil")")
            let hasPlannedRow = cardAnswer.rows.contains { row in
                row.title == "Planned" && row.amount == 70
            }
            let hasVariableRow = cardAnswer.rows.contains { row in
                row.title == "Variable" && row.amount == 30
            }
            #expect(hasPlannedRow)
            #expect(hasVariableRow)
        }
    }

    @Test func resolver_phraseInvarianceWorksAcrossNonHardcodedEntityTypes() async throws {
        let fixture = try makeFixture(includeTransportationCategory: true)
        let brain = legacyRuleBasedBrain()

        let transportation = await answer("Summarize my Transportation.", using: brain, fixture: fixture)
        #expect(transportation.kind == .metric)
        #expect(transportation.title == "Transportation Spend")
        #expect((transportation.primaryValue ?? "").contains("60"))

        let paycheck = await answer("Paycheck income", using: brain, fixture: fixture)
        #expect(paycheck.kind == .metric)
        #expect(paycheck.title == "Paycheck Income")
        #expect((paycheck.primaryValue ?? "").contains("6,200") || (paycheck.primaryValue ?? "").contains("6200"))

        let savings = await answer("Summarize my Savings Account.", using: brain, fixture: fixture)
        #expect(savings.kind == .metric)
        #expect(savings.title == "Savings Account Balance")

        let balance = await answer("Alejandro balance", using: brain, fixture: fixture)
        #expect(balance.kind == .metric)
        #expect(balance.title == "Alejandro Balance")

        let merchant = await answer("Target spend", using: brain, fixture: fixture)
        #expect(merchant.kind == .metric)
        #expect(merchant.title == "Target groceries Spend")
        #expect((merchant.primaryValue ?? "").contains("40"))

        let preset = await answer("Summarize my Phone preset.", using: brain, fixture: fixture)
        #expect(preset.kind == .metric)
        #expect(preset.title == "Phone Preset")
        #expect(preset.primaryValue == CurrencyFormatter.string(from: 90))

        let budget = await answer("Summarize my April 2026 budget.", using: brain, fixture: fixture)
        #expect(budget.kind == .list)
        #expect(budget.title == "Budget Overview")
        #expect(budget.subtitle?.isEmpty == false)
    }

    @Test func resolver_unknownNamedTargetNeverFallsBackToAggregate() async throws {
        let fixture = try makeFixture(includeDebitCard: false)
        let brain = legacyRuleBasedBrain()

        let answer = await answer("Summarize my Debit Card.", using: brain, fixture: fixture)

        #expect(answer.kind == .message)
        #expect(answer.title == "I can't answer that yet")
        #expect(answer.subtitle?.contains("could not find") == true)
        #expect(answer.title != "Card Spend")
    }

    @Test func resolver_incomeComparisonDoesNotInventSourceFromComparisonWords() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let interpreter = MarinaRuleBasedInterpreter()
        let prompt = "Compare my actual income this month to last month. Am I up or down?"

        let interpreted = interpreter.interpret(prompt)
        #expect(interpreted.entity == .income)
        #expect(interpreted.operation == .compare)
        #expect(interpreted.targetName == nil)
        #expect(interpreted.dimensions.contains(.incomeSource) == false)

        let answer = await answer(prompt, using: brain, fixture: fixture)
        #expect(answer.kind == .comparison)
        #expect(answer.title == "Income Comparison")
    }

    @Test func starterPromptFactoryUsesWorkspaceCardsWithoutHardcodedAppleCard() throws {
        let noCardPrompts = MarinaStarterPromptFactory.promptPool(cardNames: [])
        #expect(noCardPrompts.contains("Summarize my Apple Card.") == false)

        let debitPrompts = MarinaStarterPromptFactory.promptPool(cardNames: ["Debit Card"])
        #expect(debitPrompts.contains("Summarize my Debit Card."))
        #expect(debitPrompts.contains("Summarize my Apple Card.") == false)
    }

    @Test func promptSuite_negativeCasesStaySafe() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let interpreter = MarinaRuleBasedInterpreter()

        let ambiguous = interpreter.interpret("How much did I spend on Apple?")
        #expect(ambiguous.entity == .variableExpense)
        #expect(ambiguous.targetName == "Apple")

        let readOnly = await answer("Delete my Apple Card expense", using: brain, fixture: fixture)
        #expect(readOnly.kind == .message)
        #expect(readOnly.title == "I can't answer that yet")
        #expect(readOnly.subtitle?.contains("read-only") == true)
        #expect(readOnly.subtitle?.contains("I'm") == true)
        #expect(readOnly.subtitle?.contains("Marina") == false)

        let unknown = await answer("What did I spend on Food?", using: brain, fixture: fixture)
        #expect(unknown.kind == .message)
        #expect(unknown.subtitle?.contains("could not find") == true)
    }

    @Test func clarification_appleMerchantOrCardStoresExecutableChoices() async throws {
        let fixture = try makeFixture(includeAppleMerchantExpense: true)
        let brain = legacyRuleBasedBrain()

        let clarification = await answer("How much did I spend on Apple?", using: brain, fixture: fixture)
        #expect(clarification.kind == .message)
        #expect(clarification.title == "Can you clarify?")

        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected clarification choices attachment.")
            return
        }

        #expect(choices.choices.map(\.title).contains("Apple Store"))
        #expect(choices.choices.map(\.title).contains("Apple Card"))
        #expect(choices.choice(matching: "Apple Store")?.kindLabel == "Expense match")
        #expect(choices.choice(matching: "Apple Card")?.kindLabel == "Card")
        #expect(choices.choices.contains { $0.title.contains("Text") } == false)

        let merchantChoice = try #require(choices.choice(matching: "merchant"))
        let merchantAnswer = await answer(merchantChoice.request, prompt: "merchant", using: brain, fixture: fixture)
        #expect(merchantAnswer.kind == .metric)
        #expect(merchantAnswer.title == "Apple Store Spend")
        #expect((merchantAnswer.primaryValue ?? "").contains("300"))

        let cardChoice = try #require(choices.choice(matching: "Apple Card"))
        let cardAnswer = await answer(cardChoice.request, prompt: "Apple Card", using: brain, fixture: fixture)
        #expect(cardAnswer.kind == .metric)
        #expect(cardAnswer.title == "Apple Card Spend")
    }

    @Test func resolver_appleCardOnlyDoesNotOfferSyntheticTextChoice() async throws {
        let fixture = try makeFixture(includeAppleMerchantExpense: false)
        let brain = legacyRuleBasedBrain()

        let answer = await answer("How much did I spend on Apple?", using: brain, fixture: fixture)

        #expect(answer.kind == .metric)
        #expect(answer.title == "Apple Card Spend")
        #expect(answer.attachment == nil)
    }

    @Test func resolver_groceryAmbiguityCreatesExecutableCategoryAndTextChoices() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()

        let clarification = await answer("How much did I spend on Grocery?", using: brain, fixture: fixture)
        #expect(clarification.kind == .message)
        #expect(clarification.title == "Can you clarify?")

        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected Grocery clarification choices.")
            return
        }

        #expect(choices.choices.map(\.title).contains("Groceries"))
        #expect(choices.choices.map(\.title).contains("Grocery Envelope"))
        #expect(choices.choices.map(\.title).contains("Target groceries"))
        #expect(choices.choices.map(\.title).contains("All expense matches for \"Grocery\""))
        #expect(choices.choice(matching: "category")?.kindLabel == "Category")
        #expect(choices.choice(matching: "Grocery Envelope")?.kindLabel == "Planned expense match")
        #expect(choices.choice(matching: "Target groceries")?.kindLabel == "Expense match")
        #expect(choices.choice(matching: "description")?.kindLabel == "Expense search")
        #expect(choices.choices.contains { $0.title.contains("Text") } == false)

        let categoryChoice = try #require(choices.choice(matching: "category"))
        let categoryAnswer = await answer(categoryChoice.request, prompt: "category", using: brain, fixture: fixture)
        #expect(categoryAnswer.kind == .metric)
        #expect(categoryAnswer.title == "Groceries Spend")
        #expect((categoryAnswer.primaryValue ?? "").contains("190"))

        let textChoice = try #require(choices.choice(matching: "description"))
        let textAnswer = await answer(textChoice.request, prompt: "description", using: brain, fixture: fixture)
        #expect(textAnswer.kind == .metric)
        #expect(textAnswer.title == "All expense matches for \"Grocery\" Spend")
        #expect((textAnswer.primaryValue ?? "").contains("190"))
    }

    @Test func resolver_expenseMatchChoiceUsesStoredTitleInButtonAndAnswer() async throws {
        let fixture = try makeFixture(includeGroceryOutletExpense: true)
        let brain = legacyRuleBasedBrain()

        let clarification = await answer("How much did I spend on Grocery?", using: brain, fixture: fixture)
        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected Grocery clarification choices.")
            return
        }

        let groceryOutletChoice = try #require(choices.choice(matching: "Grocery Outlet of Midt"))
        #expect(groceryOutletChoice.title == "Grocery Outlet of Midt")
        #expect(groceryOutletChoice.kindLabel == "Expense match")
        #expect(choices.choices.contains { $0.title.contains("Text") } == false)

        let answer = await answer(groceryOutletChoice.request, prompt: "Grocery Outlet of Midt", using: brain, fixture: fixture)
        #expect(answer.kind == .metric)
        #expect(answer.title == "Grocery Outlet of Midt Spend")
        #expect((answer.primaryValue ?? "").contains("42"))
    }

    @Test func resolver_multipleExpenseTextMatchesUsesExplicitAggregateChoice() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()

        let clarification = await answer("Show Grocery expenses", using: brain, fixture: fixture)
        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected Grocery list clarification choices.")
            return
        }

        let aggregate = try #require(choices.choice(matching: "description"))
        #expect(aggregate.title == "All expense matches for \"Grocery\"")
        #expect(aggregate.kindLabel == "Expense search")
        #expect(choices.choices.contains { $0.title.contains("Text") } == false)
    }

    @Test func resolver_categoryOnlySpendTargetAutoResolvesWithoutTextChoice() async throws {
        let fixture = try makeFixture(includeTransportationCategory: true)
        let brain = legacyRuleBasedBrain()

        let answer = await answer("What did I spend on Transportation?", using: brain, fixture: fixture)

        #expect(answer.kind == .metric)
        #expect(answer.title == "Transportation Spend")
        #expect(answer.attachment == nil)
        #expect((answer.primaryValue ?? "").contains("60"))
    }

    @Test func resolver_showGroceryExpensesCanResolveCategoryOrExpenseTextLists() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()

        let clarification = await answer("Show Grocery expenses", using: brain, fixture: fixture)
        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected Grocery list clarification choices.")
            return
        }

        let categoryAnswer = await answer(try #require(choices.choice(matching: "category")).request, prompt: "category", using: brain, fixture: fixture)
        #expect(categoryAnswer.kind == .list)
        #expect(categoryAnswer.rows.contains(where: { $0.title == "Target groceries" }))
        #expect(categoryAnswer.rows.contains(where: { $0.title == "Grocery Envelope" }))

        let textAnswer = await answer(try #require(choices.choice(matching: "description")).request, prompt: "description", using: brain, fixture: fixture)
        #expect(textAnswer.kind == .list)
        #expect(textAnswer.rows.contains(where: { $0.title == "Target groceries" }))
        #expect(textAnswer.rows.contains(where: { $0.title == "Grocery Envelope" }))
    }

    @Test func capabilityMatrix_declaresEveryEntityAndRejectsInvalidShapes() throws {
        let registry = MarinaQueryCapabilityRegistry()

        for entity in MarinaSemanticEntity.allCases {
            #expect(registry.supportedOperations(for: entity).isEmpty == false, "Missing capabilities for \(entity.rawValue)")
        }

        #expect(registry.supports(entity: .budget, operation: .whatIf))
        #expect(registry.supports(entity: .income, operation: .share))
        #expect(registry.supports(entity: .preset, operation: .next))
        #expect(registry.supports(entity: .workspace, operation: .whatIf) == false)
    }

    @Test func clarification_merchantWithoutPendingContextDoesNotBecomeWorkspace() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()

        let answer = await answer("merchant", using: brain, fixture: fixture)

        #expect(answer.title != "Current Workspace")
        #expect(answer.kind == .message)
    }

    @Test func merchantNoResultsAndMerchantMatchesUseDistinctCards() async throws {
        let noAppleFixture = try makeFixture(includeAppleMerchantExpense: false)
        let appleFixture = try makeFixture(includeAppleMerchantExpense: true)
        let brain = legacyRuleBasedBrain()
        let request = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            dateRangeToken: .currentPeriod,
            textQuery: "Apple",
            expenseScope: .variable,
            expectedAnswerShape: .metric
        )

        let noResults = await answer(request, prompt: "merchant", using: brain, fixture: noAppleFixture)
        #expect(noResults.kind == .message)
        #expect(noResults.title == "No Results Found")
        #expect(noResults.primaryValue == nil)

        let metric = await answer(request, prompt: "merchant", using: brain, fixture: appleFixture)
        #expect(metric.kind == .metric)
        #expect(metric.title == "Apple Spend")
        #expect((metric.primaryValue ?? "").contains("300"))
    }

    @Test func clarificationChoices_persistResolvedStateAndCanBeCleared() throws {
        let suiteName = "MarinaSemanticPromptSuiteTests.clarificationChoices"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MarinaConversationStore(userDefaults: defaults, storageKeyPrefix: "tests.marina.answers")
        let workspaceID = UUID()
        var choices = MarinaClarificationChoices(
            question: "Did you mean Apple as a merchant, or Apple Card?",
            choices: [
                MarinaClarificationChoice(
                    title: "Merchant",
                    aliases: ["merchant", "store", "vendor"],
                    request: MarinaSemanticRequest(
                        entity: .variableExpense,
                        operation: .sum,
                        measure: .budgetImpact,
                        dimensions: [.merchantText],
                        textQuery: "Apple",
                        expenseScope: .variable,
                        expectedAnswerShape: .metric
                    )
                )
            ]
        )

        let unresolved = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "Can you clarify?",
            attachment: .clarificationChoices(choices)
        )
        store.saveAnswers([unresolved], workspaceID: workspaceID)

        let loaded = try #require(store.loadAnswers(workspaceID: workspaceID).first)
        guard case .clarificationChoices(let loadedChoices)? = loaded.attachment else {
            Issue.record("Expected persisted clarification choices.")
            return
        }
        #expect(loadedChoices.isResolved == false)
        #expect(loadedChoices.choice(matching: "vendor")?.title == "Merchant")

        choices.resolvedChoiceID = choices.choices[0].id
        let resolved = HomeAnswer(
            id: unresolved.id,
            queryID: unresolved.queryID,
            kind: unresolved.kind,
            title: unresolved.title,
            attachment: .clarificationChoices(choices),
            generatedAt: unresolved.generatedAt
        )
        store.saveAnswers([resolved], workspaceID: workspaceID)
        let reloaded = try #require(store.loadAnswers(workspaceID: workspaceID).first)
        guard case .clarificationChoices(let resolvedChoices)? = reloaded.attachment else {
            Issue.record("Expected persisted resolved clarification choices.")
            return
        }
        #expect(resolvedChoices.isResolved)

        store.saveAnswers([], workspaceID: workspaceID)
        #expect(store.loadAnswers(workspaceID: workspaceID).isEmpty)
    }

    @Test func factory_defaultUsesModelBackedInterpreterBeforeRuleBasedParser() async throws {
        let fixture = try makeFixture()
        let model = RecordingInterpreter(
            result: MarinaInterpretedSemanticRequest(
                request: MarinaSemanticRequest(entity: .income, operation: .sum, measure: .incomeAmount, expectedAnswerShape: .metric),
                confidence: .medium,
                source: .foundationModel
            )
        )
        let interpreter = MarinaModelInterpreterFactory.makeDefault(modelBackedInterpreter: model)
        let context = brainContext(fixture)

        let interpreted = try await interpreter.interpretedSemanticRequest(for: "How many cards do I have?", context: context)

        #expect(interpreted.source == .foundationModel)
        #expect(interpreted.request.entity == .income)
        #expect(model.callCount == 1)
    }

    @Test func factory_noModelBackedInterpreterReturnsUnavailableFallback() async throws {
        let fixture = try makeFixture()
        let interpreter = MarinaModelInterpreterFactory.makeDefault(modelBackedInterpreter: nil)
        let context = brainContext(fixture)

        let interpreted = try await interpreter.interpretedSemanticRequest(for: "How many cards do I have?", context: context)

        #expect(interpreted.source == .unavailableFallback)
        #expect(interpreted.request.expectedAnswerShape == .unsupported)
        #expect(interpreted.request.unsupportedReason == .unavailableModel)
    }

    @Test func migrationHybrid_highConfidencePromptDoesNotCallModelInterpreter() async throws {
        let fixture = try makeFixture()
        let model = RecordingInterpreter(
            result: MarinaInterpretedSemanticRequest(
                request: MarinaSemanticRequest(entity: .income, operation: .sum, measure: .incomeAmount, expectedAnswerShape: .metric),
                confidence: .medium,
                source: .foundationModel
            )
        )
        let hybrid = MarinaHybridInterpreter(modelBackedInterpreter: model)
        let context = brainContext(fixture)

        let interpreted = try await hybrid.interpretedSemanticRequest(for: "How many cards do I have?", context: context)

        #expect(interpreted.source == .ruleBased)
        #expect(interpreted.request.entity == .card)
        #expect(model.callCount == 0)
    }

    @Test func migrationHybrid_lowConfidencePromptCallsModelInterpreter() async throws {
        let fixture = try makeFixture()
        let model = RecordingInterpreter(
            result: MarinaInterpretedSemanticRequest(
                request: MarinaSemanticRequest(entity: .income, operation: .sum, measure: .incomeAmount, expectedAnswerShape: .metric),
                confidence: .medium,
                source: .foundationModel
            )
        )
        let hybrid = MarinaHybridInterpreter(modelBackedInterpreter: model)
        let context = brainContext(fixture)

        let interpreted = try await hybrid.interpretedSemanticRequest(for: "Did my paycheck vibe improve?", context: context)

        #expect(interpreted.source == .foundationModel)
        #expect(interpreted.request.entity == .income)
        #expect(model.callCount == 1)
    }

    @Test func validator_repairsFoundationModelMerchantSpendAndRejectsUnknownCategory() throws {
        let fixture = try makeFixture()
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(for: fixture.workspace, modelContext: fixture.context)
        let validator = MarinaSemanticRequestValidator()
        let merchantAsCard = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.card],
                dateRangeToken: .currentPeriod,
                targetName: "Target",
                expectedAnswerShape: .metric
            ),
            confidence: .medium,
            source: .foundationModel
        )

        let repaired = validator.validate(interpreted: merchantAsCard, snapshot: snapshot)
        #expect(repaired.source == .repairedFoundationModel)
        #expect(repaired.request.entity == .variableExpense)
        #expect(repaired.request.textQuery == "Target")

        let unknownCategory = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .category,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.category],
                targetName: "Food",
                expectedAnswerShape: .metric
            ),
            confidence: .high,
            source: .ruleBased
        )
        let rejected = validator.validate(interpreted: unknownCategory, snapshot: snapshot)
        #expect(rejected.request.expectedAnswerShape == .unsupported)
        #expect(rejected.request.unsupportedReason == .unresolvedEntity)
    }

    @Test func hybrid_modelUnavailableFallsBackCleanlyAndModelErrorsAreFriendly() async throws {
        let fixture = try makeFixture()
        let context = brainContext(fixture)
        let hybrid = MarinaHybridInterpreter(modelBackedInterpreter: nil)

        let unavailable = try await hybrid.interpretedSemanticRequest(for: "Is my paycheck vibe improving?", context: context)
        #expect(unavailable.source == .unavailableFallback)
        #expect(unavailable.request.unsupportedReason == .unavailableModel)

        let executor = MarinaQueryExecutor()
        let unavailablePlan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .unsupported,
                unsupportedReason: .unavailableModel
            ),
            dateRange: nil,
            comparisonDateRange: nil,
            now: fixture.now
        )
        let unavailableAnswer = executor.execute(plan: unavailablePlan, snapshot: try MarinaWorkspaceSnapshotProvider().snapshot(for: fixture.workspace, modelContext: fixture.context))
        #expect(unavailableAnswer.title == "I can't answer that yet")
        #expect(unavailableAnswer.subtitle?.contains("My on-device language model") == true)
        #expect(unavailableAnswer.subtitle?.contains("Marina") == false)

        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .unsupported,
                unsupportedReason: .modelGuardrail
            ),
            dateRange: nil,
            comparisonDateRange: nil,
            now: fixture.now
        )
        let answer = executor.execute(plan: plan, snapshot: try MarinaWorkspaceSnapshotProvider().snapshot(for: fixture.workspace, modelContext: fixture.context))
        #expect(answer.kind == .message)
        #expect(answer.subtitle?.contains("declined") == true)
        #expect(answer.title == "I can't answer that yet")
        #expect(answer.subtitle?.contains("I can still answer") == true)
    }

    @Test func insightContext_buildsCompactFactsForSupportedAnswerShapes() throws {
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .remainingRoom,
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )

        let metric = MarinaInsightContext(
            prompt: "What is my safe spend today?",
            result: MarinaExecutionResult(
                kind: .metric,
                title: "Safe Spend Today",
                subtitle: "Apr 1, 2026 - Apr 30, 2026",
                primaryValue: "$42.00",
                rows: [HomeAnswerRow(title: "Period room", value: "$420.00", amount: 420)]
            ),
            plan: plan
        )
        #expect(metric.isNarratable)
        #expect(metric.answerKind == .metric)
        #expect(metric.entity == .budget)
        #expect(metric.operation == .forecast)
        #expect(metric.measure == .remainingRoom)
        #expect(metric.rows.count == 1)

        let list = MarinaInsightContext(
            prompt: nil,
            result: MarinaExecutionResult(
                kind: .list,
                title: "Top Categories",
                rows: [HomeAnswerRow(title: "Groceries", value: "$120.00")]
            ),
            plan: plan
        )
        #expect(list.isNarratable)
        #expect(list.answerKind == .list)

        let comparison = MarinaInsightContext(
            prompt: nil,
            result: MarinaExecutionResult(
                kind: .comparison,
                title: "Budget Comparison",
                primaryValue: "Down $18.00",
                rows: [
                    HomeAnswerRow(title: "Current period", value: "$200.00"),
                    HomeAnswerRow(title: "Previous period", value: "$218.00")
                ]
            ),
            plan: plan
        )
        #expect(comparison.isNarratable)
        #expect(comparison.rows.count == 2)

        let emptyMessage = MarinaInsightContext(
            prompt: nil,
            result: MarinaExecutionResult(kind: .message, title: "No Expenses Found"),
            plan: plan
        )
        #expect(emptyMessage.isNarratable == false)
    }

    @Test func insightContext_buildsReconciliationPerspectiveOnlyForAllHistoryBalance() throws {
        let positive = reconciliationInsightContext(amount: 21.06)
        #expect(positive.perspective?.partyName == "Alejandro")
        #expect(positive.perspective?.direction == .partyOwesUser)
        #expect(positive.perspective?.requiredRelationshipSentence == "Alejandro owes you \(CurrencyFormatter.string(from: 21.06)).")

        let negative = reconciliationInsightContext(amount: -18.40)
        #expect(negative.perspective?.partyName == "Alejandro")
        #expect(negative.perspective?.direction == .userOwesParty)
        #expect(negative.perspective?.requiredRelationshipSentence == "You owe Alejandro \(CurrencyFormatter.string(from: 18.40)).")

        let zero = reconciliationInsightContext(amount: 0)
        #expect(zero.perspective?.partyName == "Alejandro")
        #expect(zero.perspective?.direction == .settled)
        #expect(zero.perspective?.requiredRelationshipSentence == "Alejandro is settled up with you.")

        let ranged = reconciliationInsightContext(
            amount: 21.06,
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30))
        )
        #expect(ranged.perspective == nil)
    }

    @Test func insightFactsDigest_capsRowsAndUsesOnlySuppliedFacts() throws {
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                expectedAnswerShape: .list
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        let rows = (1...10).map { index in
            HomeAnswerRow(title: "Row \(index)", value: "$\(index)")
        }
        let context = MarinaInsightContext(
            prompt: "Show category spotlight.",
            result: MarinaExecutionResult(kind: .list, title: "Category Spotlight", rows: rows),
            plan: plan
        )
        let digest = MarinaAnswerFactsDigest(context: context).text()

        #expect(context.rows.count == MarinaInsightContext.maxRows)
        #expect(digest.contains("Row 1"))
        #expect(digest.contains("Row 6"))
        #expect(digest.contains("Row 7") == false)
        #expect(digest.contains("Personal") == false)
    }

    @Test func insightFactsDigest_exposesPronounRulesAndRequiredReconciliationSentence() throws {
        let context = reconciliationInsightContext(amount: 21.06)
        let digest = MarinaAnswerFactsDigest(context: context).text()

        #expect(digest.contains("Pronoun rules: Marina may use I/me/my only for assistant actions or limitations."))
        #expect(digest.contains("Words like me in the prompt refer to the user, not Marina."))
        #expect(digest.contains("Named reconciliation party: Alejandro"))
        #expect(digest.contains("Reconciliation party pronouns: Use the party name first"))
        #expect(digest.contains("Required relationship sentence: Alejandro owes you \(CurrencyFormatter.string(from: 21.06))."))
        #expect(digest.contains("SwiftData") == false)
    }

    @Test func followUpBuilder_categoryMetricCreatesPreviousBiggestAndShareSuggestions() throws {
        let context = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .category,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.category],
                dateRangeToken: .currentPeriod,
                targetName: "Groceries",
                expenseScope: .unified,
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            answerKind: .metric,
            answerTitle: "Groceries Spend",
            answerSubtitle: nil,
            primaryValue: "$120.00",
            rowReferences: [
                MarinaAnswerSemanticRowReference(row: HomeAnswerRow(title: "Total", value: "$120.00", amount: 120))
            ]
        )

        let followUps = MarinaFollowUpBuilder().followUps(for: context)
        let previous = try #require(followUps.first { $0.reason == .comparePreviousPeriod })
        let biggest = try #require(followUps.first { $0.title == "Show biggest expenses in this category" })
        let share = try #require(followUps.first { $0.title == "Show category share" })

        #expect(previous.executionMode == .executable)
        #expect(previous.semanticRequest?.dateRangeToken == .previousPeriod)
        #expect(biggest.executionMode == .executable)
        #expect(biggest.semanticRequest?.entity == .variableExpense)
        #expect(biggest.semanticRequest?.operation == .list)
        #expect(biggest.semanticRequest?.sort == .amountDescending)
        #expect(share.executionMode == .executable)
        #expect(share.semanticRequest?.entity == .category)
        #expect(share.semanticRequest?.operation == .group)
    }

    @Test func followUpBuilder_budgetRoomCreatesSafeSpendWhatIfAndCategoryAvailabilitySuggestions() throws {
        let context = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .remainingRoom,
                dateRangeToken: .currentPeriod,
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            answerKind: .metric,
            answerTitle: "Safe Spend Today",
            answerSubtitle: nil,
            primaryValue: "$42.00",
            rowReferences: [
                MarinaAnswerSemanticRowReference(row: HomeAnswerRow(title: "Period room", value: "$420.00", amount: 420))
            ]
        )

        let followUps = MarinaFollowUpBuilder().followUps(for: context)
        let safeSpend = try #require(followUps.first { $0.reason == .safeDailySpend })
        let whatIf = try #require(followUps.first { $0.reason == .whatIf })
        let availability = try #require(followUps.first { $0.title == "Which categories still have room?" })

        #expect(safeSpend.executionMode == .executable)
        #expect(safeSpend.semanticRequest?.entity == .budget)
        #expect(safeSpend.semanticRequest?.operation == .forecast)
        #expect(safeSpend.semanticRequest?.measure == .safeDailySpend)
        #expect(safeSpend.semanticRequest?.expectedAnswerShape == .metric)
        #expect(whatIf.executionMode == .executable)
        #expect(whatIf.semanticRequest?.operation == .whatIf)
        #expect(whatIf.semanticRequest?.whatIfAmount == 50)
        #expect(availability.executionMode == .executable)
        #expect(availability.semanticRequest?.entity == .category)
        #expect(availability.semanticRequest?.measure == .categoryAvailability)
        #expect(availability.semanticRequest?.categoryAvailabilityFilter == .underLimit)
    }

    @Test func followUpBuilder_incomeCreatesExpectedCoverageAndPreviousPeriodSuggestions() throws {
        let context = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .income,
                operation: .share,
                measure: .incomeAmount,
                dateRangeToken: .currentPeriod,
                incomeState: .all,
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            answerKind: .metric,
            answerTitle: "Income Progress",
            answerSubtitle: nil,
            primaryValue: "80%",
            rowReferences: []
        )

        let followUps = MarinaFollowUpBuilder().followUps(for: context)
        let expected = try #require(followUps.first { $0.title == "What income is still expected?" })
        let coverage = try #require(followUps.first { $0.title == "Does income cover planned expenses?" })
        let comparison = try #require(followUps.first { $0.reason == .comparePreviousPeriod })

        #expect(expected.executionMode == .executable)
        #expect(expected.semanticRequest?.operation == .list)
        #expect(expected.semanticRequest?.incomeState == .planned)
        #expect(coverage.executionMode == .executable)
        #expect(coverage.semanticRequest?.entity == .income)
        #expect(coverage.semanticRequest?.operation == .share)
        #expect(coverage.semanticRequest?.measure == .coverageRatio)
        #expect(comparison.executionMode == .executable)
        #expect(comparison.semanticRequest?.operation == .compare)
        #expect(comparison.semanticRequest?.incomeState == .all)
    }

    @Test func followUpBuilder_suppressesPreviousPeriodWhenAnswerAlreadyCompares() throws {
        let context = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .income,
                operation: .compare,
                measure: .incomeAmount,
                dateRangeToken: .currentPeriod,
                expectedAnswerShape: .comparison
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: HomeQueryDateRange(startDate: date(2026, 3, 2), endDate: date(2026, 3, 31)),
            answerKind: .comparison,
            answerTitle: "Income Comparison",
            answerSubtitle: nil,
            primaryValue: "Down $100.00",
            rowReferences: []
        )

        let followUps = MarinaFollowUpBuilder().followUps(for: context)

        #expect(followUps.contains { $0.reason == .comparePreviousPeriod } == false)
        #expect(MarinaRecommendedFollowUp.suggestion(from: followUps)?.reason != .comparePreviousPeriod)
    }

    @Test func followUpBuilder_listSuppressesPreviousPeriodWhenAlreadyPreviousOrComparison() throws {
        let previousContext = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .list,
                measure: .budgetImpact,
                dateRangeToken: .previousPeriod,
                expectedAnswerShape: .list
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 3, 2), endDate: date(2026, 3, 31)),
            comparisonDateRange: nil,
            answerKind: .list,
            answerTitle: "Expenses",
            answerSubtitle: nil,
            primaryValue: nil,
            rowReferences: [
                MarinaAnswerSemanticRowReference(row: HomeAnswerRow(title: "Coffee", value: "$5.00", amount: 5))
            ]
        )
        let comparisonContext = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .list,
                measure: .budgetImpact,
                dateRangeToken: .currentPeriod,
                expectedAnswerShape: .list
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: HomeQueryDateRange(startDate: date(2026, 3, 2), endDate: date(2026, 3, 31)),
            answerKind: .list,
            answerTitle: "Expenses",
            answerSubtitle: nil,
            primaryValue: nil,
            rowReferences: [
                MarinaAnswerSemanticRowReference(row: HomeAnswerRow(title: "Coffee", value: "$5.00", amount: 5))
            ]
        )

        let previousFollowUps = MarinaFollowUpBuilder().followUps(for: previousContext)
        let comparisonFollowUps = MarinaFollowUpBuilder().followUps(for: comparisonContext)

        #expect(previousFollowUps.contains { $0.reason == .comparePreviousPeriod } == false)
        #expect(comparisonFollowUps.contains { $0.reason == .comparePreviousPeriod } == false)
        #expect(previousFollowUps.contains { $0.title == "Show more" })
        #expect(comparisonFollowUps.contains { $0.title == "Show more" })
    }

    @Test func followUpBuilder_groupedSpendListsSeparateShowMoreFromExpenseDrillDown() throws {
        let context = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category, .date],
                dateRangeToken: .currentPeriod,
                resultLimit: 3,
                sort: .amountDescending,
                expenseScope: .unified,
                expectedAnswerShape: .list
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            answerKind: .list,
            answerTitle: "Spend Trends",
            answerSubtitle: "April 2026",
            primaryValue: "$2,435.40",
            rowReferences: [
                MarinaAnswerSemanticRowReference(row: HomeAnswerRow(title: "Bills & Utilities", value: "$2,200.94 (90.4%)", amount: 2_200.94)),
                MarinaAnswerSemanticRowReference(row: HomeAnswerRow(title: "Shopping", value: "$148.57 (6.1%)", amount: 148.57))
            ]
        )

        let followUps = MarinaFollowUpBuilder().followUps(for: context)
        let showMore = try #require(followUps.first { $0.reason == .showMore })
        let inspectRows = try #require(followUps.first { $0.reason == .inspectRows })

        #expect(showMore.semanticRequest?.entity == .category)
        #expect(showMore.semanticRequest?.operation == .group)
        #expect(showMore.semanticRequest?.resultLimit == 10)
        #expect(inspectRows.semanticRequest?.entity == .variableExpense)
        #expect(inspectRows.semanticRequest?.operation == .list)
        #expect(inspectRows.semanticRequest?.measure == .budgetImpact)
        #expect(inspectRows.semanticRequest?.sort == .amountDescending)
        #expect(inspectRows.semanticRequest?.expenseScope == .unified)
        #expect(inspectRows.semanticRequest?.dimensions.contains(.date) == false)
        #expect(inspectRows.semanticRequest?.dimensions.contains(.category) == false)
    }

    @Test func followUpBuilder_concreteExpenseListsDoNotRecommendInspectRowsAgain() throws {
        let context = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .list,
                measure: .budgetImpact,
                dateRangeToken: .currentPeriod,
                resultLimit: 5,
                sort: .amountDescending,
                expenseScope: .unified,
                expectedAnswerShape: .list
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            answerKind: .list,
            answerTitle: "Recent Expenses",
            answerSubtitle: "April 2026",
            primaryValue: nil,
            rowReferences: [
                MarinaAnswerSemanticRowReference(row: HomeAnswerRow(title: "Rent", value: "$1,200.00", sourceID: UUID(), objectType: .plannedExpense, amount: 1_200))
            ]
        )

        let followUps = MarinaFollowUpBuilder().followUps(for: context)

        #expect(followUps.contains { $0.reason == .inspectRows } == false)
        #expect(followUps.contains { $0.reason == .showMore })
    }

    @Test func followUpBuilder_allInspectRowsSuggestionsExecuteRowListRequests() throws {
        let categoryContext = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .category,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.category],
                dateRangeToken: .currentPeriod,
                targetName: "Groceries",
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            answerKind: .metric,
            answerTitle: "Groceries Spend",
            answerSubtitle: nil,
            primaryValue: "$120.00",
            rowReferences: []
        )
        let cardContext = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.card],
                dateRangeToken: .currentPeriod,
                targetName: "Apple Card",
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            answerKind: .metric,
            answerTitle: "Apple Card Spend",
            answerSubtitle: nil,
            primaryValue: "$100.00",
            rowReferences: []
        )
        let trendContext = MarinaAnswerSemanticContext(
            request: MarinaSemanticRequest(
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category, .date],
                dateRangeToken: .currentPeriod,
                resultLimit: 3,
                sort: .amountDescending,
                expenseScope: .unified,
                expectedAnswerShape: .list
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            answerKind: .list,
            answerTitle: "Spend Trends",
            answerSubtitle: nil,
            primaryValue: "$100.00",
            rowReferences: []
        )

        let followUps = [categoryContext, cardContext, trendContext]
            .flatMap { MarinaFollowUpBuilder().followUps(for: $0) }
            .filter { $0.reason == .inspectRows }

        #expect(followUps.isEmpty == false)
        #expect(followUps.allSatisfy { $0.semanticRequest?.entity == .variableExpense })
        #expect(followUps.allSatisfy { $0.semanticRequest?.operation == .list })
        #expect(followUps.allSatisfy { $0.semanticRequest?.expectedAnswerShape == .list })
    }

    @Test func followUpBuilder_marksExecutableAndClarificationDrivenSuggestionsExplicitly() throws {
        let builder = MarinaFollowUpBuilder()
        let contexts = [
            MarinaAnswerSemanticContext(
                request: MarinaSemanticRequest(
                    entity: .category,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.category],
                    dateRangeToken: .currentPeriod,
                    targetName: "Groceries",
                    expectedAnswerShape: .metric
                ),
                dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
                comparisonDateRange: nil,
                answerKind: .metric,
                answerTitle: "Groceries Spend",
                answerSubtitle: nil,
                primaryValue: "$120.00",
                rowReferences: []
            ),
            MarinaAnswerSemanticContext(
                request: MarinaSemanticRequest(
                    entity: .budget,
                    operation: .forecast,
                    measure: .remainingRoom,
                    dateRangeToken: .currentPeriod,
                    expectedAnswerShape: .metric
                ),
                dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
                comparisonDateRange: nil,
                answerKind: .metric,
                answerTitle: "Safe Spend Today",
                answerSubtitle: nil,
                primaryValue: "$42.00",
                rowReferences: []
            ),
            MarinaAnswerSemanticContext(
                request: MarinaSemanticRequest(
                    entity: .income,
                    operation: .share,
                    measure: .incomeAmount,
                    dateRangeToken: .currentPeriod,
                    expectedAnswerShape: .metric
                ),
                dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
                comparisonDateRange: nil,
                answerKind: .metric,
                answerTitle: "Income Progress",
                answerSubtitle: nil,
                primaryValue: "80%",
                rowReferences: []
            ),
            MarinaAnswerSemanticContext(
                request: MarinaSemanticRequest(
                    entity: .card,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    dateRangeToken: .currentPeriod,
                    targetName: "Apple Card",
                    expectedAnswerShape: .metric
                ),
                dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
                comparisonDateRange: nil,
                answerKind: .metric,
                answerTitle: "Apple Card Spend",
                answerSubtitle: nil,
                primaryValue: "$100.00",
                rowReferences: []
            )
        ]
        let followUps = contexts.flatMap { builder.followUps(for: $0) }
        let cardCompare = try #require(followUps.first { $0.title == "Compare this card to another card" })
        let cardLargest = try #require(followUps.first { $0.title == "Show largest expenses on this card" })

        #expect(followUps.allSatisfy { followUp in
            followUp.executionMode != .executable || followUp.semanticRequest != nil
        })
        #expect(followUps.allSatisfy { followUp in
            followUp.semanticRequest != nil || followUp.executionMode == .clarificationRequired
        })
        #expect(cardLargest.executionMode == .executable)
        #expect(cardLargest.semanticRequest?.entity == .variableExpense)
        #expect(cardCompare.executionMode == .clarificationRequired)
        #expect(cardCompare.semanticRequest == nil)
        #expect(followUps.contains(where: { $0.title == "Break this card down by category" }) == false)
    }

    @Test func followUpSuggestion_decodesLegacyExecutionModeFromSemanticRequestPresence() throws {
        let executable = MarinaFollowUpSuggestion(
            title: "Show biggest expenses in this category",
            prompt: "Show biggest expenses in Groceries.",
            reason: .inspectRows,
            executionMode: .executable,
            semanticRequest: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .list,
                measure: .budgetImpact,
                dimensions: [.category],
                targetName: "Groceries",
                expectedAnswerShape: .list
            )
        )
        let clarification = MarinaFollowUpSuggestion(
            title: "Compare this card to another card",
            prompt: "Compare Apple Card to another card.",
            reason: .comparePreviousPeriod,
            executionMode: .clarificationRequired
        )

        let decodedExecutable = try decodeLegacyFollowUpWithoutExecutionMode(executable)
        let decodedClarification = try decodeLegacyFollowUpWithoutExecutionMode(clarification)

        #expect(decodedExecutable.executionMode == .executable)
        #expect(decodedExecutable.semanticRequest != nil)
        #expect(decodedClarification.executionMode == .clarificationRequired)
        #expect(decodedClarification.semanticRequest == nil)
    }

    @Test func insightContext_recommendedFollowUpSelectionIsDeterministic() throws {
        let safeDaily = followUp(
            title: "What can I spend per day?",
            prompt: "What can I spend per day?",
            reason: .safeDailySpend,
            mode: .executable
        )
        let whatIf = followUp(
            title: "What if I spend $50?",
            prompt: "What if I spend $50?",
            reason: .whatIf,
            mode: .executable
        )
        let clarification = followUp(
            title: "Compare this card to another card",
            prompt: "Compare Apple Card to another card.",
            reason: .comparePreviousPeriod,
            mode: .clarificationRequired
        )

        let prefersWhatIf = insightContext(followUps: [safeDaily, whatIf, clarification])
        #expect(prefersWhatIf.recommendedFollowUp?.title == "What if I spend $50?")

        let prefersExecutable = insightContext(followUps: [clarification, safeDaily])
        #expect(prefersExecutable.recommendedFollowUp?.title == "What can I spend per day?")

        let fallsBackToClarification = insightContext(followUps: [clarification])
        #expect(fallsBackToClarification.recommendedFollowUp?.title == "Compare this card to another card")

        let noFollowUp = insightContext(followUps: [])
        #expect(noFollowUp.recommendedFollowUp == nil)
    }

    @Test func recommendedFollowUpMemory_noMemorySelectionRemainsUnchanged() throws {
        let safeDaily = followUp(
            title: "What can I spend per day?",
            prompt: "What can I spend per day?",
            reason: .safeDailySpend,
            mode: .executable
        )
        let whatIf = followUp(
            title: "What if I spend $50?",
            prompt: "What if I spend $50?",
            reason: .whatIf,
            mode: .executable
        )

        #expect(MarinaRecommendedFollowUp.suggestion(from: [safeDaily, whatIf])?.reason == .whatIf)
    }

    @Test func recommendedFollowUpMemory_suppressesRecentlySuggestedIdenticalFollowUp() throws {
        let suggested = semanticFollowUp(reason: .safeDailySpend, targetName: "April Budget")
        let memory = MarinaConversationContext(recentAnswers: [
            answerWithFollowUps([suggested])
        ]).followUpMemory

        #expect(MarinaRecommendedFollowUp.suggestion(from: [suggested], memory: memory) == nil)
    }

    @Test func recommendedFollowUpMemory_suppressesRecentlyDeclinedIdenticalFollowUp() throws {
        let declined = semanticFollowUp(reason: .whatIf, targetName: "April Budget", whatIfAmount: 50)
        let memory = MarinaConversationContext(recentAnswers: [
            answerWithFollowUps([declined], userPrompt: "How much room do I have?"),
            HomeAnswer(queryID: UUID(), kind: .message, userPrompt: "No thanks", title: "")
        ]).followUpMemory

        #expect(memory.recentDeclines == [MarinaFollowUpMemoryEntry(followUp: declined)])
        #expect(MarinaRecommendedFollowUp.suggestion(from: [declined], memory: memory) == nil)
    }

    @Test func recommendedFollowUpMemory_allSuppressedCandidatesReturnNoRecommendation() throws {
        let suggested = semanticFollowUp(reason: .breakdown, targetName: "Groceries", entity: .category)
        let memory = MarinaConversationContext(recentAnswers: [
            answerWithFollowUps([suggested])
        ]).followUpMemory

        #expect(MarinaRecommendedFollowUp.filteredFollowUps(from: [suggested], memory: memory).isEmpty)
    }

    @Test func recommendedFollowUpMemory_sameReasonDifferentTargetRemainsEligible() throws {
        let groceries = semanticFollowUp(reason: .breakdown, targetName: "Groceries", entity: .category)
        let dining = semanticFollowUp(reason: .breakdown, targetName: "Dining", entity: .category)
        let memory = MarinaConversationContext(recentAnswers: [
            answerWithFollowUps([groceries])
        ]).followUpMemory

        #expect(MarinaRecommendedFollowUp.suggestion(from: [dining], memory: memory) == dining)
    }

    @Test func recommendedFollowUpMemory_acceptanceIsNotStoredAsDecline() throws {
        let accepted = semanticFollowUp(reason: .comparePreviousPeriod, targetName: "Income", entity: .income)
        let memory = MarinaConversationContext(recentAnswers: [
            answerWithFollowUps([accepted], userPrompt: "How is income progress?"),
            HomeAnswer(queryID: UUID(), kind: .comparison, userPrompt: "Yes", title: "Income Comparison")
        ]).followUpMemory

        #expect(memory.recentAcceptances == [MarinaFollowUpMemoryEntry(followUp: accepted)])
        #expect(memory.recentDeclines.isEmpty)
    }

    @Test func recommendedFollowUpMemory_negativeWithoutVisibleFollowUpDoesNotDecline() throws {
        let memory = MarinaConversationContext(recentAnswers: [
            HomeAnswer(queryID: UUID(), kind: .message, userPrompt: "No", title: "")
        ]).followUpMemory

        #expect(memory.recentDeclines.isEmpty)
        #expect(memory.recentAcceptances.isEmpty)
    }

    @Test func recommendedFollowUpMemory_showMoreDoesNotLoopForSameListContext() throws {
        let first = semanticFollowUp(
            reason: .showMore,
            targetName: "Groceries",
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            resultLimit: 10,
            answerShape: .list
        )
        let next = semanticFollowUp(
            reason: .showMore,
            targetName: "Groceries",
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            resultLimit: 15,
            answerShape: .list
        )
        let memory = MarinaConversationContext(recentAnswers: [
            answerWithFollowUps([first])
        ]).followUpMemory

        #expect(MarinaRecommendedFollowUp.suggestion(from: [next], memory: memory) == nil)
    }

    @Test func insightAnalyzer_emitsDomainSignalsForFormulaAnswers() throws {
        let analyzer = MarinaInsightAnalyzer()

        let safeDaily = analyzer.insightBundle(
            for: MarinaExecutionResult(
                kind: .metric,
                title: "Safe Daily Spend",
                rows: [
                    HomeAnswerRow(title: "Remaining room", value: "$20.00", amount: 20),
                    HomeAnswerRow(title: "Remaining days", value: "3", amount: 3),
                    HomeAnswerRow(title: "Safe per day", value: "$6.67", amount: 6.67)
                ]
            ),
            plan: formulaPlan(entity: .budget, operation: .forecast, measure: .safeDailySpend)
        )
        #expect(safeDaily.meaning == "This shows how much room remains per day for the rest of the selected period.")
        #expect(safeDaily.signals.contains(where: { $0.kind == .caution && $0.title == "Daily room is tight" }))

        let paceAhead = analyzer.insightBundle(
            for: MarinaExecutionResult(
                kind: .comparison,
                title: "Pace Difference",
                rows: [
                    HomeAnswerRow(title: "Spent so far", value: "$112.00", amount: 112),
                    HomeAnswerRow(title: "Expected by now", value: "$100.00", amount: 100),
                    HomeAnswerRow(title: "Pace difference", value: "Up $12.00", amount: 12)
                ]
            ),
            plan: formulaPlan(entity: .budget, operation: .compare, measure: .paceDifference)
        )
        #expect(paceAhead.signals.contains(where: { $0.kind == .caution && $0.title == "Spending is ahead of pace" }))

        let paceBehind = analyzer.insightBundle(
            for: MarinaExecutionResult(
                kind: .comparison,
                title: "Pace Difference",
                rows: [
                    HomeAnswerRow(title: "Spent so far", value: "$88.00", amount: 88),
                    HomeAnswerRow(title: "Expected by now", value: "$100.00", amount: 100),
                    HomeAnswerRow(title: "Pace difference", value: "Down $12.00", amount: -12)
                ]
            ),
            plan: formulaPlan(entity: .budget, operation: .compare, measure: .paceDifference)
        )
        #expect(paceBehind.signals.contains(where: { $0.kind == .celebration && $0.title == "Spending is behind pace" }))

        let coverageShort = analyzer.insightBundle(
            for: MarinaExecutionResult(
                kind: .metric,
                title: "Income Coverage",
                rows: [
                    HomeAnswerRow(title: "Income", value: "$950.00", amount: 950),
                    HomeAnswerRow(title: "Planned expenses", value: "$1,000.00", amount: 1_000),
                    HomeAnswerRow(title: "Coverage percent", value: "95.0%", amount: 0.95),
                    HomeAnswerRow(title: "Difference", value: "Down $50.00", amount: -50)
                ]
            ),
            plan: formulaPlan(entity: .income, operation: .share, measure: .coverageRatio)
        )
        #expect(coverageShort.signals.contains(where: { $0.kind == .caution && $0.title == "Income does not fully cover planned expenses" }))

        let coverageOver = analyzer.insightBundle(
            for: MarinaExecutionResult(
                kind: .metric,
                title: "Income Coverage",
                rows: [
                    HomeAnswerRow(title: "Income", value: "$1,050.00", amount: 1_050),
                    HomeAnswerRow(title: "Planned expenses", value: "$1,000.00", amount: 1_000),
                    HomeAnswerRow(title: "Coverage percent", value: "105.0%", amount: 1.05),
                    HomeAnswerRow(title: "Difference", value: "Up $50.00", amount: 50)
                ]
            ),
            plan: formulaPlan(entity: .income, operation: .share, measure: .coverageRatio)
        )
        #expect(coverageOver.signals.contains(where: { $0.kind == .opportunity && $0.title == "Income covers planned expenses" }))

        let recurring = analyzer.insightBundle(
            for: MarinaExecutionResult(
                kind: .metric,
                title: "Recurring Burden",
                rows: [
                    HomeAnswerRow(title: "Recurring total", value: "$800.00", amount: 800),
                    HomeAnswerRow(title: "Planned expenses", value: "$1,000.00", amount: 1_000),
                    HomeAnswerRow(title: "Recurring burden", value: "80.0%", amount: 0.8)
                ]
            ),
            plan: formulaPlan(entity: .preset, operation: .sum, measure: .recurringBurden)
        )
        #expect(recurring.signals.contains(where: { $0.kind == .caution && $0.title == "Most planned expenses are recurring" }))

        let concentration = analyzer.insightBundle(
            for: MarinaExecutionResult(
                kind: .metric,
                title: "Category Spend Share",
                rows: [
                    HomeAnswerRow(title: "Category", value: "Bills"),
                    HomeAnswerRow(title: "Category spend", value: "$400.00", amount: 400),
                    HomeAnswerRow(title: "Total spend", value: "$1,000.00", amount: 1_000),
                    HomeAnswerRow(title: "Concentration", value: "40.0%", amount: 0.4)
                ]
            ),
            plan: formulaPlan(entity: .category, operation: .share, measure: .concentration)
        )
        #expect(concentration.signals.contains(where: { $0.kind == .caution && $0.title == "One category is carrying a large share" }))

        let generic = analyzer.insightBundle(
            for: MarinaExecutionResult(
                kind: .metric,
                title: "Groceries Spend",
                rows: [HomeAnswerRow(title: "Total", value: "$120.00", amount: 120)]
            ),
            plan: formulaPlan(entity: .category, operation: .sum, measure: .budgetImpact)
        )
        #expect(generic.signals.contains(where: { $0.kind == .context && $0.title == "Primary detail" }))
    }

    @Test func insightFactsDigest_includesSuppliedFollowUpsWithoutInventingOthers() throws {
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .category,
                operation: .sum,
                measure: .budgetImpact,
                targetName: "Groceries",
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        let bundle = MarinaInsightBundle(
            headlineFact: "Groceries Spend: $120.00",
            meaning: "This metric answer reflects category sum for Apr 1, 2026 - Apr 30, 2026.",
            signals: [
                MarinaInsightSignal(kind: .context, title: "Primary detail", detail: "Total: $120.00"),
                MarinaInsightSignal(kind: .caution, title: "Daily room is tight", detail: "The remaining room is spread thin across the days left in this period.")
            ],
            followUps: [
                MarinaFollowUpSuggestion(
                    title: "Show biggest expenses in this category",
                    prompt: "Show biggest expenses in Groceries.",
                    reason: .inspectRows,
                    executionMode: .executable,
                    semanticRequest: MarinaSemanticRequest(
                        entity: .variableExpense,
                        operation: .list,
                        measure: .budgetImpact,
                        dimensions: [.category],
                        targetName: "Groceries",
                        expectedAnswerShape: .list
                    )
                )
            ]
        )
        let context = MarinaInsightContext(
            prompt: "How much did I spend on groceries?",
            result: MarinaExecutionResult(
                kind: .metric,
                title: "Groceries Spend",
                primaryValue: "$120.00",
                rows: [HomeAnswerRow(title: "Total", value: "$120.00", amount: 120)]
            ),
            plan: plan,
            insightBundle: bundle
        )

        let digest = MarinaAnswerFactsDigest(context: context).text()

        #expect(digest.contains("Deterministic headline fact: Groceries Spend: $120.00"))
        #expect(digest.contains("Deterministic signals:"))
        #expect(digest.contains("caution: Daily room is tight - The remaining room is spread thin across the days left in this period."))
        #expect(digest.contains("Recommended follow-up:"))
        #expect(digest.contains("Question: Want to see the biggest expenses behind this?"))
        #expect(digest.contains("Show biggest expenses in this category: Show biggest expenses in Groceries. [inspectRows, executable]"))
        #expect(digest.contains("Deterministic follow-ups:"))
        #expect(digest.contains("Show biggest expenses in this category: Show biggest expenses in Groceries. [inspectRows, executable]"))
        #expect(digest.contains("Which categories still have room?") == false)
    }

    #if canImport(FoundationModels)
    @Test func readAnswerFactsTool_returnsOnlySuppliedFacts() async throws {
        guard #available(iOS 26.0, *) else { return }

        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        let context = MarinaInsightContext(
            prompt: "Summarize my Apple Card.",
            result: MarinaExecutionResult(
                kind: .metric,
                title: "Apple Card Spend",
                primaryValue: "$1,370.00",
                rows: [HomeAnswerRow(title: "Variable", value: "$80.00")]
            ),
            plan: plan
        )
        let tool = MarinaReadAnswerFactsTool(context: context)
        let output = try await tool.call(arguments: MarinaReadAnswerFactsTool.Arguments(focus: nil))

        #expect(output.contains("Apple Card Spend"))
        #expect(output.contains("$1,370.00"))
        #expect(output.contains("Variable"))
        #expect(output.contains("SwiftData") == false)
    }

    @Test func foundationModelsInsightInstructionsRequireRecommendedFollowUpOnly() throws {
        guard #available(iOS 26.0, *) else { return }

        let instructions = MarinaFoundationModelsInsightRuntime.baseInstructions

        #expect(instructions.contains("If a Recommended follow-up question is supplied, write the answer, then a blank line, then that exact Recommended follow-up question."))
        #expect(instructions.contains("Do not invent, rewrite, or substitute follow-ups"))
        #expect(instructions.contains("Do not show raw follow-up prompts as visible questions unless they exactly match the Recommended follow-up question."))
        #expect(instructions.contains("If no Recommended follow-up question is supplied, do not add a next-step question."))
    }
    #endif

    @Test func deterministicInsightNarrator_producesWarmFallback() async throws {
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .remainingRoom,
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        let context = MarinaInsightContext(
            prompt: "What is my safe spend today?",
            result: MarinaExecutionResult(
                kind: .metric,
                title: "Safe Spend Today",
                primaryValue: "$42.00",
                rows: [HomeAnswerRow(title: "Period room", value: "$420.00")]
            ),
            plan: plan
        )

        let narration = try await MarinaDeterministicInsightNarrator().narration(for: context)
        #expect(narration?.contains("Safe Spend Today") == true)
        #expect(narration?.contains("$42.00") == true)
        #expect(narration?.contains("Period room") == true)
        #expect(narration?.hasPrefix("Marina:") == false)
    }

    @Test func narrationFinalizer_appendsRecommendedFollowUpWhenMissing() throws {
        let context = insightContext(followUps: [
            followUp(
                title: "What if I spend $50?",
                prompt: "What if I spend $50?",
                reason: .whatIf,
                mode: .executable
            )
        ])

        let finalized = MarinaNarrationFinalizer.finalized("Your safe daily room is tight for the rest of this period.", context: context)

        #expect(finalized == "Your safe daily room is tight for the rest of this period.\n\nWant to see what happens if you spend $50?")
    }

    @Test func recommendedFollowUpFormatterCreatesNaturalConfirmationQuestions() throws {
        let incomeComparison = MarinaFollowUpSuggestion(
            title: "Compare income to last period",
            prompt: "Compare income to last period.",
            reason: .comparePreviousPeriod,
            executionMode: .executable,
            semanticRequest: MarinaSemanticRequest(
                entity: .income,
                operation: .compare,
                measure: .incomeAmount,
                dateRangeToken: .currentPeriod,
                incomeState: .all,
                expectedAnswerShape: .comparison
            )
        )
        #expect(MarinaRecommendedFollowUp.confirmationQuestion(for: incomeComparison) == "Want to compare your income to last period?")

        let safeDaily = MarinaNarrationFinalizer.finalized("Your room is ready.", context: insightContext(followUps: [
            followUp(
                title: "What can I spend per day?",
                prompt: "What can I spend per day?",
                reason: .safeDailySpend,
                mode: .executable
            )
        ]))
        #expect(safeDaily == "Your room is ready.\n\nWant to check what you can spend per day?")

        let breakdown = MarinaNarrationFinalizer.finalized("Groceries is the main category.", context: insightContext(followUps: [
            followUp(
                title: "Show category share",
                prompt: "Show category share",
                reason: .breakdown,
                mode: .executable
            )
        ]))
        #expect(breakdown == "Groceries is the main category.\n\nWant to see the category breakdown?")

        let clarification = MarinaNarrationFinalizer.finalized("Pick another card to compare.", context: insightContext(followUps: [
            followUp(
                title: "Compare this card to another card",
                prompt: "Compare Apple Card to another card.",
                reason: .comparePreviousPeriod,
                mode: .clarificationRequired
            )
        ]))
        #expect(clarification == "Pick another card to compare.\n\nWant to narrow that down?")

        let showMore = MarinaFollowUpSuggestion(
            title: "Show more",
            prompt: "Show more.",
            reason: .showMore,
            executionMode: .executable,
            semanticRequest: MarinaSemanticRequest(
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category, .date],
                resultLimit: 10,
                expectedAnswerShape: .list
            )
        )
        #expect(MarinaRecommendedFollowUp.confirmationQuestion(for: showMore) == "Want to see more rows?")
    }

    @Test func factsDigestIncludesShowMoreFollowUpReason() throws {
        let context = insightContext(followUps: [
            MarinaFollowUpSuggestion(
                title: "Show more",
                prompt: "Show more.",
                reason: .showMore,
                executionMode: .executable,
                semanticRequest: MarinaSemanticRequest(
                    entity: .category,
                    operation: .group,
                    measure: .budgetImpact,
                    dimensions: [.category, .date],
                    resultLimit: 10,
                    expectedAnswerShape: .list
                )
            )
        ])
        let digest = MarinaAnswerFactsDigest(context: context).text()

        #expect(digest.contains("Question: Want to see more rows?"))
        #expect(digest.contains("Show more: Show more. [showMore, executable]"))
    }

    @Test func narrationFinalizer_doesNotDuplicateRecommendedFollowUp() throws {
        let context = insightContext(followUps: [
            followUp(
                title: "What if I spend $50?",
                prompt: "What if I spend $50?",
                reason: .whatIf,
                mode: .executable
            )
        ])
        let alreadyIncluded = "Your safe daily room is tight.\n\nWant to see what happens if you spend $50?"

        let finalized = MarinaNarrationFinalizer.finalized(alreadyIncluded, context: context)

        #expect(finalized == alreadyIncluded)
    }

    @Test func narrationFinalizer_skipsWhenNoRecommendedFollowUpExists() throws {
        let context = insightContext(followUps: [])

        let finalized = MarinaNarrationFinalizer.finalized("Your safe spend is ready.", context: context)

        #expect(finalized == "Your safe spend is ready.")
    }

    @Test func deterministicInsightNarrator_appendsRecommendedFollowUp() async throws {
        let context = insightContext(followUps: [
            followUp(
                title: "What if I spend $50?",
                prompt: "What if I spend $50?",
                reason: .whatIf,
                mode: .executable
            )
        ])

        let narration = try await MarinaDeterministicInsightNarrator().narration(for: context)

        #expect(narration?.contains("\n\nWant to see what happens if you spend $50?") == true)
        #expect(narration?.contains("?”?") == false)
    }

    @Test func deterministicInsightNarrator_usesReconciliationPerspectiveSentence() async throws {
        let context = reconciliationInsightContext(amount: 21.06)

        let narration = try await MarinaDeterministicInsightNarrator().narration(for: context)

        #expect(narration == "Alejandro owes you \(CurrencyFormatter.string(from: 21.06)).")
    }

    @Test func deterministicInsightNarrator_streamYieldsOneInstantFallback() async throws {
        let context = insightContext(
            kind: .metric,
            title: "Safe Spend Today",
            primaryValue: "$42.00",
            rows: [HomeAnswerRow(title: "Period room", value: "$420.00")]
        )

        let values = try await collect(MarinaDeterministicInsightNarrator().narrationStream(for: context))

        #expect(values.count == 1)
        #expect(values.first?.contains("Safe Spend Today") == true)
    }

    @Test func insightNarrator_streamSkipsNonNarratableContext() async throws {
        let context = insightContext(
            kind: .message,
            title: "Can you clarify?",
            primaryValue: nil,
            rows: []
        )

        let values = try await collect(MarinaInsightNarrator().narrationStream(for: context))

        #expect(values.isEmpty)
    }

    @Test func insightNarrator_modelStreamFailureFallsBackInstantly() async throws {
        let context = insightContext(
            kind: .metric,
            title: "Safe Spend Today",
            primaryValue: "$42.00",
            rows: [HomeAnswerRow(title: "Period room", value: "$420.00")]
        )
        let narrator = MarinaInsightNarrator(modelStreamProvider: { _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: TestNarrationError.failed)
            }
        })

        let values = try await collect(narrator.narrationStream(for: context))

        #expect(values.count == 1)
        #expect(values.first?.contains("Safe Spend Today") == true)
    }

    @Test func insightNarrator_modelStreamYieldsFinalRecommendedFollowUpWhenOmitted() async throws {
        let context = insightContext(followUps: [
            followUp(
                title: "What if I spend $50?",
                prompt: "What if I spend $50?",
                reason: .whatIf,
                mode: .executable
            )
        ])
        let narrator = MarinaInsightNarrator(modelStreamProvider: { _ in
            AsyncThrowingStream { continuation in
                continuation.yield("Your safe daily room is tight.")
                continuation.finish()
            }
        })

        let values = try await collect(narrator.narrationStream(for: context))

        #expect(values == [
            "Your safe daily room is tight.",
            "Your safe daily room is tight.\n\nWant to see what happens if you spend $50?"
        ])
    }

    @Test func voiceSanitizer_removesLeadingNameLabelsAndPreservesLaterMentions() throws {
        #expect(MarinaVoiceSanitizer.sanitizedFinal("Marina: I see your safe spend.") == "I see your safe spend.")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("Marina says: I see your safe spend.") == "I see your safe spend.")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("This is how Marina sees the answer.") == "This is how Marina sees the answer.")
    }

    @Test func voiceSanitizer_suppressesPartialStreamingNameLabels() throws {
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("M") == nil)
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("Ma") == nil)
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("Marina") == nil)
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("Marina: I see your safe spend.") == "I see your safe spend.")
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("I see your safe spend.") == "I see your safe spend.")
    }

    @Test func voiceSanitizer_rewritesAssistantOwnedFinancialOpenings() throws {
        #expect(MarinaVoiceSanitizer.sanitizedFinal("My income status is on track.") == "Your income status is on track.")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("My budget has room left.") == "Your budget has room left.")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("My read is that your income is on track.") == "My read is that your income is on track.")
    }

    @Test func voiceSanitizer_suppressesPartialAssistantOwnedFinancialOpenings() throws {
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("My income") == nil)
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("My income status is on track.") == "Your income status is on track.")
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("My read is that your income is on track.") == "My read is that your income is on track.")
    }

    @Test func voiceSanitizer_repairsReconciliationOwnershipInversions() throws {
        let positive = reconciliationInsightContext(amount: 21.06)
        let negative = reconciliationInsightContext(amount: -18.40)

        #expect(MarinaVoiceSanitizer.sanitizedFinal("You owe me \(CurrencyFormatter.string(from: 21.06)).", context: positive) == "Alejandro owes you \(CurrencyFormatter.string(from: 21.06)).")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("I owe you \(CurrencyFormatter.string(from: 18.40)).", context: negative) == "You owe Alejandro \(CurrencyFormatter.string(from: 18.40)).")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("Alejandro owes you \(CurrencyFormatter.string(from: 21.06)).", context: positive) == "Alejandro owes you \(CurrencyFormatter.string(from: 21.06)).")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("I can check your balance again.", context: positive) == "I can check your balance again.")
    }

    @Test func voiceSanitizer_suppressesPartialReconciliationOwnershipInversions() throws {
        let context = reconciliationInsightContext(amount: 21.06)

        #expect(MarinaVoiceSanitizer.sanitizedStreaming("You owe", context: context) == nil)
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("You owe me", context: context) == nil)
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("You owe me \(CurrencyFormatter.string(from: 21.06)).", context: context) == "Alejandro owes you \(CurrencyFormatter.string(from: 21.06)).")
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("Alejandro owes you \(CurrencyFormatter.string(from: 21.06)).", context: context) == "Alejandro owes you \(CurrencyFormatter.string(from: 21.06)).")
    }

    @Test func insightNarrator_modelStreamStripsLeadingNameLabel() async throws {
        let context = insightContext(
            kind: .metric,
            title: "Safe Spend Today",
            primaryValue: "$42.00",
            rows: [HomeAnswerRow(title: "Period room", value: "$420.00")]
        )
        let narrator = MarinaInsightNarrator(modelStreamProvider: { _ in
            AsyncThrowingStream { continuation in
                continuation.yield("Marina:")
                continuation.yield("Marina: I see your safe spend.")
                continuation.finish()
            }
        })

        let values = try await collect(narrator.narrationStream(for: context))

        #expect(values == ["I see your safe spend."])
    }

    @Test func insightNarrator_modelStreamRepairsReconciliationOwnershipInversion() async throws {
        let context = reconciliationInsightContext(amount: 21.06)
        let narrator = MarinaInsightNarrator(modelStreamProvider: { _ in
            AsyncThrowingStream { continuation in
                continuation.yield("You owe")
                continuation.yield("You owe me \(CurrencyFormatter.string(from: 21.06)).")
                continuation.finish()
            }
        })

        let values = try await collect(narrator.narrationStream(for: context))

        #expect(values == ["Alejandro owes you \(CurrencyFormatter.string(from: 21.06))."])
    }

    @Test func brain_addsInsightToSuccessfulAnswersAndSkipsTerminalAnswers() async throws {
        let fixture = try makeFixture()
        let narrator = RecordingInsightNarrator(response: "Stub insight.")
        let brain = legacyRuleBasedBrain(insightNarrator: narrator)

        let successful = await answer("What is my safe spend today?", using: brain, fixture: fixture)
        #expect(successful.kind == .metric)
        #expect(successful.explanation == "Stub insight.")
        #expect(narrator.contexts.count == 1)
        #expect(narrator.contexts.first?.title == "Safe Spend Today")

        let unsupported = await answer("delete my Apple Card", using: brain, fixture: fixture)
        #expect(unsupported.kind == .message)
        #expect(unsupported.explanation == nil)
        #expect(narrator.contexts.count == 1)

        let clarification = await answer(
            MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .clarification,
                clarificationQuestion: "Which matching record should Marina use?",
                unsupportedReason: .ambiguousEntity
            ),
            prompt: "Clarify this.",
            using: brain,
            fixture: fixture
        )
        #expect(clarification.kind == .message)
        #expect(clarification.explanation == nil)
        #expect(narrator.contexts.count == 1)
    }

    @Test func brain_keepsOriginalAnswerWhenInsightNarratorFails() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain(insightNarrator: ThrowingInsightNarrator())

        let answer = await answer("What is my safe spend today?", using: brain, fixture: fixture)
        #expect(answer.kind == .metric)
        #expect(answer.primaryValue != nil)
        #expect(answer.explanation == nil)
    }

    @Test func brain_answerSeedReturnsCardBeforeNarrationAndIncludesContextOnlyForNarratableAnswers() async throws {
        let fixture = try makeFixture()
        let narrator = RecordingInsightNarrator(response: "Stub insight.")
        let brain = legacyRuleBasedBrain(insightNarrator: narrator)

        let successful = await brain.answerSeed(
            prompt: "What is my safe spend today?",
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )

        #expect(successful.answer.kind == .metric)
        #expect(successful.answer.explanation == nil)
        #expect(successful.insightContext?.title == "Safe Spend Today")
        #expect(narrator.contexts.isEmpty)

        let terminal = await brain.answerSeed(
            prompt: "delete my Apple Card",
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )

        #expect(terminal.answer.kind == .message)
        #expect(terminal.insightContext == nil)
        #expect(narrator.contexts.isEmpty)
    }

    @Test func brain_completedAnswerCombinesStreamedNarrationWithSeed() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let seed = await brain.answerSeed(
            prompt: "What is my safe spend today?",
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )

        let completed = brain.completedAnswer(from: seed, streamingNarration: "Streamed insight.")

        #expect(completed.id == seed.answer.id)
        #expect(completed.rows == seed.answer.rows)
        #expect(completed.explanation == "Streamed insight.")
    }

    @Test func homeMetricParity_matchesCardCategoryAvailabilityIncomeAndNextPlannedCalculators() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let homeContext = MarinaPanelHomeContext(dateRange: fixture.currentRange)
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(
            for: fixture.workspace,
            modelContext: fixture.context,
            homeContext: homeContext,
            now: fixture.now
        )

        let appleCard = try #require(snapshot.cards.first(where: { $0.name == "Apple Card" }))
        let cardMetrics = HomeCardMetricsCalculator.metrics(
            for: appleCard,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            start: fixture.currentRange.startDate,
            end: fixture.currentRange.endDate,
            excludeFuturePlannedExpenses: false,
            excludeFutureVariableExpenses: false,
            now: fixture.now
        )
        let cardAnswer = await answer("Summarize my Apple Card.", using: brain, fixture: fixture, homeContext: homeContext)
        #expect(cardAnswer.primaryValue == CurrencyFormatter.string(from: cardMetrics.total))
        #expect(cardAnswer.rows.contains(where: { $0.title == "Planned" && $0.amount == cardMetrics.plannedTotal }))
        #expect(cardAnswer.rows.contains(where: { $0.title == "Variable" && $0.amount == cardMetrics.variableTotal }))

        let availability = HomeCategoryLimitsAggregator.build(
            budgets: snapshot.budgets,
            categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            rangeStart: fixture.currentRange.startDate,
            rangeEnd: fixture.currentRange.endDate
        )
        let availabilityAnswer = await answer("Show category availability.", using: brain, fixture: fixture, homeContext: homeContext)
        #expect(availabilityAnswer.rows.first(where: { $0.title == "Over" })?.value == AppNumberFormat.integer(availability.overCount))
        #expect(availabilityAnswer.rows.first(where: { $0.title == "Near" })?.value == AppNumberFormat.integer(availability.nearCount))

        let incomeProgress = HomeQueryEngine().execute(
            query: HomeQuery(intent: .incomeProgressSummary, dateRange: fixture.currentRange),
            categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            incomes: snapshot.incomes,
            now: fixture.now
        )
        let incomeAnswer = await answer("How is my income progress?", using: brain, fixture: fixture, homeContext: homeContext)
        #expect(incomeAnswer.primaryValue == incomeProgress.primaryValue)

        let safeSpend = HomeQueryEngine().execute(
            query: HomeQuery(intent: .safeSpendToday, dateRange: fixture.currentRange),
            budgets: snapshot.budgets,
            categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            incomes: snapshot.incomes,
            savingsEntries: snapshot.savingsEntries,
            now: fixture.now
        )
        let safeSpendAnswer = await answer("What is my safe spend today?", using: brain, fixture: fixture, homeContext: homeContext)
        #expect(safeSpendAnswer.primaryValue == safeSpend.primaryValue)

        let next = try #require(
            HomeNextPlannedExpenseFinder.nextExpense(
                from: snapshot.homePlannedExpenses,
                in: fixture.currentRange.startDate,
                to: fixture.currentRange.endDate,
                now: fixture.now
            )
        )
        let nextAnswer = await answer("What is my next planned expense?", using: brain, fixture: fixture, homeContext: homeContext)
        #expect(nextAnswer.rows.first(where: { $0.title == "Expense" })?.value == next.title)
    }

    @Test func homeMetricParity_honorsFutureExclusionButKeepsNextPlannedUnfiltered() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let includeFutureContext = MarinaPanelHomeContext(dateRange: fixture.currentRange)
        let excludeFutureContext = MarinaPanelHomeContext(
            dateRange: fixture.currentRange,
            excludeFuturePlannedExpensesFromCalculations: true,
            excludeFutureVariableExpensesFromCalculations: true
        )

        let included = await answer("Summarize my Apple Card.", using: brain, fixture: fixture, homeContext: includeFutureContext)
        let excluded = await answer("Summarize my Apple Card.", using: brain, fixture: fixture, homeContext: excludeFutureContext)
        #expect(included.primaryValue == CurrencyFormatter.string(from: 1_370))
        #expect(excluded.primaryValue == CurrencyFormatter.string(from: 1_280))

        let next = await answer("What is my next planned expense?", using: brain, fixture: fixture, homeContext: excludeFutureContext)
        #expect(next.primaryValue == CurrencyFormatter.string(from: 90))
        let nextHasExpenseRow = next.rows.contains { row in
            row.title == "Expense" && row.value == "Phone"
        }
        #expect(nextHasExpenseRow)
    }

    @Test func homeMetricParity_ignoresOrphanBudgetGeneratedPlannedExpenses() async throws {
        let fixture = try makeFixture()
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(
            for: fixture.workspace,
            modelContext: fixture.context,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            now: fixture.now
        )
        let appleCard = try #require(snapshot.cards.first(where: { $0.name == "Apple Card" }))
        let bills = try #require(snapshot.categories.first(where: { $0.name == "Bills" }))
        let orphan = PlannedExpense(
            title: "Orphan Generated Row",
            plannedAmount: 500,
            expenseDate: date(2026, 4, 9),
            workspace: fixture.workspace,
            card: appleCard,
            category: bills,
            sourceBudgetID: UUID()
        )
        fixture.context.insert(orphan)
        try fixture.context.save()

        let brain = legacyRuleBasedBrain()
        let answer = await answer("Summarize my Apple Card.", using: brain, fixture: fixture)
        #expect(answer.primaryValue == CurrencyFormatter.string(from: 1_370))
    }

    @Test func categoryAvailabilityList_returnsFilteredOverCategories() async throws {
        let fixture = try makeFixture(includeTransportationCategory: true)
        try addCategoryAvailabilityListScenario(to: fixture)
        let brain = legacyRuleBasedBrain()
        let expected = try expectedCategoryAvailabilityNames(fixture: fixture, filter: .over, limit: 5)

        let answer = await answer("Which 5 categories are over limit?", using: brain, fixture: fixture)

        #expect(answer.kind == .list)
        #expect(answer.title == "Categories Over Limit")
        #expect(answer.rows.map(\.title) == expected)
        #expect(answer.rows.allSatisfy { $0.objectType == .category })
        #expect(answer.rows.allSatisfy { $0.value.contains("Over") && $0.value.contains("Spent") })
    }

    @Test func categoryAvailabilityList_returnsNearAndUnderLimitCategories() async throws {
        let fixture = try makeFixture(includeTransportationCategory: true)
        try addCategoryAvailabilityListScenario(to: fixture)
        let brain = legacyRuleBasedBrain()

        let near = await answer("Which categories are near limit?", using: brain, fixture: fixture)
        let expectedNear = try expectedCategoryAvailabilityNames(fixture: fixture, filter: .near, limit: 5)
        #expect(near.kind == .list)
        #expect(near.title == "Categories Near Limit")
        #expect(near.rows.map(\.title) == expectedNear)

        let under = await answer("List categories under limit.", using: brain, fixture: fixture)
        let expectedUnder = try expectedCategoryAvailabilityNames(fixture: fixture, filter: .underLimit, limit: 5)
        #expect(under.kind == .list)
        #expect(under.title == "Categories Under Limit")
        #expect(under.rows.map(\.title) == expectedUnder)
        #expect(under.rows.contains(where: { $0.title == "Health" }))
        #expect(under.rows.contains(where: { $0.title == "Books" }))
    }

    @Test func categoryAvailabilityFollowUp_usesPreviousAvailabilityAnswer() async throws {
        let fixture = try makeFixture(includeTransportationCategory: true)
        try addCategoryAvailabilityListScenario(to: fixture)
        let brain = legacyRuleBasedBrain()
        let summary = await answer("Show category availability.", using: brain, fixture: fixture)
        let context = MarinaConversationContext(recentAnswers: [summary])

        let followUp = await answer(
            "Which 5 are over limit?",
            using: brain,
            fixture: fixture,
            conversationContext: context
        )

        #expect(summary.title == "Category Availability")
        let expected = try expectedCategoryAvailabilityNames(fixture: fixture, filter: .over, limit: 5)
        #expect(followUp.kind == .list)
        #expect(followUp.title == "Categories Over Limit")
        #expect(followUp.rows.map(\.title) == expected)
    }

    @Test func semanticContext_persistsAndSurvivesStreamingNarrationReplacement() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let seed = await brain.answerSeed(
            prompt: "Summarize my Apple Card.",
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )

        let context = try #require(seed.answer.semanticContext)
        #expect(context.request.entity == .card)
        #expect(context.request.targetName == "Apple Card")
        #expect(context.answerTitle == "Apple Card Spend")
        #expect(context.rowReferences.contains(where: { $0.title == "Variable" }))

        let insightBundle = try #require(seed.answer.insightBundle)
        let largest = try #require(insightBundle.followUps.first(where: { $0.title == "Show largest expenses on this card" }))
        let compare = try #require(insightBundle.followUps.first(where: { $0.title == "Compare this card to another card" }))
        #expect(largest.executionMode == .executable)
        #expect(largest.semanticRequest?.entity == .variableExpense)
        #expect(compare.executionMode == .clarificationRequired)
        #expect(compare.semanticRequest == nil)

        let streamed = brain.completedAnswer(from: seed, streamingNarration: "Apple Card is the largest card this period.")
        #expect(streamed.semanticContext == seed.answer.semanticContext)
        #expect(streamed.insightBundle == seed.answer.insightBundle)

        let suiteName = "MarinaSemanticPromptSuiteTests.semanticContext"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MarinaConversationStore(userDefaults: defaults, storageKeyPrefix: "tests.marina.semanticContext")
        store.saveAnswers([streamed], workspaceID: fixture.workspace.id)

        let loaded = try #require(store.loadAnswers(workspaceID: fixture.workspace.id).first)
        #expect(loaded.semanticContext == streamed.semanticContext)
        #expect(loaded.insightBundle == streamed.insightBundle)
        #expect(MarinaConversationContext(recentAnswers: [loaded]).lastSemanticContext == streamed.semanticContext)
    }

    @Test func recommendedFollowUpConfirmation_yesExecutesStoredRequestAndKeepsVisiblePrompt() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let summary = await answer("How is income progress?", using: brain, fixture: fixture)
        let context = MarinaConversationContext(recentAnswers: [summary])

        let recommendation = try #require(context.lastRecommendedFollowUp)
        #expect(MarinaRecommendedFollowUp.confirmationQuestion(for: recommendation) == "Want to compare your income to last period?")

        let yes = await answer("Yes", using: brain, fixture: fixture, conversationContext: context)

        #expect(yes.userPrompt == "Yes")
        #expect(yes.kind == .comparison)
        #expect(yes.title == "Income Comparison")
        #expect(yes.semanticContext?.request.entity == .income)
        #expect(yes.semanticContext?.request.operation == .compare)
        #expect(yes.insightBundle?.followUps.contains { $0.reason == .comparePreviousPeriod } == false)
        #expect(MarinaConversationContext(recentAnswers: [yes]).lastRecommendedFollowUp?.reason != .comparePreviousPeriod)
    }

    @Test func recommendedFollowUpConfirmation_noReturnsCasualMessageWithoutQuery() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let summary = await answer("How is income progress?", using: brain, fixture: fixture)

        let no = await answer(
            "No",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [summary])
        )

        #expect(no.userPrompt == "No")
        #expect(no.kind == .message)
        #expect(no.title == "")
        #expect(no.subtitle == nil)
        #expect(no.rows.isEmpty)
        #expect(no.attachment == nil)
        #expect(no.explanation == "No problem. I’m here whenever you want to dig into something else.")
        #expect(no.semanticContext == nil)
        #expect(no.insightBundle == nil)
        #expect(MarinaPanelView.hasAssistantCardContent(no) == false)

        let messages = MarinaConversationDisplayAdapter.messages(from: [no])
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].prompt == "No")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].answer?.explanation == "No problem. I’m here whenever you want to dig into something else.")
    }

    @Test func marinaPanel_assistantCardContentPredicateTreatsNormalAnswersAsVisible() throws {
        let metric = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            title: "Safe Spend Today",
            primaryValue: "$42.00"
        )
        let message = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "Can you clarify?",
            subtitle: "I found a few matches."
        )

        #expect(MarinaPanelView.hasAssistantCardContent(metric))
        #expect(MarinaPanelView.hasAssistantCardContent(message))
    }

    @Test func spendTrendsRecommendedFollowUpsDrillIntoExpenseRowsAfterComparison() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let trends = await answer("Show my spend trends.", using: brain, fixture: fixture)
        let trendsContext = MarinaConversationContext(recentAnswers: [trends])

        #expect(trends.title == "Spend Trends")
        #expect(trendsContext.lastRecommendedFollowUp?.reason == .comparePreviousPeriod)

        let previous = await answer("Yes please", using: brain, fixture: fixture, conversationContext: trendsContext)
        let previousContext = MarinaConversationContext(recentAnswers: [previous])

        #expect(previous.title == "Spend Trends")
        #expect(previous.semanticContext?.request.operation == .group)
        #expect(previous.semanticContext?.request.dateRangeToken == .previousPeriod)
        #expect(previousContext.lastRecommendedFollowUp?.reason == .inspectRows)

        let drillDown = await answer("Sure", using: brain, fixture: fixture, conversationContext: previousContext)

        #expect(drillDown.title == "Recent Expenses")
        #expect(drillDown.kind == .list)
        #expect(drillDown.semanticContext?.request.entity == .variableExpense)
        #expect(drillDown.semanticContext?.request.operation == .list)
        #expect(drillDown.semanticContext?.request.sort == .amountDescending)
        #expect(drillDown.semanticContext?.request.dimensions.contains(.date) == false)
        #expect(drillDown.rows.isEmpty == false)
        #expect(drillDown.rows.allSatisfy { $0.objectType == .plannedExpense || $0.objectType == .variableExpense })
        #expect(drillDown.insightBundle?.followUps.contains { $0.reason == .inspectRows } == false)
    }

    @Test func spendTrendsExpenseDriverPromptRoutesToExpenseRows() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()

        let answer = await answer("See the expenses driving my spend trends.", using: brain, fixture: fixture)

        #expect(answer.title == "Recent Expenses")
        #expect(answer.kind == .list)
        #expect(answer.semanticContext?.request.entity == .variableExpense)
        #expect(answer.semanticContext?.request.operation == .list)
        #expect(answer.semanticContext?.request.sort == .amountDescending)
        #expect(answer.rows.isEmpty == false)
    }

    @Test func comparisonDriverPromptsKeepCategoryDriversUnlessExpensesAreExplicit() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let comparison = await answer("Compare this budget period to last period.", using: brain, fixture: fixture)
        let context = MarinaConversationContext(recentAnswers: [comparison])

        let categoryDrivers = await answer("what drove the increase?", using: brain, fixture: fixture, conversationContext: context)
        #expect(categoryDrivers.kind == .list)
        #expect(categoryDrivers.semanticContext?.request.entity == .category)
        #expect(categoryDrivers.semanticContext?.request.operation == .group)

        let expenseDrivers = await answer("which expenses drove the increase?", using: brain, fixture: fixture, conversationContext: context)
        #expect(expenseDrivers.kind == .list)
        #expect(expenseDrivers.title == "Recent Expenses")
        #expect(expenseDrivers.semanticContext?.request.entity == .variableExpense)
        #expect(expenseDrivers.semanticContext?.request.operation == .list)
        #expect(expenseDrivers.rows.allSatisfy { $0.objectType == .plannedExpense || $0.objectType == .variableExpense })
    }

    @Test func recommendedFollowUpConfirmation_yesWithoutRecommendationDoesNotResolveHiddenRequest() throws {
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "Plain Answer"
        )
        let context = MarinaConversationContext(recentAnswers: [answer])

        #expect(MarinaFollowUpResolver().resolve(prompt: "Yes", conversationContext: context) == nil)
    }

    @Test func recommendedFollowUpConfirmation_aliasesRecognizeCommonYesAndNoReplies() throws {
        let yesReplies = [
            "yes",
            "sure",
            "okay",
            "go for it!",
            "let’s do it",
            "sounds good",
            "yup",
            "please do",
            "works for me"
        ]
        let noReplies = [
            "no",
            "nah",
            "no thanks",
            "no, thanks.",
            "no thank you",
            "not right now",
            "maybe later",
            "pass",
            "don’t do it"
        ]

        for reply in yesReplies {
            #expect(MarinaRecommendedFollowUp.isAffirmative(reply), "\(reply) should confirm the recommended follow-up.")
            #expect(MarinaRecommendedFollowUp.isNegative(reply) == false, "\(reply) should not decline the recommended follow-up.")
        }

        for reply in noReplies {
            #expect(MarinaRecommendedFollowUp.isNegative(reply), "\(reply) should decline the recommended follow-up.")
            #expect(MarinaRecommendedFollowUp.isAffirmative(reply) == false, "\(reply) should not confirm the recommended follow-up.")
        }
    }

    @Test func followUpResolver_drillsDownAndCorrectsCardAnswers() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let summary = await answer("Summarize my Apple Card.", using: brain, fixture: fixture)
        let context = MarinaConversationContext(recentAnswers: [summary])

        let largest = await answer("show largest 2", using: brain, fixture: fixture, conversationContext: context)
        #expect(largest.kind == .list)
        #expect(largest.title == "Apple Card Expenses")
        #expect(Array(largest.rows.map(\.title).prefix(2)) == ["Rent", "Phone"])
        #expect(Array(largest.rows.map(\.objectType).prefix(2)) == [.plannedExpense, .plannedExpense])

        let chase = await answer("what about Chase?", using: brain, fixture: fixture, conversationContext: context)
        #expect(chase.kind == .metric)
        #expect(chase.title == "Chase Spend")

        let appleStore = await answer("not Apple Card, Apple Store", using: brain, fixture: fixture, conversationContext: context)
        #expect(appleStore.kind == .metric)
        #expect(appleStore.title == "Apple Store Spend")
        #expect(appleStore.primaryValue == CurrencyFormatter.string(from: 300))
    }

    @Test func followUpResolver_completeStandaloneExpenseListDoesNotInheritRecentCardContext() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let summary = await answer("Summarize my Apple Card.", using: brain, fixture: fixture)
        let context = MarinaConversationContext(recentAnswers: [summary])

        let standalone = await answer(
            "List my most recent 5 expenses on Chase",
            using: brain,
            fixture: fixture,
            conversationContext: context
        )

        #expect(standalone.kind == .list)
        #expect(standalone.title == "Chase Expenses")
        #expect(standalone.semanticContext?.request.entity == .variableExpense)
        #expect(standalone.semanticContext?.request.operation == .list)
        #expect(standalone.semanticContext?.request.targetName == "Chase")
        #expect(standalone.semanticContext?.request.targetName != "Apple Card")
    }

    @Test func stabilization_knownPromptShapesStayTargetedWithMockedModelOutput() async throws {
        let fixture = try makeFixture(includeDebitCard: true, includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "What did I spend at Uber?": interpreted(.foundationModel, request: merchantSpend("Uber")),
            "Show my Food & Drink expenses from last month.": interpreted(.foundationModel, request: categoryList("Food & Drink", dateRangeToken: .previousMonth)),
            "How much did I spend on Groceries last month?": interpreted(.foundationModel, request: categorySpendTotalAsCategory("Groceries", dateRangeToken: .previousMonth)),
            "Compare Apple Card to Debit Card.": interpreted(.foundationModel, request: cardComparison("Apple Card", "Debit Card")),
            "What is my safe spend today?": interpreted(.foundationModel, request: safeDailySpend()),
            "What is eating my budget?": interpreted(.foundationModel, request: budgetConcentration())
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let uber = await seed("What did I spend at Uber?", using: brain, fixture: fixture)
        #expect(uber.answer.kind == .metric)
        #expect(uber.answer.title != "Card Spend")
        #expect(uber.debugTrace?.validatorOutput.textQuery == "Uber")
        #expect(uber.debugTrace?.validatorOutput.dimensions.contains(.merchantText) == true)
        #expect(uber.debugTrace?.executionRoute == .universal)
        #expect(uber.debugTrace?.universalScenario == .merchantVariableSpend)

        let food = await seed("Show my Food & Drink expenses from last month.", using: brain, fixture: fixture)
        #expect(food.answer.kind == .list)
        #expect(food.debugTrace?.validatorOutput.targetName == "Food & Drink")
        #expect(food.debugTrace?.validatorOutput.dateRangeToken == .previousMonth)
        #expect(food.answer.rows.isEmpty == false)
        #expect(food.answer.rows.contains { $0.title.contains("Burger") || $0.title.contains("Cafe") })

        let groceries = await seed("How much did I spend on Groceries last month?", using: brain, fixture: fixture)
        #expect(groceries.answer.kind == .metric)
        #expect(groceries.answer.title != "Budget Overview")
        #expect(groceries.debugTrace?.validatorOutput.targetName == "Groceries")
        #expect(groceries.debugTrace?.validatorOutput.dateRangeToken == .previousMonth)
        #expect(groceries.debugTrace?.validatorOutput.expenseScope == .unified)

        let comparison = await seed("Compare Apple Card to Debit Card.", using: brain, fixture: fixture)
        #expect(comparison.answer.kind == .comparison)
        #expect(comparison.answer.title == "Card Spend Comparison")
        #expect(comparison.debugTrace?.validatorOutput.targetName == "Apple Card")
        #expect(comparison.debugTrace?.validatorOutput.comparisonTargetName == "Debit Card")

        let safeSpend = await seed("What is my safe spend today?", using: brain, fixture: fixture)
        #expect(safeSpend.answer.kind == .metric)
        #expect(safeSpend.answer.title == "Safe Daily Spend")
        #expect(safeSpend.debugTrace?.validatorOutput.measure == .safeDailySpend)
        #expect(safeSpend.answer.primaryValue?.isEmpty == false)

        let concentration = await seed("What is eating my budget?", using: brain, fixture: fixture)
        #expect(concentration.answer.kind == .metric)
        #expect(concentration.answer.title == "Category Spend Share")
        #expect(concentration.answer.rows.contains { $0.title == "Category spend" })
        #expect(concentration.answer.rows.contains { $0.title == "Total spend" })
        #expect(concentration.answer.rows.contains { $0.title == "Concentration" })
    }

    @Test func stabilization_promptTargetLossCannotValidateToBroadAnswer() async throws {
        let fixture = try makeFixture(includeDebitCard: true, includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "What did I spend at Uber?": interpreted(.foundationModel, request: cardSpend("Apple Card")),
            "Show my Food & Drink expenses from last month.": interpreted(.foundationModel, request: broadExpenseList(dateRangeToken: .previousMonth)),
            "How much did I spend on Groceries last month?": interpreted(.foundationModel, request: budgetOverview(dateRangeToken: .previousMonth)),
            "Compare Apple Card to Debit Card.": interpreted(.foundationModel, request: MarinaSemanticRequest(
                entity: .card,
                operation: .compare,
                measure: .budgetImpact,
                dimensions: [.card],
                expectedAnswerShape: .comparison
            ))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let wrongTarget = await seed("What did I spend at Uber?", using: brain, fixture: fixture)
        #expect(wrongTarget.answer.kind == .message)
        #expect(wrongTarget.debugTrace?.validatorOutput.expectedAnswerShape == .unsupported)
        #expect(wrongTarget.debugTrace?.validatorOutput.unsupportedReason == .unresolvedEntity)
        #expect(wrongTarget.answer.title != "Card Spend")

        let food = await seed("Show my Food & Drink expenses from last month.", using: brain, fixture: fixture)
        #expect(food.debugTrace?.validatorOutput.expectedAnswerShape != .unsupported)
        #expect(food.debugTrace?.validatorOutput.dateRangeToken == .previousMonth)
        #expect(food.answer.title != "Budget Overview")

        let groceries = await seed("How much did I spend on Groceries last month?", using: brain, fixture: fixture)
        #expect(groceries.answer.kind == .message)
        #expect(groceries.debugTrace?.validatorOutput.expectedAnswerShape == .clarification)
        #expect(groceries.debugTrace?.validatorOutput.unsupportedReason == .ambiguousEntity)
        #expect(groceries.answer.title != "Budget Overview")

        let comparison = await seed("Compare Apple Card to Debit Card.", using: brain, fixture: fixture)
        #expect(comparison.answer.kind == .comparison)
        #expect(comparison.debugTrace?.validatorOutput.targetName == "Apple Card")
        #expect(comparison.debugTrace?.validatorOutput.comparisonTargetName == "Debit Card")
        #expect(comparison.debugTrace?.validatorOutput.expectedAnswerShape == .comparison)
        #expect(comparison.answer.title == "Card Spend Comparison")
    }

    @Test func stabilization_standalonePromptsDoNotInheritPreviousContextWithMockedModelOutput() async throws {
        let fixture = try makeFixture(includeDebitCard: true, includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "What is my safe spend today?": interpreted(.foundationModel, request: safeDailySpend()),
            "What did I spend at Uber?": interpreted(.foundationModel, request: merchantSpend("Uber")),
            "What is eating my budget?": interpreted(.foundationModel, request: budgetConcentration()),
            "Show my Food & Drink expenses from last month.": interpreted(.foundationModel, request: categoryList("Food & Drink", dateRangeToken: .previousMonth)),
            "Compare Apple Card to Debit Card.": interpreted(.foundationModel, request: cardComparison("Apple Card", "Debit Card")),
            "How much did I spend on Groceries last month?": interpreted(.foundationModel, request: categorySpendTotalAsCategory("Groceries", dateRangeToken: .previousMonth))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let safeSpend = await seed("What is my safe spend today?", using: brain, fixture: fixture)
        let uberAfterSafeSpend = await seed(
            "What did I spend at Uber?",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [safeSpend.answer])
        )
        #expect(uberAfterSafeSpend.debugTrace?.promptTreatment == .standalone)
        #expect(uberAfterSafeSpend.debugTrace?.priorContextChangedRequest == false)
        #expect(uberAfterSafeSpend.debugTrace?.validatorOutput.textQuery == "Uber")
        #expect(uberAfterSafeSpend.answer.title != "Safe Daily Spend")
        #expect(uberAfterSafeSpend.answer.title != "Card Spend")

        let concentration = await seed("What is eating my budget?", using: brain, fixture: fixture)
        let foodAfterConcentration = await seed(
            "Show my Food & Drink expenses from last month.",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [concentration.answer])
        )
        #expect(foodAfterConcentration.debugTrace?.promptTreatment == .standalone)
        #expect(foodAfterConcentration.debugTrace?.priorContextChangedRequest == false)
        #expect(foodAfterConcentration.debugTrace?.validatorOutput.targetName == "Food & Drink")
        #expect(foodAfterConcentration.debugTrace?.validatorOutput.dateRangeToken == .previousMonth)

        let comparison = await seed("Compare Apple Card to Debit Card.", using: brain, fixture: fixture)
        let groceriesAfterComparison = await seed(
            "How much did I spend on Groceries last month?",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [comparison.answer])
        )
        #expect(groceriesAfterComparison.debugTrace?.promptTreatment == .standalone)
        #expect(groceriesAfterComparison.debugTrace?.priorContextChangedRequest == false)
        #expect(groceriesAfterComparison.debugTrace?.validatorOutput.targetName == "Groceries")
        #expect(groceriesAfterComparison.debugTrace?.validatorOutput.comparisonTargetName == nil)
        #expect(groceriesAfterComparison.answer.title != "Card Spend Comparison")
    }

    @Test func stabilization_formulaConceptsRepairGenericFoundationModelShapes() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "What is my safe spend today?": interpreted(.foundationModel, request: genericBudgetList(shape: .metric)),
            "What is my projected spend this month?": interpreted(.foundationModel, request: genericBudgetList(dateRangeToken: .currentMonth, shape: .metric)),
            "Am I spending too fast this month?": interpreted(.foundationModel, request: genericBudgetCompare(dateRangeToken: .currentMonth)),
            "What is eating my budget?": interpreted(.foundationModel, request: genericCategoryList())
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let safeSpend = await seed("What is my safe spend today?", using: brain, fixture: fixture)
        #expect(safeSpend.debugTrace?.validatorOutput.entity == .budget)
        #expect(safeSpend.debugTrace?.validatorOutput.operation == .forecast)
        #expect(safeSpend.debugTrace?.validatorOutput.measure == .safeDailySpend)
        #expect(safeSpend.debugTrace?.validatorOutput.expectedAnswerShape == .metric)
        #expect(safeSpend.debugTrace?.interpretedSource == .foundationModel)
        #expect(safeSpend.debugTrace?.validatorNotes.contains("Validation repaired known formula-backed concept semantic shape.") == true)
        #expect(safeSpend.answer.kind == .metric)
        #expect(safeSpend.answer.title == "Safe Daily Spend")
        #expect(safeSpend.answer.title != "Budget Overview")

        let projected = await seed(
            "What is my projected spend this month?",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [safeSpend.answer])
        )
        #expect(projected.debugTrace?.promptTreatment == .standalone)
        #expect(projected.debugTrace?.priorContextChangedRequest == false)
        #expect(projected.debugTrace?.validatorOutput.entity == .budget)
        #expect(projected.debugTrace?.validatorOutput.operation == .forecast)
        #expect(projected.debugTrace?.validatorOutput.measure == .projectedSpend)
        #expect(projected.debugTrace?.validatorOutput.dateRangeToken == .currentMonth)
        #expect(projected.answer.kind == .metric)
        #expect(projected.answer.title == "Projected Spend")
        #expect(projected.answer.title != "Budget Overview")

        let pace = await seed("Am I spending too fast this month?", using: brain, fixture: fixture)
        #expect(pace.debugTrace?.validatorOutput.entity == .budget)
        #expect(pace.debugTrace?.validatorOutput.operation == .compare)
        #expect(pace.debugTrace?.validatorOutput.measure == .paceDifference)
        #expect(pace.debugTrace?.validatorOutput.expectedAnswerShape == .comparison)
        #expect(pace.answer.kind == .comparison)
        #expect(pace.answer.title == "Pace Difference")

        let concentration = await seed("What is eating my budget?", using: brain, fixture: fixture)
        #expect(concentration.debugTrace?.validatorOutput.entity == .category)
        #expect(concentration.debugTrace?.validatorOutput.operation == .share)
        #expect(concentration.debugTrace?.validatorOutput.measure == .concentration)
        #expect(concentration.debugTrace?.validatorOutput.expectedAnswerShape == .metric)
        #expect(concentration.answer.kind == .metric)
        #expect(concentration.answer.title == "Category Spend Share")
        #expect(concentration.answer.rows.contains { $0.title == "Category spend" })
        #expect(concentration.answer.rows.contains { $0.title == "Total spend" })
        #expect(concentration.answer.rows.contains { $0.title == "Concentration" })
    }

    @Test func stabilization_formulaRepairDoesNotOverrideExplicitExpenseTargets() async throws {
        let fixture = try makeFixture(includeDebitCard: true, includeStabilizationTargets: true)
        let badCardList = MarinaSemanticRequest(
            entity: .card,
            operation: .list,
            measure: .budgetImpact,
            dimensions: [.card],
            resultLimit: 10,
            sort: .dateDescending,
            expectedAnswerShape: .list
        )
        let badCardMetric = MarinaSemanticRequest(
            entity: .card,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            expectedAnswerShape: .metric
        )
        let interpreter = PromptMappedInterpreter([
            "Show my Hair Care expenses": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Hair Care")),
            "What did I spend at Uber": interpreted(.foundationModel, request: badCardMetric),
            "Compare Apple Card to Debit Card": interpreted(.foundationModel, request: genericCardComparison()),
            "Show my Apple Card expenses": interpreted(.foundationModel, request: badCardList)
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let hairCare = await seed("Show my Hair Care expenses", using: brain, fixture: fixture)
        assertCategoryExpenseListContract(
            hairCare.debugTrace?.validatorOutput,
            targetName: "Hair Care",
            dateRangeToken: .currentPeriod
        )
        #expect(hairCare.answer.rows.contains { $0.title == "Salon Visit" })
        #expect(hairCare.debugTrace?.validatorOutput.measure != .concentration)

        let uber = await seed("What did I spend at Uber", using: brain, fixture: fixture)
        #expect(uber.debugTrace?.validatorOutput.entity == .variableExpense)
        #expect(uber.debugTrace?.validatorOutput.dimensions == [.merchantText])
        #expect(uber.debugTrace?.validatorOutput.textQuery == "Uber")
        #expect(uber.debugTrace?.validatorOutput.measure == .budgetImpact)
        #expect(uber.answer.title != "Budget Overview")
        #expect(uber.answer.title != "Safe Daily Spend")

        let comparison = await seed("Compare Apple Card to Debit Card", using: brain, fixture: fixture)
        #expect(comparison.debugTrace?.validatorOutput.entity == .card)
        #expect(comparison.debugTrace?.validatorOutput.operation == .compare)
        #expect(comparison.debugTrace?.validatorOutput.measure == .budgetImpact)
        #expect(comparison.debugTrace?.validatorOutput.targetName == "Apple Card")
        #expect(comparison.debugTrace?.validatorOutput.comparisonTargetName == "Debit Card")
        #expect(comparison.answer.kind == .comparison)
        #expect(comparison.answer.title == "Card Spend Comparison")

        let appleCard = await seed("Show my Apple Card expenses", using: brain, fixture: fixture)
        #expect(appleCard.debugTrace?.validatorOutput.entity == .variableExpense)
        #expect(appleCard.debugTrace?.validatorOutput.dimensions == [.card])
        #expect(appleCard.debugTrace?.validatorOutput.targetName == "Apple Card")
        #expect(appleCard.debugTrace?.validatorOutput.measure == .budgetImpact)
        #expect(appleCard.answer.kind == .list)
        #expect(appleCard.answer.title != "Category Spend Share")
    }

    @Test func semanticContracts_categoryExpenseListsValidateToUnifiedExpenseRows() async throws {
        let fixture = try makeFixture(includeDebitCard: true, includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "Show my Hair Care Expenses": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Hair Care")),
            "What did I spend on Hair Care last month?": interpreted(.foundationModel, request: droppedCategoryExpenseList(dateRangeToken: .previousMonth)),
            "Show my Food & Drink expenses from last month.": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Food & Drink", dateRangeToken: .previousMonth))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let hairCare = await seed("Show my Hair Care Expenses", using: brain, fixture: fixture)
        assertCategoryExpenseListContract(hairCare.debugTrace?.validatorOutput, targetName: "Hair Care", dateRangeToken: .currentPeriod)
        #expect(hairCare.answer.kind == .list)
        #expect(hairCare.answer.rows.contains { $0.title == "Salon Visit" })

        let droppedHairCare = await seed("What did I spend on Hair Care last month?", using: brain, fixture: fixture)
        assertCategoryExpenseListContract(droppedHairCare.debugTrace?.validatorOutput, targetName: "Hair Care", dateRangeToken: .previousMonth)
        #expect(droppedHairCare.debugTrace?.candidateSearches.contains { $0.rawTargetText == "Hair Care" && $0.slot == "explicitPromptTarget" } == true)
        #expect(droppedHairCare.debugTrace?.validatorOutput.expectedAnswerShape != .unsupported)

        let food = await seed("Show my Food & Drink expenses from last month.", using: brain, fixture: fixture)
        assertCategoryExpenseListContract(food.debugTrace?.validatorOutput, targetName: "Food & Drink", dateRangeToken: .previousMonth)
        #expect(food.answer.kind == .list)
        #expect(food.answer.rows.isEmpty == false)
    }

    @Test func emptyCategoryExpenseListOffersExecutablePreviousPeriodFollowUp() async throws {
        let fixture = try makeFixture(
            includeDebitCard: true,
            includeStabilizationTargets: true,
            includeHairCareExpense: false
        )
        let interpreter = PromptMappedInterpreter([
            "Show my Hair Care expenses.": interpreted(.foundationModel, request: categoryList("Hair Care"))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let empty = await seed("Show my Hair Care expenses.", using: brain, fixture: fixture)
        let followUp = try #require(empty.answer.insightBundle?.followUps.first)

        #expect(empty.answer.kind == .message)
        #expect(empty.answer.title == "I didn't find any Hair Care expenses in this budgeting period.")
        #expect(followUp.reason == .comparePreviousPeriod)
        #expect(followUp.executionMode == .executable)
        #expect(followUp.semanticRequest?.dateRangeToken == .previousPeriod)
        #expect(MarinaRecommendedFollowUp.confirmationQuestion(for: followUp) == "Want me to check last period?")
        #expect(empty.answer.insightBundle?.followUps.contains { $0.reason == .searchAllTime } == true)

        let confirmed = await seed(
            "Yes",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [empty.answer])
        )

        #expect(confirmed.debugTrace?.promptTreatment == .recommendedFollowUpConfirmation)
        #expect(confirmed.debugTrace?.validatorOutput.dateRangeToken == .previousPeriod)
        #expect(confirmed.debugTrace?.validatorOutput.targetName == "Hair Care")
        #expect(confirmed.answer.kind == .message)
        #expect(confirmed.answer.title == "I didn't find any Hair Care expenses in last budgeting period.")
    }

    @Test func yearToDateWordingRepairsCurrentPeriodModelOutput() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let prompts = [
            "What have I spent on groceries so far this year?",
            "What did I spend on Groceries this year?",
            "Groceries year to date"
        ]
        let interpreter = PromptMappedInterpreter(
            Dictionary(uniqueKeysWithValues: prompts.map {
                ($0, interpreted(.foundationModel, request: categorySpendTotalAsCategory("Groceries", dateRangeToken: .currentPeriod)))
            })
        )
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        for prompt in prompts {
            let result = await seed(prompt, using: brain, fixture: fixture)
            let request = try #require(result.debugTrace?.validatorOutput)
            #expect(request.dateRangeToken == .yearToDate, "\(prompt)")
            #expect(request.dateRangeToken != .currentPeriod, "\(prompt)")
            #expect(request.targetName == "Groceries", "\(prompt)")
            #expect(request.dimensions.contains(.category), "\(prompt)")
        }
    }

    @Test func semanticContracts_categorySpendTotalValidatesToUnifiedCategoryMetric() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "How much did I spend on Groceries last month?": interpreted(.foundationModel, request: categorySpendTotalAsCategory("Groceries", dateRangeToken: .previousMonth))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let groceries = await seed("How much did I spend on Groceries last month?", using: brain, fixture: fixture)
        let request = try #require(groceries.debugTrace?.validatorOutput)
        #expect(request.entity == .category)
        #expect(request.operation == .sum)
        #expect(request.measure == .budgetImpact)
        #expect(request.dimensions.contains(.category))
        #expect(request.targetName == "Groceries")
        #expect(request.dateRangeToken == .previousMonth)
        #expect(request.expenseScope == .unified)
        #expect(request.expectedAnswerShape == .metric)
        #expect(groceries.answer.kind == .metric)
        #expect(groceries.answer.title != "Budget Overview")
    }

    @Test func semanticContracts_merchantSpendRetainsMerchantText() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "What did I spend at Uber?": interpreted(.foundationModel, request: merchantSpend("Uber"))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let uber = await seed("What did I spend at Uber?", using: brain, fixture: fixture)
        let request = try #require(uber.debugTrace?.validatorOutput)
        #expect(request.entity == .variableExpense)
        #expect(request.operation == .sum)
        #expect(request.measure == .budgetImpact)
        #expect(request.dimensions.contains(.merchantText))
        #expect(request.textQuery == "Uber" || request.targetDisplayName == "Uber")
        #expect(request.dimensions.contains(.card) == false)
        #expect(request.targetName == nil)
        #expect(uber.answer.title != "Card Spend")
        #expect(uber.answer.title != "Budget Overview")
    }

    @Test func semanticContracts_multiCardCompareRetainsBothExistingCards() async throws {
        let fixture = try makeFixture(includeDebitCard: true, includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "Compare Apple Card to Debit Card.": interpreted(.foundationModel, request: cardComparison("Apple Card", "Debit Card"))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let comparison = await seed("Compare Apple Card to Debit Card.", using: brain, fixture: fixture)
        let request = try #require(comparison.debugTrace?.validatorOutput)
        #expect(request.entity == .card)
        #expect(request.operation == .compare)
        #expect(request.measure == .budgetImpact)
        #expect(request.dimensions.contains(.card))
        #expect(request.targetName == "Apple Card")
        #expect(request.comparisonTargetName == "Debit Card")
        #expect(request.expectedAnswerShape == .comparison)
        #expect(comparison.answer.kind == .comparison)
        #expect(comparison.answer.title != "I can't answer that yet.")
    }

    @Test func semanticContracts_explicitTargetStabilizationRecoversManualQAPrompts() async throws {
        let fixture = try makeFixture(includeDebitCard: true, includeStabilizationTargets: true)
        let droppedCardComparison = MarinaSemanticRequest(
            entity: .card,
            operation: .compare,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: .previousMonth,
            expectedAnswerShape: .comparison
        )
        let badCardList = MarinaSemanticRequest(
            entity: .card,
            operation: .list,
            measure: .budgetImpact,
            dimensions: [.card],
            resultLimit: 10,
            sort: .dateDescending,
            expectedAnswerShape: .list
        )
        let badCardMetric = MarinaSemanticRequest(
            entity: .card,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            expectedAnswerShape: .metric
        )
        let interpreter = PromptMappedInterpreter([
            "Compare Apple Card to Debit Card last month.": interpreted(.foundationModel, request: droppedCardComparison),
            "Which was higher last month, Apple Card or Debit Card?": interpreted(.foundationModel, request: droppedCardComparison),
            "Compare my debit card and Apple Card spend last month.": interpreted(.foundationModel, request: badCardList),
            "Which card had more spend last month, my debit card or Apple Card?": interpreted(.foundationModel, request: badCardList),
            "Which card had less spend last month, my debit card or Apple Card?": interpreted(.foundationModel, request: badCardList),
            "Show my Apple Card expenses.": interpreted(.foundationModel, request: badCardList),
            "Show my Uber expenses.": interpreted(.foundationModel, request: badCardList),
            "Show me my Uber expenses.": interpreted(.foundationModel, request: badCardList),
            "What did I spend at Uber?": interpreted(.foundationModel, request: badCardMetric)
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let comparison = await seed("Compare Apple Card to Debit Card last month.", using: brain, fixture: fixture)
        #expect(comparison.answer.kind == .comparison)
        #expect(comparison.debugTrace?.validatorOutput.targetName == "Apple Card")
        #expect(comparison.debugTrace?.validatorOutput.comparisonTargetName == "Debit Card")
        #expect(comparison.debugTrace?.validatorOutput.dateRangeToken == .previousMonth)

        let higher = await seed("Which was higher last month, Apple Card or Debit Card?", using: brain, fixture: fixture)
        #expect(higher.answer.kind == .comparison)
        #expect(higher.debugTrace?.validatorOutput.targetName == "Apple Card")
        #expect(higher.debugTrace?.validatorOutput.comparisonTargetName == "Debit Card")
        #expect(higher.debugTrace?.validatorOutput.expectedAnswerShape == .comparison)

        let naturalComparison = await seed("Compare my debit card and Apple Card spend last month.", using: brain, fixture: fixture)
        #expect(naturalComparison.answer.kind == .comparison)
        #expect(naturalComparison.answer.title == "Card Spend Comparison")
        #expect(naturalComparison.debugTrace?.validatorOutput.entity == .card)
        #expect(naturalComparison.debugTrace?.validatorOutput.operation == .compare)
        #expect(naturalComparison.debugTrace?.validatorOutput.measure == .budgetImpact)
        #expect(naturalComparison.debugTrace?.validatorOutput.dimensions == [.card])
        #expect(naturalComparison.debugTrace?.validatorOutput.targetName == "Debit Card")
        #expect(naturalComparison.debugTrace?.validatorOutput.comparisonTargetName == "Apple Card")
        #expect(naturalComparison.debugTrace?.validatorOutput.expectedAnswerShape == .comparison)

        let moreSpendComparison = await seed("Which card had more spend last month, my debit card or Apple Card?", using: brain, fixture: fixture)
        #expect(moreSpendComparison.answer.kind == .comparison)
        #expect(moreSpendComparison.answer.title == "Card Spend Comparison")
        #expect(moreSpendComparison.debugTrace?.validatorOutput.entity == .card)
        #expect(moreSpendComparison.debugTrace?.validatorOutput.operation == .compare)
        #expect(moreSpendComparison.debugTrace?.validatorOutput.measure == .budgetImpact)
        #expect(moreSpendComparison.debugTrace?.validatorOutput.targetName == "Debit Card")
        #expect(moreSpendComparison.debugTrace?.validatorOutput.comparisonTargetName == "Apple Card")
        #expect(moreSpendComparison.debugTrace?.validatorOutput.expectedAnswerShape == .comparison)

        let lessSpendComparison = await seed("Which card had less spend last month, my debit card or Apple Card?", using: brain, fixture: fixture)
        #expect(lessSpendComparison.answer.kind == .comparison)
        #expect(lessSpendComparison.answer.title == "Card Spend Comparison")
        #expect(lessSpendComparison.debugTrace?.validatorOutput.entity == .card)
        #expect(lessSpendComparison.debugTrace?.validatorOutput.operation == .compare)
        #expect(lessSpendComparison.debugTrace?.validatorOutput.measure == .budgetImpact)
        #expect(lessSpendComparison.debugTrace?.validatorOutput.targetName == "Debit Card")
        #expect(lessSpendComparison.debugTrace?.validatorOutput.comparisonTargetName == "Apple Card")
        #expect(lessSpendComparison.debugTrace?.validatorOutput.expectedAnswerShape == .comparison)

        let appleCardList = await seed("Show my Apple Card expenses.", using: brain, fixture: fixture)
        #expect(appleCardList.answer.kind == .list)
        #expect(appleCardList.debugTrace?.validatorOutput.entity == .variableExpense)
        #expect(appleCardList.debugTrace?.validatorOutput.dimensions == [.card])
        #expect(appleCardList.debugTrace?.validatorOutput.targetName == "Apple Card")
        #expect(appleCardList.debugTrace?.validatorOutput.expenseScope == .unified)

        let uberList = await seed("Show my Uber expenses.", using: brain, fixture: fixture)
        #expect(uberList.answer.kind == .list)
        #expect(uberList.debugTrace?.validatorOutput.entity == .variableExpense)
        #expect(uberList.debugTrace?.validatorOutput.dimensions == [.merchantText])
        #expect(uberList.debugTrace?.validatorOutput.textQuery == "Uber")
        #expect(uberList.debugTrace?.validatorOutput.expenseScope == .unified)

        let uberListWithMe = await seed("Show me my Uber expenses.", using: brain, fixture: fixture)
        #expect(uberListWithMe.answer.kind == .list)
        #expect(uberListWithMe.debugTrace?.validatorOutput.textQuery == "Uber")
        #expect(uberListWithMe.debugTrace?.validatorOutput.expectedAnswerShape == .list)

        let uberMetric = await seed("What did I spend at Uber?", using: brain, fixture: fixture)
        #expect(uberMetric.answer.kind == .metric)
        #expect(uberMetric.debugTrace?.validatorOutput.entity == .variableExpense)
        #expect(uberMetric.debugTrace?.validatorOutput.dimensions == [.merchantText])
        #expect(uberMetric.debugTrace?.validatorOutput.textQuery == "Uber")
        #expect(uberMetric.debugTrace?.validatorOutput.expectedAnswerShape == .metric)
    }

    @Test func semanticContracts_standalonePromptsMatchFreshChatAfterUnrelatedContext() async throws {
        let fixture = try makeFixture(includeDebitCard: true, includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "What is my safe spend today?": interpreted(.foundationModel, request: safeDailySpend()),
            "What is eating my budget?": interpreted(.foundationModel, request: budgetConcentration()),
            "Compare Apple Card to Debit Card.": interpreted(.foundationModel, request: cardComparison("Apple Card", "Debit Card")),
            "What did I spend at Uber?": interpreted(.foundationModel, request: merchantSpend("Uber")),
            "Show my Food & Drink expenses from last month.": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Food & Drink", dateRangeToken: .previousMonth)),
            "How much did I spend on Groceries last month?": interpreted(.foundationModel, request: categorySpendTotalAsCategory("Groceries", dateRangeToken: .previousMonth))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let unrelatedSafeSpend = await seed("What is my safe spend today?", using: brain, fixture: fixture)
        await assertStandaloneContract(
            "What did I spend at Uber?",
            using: brain,
            fixture: fixture,
            priorAnswer: unrelatedSafeSpend.answer
        )

        let unrelatedConcentration = await seed("What is eating my budget?", using: brain, fixture: fixture)
        await assertStandaloneContract(
            "Show my Food & Drink expenses from last month.",
            using: brain,
            fixture: fixture,
            priorAnswer: unrelatedConcentration.answer
        )

        let unrelatedComparison = await seed("Compare Apple Card to Debit Card.", using: brain, fixture: fixture)
        await assertStandaloneContract(
            "How much did I spend on Groceries last month?",
            using: brain,
            fixture: fixture,
            priorAnswer: unrelatedComparison.answer
        )
    }

    @Test func standalonePrompt_doesNotUseRecentContext_forSubscriptionsExpenseList() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "What is my safe spend today?": interpreted(.foundationModel, request: safeDailySpend()),
            "Show me my Subscriptions expenses for this month.": interpreted(
                .foundationModel,
                request: categoryExpenseListAsCategory("Subscriptions", dateRangeToken: .currentMonth)
            )
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let safeSpend = await seed("What is my safe spend today?", using: brain, fixture: fixture)
        let subscriptions = await seed(
            "Show me my Subscriptions expenses for this month.",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [safeSpend.answer])
        )

        #expect(subscriptions.debugTrace?.promptTreatment == .standalone)
        #expect(subscriptions.debugTrace?.priorContextChangedRequest == false)
        #expect(subscriptions.debugTrace?.explicitPromptTargets.contains("Subscriptions") == true)
        #expect(subscriptions.debugTrace?.explicitPromptTargets.contains("Me My Subscriptions") == false)
        assertCategoryExpenseListContract(
            subscriptions.debugTrace?.validatorOutput,
            targetName: "Subscriptions",
            dateRangeToken: .currentMonth
        )
        #expect(subscriptions.answer.rows.contains { $0.title == "Music Subscription" })
    }

    @Test func standalonePrompt_doesNotUseRecentContext_forProjectedSpend() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "What is my safe spend today?": interpreted(.foundationModel, request: safeDailySpend()),
            "What is my projected spend this month?": interpreted(.foundationModel, request: projectedSpend(dateRangeToken: .currentMonth))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let safeSpend = await seed("What is my safe spend today?", using: brain, fixture: fixture)
        let projected = await seed(
            "What is my projected spend this month?",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [safeSpend.answer])
        )

        #expect(projected.debugTrace?.promptTreatment == .standalone)
        #expect(projected.debugTrace?.priorContextChangedRequest == false)
        #expect(projected.debugTrace?.validatorOutput.measure == .projectedSpend)
        #expect(projected.answer.title != "Budget Overview")
    }

    @Test func standalonePrompt_doesNotUseRecentContext_forUberSpend() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "What is my safe spend today?": interpreted(.foundationModel, request: safeDailySpend()),
            "What did I spend at Uber?": interpreted(.foundationModel, request: merchantSpend("Uber"))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let safeSpend = await seed("What is my safe spend today?", using: brain, fixture: fixture)
        let uber = await seed(
            "What did I spend at Uber?",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [safeSpend.answer])
        )

        #expect(uber.debugTrace?.promptTreatment == .standalone)
        #expect(uber.debugTrace?.priorContextChangedRequest == false)
        #expect(uber.debugTrace?.validatorOutput.textQuery == "Uber")
        #expect(uber.debugTrace?.validatorOutput.dimensions.contains(.merchantText) == true)
        #expect(uber.debugTrace?.validatorOutput.dimensions.contains(.card) == false)
        #expect(uber.answer.title != "Budget Overview")
        #expect(uber.answer.title != "Card Spend")
    }

    @Test func standalonePrompt_doesNotUseRecentContext_forGroceriesAfterComparison() async throws {
        let fixture = try makeFixture(includeDebitCard: true, includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "Compare Apple Card to Debit Card.": interpreted(.foundationModel, request: cardComparison("Apple Card", "Debit Card")),
            "How much did I spend on Groceries last month?": interpreted(
                .foundationModel,
                request: categorySpendTotalAsCategory("Groceries", dateRangeToken: .previousMonth)
            )
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let comparison = await seed("Compare Apple Card to Debit Card.", using: brain, fixture: fixture)
        let groceries = await seed(
            "How much did I spend on Groceries last month?",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [comparison.answer])
        )

        #expect(groceries.debugTrace?.promptTreatment == .standalone)
        #expect(groceries.debugTrace?.priorContextChangedRequest == false)
        #expect(groceries.debugTrace?.validatorOutput.targetName == "Groceries")
        #expect(groceries.debugTrace?.validatorOutput.comparisonTargetName == nil)
        #expect(groceries.answer.title != "Card Spend Comparison")
    }

    @Test func fullPromptAfterRecommendedFollowUp_doesNotExecuteVisibleFollowUp() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "How is income progress?": interpreted(.foundationModel, request: incomeProgress()),
            "Show my Hair Care expenses.": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Hair Care"))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let income = await seed("How is income progress?", using: brain, fixture: fixture)
        let context = MarinaConversationContext(recentAnswers: [income.answer])
        #expect(context.lastRecommendedFollowUp != nil)

        let hairCare = await seed(
            "Show my Hair Care expenses.",
            using: brain,
            fixture: fixture,
            conversationContext: context
        )

        #expect(hairCare.debugTrace?.promptTreatment == .standalone)
        #expect(hairCare.debugTrace?.priorContextChangedRequest == false)
        assertCategoryExpenseListContract(
            hairCare.debugTrace?.validatorOutput,
            targetName: "Hair Care",
            dateRangeToken: .currentPeriod
        )
        #expect(hairCare.answer.rows.contains { $0.title == "Salon Visit" })
        #expect(hairCare.answer.title != "Income Comparison")
    }

    @Test func showMeMoreAfterVisibleShowMore_executesRecommendedFollowUp() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "Show my Food & Drink expenses from last month.": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Food & Drink", dateRangeToken: .previousMonth)),
            "Show me more.": interpreted(.foundationModel, request: budgetOverview())
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)
        let context = await foodDrinkShowMoreContext(using: brain, fixture: fixture)

        let more = await seed("Show me more.", using: brain, fixture: fixture, conversationContext: context)

        #expect(more.debugTrace?.promptTreatment == .recommendedFollowUpConfirmation)
        #expect(more.debugTrace?.priorContextChangedRequest == true)
        #expect(more.debugTrace?.interpretedSource == .ruleBased)
        #expect(more.debugTrace?.validatorOutput.targetName == "Food & Drink")
        #expect(more.debugTrace?.validatorOutput.dateRangeToken == .previousMonth)
        #expect(more.debugTrace?.validatorOutput.resultLimit == 13)
        #expect(more.answer.title != "Budget Overview")
        #expect(interpreter.prompts.contains("Show me more.") == false)
    }

    @Test func yesAfterVisibleShowMore_executesRecommendedFollowUp() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "Show my Food & Drink expenses from last month.": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Food & Drink", dateRangeToken: .previousMonth)),
            "Yes.": interpreted(.foundationModel, request: budgetOverview())
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)
        let context = await foodDrinkShowMoreContext(using: brain, fixture: fixture)

        let yes = await seed("Yes.", using: brain, fixture: fixture, conversationContext: context)

        #expect(yes.debugTrace?.promptTreatment == .recommendedFollowUpConfirmation)
        #expect(yes.debugTrace?.priorContextChangedRequest == true)
        #expect(yes.debugTrace?.interpretedSource == .ruleBased)
        #expect(yes.debugTrace?.validatorOutput.targetName == "Food & Drink")
        #expect(yes.debugTrace?.validatorOutput.dateRangeToken == .previousMonth)
        #expect(yes.debugTrace?.validatorOutput.resultLimit == 13)
        #expect(yes.answer.title != "Budget Overview")
        #expect(interpreter.prompts.contains("Yes.") == false)
    }

    @Test func limitedFoodDrinkListKeepsFullTotalStableThroughShowMoreAndSure() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "Show my Food & Drink expenses from last month.": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Food & Drink", dateRangeToken: .previousMonth)),
            "Show me more.": interpreted(.foundationModel, request: budgetOverview()),
            "Sure.": interpreted(.foundationModel, request: budgetOverview())
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)

        let first = await seed("Show my Food & Drink expenses from last month.", using: brain, fixture: fixture)
        let firstAnswer = first.answer
        let firstContext = try #require(firstAnswer.semanticContext)
        let firstFollowUp = try #require(firstAnswer.insightBundle?.followUps.first(where: { $0.reason == .showMore }))

        #expect(firstAnswer.title == "Food & Drink Expenses")
        #expect(firstAnswer.rows.count == 8)
        #expect(firstContext.displayedRowCount == 8)
        #expect(firstContext.totalRowCount == 11)
        #expect(firstAnswer.subtitle == "Showing 8 of 11 Food & Drink expenses from last month.")
        #expect(firstAnswer.primaryValue == CurrencyFormatter.string(from: 112))
        #expect(MarinaRecommendedFollowUp.confirmationQuestion(for: firstFollowUp) == "Want to see the remaining 3?")

        let more = await seed(
            "Show me more.",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [firstAnswer])
        )
        let moreAnswer = more.answer
        let moreIDs = moreAnswer.rows.compactMap(\.sourceID)

        #expect(more.debugTrace?.promptTreatment == .recommendedFollowUpConfirmation)
        #expect(more.debugTrace?.validatorOutput.resultLimit == 13)
        #expect(moreAnswer.rows.count == 11)
        #expect(moreAnswer.primaryValue == firstAnswer.primaryValue)
        #expect(Set(moreIDs).count == moreIDs.count)
        #expect(moreAnswer.rows.contains { $0.title == "Burger Spot" })
        #expect(moreAnswer.rows.contains { $0.title == "Food & Drink Extra 9" })

        let sure = await seed(
            "Sure.",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [firstAnswer])
        )

        #expect(sure.debugTrace?.promptTreatment == .recommendedFollowUpConfirmation)
        #expect(sure.debugTrace?.validatorOutput.targetName == "Food & Drink")
        #expect(sure.debugTrace?.validatorOutput.resultLimit == 13)
        #expect(sure.answer.primaryValue == firstAnswer.primaryValue)
        #expect(interpreter.prompts.contains("Show me more.") == false)
        #expect(interpreter.prompts.contains("Sure.") == false)
    }

    @Test func noAfterVisibleShowMore_declinesWithoutModelCall() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "Show my Food & Drink expenses from last month.": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Food & Drink", dateRangeToken: .previousMonth)),
            "No.": interpreted(.foundationModel, request: budgetOverview())
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)
        let context = await foodDrinkShowMoreContext(using: brain, fixture: fixture)

        let no = await seed("No.", using: brain, fixture: fixture, conversationContext: context)

        #expect(no.debugTrace?.promptTreatment == .declinedFollowUp)
        #expect(no.answer.kind == .message)
        #expect(no.answer.title == "")
        #expect(no.scriptedNarration == "No problem. I’m here whenever you want to dig into something else.")
        #expect(interpreter.prompts.contains("No.") == false)
    }

    @Test func fullPromptAfterVisibleShowMore_remainsStandalone() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "Show my Food & Drink expenses from last month.": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Food & Drink", dateRangeToken: .previousMonth)),
            "Show my Hair Care expenses.": interpreted(.foundationModel, request: categoryExpenseListAsCategory("Hair Care"))
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)
        let context = await foodDrinkShowMoreContext(using: brain, fixture: fixture)

        let hairCare = await seed(
            "Show my Hair Care expenses.",
            using: brain,
            fixture: fixture,
            conversationContext: context
        )

        #expect(hairCare.debugTrace?.promptTreatment == .standalone)
        #expect(hairCare.debugTrace?.priorContextChangedRequest == false)
        assertCategoryExpenseListContract(
            hairCare.debugTrace?.validatorOutput,
            targetName: "Hair Care",
            dateRangeToken: .currentPeriod
        )
        #expect(hairCare.answer.rows.contains { $0.title == "Salon Visit" })
        #expect(hairCare.answer.title != "Budget Overview")
        #expect(hairCare.debugTrace?.validatorOutput.resultLimit != 15)
    }

    @Test func showMeMoreWithoutVisibleFollowUp_usesListContextOrTypedUnsupported() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let interpreter = PromptMappedInterpreter([
            "Show me more.": interpreted(.foundationModel, request: budgetOverview())
        ])
        let brain = modelBackedBrain(interpreter: interpreter, policy: .internalParityProven)
        var listRequest = categoryExpenseListAsCategory("Food & Drink", dateRangeToken: .previousMonth)
        listRequest.resultLimit = 5
        let listContext = MarinaAnswerSemanticContext(
            request: listRequest,
            dateRange: fixture.currentRange,
            comparisonDateRange: nil,
            answerKind: .list,
            answerTitle: "Food & Drink Expenses",
            answerSubtitle: nil,
            primaryValue: nil,
            rowReferences: []
        )
        let listAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            userPrompt: "Show my Food & Drink expenses from last month.",
            title: "Food & Drink Expenses",
            semanticContext: listContext
        )
        let contextual = await seed(
            "Show me more.",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [listAnswer])
        )

        #expect(contextual.debugTrace?.promptTreatment == .contextualFollowUp)
        #expect(contextual.debugTrace?.priorContextChangedRequest == true)
        #expect(contextual.debugTrace?.interpretedSource == .ruleBased)
        #expect(contextual.debugTrace?.validatorOutput.targetName == "Food & Drink")
        #expect(contextual.debugTrace?.validatorOutput.resultLimit == 10)
        #expect(contextual.answer.title != "Budget Overview")

        let unsupported = await seed("Show me more.", using: brain, fixture: fixture)

        #expect(unsupported.debugTrace?.promptTreatment == .contextualFollowUp)
        #expect(unsupported.debugTrace?.priorContextChangedRequest == true)
        #expect(unsupported.debugTrace?.interpretedSource == .ruleBased)
        #expect(unsupported.debugTrace?.validatorOutput.expectedAnswerShape == .unsupported)
        #expect(unsupported.debugTrace?.validatorOutput.unsupportedReason == .unsupportedCombination)
        #expect(unsupported.answer.title != "Budget Overview")
        #expect(interpreter.prompts.contains("Show me more.") == false)
    }

    @Test func showMoreAfterList_stillUsesContext() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let showMore = MarinaFollowUpSuggestion(
            title: "Show more",
            prompt: "Show more.",
            reason: .showMore,
            executionMode: .executable,
            semanticRequest: MarinaSemanticRequest(
                entity: .category,
                operation: .list,
                measure: .categoryAvailability,
                dimensions: [.category],
                dateRangeToken: .currentPeriod,
                resultLimit: 10,
                expectedAnswerShape: .list
            )
        )
        let list = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            userPrompt: "Show category availability.",
            title: "Category Availability",
            insightBundle: MarinaInsightBundle(followUps: [showMore])
        )
        let context = MarinaConversationContext(recentAnswers: [list])
        #expect(context.lastRecommendedFollowUp?.reason == .showMore)

        let more = await seed("Show more.", using: brain, fixture: fixture, conversationContext: context)

        #expect(more.debugTrace?.promptTreatment == .recommendedFollowUpConfirmation)
        #expect(more.debugTrace?.priorContextChangedRequest == true)
        #expect(more.debugTrace?.validatorOutput.resultLimit == 10)
    }

    @Test func whatAboutLastMonth_stillUsesContextWhenPriorRequestExists() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let savings = await answer("Summarize my Savings Account.", using: brain, fixture: fixture)

        let previous = await seed(
            "what about last month",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [savings])
        )

        #expect(previous.debugTrace?.promptTreatment == .contextualFollowUp)
        #expect(previous.debugTrace?.priorContextChangedRequest == true)
        #expect(previous.debugTrace?.validatorOutput.dateRangeToken == .previousMonth)
        #expect(previous.answer.title == "Savings Status")
    }

    @Test func semanticContracts_savingsContributionWhatIfIsFutureWorkAtRoutingAndFormulaLayers() throws {
        let fixture = try makeFixture()
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(for: fixture.workspace, modelContext: fixture.context)
        let request = MarinaSemanticRequest(
            entity: .savingsAccount,
            operation: .whatIf,
            measure: .savingsTotal,
            dateRangeToken: .currentMonth,
            whatIfAmount: 1_000,
            expectedAnswerShape: .comparison
        )

        let validated = MarinaSemanticRequestValidator().validate(
            interpreted: interpreted(.foundationModel, request: request),
            snapshot: snapshot,
            originalPrompt: "What if I saved 1000 instead of 723.44?"
        )

        #expect(request.whatIfAmount == 1_000)
        #expect(validated.request.expectedAnswerShape == .unsupported)
        #expect(validated.request.unsupportedReason == .incomeSavingsWhatIfUnsupported)
        #expect(MarinaUniversalRoutingPolicy.internalParityProven.scenario(for: request) == nil)
        #expect(MarinaUniversalRoutingPolicy.internalParityProven.allows(request) == false)
        #expect(MarinaSemanticUniversalPlanBridge().makePlan(from: request) == .unsupported(.unsupportedCombination))
        #expect(MarinaFormulaRegistry().supports(measure: .savingsTotal, surface: .semantic(.savingsAccount), operation: .whatIf) == false)
    }

    @Test func stabilization_nonexistentAndWeakTargetsDoNotBecomeConfidentBroadAnswers() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let validator = MarinaSemanticRequestValidator()
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(for: fixture.workspace, modelContext: fixture.context)

        let missingMerchant = validator.validate(
            interpreted: interpreted(.foundationModel, request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                targetName: "Moon Cafe",
                expectedAnswerShape: .metric
            )),
            snapshot: snapshot,
            originalPrompt: "What did I spend at Moon Cafe?"
        )
        #expect(missingMerchant.request.expectedAnswerShape == .unsupported)
        #expect(missingMerchant.request.unsupportedReason == .unresolvedEntity)

        let weakSearch = MarinaCandidateSearchService().search(
            MarinaCandidateSearchRequest(
                rawTargetText: "Food Coffee",
                semanticRequest: categorySpend("Food Coffee"),
                snapshot: snapshot
            )
        )
        #expect(weakSearch.ambiguityStatus == .weakOnly || weakSearch.ambiguityStatus == .noUsefulCandidate)
        #expect(weakSearch.recommendedMatch == nil)
    }

    @Test func stabilization_narrationReceivesOnlyDeterministicEvidence() async throws {
        let fixture = try makeFixture(includeStabilizationTargets: true)
        let narrator = RecordingInsightNarrator(response: "Uber was your biggest category at $999.")
        let brain = modelBackedBrain(
            interpreter: PromptMappedInterpreter([
                "What did I spend at Uber?": interpreted(.foundationModel, request: merchantSpend("Uber"))
            ]),
            policy: .internalParityProven,
            insightNarrator: narrator
        )

        _ = await answer("What did I spend at Uber?", using: brain, fixture: fixture)

        let context = try #require(narrator.contexts.first)
        #expect(context.entity == .variableExpense)
        #expect(context.measure == .budgetImpact)
        #expect(context.rows.allSatisfy { $0.title.contains("Uber") || $0.role != .evidence })
        #expect(context.rows.contains { $0.amount == 18 })
        #expect(context.rows.contains { $0.title.contains("Debit Card") } == false)
        #expect(context.rows.contains { $0.title.contains("Apple Card") } == false)
    }

    @Test func followUpResolver_drillsFromCategoryAvailabilityIntoCategoryTransactions() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let availability = await answer("Show category availability.", using: brain, fixture: fixture)
        let context = MarinaConversationContext(recentAnswers: [availability])

        let dining = await answer("show Dining transactions", using: brain, fixture: fixture, conversationContext: context)

        #expect(dining.kind == .list)
        #expect(dining.title == "Dining Expenses")
        #expect(dining.rows.map(\.title).contains("Starbucks"))
    }

    @Test func followUpResolver_refinesExpenseIncomeSavingsReconciliationAndPresetAnswers() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()

        let targetSpend = await answer("Target spend", using: brain, fixture: fixture)
        let targetDetails = await answer(
            "show details",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [targetSpend])
        )
        #expect(targetDetails.kind == .list)
        #expect(targetDetails.rows.contains(where: { $0.title == "Target groceries" }))

        let incomeProgress = await answer("How is income progress?", using: brain, fixture: fixture)
        let paycheckLastMonth = await answer(
            "actual only for Paycheck last month",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [incomeProgress])
        )
        #expect(paycheckLastMonth.kind == .metric)
        #expect(paycheckLastMonth.title == "Paycheck Actual Income")
        #expect(paycheckLastMonth.primaryValue == CurrencyFormatter.string(from: 2_800))

        let savings = await answer("Summarize my Savings Account.", using: brain, fixture: fixture)
        let savingsLastMonth = await answer(
            "last month",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [savings])
        )
        #expect(savingsLastMonth.title == "Savings Status")

        let reconciliation = await answer("Alejandro balance", using: brain, fixture: fixture)
        let previousReconciliation = await answer(
            "last month",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [reconciliation])
        )
        #expect(previousReconciliation.kind == .metric)
        #expect(previousReconciliation.title == "Alejandro Balance")
        #expect(previousReconciliation.primaryValue == CurrencyFormatter.string(from: 20))

        let preset = await answer("Summarize my Phone preset.", using: brain, fixture: fixture)
        let rentPreset = await answer(
            "what about Rent?",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [preset])
        )
        #expect(rentPreset.kind == .metric)
        #expect(rentPreset.title == "Rent Preset")
    }

    @Test func followUpResolver_comparisonDriversAndAmbiguousCorrectionsStayDeterministic() async throws {
        let fixture = try makeFixture(includeAppleMerchantExpense: true)
        let brain = legacyRuleBasedBrain()

        let comparison = await answer("Compare this budget period to last period.", using: brain, fixture: fixture)
        let drivers = await answer(
            "what drove the increase?",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [comparison])
        )
        #expect(comparison.kind == .comparison)
        #expect(drivers.kind == .list)
        #expect(drivers.rows.isEmpty == false)

        let clarification = await answer("How much did I spend on Apple?", using: brain, fixture: fixture)
        let stillClarifies = await answer(
            "I meant Apple",
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [clarification])
        )
        #expect(clarification.title == "Can you clarify?")
        #expect(stillClarifies.title == "Can you clarify?")
        guard case .clarificationChoices(let choices)? = stillClarifies.attachment else {
            Issue.record("Expected Apple ambiguity to stay a clarification.")
            return
        }
        #expect(choices.choices.map(\.title).contains("Apple Store"))
        #expect(choices.choices.map(\.title).contains("Apple Card"))
    }

    @Test func categoryAvailabilityList_emptyStatesAreSpecific() async throws {
        let fixture = try makeFixture()
        let brain = legacyRuleBasedBrain()
        let may = HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31))

        let noBudget = await answer(
            "Which categories are over limit?",
            using: brain,
            fixture: fixture,
            homeContext: MarinaPanelHomeContext(dateRange: may)
        )
        #expect(noBudget.kind == .message)
        #expect(noBudget.title == "Categories Over Limit")
        #expect(noBudget.subtitle == "No budget overlaps May 2026.")

        let noOver = await answer("Which categories are over limit?", using: brain, fixture: fixture)
        #expect(noOver.kind == .message)
        #expect(noOver.title == "Categories Over Limit")
        #expect(noOver.subtitle == "No categories are over limit for April 2026.")
    }

    @Test func safeSpendWhatIf_uncappedCategoriesUseBaseRoom() async throws {
        let fixture = try makeFixture(includeAppleMerchantExpense: false)
        let brain = legacyRuleBasedBrain()

        let answer = await answer("If I spend $5 on Groceries, what happens to my safe spend?", using: brain, fixture: fixture)

        #expect(answer.kind == .comparison)
        let currentSafeSpend = answer.rows.first(where: { $0.title == "Current safe spend today" })?.amount ?? -1
        let safeSpendAfter = answer.rows.first(where: { $0.title == "Safe spend after" })?.amount ?? -1
        #expect(abs(currentSafeSpend - 145) < 0.0001)
        #expect(abs(safeSpendAfter - 144.54545454545453) < 0.0001)
        #expect(answer.rows.first(where: { $0.title == "Period room after" })?.amount == 1_590)
    }

    @Test func safeSpendWhatIf_allCategoriesCappedReducesCategoryCapRoom() async throws {
        let fixture = try makeFixture(includeAppleMerchantExpense: false)
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(
            for: fixture.workspace,
            modelContext: fixture.context,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            now: fixture.now
        )
        let budget = try #require(snapshot.budgets.first(where: { $0.name == "April 2026" }))
        let dining = try #require(snapshot.categories.first(where: { $0.name == "Dining" }))
        let bills = try #require(snapshot.categories.first(where: { $0.name == "Bills" }))
        let diningLimit = BudgetCategoryLimit(minAmount: 0, maxAmount: 200, budget: budget, category: dining)
        let billsLimit = BudgetCategoryLimit(minAmount: 0, maxAmount: 2_000, budget: budget, category: bills)
        budget.categoryLimits = (budget.categoryLimits ?? []) + [diningLimit, billsLimit]
        fixture.context.insert(diningLimit)
        fixture.context.insert(billsLimit)
        try fixture.context.save()

        let brain = legacyRuleBasedBrain()
        let answer = await answer("If I spend $5 on Groceries, what happens to my safe spend?", using: brain, fixture: fixture)

        #expect(answer.kind == .comparison)
        let currentSafeSpend = answer.rows.first(where: { $0.title == "Current safe spend today" })?.amount ?? -1
        let safeSpendAfter = answer.rows.first(where: { $0.title == "Safe spend after" })?.amount ?? -1
        #expect(abs(currentSafeSpend - 81.36363636363636) < 0.0001)
        #expect(abs(safeSpendAfter - 80.9090909090909) < 0.0001)
        #expect(answer.rows.first(where: { $0.title == "Period room after" })?.amount == 890)
    }

    @Test func conversationDisplayAdapter_preservesUserPromptAsSeparateMessage() throws {
        let suiteName = "MarinaSemanticPromptSuiteTests.conversationDisplay"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MarinaConversationStore(userDefaults: defaults, storageKeyPrefix: "tests.marina.display")
        let workspaceID = UUID()
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            userPrompt: "What is my safe spend today?",
            title: "Safe Spend Today",
            primaryValue: "$42.00"
        )

        store.saveAnswers([answer], workspaceID: workspaceID)
        let loaded = store.loadAnswers(workspaceID: workspaceID)
        #expect(loaded.first?.userPrompt == "What is my safe spend today?")

        let messages = MarinaConversationDisplayAdapter.messages(from: loaded)
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].prompt == "What is my safe spend today?")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].answer?.title == "Safe Spend Today")
    }

    private func answer(
        _ prompt: String,
        using brain: MarinaBrain,
        fixture: Fixture,
        homeContext: MarinaPanelHomeContext? = nil,
        conversationContext: MarinaConversationContext = MarinaConversationContext()
    ) async -> HomeAnswer {
        let resolvedHomeContext = homeContext ?? MarinaPanelHomeContext(dateRange: fixture.currentRange)
        return await brain.answer(
            prompt: prompt,
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: resolvedHomeContext,
            defaultBudgetingPeriod: .monthly,
            conversationContext: conversationContext,
            now: fixture.now
        )
    }

    private func answer(
        _ request: MarinaSemanticRequest,
        prompt: String,
        using brain: MarinaBrain,
        fixture: Fixture
    ) async -> HomeAnswer {
        await brain.answer(
            resolvedRequest: request,
            prompt: prompt,
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )
    }

    private func seed(
        _ prompt: String,
        using brain: MarinaBrain,
        fixture: Fixture,
        homeContext: MarinaPanelHomeContext? = nil,
        conversationContext: MarinaConversationContext = MarinaConversationContext()
    ) async -> MarinaAnswerSeed {
        await brain.answerSeed(
            prompt: prompt,
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: homeContext ?? MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            conversationContext: conversationContext,
            now: fixture.now
        )
    }

    private func foodDrinkShowMoreContext(
        using brain: MarinaBrain,
        fixture: Fixture
    ) async -> MarinaConversationContext {
        let food = await seed("Show my Food & Drink expenses from last month.", using: brain, fixture: fixture)
        let context = MarinaConversationContext(recentAnswers: [food.answer])
        #expect(food.debugTrace?.promptTreatment == .standalone)
        #expect(food.debugTrace?.validatorOutput.targetName == "Food & Drink")
        #expect(context.lastRecommendedFollowUp?.reason == .showMore)
        #expect(context.lastRecommendedFollowUp?.semanticRequest?.resultLimit == 13)
        #expect(context.lastRecommendedFollowUp.map { MarinaRecommendedFollowUp.confirmationQuestion(for: $0) } == "Want to see the remaining 3?")
        return context
    }

    private func legacyRuleBasedBrain(
        insightNarrator: (any MarinaInsightNarrating)? = nil
    ) -> MarinaBrain {
        MarinaBrain(
            interpreter: MarinaRuleBasedInterpreter(),
            insightNarrator: insightNarrator,
            universalRoutingPolicyProvider: { .disabled }
        )
    }

    private func modelBackedBrain(
        interpreter: any MarinaModelInterpreting,
        policy: MarinaUniversalRoutingPolicy,
        insightNarrator: (any MarinaInsightNarrating)? = nil
    ) -> MarinaBrain {
        MarinaBrain(
            interpreter: interpreter,
            insightNarrator: insightNarrator,
            universalRoutingPolicyProvider: { policy }
        )
    }

    private func interpreted(
        _ source: MarinaSemanticSource,
        request: MarinaSemanticRequest
    ) -> MarinaInterpretedSemanticRequest {
        MarinaInterpretedSemanticRequest(
            request: request,
            confidence: .medium,
            source: source
        )
    }

    private func merchantSpend(_ textQuery: String) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            textQuery: textQuery,
            targetDisplayName: textQuery,
            expenseScope: .variable,
            expectedAnswerShape: .metric
        )
    }

    private func categoryExpenseListAsCategory(
        _ categoryName: String,
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .category,
            operation: .list,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: dateRangeToken,
            targetName: categoryName,
            targetDisplayName: categoryName,
            resultLimit: 8,
            sort: nil,
            expenseScope: nil,
            expectedAnswerShape: .list
        )
    }

    private func categorySpendTotalAsCategory(
        _ categoryName: String,
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .category,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: dateRangeToken,
            targetName: categoryName,
            targetDisplayName: categoryName,
            expenseScope: .unified,
            expectedAnswerShape: .metric
        )
    }

    private func categorySpend(
        _ categoryName: String,
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: dateRangeToken,
            targetName: categoryName,
            targetDisplayName: categoryName,
            expenseScope: .variable,
            expectedAnswerShape: .metric
        )
    }

    private func categoryList(
        _ categoryName: String,
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: dateRangeToken,
            targetName: categoryName,
            targetDisplayName: categoryName,
            resultLimit: 10,
            sort: .dateDescending,
            expenseScope: .unified,
            expectedAnswerShape: .list
        )
    }

    private func droppedCategoryExpenseList(
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dimensions: [.category, .merchantText],
            dateRangeToken: dateRangeToken,
            resultLimit: 10,
            sort: .dateDescending,
            expenseScope: .unified,
            expectedAnswerShape: .list
        )
    }

    private func assertCategoryExpenseListContract(
        _ request: MarinaSemanticRequest?,
        targetName: String,
        dateRangeToken: MarinaSemanticDateRangeToken
    ) {
        guard let request else {
            Issue.record("Expected validated semantic request.")
            return
        }
        #expect(request.entity == .variableExpense)
        #expect(request.operation == .list)
        #expect(request.measure == .budgetImpact)
        #expect(request.dimensions.contains(.category))
        #expect(request.dimensions.contains(.merchantText) == false)
        #expect(request.targetName == targetName)
        #expect(request.dateRangeToken == dateRangeToken)
        #expect(request.expenseScope == .unified)
        #expect(request.expectedAnswerShape == .list)
    }

    private func assertStandaloneContract(
        _ prompt: String,
        using brain: MarinaBrain,
        fixture: Fixture,
        priorAnswer: HomeAnswer
    ) async {
        let fresh = await seed(prompt, using: brain, fixture: fixture)
        let contextual = await seed(
            prompt,
            using: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [priorAnswer])
        )

        #expect(contextual.debugTrace?.promptTreatment == .standalone)
        #expect(contextual.debugTrace?.priorContextChangedRequest == false)
        #expect(contextual.debugTrace?.validatorOutput == fresh.debugTrace?.validatorOutput)
        #expect(contextual.answer.kind == fresh.answer.kind)
        #expect(contextual.answer.title == fresh.answer.title)
    }

    private func cardSpend(_ cardName: String) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .card,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            targetName: cardName,
            targetDisplayName: cardName,
            expenseScope: .variable,
            expectedAnswerShape: .metric
        )
    }

    private func cardComparison(_ leftName: String, _ rightName: String) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .card,
            operation: .compare,
            measure: .budgetImpact,
            dimensions: [.card],
            targetName: leftName,
            comparisonTargetName: rightName,
            expectedAnswerShape: .comparison
        )
    }

    private func safeDailySpend() -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .safeDailySpend,
            expectedAnswerShape: .metric
        )
    }

    private func projectedSpend(dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .projectedSpend,
            dateRangeToken: dateRangeToken,
            expectedAnswerShape: .metric
        )
    }

    private func incomeProgress() -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .income,
            operation: .share,
            measure: .incomeAmount,
            dateRangeToken: .currentPeriod,
            incomeState: .all,
            expectedAnswerShape: .metric
        )
    }

    private func budgetConcentration() -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .category,
            operation: .share,
            measure: .concentration,
            expectedAnswerShape: .metric
        )
    }

    private func genericBudgetList(
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod,
        shape: MarinaSemanticAnswerShape = .list
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .budget,
            operation: .list,
            measure: nil,
            dateRangeToken: dateRangeToken,
            expectedAnswerShape: shape
        )
    }

    private func genericBudgetCompare(
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .budget,
            operation: .compare,
            measure: nil,
            dateRangeToken: dateRangeToken,
            expectedAnswerShape: .comparison
        )
    }

    private func genericCategoryList(
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .category,
            operation: .list,
            measure: nil,
            dimensions: [.category],
            dateRangeToken: dateRangeToken,
            expectedAnswerShape: .list
        )
    }

    private func genericCardComparison() -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .card,
            operation: .compare,
            measure: .budgetImpact,
            dimensions: [.card],
            expectedAnswerShape: .comparison
        )
    }

    private func broadExpenseList(dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dateRangeToken: dateRangeToken,
            resultLimit: 10,
            sort: .dateDescending,
            expenseScope: .unified,
            expectedAnswerShape: .list
        )
    }

    private func budgetOverview(dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .remainingRoom,
            dateRangeToken: dateRangeToken,
            expectedAnswerShape: .metric
        )
    }

    private func addCategoryAvailabilityListScenario(to fixture: Fixture) throws {
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(
            for: fixture.workspace,
            modelContext: fixture.context,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            now: fixture.now
        )
        let budget = try #require(snapshot.budgets.first(where: { $0.name == "April 2026" }))
        let groceries = try #require(snapshot.categories.first(where: { $0.name == "Groceries" }))
        let dining = try #require(snapshot.categories.first(where: { $0.name == "Dining" }))
        let bills = try #require(snapshot.categories.first(where: { $0.name == "Bills" }))
        let transportation = try #require(snapshot.categories.first(where: { $0.name == "Transportation" }))

        let travel = Category(name: "Travel", hexColor: "#7C3AED", workspace: fixture.workspace)
        let health = Category(name: "Health", hexColor: "#DB2777", workspace: fixture.workspace)
        let books = Category(name: "Books", hexColor: "#CA8A04", workspace: fixture.workspace)
        let travelPlan = PlannedExpense(
            title: "Weekend Trip",
            plannedAmount: 75,
            expenseDate: date(2026, 4, 16),
            workspace: fixture.workspace,
            category: travel
        )
        let healthPlan = PlannedExpense(
            title: "Prescription",
            plannedAmount: 95,
            expenseDate: date(2026, 4, 17),
            workspace: fixture.workspace,
            category: health
        )
        let booksPlan = PlannedExpense(
            title: "Bookstore",
            plannedAmount: 40,
            expenseDate: date(2026, 4, 18),
            workspace: fixture.workspace,
            category: books
        )

        fixture.context.insert(travel)
        fixture.context.insert(health)
        fixture.context.insert(books)
        fixture.context.insert(travelPlan)
        fixture.context.insert(healthPlan)
        fixture.context.insert(booksPlan)

        setLimit(100, for: groceries, in: budget, context: fixture.context)
        setLimit(20, for: dining, in: budget, context: fixture.context)
        setLimit(1_000, for: bills, in: budget, context: fixture.context)
        setLimit(20, for: transportation, in: budget, context: fixture.context)
        setLimit(50, for: travel, in: budget, context: fixture.context)
        setLimit(100, for: health, in: budget, context: fixture.context)
        setLimit(100, for: books, in: budget, context: fixture.context)

        try fixture.context.save()
    }

    private func setLimit(
        _ maxAmount: Double,
        for category: Offshore.Category,
        in budget: Budget,
        context: ModelContext
    ) {
        if let existing = budget.categoryLimits?.first(where: { $0.category?.id == category.id }) {
            existing.maxAmount = maxAmount
            return
        }

        let limit = BudgetCategoryLimit(minAmount: 0, maxAmount: maxAmount, budget: budget, category: category)
        budget.categoryLimits = (budget.categoryLimits ?? []) + [limit]
        context.insert(limit)
    }

    private func expectedCategoryAvailabilityNames(
        fixture: Fixture,
        filter: MarinaCategoryAvailabilityFilter,
        limit: Int
    ) throws -> [String] {
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(
            for: fixture.workspace,
            modelContext: fixture.context,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            now: fixture.now
        )
        let result = HomeCategoryLimitsAggregator.build(
            budgets: snapshot.budgets,
            categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            rangeStart: fixture.currentRange.startDate,
            rangeEnd: fixture.currentRange.endDate
        )

        return result.metrics
            .filter { metric in
                let status = metric.status(for: .all, nearThreshold: HomeCategoryLimitsAggregator.defaultNearThreshold)
                switch filter {
                case .all:
                    return true
                case .over:
                    return metric.isLimited && status == .over
                case .near:
                    return metric.isLimited && status == .near
                case .underLimit:
                    return metric.isLimited && status != .over
                }
            }
            .prefix(limit)
            .map(\.name)
    }

    private func brainContext(_ fixture: Fixture) -> MarinaBrainContext {
        MarinaBrainContext(
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )
    }

    private func insightContext(
        kind: HomeAnswerKind,
        title: String,
        primaryValue: String?,
        rows: [HomeAnswerRow]
    ) -> MarinaInsightContext {
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .remainingRoom,
                expectedAnswerShape: kind == .comparison ? .comparison : (kind == .list ? .list : .metric)
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        return MarinaInsightContext(
            prompt: "What is my safe spend today?",
            result: MarinaExecutionResult(
                kind: kind,
                title: title,
                primaryValue: primaryValue,
                rows: rows
            ),
            plan: plan
        )
    }

    private func insightContext(followUps: [MarinaFollowUpSuggestion]) -> MarinaInsightContext {
        MarinaInsightContext(
            prompt: "What is my safe spend today?",
            result: MarinaExecutionResult(
                kind: .metric,
                title: "Safe Spend Today",
                primaryValue: "$42.00",
                rows: [HomeAnswerRow(title: "Period room", value: "$420.00", amount: 420)]
            ),
            plan: formulaPlan(entity: .budget, operation: .forecast, measure: .remainingRoom),
            insightBundle: MarinaInsightBundle(followUps: followUps)
        )
    }

    private func followUp(
        title: String,
        prompt: String,
        reason: MarinaFollowUpSuggestion.Reason,
        mode: MarinaFollowUpExecutionMode
    ) -> MarinaFollowUpSuggestion {
        MarinaFollowUpSuggestion(
            title: title,
            prompt: prompt,
            reason: reason,
            executionMode: mode,
            semanticRequest: mode == .executable
                ? MarinaSemanticRequest(
                    entity: .budget,
                    operation: reason == .whatIf ? .whatIf : .forecast,
                    measure: reason == .safeDailySpend ? .safeDailySpend : .remainingRoom,
                    expectedAnswerShape: reason == .whatIf ? .comparison : .metric
                )
                : nil
        )
    }

    private func semanticFollowUp(
        reason: MarinaFollowUpSuggestion.Reason,
        targetName: String?,
        entity: MarinaSemanticEntity = .budget,
        operation: MarinaSemanticOperation? = nil,
        measure: MarinaSemanticMeasure? = nil,
        resultLimit: Int? = nil,
        whatIfAmount: Double? = nil,
        answerShape: MarinaSemanticAnswerShape? = nil
    ) -> MarinaFollowUpSuggestion {
        let resolvedOperation = operation ?? {
            switch reason {
            case .whatIf:
                return .whatIf
            case .comparePreviousPeriod:
                return .compare
            case .showMore, .inspectRows, .searchAllTime:
                return .list
            case .breakdown:
                return .group
            case .forecast, .safeDailySpend, .nextDue:
                return .forecast
            }
        }()
        let resolvedMeasure = measure ?? {
            switch reason {
            case .safeDailySpend:
                return MarinaSemanticMeasure.safeDailySpend
            case .whatIf, .breakdown, .inspectRows, .showMore, .searchAllTime:
                return .budgetImpact
            case .comparePreviousPeriod, .forecast, .nextDue:
                return .incomeAmount
            }
        }()
        let resolvedShape = answerShape ?? {
            switch resolvedOperation {
            case .list, .group, .next, .last:
                return .list
            case .compare, .whatIf:
                return .comparison
            case .count, .sum, .average, .share, .forecast:
                return .metric
            }
        }()

        return MarinaFollowUpSuggestion(
            title: reason.rawValue,
            prompt: targetName.map { "\(reason.rawValue) \($0)" } ?? reason.rawValue,
            reason: reason,
            executionMode: .executable,
            semanticRequest: MarinaSemanticRequest(
                entity: entity,
                operation: resolvedOperation,
                measure: resolvedMeasure,
                dateRangeToken: .currentPeriod,
                targetName: targetName,
                resultLimit: resultLimit,
                whatIfAmount: whatIfAmount,
                expectedAnswerShape: resolvedShape
            )
        )
    }

    private func answerWithFollowUps(
        _ followUps: [MarinaFollowUpSuggestion],
        userPrompt: String = "Summary"
    ) -> HomeAnswer {
        HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            userPrompt: userPrompt,
            title: "Summary",
            insightBundle: MarinaInsightBundle(followUps: followUps)
        )
    }

    private func reconciliationInsightContext(
        amount: Double,
        dateRange: HomeQueryDateRange? = nil
    ) -> MarinaInsightContext {
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .reconciliationAccount,
                operation: .sum,
                measure: .reconciliationBalance,
                targetName: "Alejandro",
                expectedAnswerShape: .metric
            ),
            dateRange: dateRange,
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        return MarinaInsightContext(
            prompt: "What does Alejandro owe me?",
            result: MarinaExecutionResult(
                kind: .metric,
                title: "Alejandro Balance",
                subtitle: dateRange == nil ? "Current outstanding balance across all history" : "Apr 1, 2026 - Apr 30, 2026",
                primaryValue: CurrencyFormatter.string(from: amount),
                rows: [
                    HomeAnswerRow(
                        title: "Balance",
                        value: CurrencyFormatter.string(from: amount),
                        amount: amount
                    )
                ]
            ),
            plan: plan
        )
    }

    private func formulaPlan(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure,
        shape: MarinaSemanticAnswerShape = .metric
    ) -> MarinaQueryPlan {
        MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: entity,
                operation: operation,
                measure: measure,
                expectedAnswerShape: shape
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
    }

    private func decodeLegacyFollowUpWithoutExecutionMode(
        _ suggestion: MarinaFollowUpSuggestion
    ) throws -> MarinaFollowUpSuggestion {
        let encoded = try JSONEncoder().encode(suggestion)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "executionMode")
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(MarinaFollowUpSuggestion.self, from: legacyData)
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var values: [String] = []
        for try await value in stream {
            values.append(value)
        }
        return values
    }

    private final class RecordingInterpreter: MarinaModelInterpreting {
        private let result: MarinaInterpretedSemanticRequest
        private(set) var callCount = 0

        init(result: MarinaInterpretedSemanticRequest) {
            self.result = result
        }

        func interpretedSemanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaInterpretedSemanticRequest {
            callCount += 1
            return result
        }
    }

    private final class PromptMappedInterpreter: MarinaModelInterpreting {
        private let results: [String: MarinaInterpretedSemanticRequest]
        private(set) var prompts: [String] = []

        init(_ results: [String: MarinaInterpretedSemanticRequest]) {
            self.results = results
        }

        func interpretedSemanticRequest(
            for prompt: String,
            context: MarinaBrainContext
        ) async throws -> MarinaInterpretedSemanticRequest {
            prompts.append(prompt)
            if let result = results[prompt] {
                return result
            }
            return MarinaInterpretedSemanticRequest(
                request: MarinaSemanticRequest(
                    entity: .workspace,
                    operation: .list,
                    expectedAnswerShape: .unsupported,
                    unsupportedReason: .unsupportedCombination
                ),
                confidence: .low,
                source: .foundationModel,
                diagnosticNotes: ["Missing mocked semantic request for prompt: \(prompt)"]
            )
        }
    }

    private final class RecordingInsightNarrator: MarinaInsightNarrating {
        private let response: String?
        private(set) var contexts: [MarinaInsightContext] = []

        init(response: String?) {
            self.response = response
        }

        func narration(for context: MarinaInsightContext) async throws -> String? {
            contexts.append(context)
            return response
        }
    }

    private struct ThrowingInsightNarrator: MarinaInsightNarrating {
        func narration(for context: MarinaInsightContext) async throws -> String? {
            throw TestNarrationError.failed
        }
    }

    private enum TestNarrationError: Error {
        case failed
    }

    private func makeFixture(
        includeAppleMerchantExpense: Bool = true,
        includeTransportationCategory: Bool = false,
        includeGroceryOutletExpense: Bool = false,
        includeDebitCard: Bool = false,
        includeStabilizationTargets: Bool = false,
        includeHairCareExpense: Bool = true
    ) throws -> Fixture {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#14B8A6")

        let appleCard = Card(name: "Apple Card", workspace: workspace)
        let chase = Card(name: "Chase", workspace: workspace)
        let debitCard = includeDebitCard ? Card(name: "Debit Card", workspace: workspace) : nil
        let otherAppleCard = Card(name: "Apple Card", workspace: otherWorkspace)

        let groceries = Category(name: "Groceries", hexColor: "#16A34A", workspace: workspace)
        let dining = Category(name: "Dining", hexColor: "#F97316", workspace: workspace)
        let bills = Category(name: "Bills", hexColor: "#2563EB", workspace: workspace)
        let transportation = includeTransportationCategory
            ? Category(name: "Transportation", hexColor: "#0F766E", workspace: workspace)
            : nil
        let foodAndDrink = includeStabilizationTargets
            ? Category(name: "Food & Drink", hexColor: "#EA580C", workspace: workspace)
            : nil
        let hairCare = includeStabilizationTargets
            ? Category(name: "Hair Care", hexColor: "#DB2777", workspace: workspace)
            : nil
        let subscriptions = includeStabilizationTargets
            ? Category(name: "Subscriptions", hexColor: "#7C3AED", workspace: workspace)
            : nil

        let currentBudget = Budget(
            name: "April 2026",
            startDate: date(2026, 4, 1),
            endDate: date(2026, 4, 30),
            workspace: workspace
        )
        let groceriesLimit = BudgetCategoryLimit(
            minAmount: 0,
            maxAmount: 200,
            budget: currentBudget,
            category: groceries
        )
        currentBudget.categoryLimits = [groceriesLimit]
        let previousBudget = Budget(
            name: "March 2026",
            startDate: date(2026, 3, 1),
            endDate: date(2026, 3, 31),
            workspace: workspace
        )

        let rentPreset = Preset(
            title: "Rent",
            plannedAmount: 1_200,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            workspace: workspace,
            defaultCard: appleCard,
            defaultCategory: bills
        )
        let phonePreset = Preset(
            title: "Phone",
            plannedAmount: 90,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            workspace: workspace,
            defaultCard: appleCard,
            defaultCategory: bills
        )
        let groceryPreset = Preset(
            title: "Grocery Envelope",
            plannedAmount: 200,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            workspace: workspace,
            defaultCard: chase,
            defaultCategory: groceries
        )

        let rent = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            actualAmount: 1_200,
            expenseDate: date(2026, 4, 3),
            workspace: workspace,
            card: appleCard,
            category: bills,
            sourcePresetID: rentPreset.id,
            sourceBudgetID: currentBudget.id
        )
        let phone = PlannedExpense(
            title: "Phone",
            plannedAmount: 90,
            expenseDate: date(2026, 4, 25),
            workspace: workspace,
            card: appleCard,
            category: bills,
            sourcePresetID: phonePreset.id,
            sourceBudgetID: currentBudget.id
        )
        let groceriesPlan = PlannedExpense(
            title: "Grocery Envelope",
            plannedAmount: 200,
            actualAmount: 150,
            expenseDate: date(2026, 4, 8),
            workspace: workspace,
            card: chase,
            category: groceries,
            sourcePresetID: groceryPreset.id,
            sourceBudgetID: currentBudget.id
        )
        let debitPlan = debitCard.map { card in
            PlannedExpense(
                title: "Debit Subscription",
                plannedAmount: 70,
                expenseDate: date(2026, 4, 9),
                workspace: workspace,
                card: card,
                category: bills
            )
        }

        let targetApril = VariableExpense(
            descriptionText: "Target groceries",
            amount: 80,
            transactionDate: date(2026, 4, 10),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let starbucks = VariableExpense(
            descriptionText: "Starbucks",
            amount: 25,
            transactionDate: date(2026, 4, 11),
            workspace: workspace,
            card: chase,
            category: dining
        )
        let appleStore = includeAppleMerchantExpense
            ? VariableExpense(
                descriptionText: "Apple Store",
                amount: 300,
                transactionDate: date(2026, 4, 13),
                workspace: workspace,
                card: chase,
                category: bills
            )
            : nil
        let groceryOutlet = includeGroceryOutletExpense
            ? VariableExpense(
                descriptionText: "Grocery Outlet of Midt",
                amount: 42,
                transactionDate: date(2026, 4, 12),
                workspace: workspace,
                card: chase,
                category: groceries
            )
            : nil
        let trainFare = transportation.map { category in
            VariableExpense(
                descriptionText: "Train fare",
                amount: 60,
                transactionDate: date(2026, 4, 14),
                workspace: workspace,
                card: chase,
                category: category
            )
        }
        let debitCoffee = debitCard.map { card in
            VariableExpense(
                descriptionText: "Debit Coffee",
                amount: 30,
                transactionDate: date(2026, 4, 15),
                workspace: workspace,
                card: card,
                category: dining
            )
        }
        let targetMarch = VariableExpense(
            descriptionText: "Target groceries",
            amount: 45,
            transactionDate: date(2026, 3, 12),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let uber = includeStabilizationTargets
            ? VariableExpense(
                descriptionText: "Uber",
                amount: 18,
                transactionDate: date(2026, 4, 18),
                workspace: workspace,
                card: chase,
                category: transportation ?? dining
            )
            : nil
        let burger = includeStabilizationTargets
            ? VariableExpense(
                descriptionText: "Burger Spot",
                amount: 55,
                transactionDate: date(2026, 3, 16),
                workspace: workspace,
                card: chase,
                category: foodAndDrink
            )
            : nil
        let cafe = includeStabilizationTargets
            ? VariableExpense(
                descriptionText: "Cafe Mocha",
                amount: 12,
                transactionDate: date(2026, 3, 17),
                workspace: workspace,
                card: debitCard ?? chase,
                category: foodAndDrink
            )
            : nil
        let extraFoodAndDrinkRows: [VariableExpense] = includeStabilizationTargets
            ? (1...9).map { index in
                VariableExpense(
                    descriptionText: "Food & Drink Extra \(index)",
                    amount: Double(index),
                    transactionDate: date(2026, 3, 17 + index),
                    workspace: workspace,
                    card: index.isMultiple(of: 2) ? (debitCard ?? chase) : chase,
                    category: foodAndDrink
                )
            }
            : []
        let salonVisit = includeStabilizationTargets && includeHairCareExpense
            ? VariableExpense(
                descriptionText: "Salon Visit",
                amount: 85,
                transactionDate: date(2026, 4, 19),
                workspace: workspace,
                card: chase,
                category: hairCare
            )
            : nil
        let musicSubscription = includeStabilizationTargets
            ? VariableExpense(
                descriptionText: "Music Subscription",
                amount: 14,
                transactionDate: date(2026, 4, 6),
                workspace: workspace,
                card: chase,
                category: subscriptions
            )
            : nil

        let actualPaycheck = Income(source: "Paycheck", amount: 3_000, date: date(2026, 4, 1), isPlanned: false, workspace: workspace)
        let plannedPaycheck = Income(source: "Paycheck", amount: 3_200, date: date(2026, 4, 1), isPlanned: true, workspace: workspace)
        let previousPaycheck = Income(source: "Paycheck", amount: 2_800, date: date(2026, 3, 1), isPlanned: false, workspace: workspace)

        let savings = SavingsAccount(name: "Savings Account", total: 1_000, workspace: workspace)
        let savingsAdjustment = SavingsLedgerEntry(
            date: date(2026, 4, 15),
            amount: 100,
            note: "Manual savings",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: savings
        )

        let alejandro = AllocationAccount(name: "Alejandro", workspace: workspace)
        let targetAllocation = ExpenseAllocation(
            allocatedAmount: 40,
            preservesGrossAmount: true,
            workspace: workspace,
            account: alejandro,
            expense: targetApril
        )
        let previousAllocation = ExpenseAllocation(
            allocatedAmount: 20,
            preservesGrossAmount: true,
            workspace: workspace,
            account: alejandro,
            expense: targetMarch
        )
        let settlement = AllocationSettlement(
            date: date(2026, 4, 20),
            note: "Alejandro paid back",
            amount: -10,
            workspace: workspace,
            account: alejandro
        )
        targetApril.allocation = targetAllocation
        targetMarch.allocation = previousAllocation
        alejandro.expenseAllocations = [targetAllocation, previousAllocation]
        alejandro.settlements = [settlement]

        context.insert(workspace)
        context.insert(otherWorkspace)
        context.insert(appleCard)
        context.insert(chase)
        if let debitCard {
            context.insert(debitCard)
        }
        context.insert(otherAppleCard)
        context.insert(groceries)
        context.insert(dining)
        context.insert(bills)
        if let transportation {
            context.insert(transportation)
        }
        if let foodAndDrink {
            context.insert(foodAndDrink)
        }
        if let hairCare {
            context.insert(hairCare)
        }
        if let subscriptions {
            context.insert(subscriptions)
        }
        context.insert(currentBudget)
        context.insert(groceriesLimit)
        context.insert(previousBudget)
        context.insert(rentPreset)
        context.insert(phonePreset)
        context.insert(groceryPreset)
        context.insert(rent)
        context.insert(phone)
        context.insert(groceriesPlan)
        if let debitPlan {
            context.insert(debitPlan)
        }
        context.insert(targetApril)
        context.insert(starbucks)
        if let appleStore {
            context.insert(appleStore)
        }
        if let groceryOutlet {
            context.insert(groceryOutlet)
        }
        if let trainFare {
            context.insert(trainFare)
        }
        if let debitCoffee {
            context.insert(debitCoffee)
        }
        context.insert(targetMarch)
        if let uber {
            context.insert(uber)
        }
        if let burger {
            context.insert(burger)
        }
        if let cafe {
            context.insert(cafe)
        }
        for row in extraFoodAndDrinkRows {
            context.insert(row)
        }
        if let salonVisit {
            context.insert(salonVisit)
        }
        if let musicSubscription {
            context.insert(musicSubscription)
        }
        context.insert(actualPaycheck)
        context.insert(plannedPaycheck)
        context.insert(previousPaycheck)
        context.insert(savings)
        context.insert(savingsAdjustment)
        context.insert(alejandro)
        context.insert(targetAllocation)
        context.insert(previousAllocation)
        context.insert(settlement)
        try context.save()

        return Fixture(
            context: context,
            workspace: workspace,
            currentRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            now: date(2026, 4, 20)
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            BudgetCategoryLimit.self,
            Card.self,
            BudgetCardLink.self,
            BudgetPresetLink.self,
            Category.self,
            Preset.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            MarinaChatSession.self,
            IncomeSeries.self,
            Income.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
