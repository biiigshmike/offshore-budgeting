import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaManualQAPromptMatrixTests {
    private struct MarinaManualQACase {
        let id: String
        let prompt: String
        let category: MarinaManualQACategory
        let expectedRouting: MarinaManualQAExpectedRouting
        let expectedScenario: MarinaUniversalRoutingScenario?
        let expectedLayer: MarinaManualQAExpectedLayer
        let notes: String
        let request: MarinaSemanticRequest
    }

    private enum MarinaManualQACategory {
        case budgets
        case expenses
        case income
        case cards
        case reconciliations
        case savings
        case presets
        case categories
        case ambiguity
        case mutationGuardrail
        case deferredFormula
    }

    private enum MarinaManualQAExpectedRouting {
        case universal
        case legacyFallback
        case unsupportedOrClarification
        case interpretationOnly
    }

    private enum MarinaManualQAExpectedLayer {
        case semanticInterpretation
        case resolver
        case universalRouting
        case legacyFallback
        case guardrail
        case deferred
    }

    @Test func debugOffNeverUsesUniversalForManualQAMatrix() throws {
        let fixture = makeFixture()
        let executor = fixture.executor(policy: .disabled)

        for testCase in allCases {
            let plan = fixture.plan(for: testCase.request)
            let result = executor.executeResult(
                plan: plan,
                snapshot: fixture.snapshot,
                planningContext: fixture.context()
            )

            guard case let .legacy(answer, diagnostics) = result else {
                Issue.record("\(failureReport(for: testCase, policy: .disabled, result: result))")
                throw ManualQATestFailure()
            }

            #expect(diagnostics == nil, "\(failureReport(for: testCase, policy: .disabled, result: result))")
            expectNoVisibleDiagnostics(answer, testCase: testCase, policy: .disabled)
        }
    }

    @Test func debugOnRoutesUniversalOwnedManualQACasesThroughUniversal() throws {
        let fixture = makeFixture()
        let executor = fixture.executor(policy: .internalParityProven)

        for testCase in universalOwnedCases {
            let plan = fixture.plan(for: testCase.request)
            let result = executor.executeResult(
                plan: plan,
                snapshot: fixture.snapshot,
                planningContext: fixture.context()
            )

            guard case let .universal(answer, diagnostics) = result else {
                Issue.record("\(failureReport(for: testCase, policy: .internalParityProven, result: result))")
                throw ManualQATestFailure()
            }

            #expect(diagnostics.usedUniversal, "\(failureReport(for: testCase, policy: .internalParityProven, result: result))")
            #expect(diagnostics.fallbackReason == nil, "\(failureReport(for: testCase, policy: .internalParityProven, result: result))")
            #expect(diagnostics.scenario == testCase.expectedScenario, "\(failureReport(for: testCase, policy: .internalParityProven, result: result))")
            #expect(testCase.expectedScenario != nil, "Universal-owned case \(testCase.id) must name a scenario.")
            expectNoVisibleDiagnostics(answer, testCase: testCase, policy: .internalParityProven)
        }
    }

    @Test func debugOnFallsBackForDeferredAndGuardrailManualQACases() throws {
        let fixture = makeFixture()
        let executor = fixture.executor(policy: .internalParityProven)

        for testCase in fallbackCases {
            let plan = fixture.plan(for: testCase.request)
            let result = executor.executeResult(
                plan: plan,
                snapshot: fixture.snapshot,
                planningContext: fixture.context()
            )

            guard case let .legacy(answer, diagnostics) = result else {
                Issue.record("\(failureReport(for: testCase, policy: .internalParityProven, result: result))")
                throw ManualQATestFailure()
            }

            #expect(diagnostics?.usedUniversal == false, "\(failureReport(for: testCase, policy: .internalParityProven, result: result))")
            #expect(diagnostics?.fallbackReason == .notAllowlisted, "\(failureReport(for: testCase, policy: .internalParityProven, result: result))")
            #expect(diagnostics?.scenario == testCase.expectedScenario, "\(failureReport(for: testCase, policy: .internalParityProven, result: result))")
            #expect(MarinaUniversalRoutingPolicy.internalParityProven.allows(testCase.request) == false, "Deferred case \(testCase.id) must not be allowlisted.")
            expectNoVisibleDiagnostics(answer, testCase: testCase, policy: .internalParityProven)
        }
    }

    @Test func matrixCoversEveryCurrentUniversalRoutingScenario() {
        let covered = Set(universalOwnedCases.compactMap(\.expectedScenario))

        #expect(covered == MarinaUniversalRoutingPolicy.internalParityProven.allowedScenarios)
        #expect(covered == Set(MarinaUniversalRoutingScenario.allCases))
    }

    private var allCases: [MarinaManualQACase] {
        universalOwnedCases + fallbackCases
    }

    private var universalOwnedCases: [MarinaManualQACase] {
        [
            MarinaManualQACase(
                id: "expense.appleMerchant.currentMonth",
                prompt: "How much did I spend at Apple this month?",
                category: .expenses,
                expectedRouting: .universal,
                expectedScenario: .merchantVariableSpend,
                expectedLayer: .universalRouting,
                notes: "Merchant text, not Apple Card.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.merchantText],
                    textQuery: "Apple",
                    expenseScope: .variable
                )
            ),
            MarinaManualQACase(
                id: "expense.appleMerchant.currentPeriod",
                prompt: "How much did I spend at Apple this period?",
                category: .expenses,
                expectedRouting: .universal,
                expectedScenario: .merchantVariableSpend,
                expectedLayer: .universalRouting,
                notes: "Current-period merchant spend should keep the same universal-owned shape.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.merchantText],
                    dateRangeToken: .currentPeriod,
                    textQuery: "Apple",
                    expenseScope: .variable
                )
            ),
            MarinaManualQACase(
                id: "expense.appleMerchant.previousMonth",
                prompt: "How much did I spend at Apple last month?",
                category: .expenses,
                expectedRouting: .universal,
                expectedScenario: .merchantVariableSpend,
                expectedLayer: .universalRouting,
                notes: "Previous-month merchant spend is already covered by the merchant scenario policy.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.merchantText],
                    dateRangeToken: .previousMonth,
                    textQuery: "Apple",
                    expenseScope: .variable
                )
            ),
            MarinaManualQACase(
                id: "expense.groceriesCategory.currentMonth",
                prompt: "How much did I spend on groceries this month?",
                category: .expenses,
                expectedRouting: .universal,
                expectedScenario: .categoryVariableSpend,
                expectedLayer: .universalRouting,
                notes: "Category-targeted variable spend.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.category],
                    targetName: "Groceries",
                    expenseScope: .variable
                )
            ),
            MarinaManualQACase(
                id: "expense.groceriesCategory.currentPeriod",
                prompt: "How much did I spend on groceries this period?",
                category: .expenses,
                expectedRouting: .universal,
                expectedScenario: .categoryVariableSpend,
                expectedLayer: .universalRouting,
                notes: "Current-period category spend should keep the same universal-owned shape.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.category],
                    dateRangeToken: .currentPeriod,
                    targetName: "Groceries",
                    expenseScope: .variable
                )
            ),
            MarinaManualQACase(
                id: "expense.groceriesCategory.previousMonth",
                prompt: "How much did I spend on groceries last month?",
                category: .expenses,
                expectedRouting: .universal,
                expectedScenario: .categoryVariableSpend,
                expectedLayer: .universalRouting,
                notes: "Previous-month category spend is already covered by the category scenario policy.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.category],
                    dateRangeToken: .previousMonth,
                    targetName: "Groceries",
                    expenseScope: .variable
                )
            ),
            MarinaManualQACase(
                id: "expense.appleCard.currentMonth",
                prompt: "How much did I spend on Apple Card this month?",
                category: .cards,
                expectedRouting: .universal,
                expectedScenario: .cardVariableSpend,
                expectedLayer: .universalRouting,
                notes: "Card-targeted variable spend.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    targetName: "Apple Card",
                    expenseScope: .variable
                )
            ),
            MarinaManualQACase(
                id: "expense.appleCard.currentPeriod",
                prompt: "How much did I spend on Apple Card this period?",
                category: .cards,
                expectedRouting: .universal,
                expectedScenario: .cardVariableSpend,
                expectedLayer: .universalRouting,
                notes: "Current-period card spend should keep the same universal-owned shape.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    dateRangeToken: .currentPeriod,
                    targetName: "Apple Card",
                    expenseScope: .variable
                )
            ),
            MarinaManualQACase(
                id: "planned.sum.currentMonth",
                prompt: "How much planned spending do I have this period?",
                category: .expenses,
                expectedRouting: .universal,
                expectedScenario: .plannedExpenseSum,
                expectedLayer: .universalRouting,
                notes: "Planned-only budget impact sum.",
                request: semanticRequest(
                    entity: .plannedExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    expenseScope: .planned
                )
            ),
            MarinaManualQACase(
                id: "expense.latestVariable.currentMonth",
                prompt: "What was my latest variable expense?",
                category: .expenses,
                expectedRouting: .universal,
                expectedScenario: .latestVariableExpense,
                expectedLayer: .universalRouting,
                notes: "Latest variable ledger activity.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .last,
                    measure: .budgetImpact,
                    expenseScope: .variable
                )
            ),
            MarinaManualQACase(
                id: "expense.biggestVariable.currentMonth",
                prompt: "Show my biggest expenses.",
                category: .expenses,
                expectedRouting: .universal,
                expectedScenario: .biggestVariableExpenseRows,
                expectedLayer: .universalRouting,
                notes: "Amount-descending variable expense rows.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .list,
                    measure: .budgetImpact,
                    resultLimit: 3,
                    sort: .amountDescending,
                    expenseScope: .variable,
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "planned.next.nextSevenDays",
                prompt: "What is my next planned expense?",
                category: .expenses,
                expectedRouting: .universal,
                expectedScenario: .nextPlannedExpense,
                expectedLayer: .universalRouting,
                notes: "Next planned expense within a date window.",
                request: semanticRequest(
                    entity: .plannedExpense,
                    operation: .next,
                    measure: .effectiveAmount,
                    dateRangeToken: .nextSevenDays,
                    expenseScope: .planned
                )
            ),
            MarinaManualQACase(
                id: "expense.unifiedByCategory.currentMonth",
                prompt: "Show my spending by category.",
                category: .categories,
                expectedRouting: .universal,
                expectedScenario: .unifiedExpenseCategoryGroups,
                expectedLayer: .universalRouting,
                notes: "Unified planned plus variable grouped by category.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .group,
                    measure: .budgetImpact,
                    dimensions: [.category],
                    expenseScope: .unified,
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "expense.unifiedByCategory.currentPeriod",
                prompt: "Show spending by category this period.",
                category: .categories,
                expectedRouting: .universal,
                expectedScenario: .unifiedExpenseCategoryGroups,
                expectedLayer: .universalRouting,
                notes: "Current-period unified category groups are already allowlisted.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .group,
                    measure: .budgetImpact,
                    dimensions: [.category],
                    dateRangeToken: .currentPeriod,
                    expenseScope: .unified,
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "expense.unifiedByCard.currentMonth",
                prompt: "Show spending by card this month.",
                category: .cards,
                expectedRouting: .universal,
                expectedScenario: .unifiedExpenseCardGroups,
                expectedLayer: .universalRouting,
                notes: "Unified planned plus variable grouped by card.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .group,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    expenseScope: .unified,
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "expense.unifiedByCard.currentPeriod",
                prompt: "Show spending by card this period.",
                category: .cards,
                expectedRouting: .universal,
                expectedScenario: .unifiedExpenseCardGroups,
                expectedLayer: .universalRouting,
                notes: "Current-period unified card groups are already allowlisted.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .group,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    dateRangeToken: .currentPeriod,
                    expenseScope: .unified,
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "income.total.currentMonth",
                prompt: "How much income came in this period?",
                category: .income,
                expectedRouting: .universal,
                expectedScenario: .incomeTotal,
                expectedLayer: .universalRouting,
                notes: "All planned and actual income total.",
                request: semanticRequest(
                    entity: .income,
                    operation: .sum,
                    measure: .incomeAmount,
                    incomeState: .all
                )
            ),
            MarinaManualQACase(
                id: "income.total.currentPeriod",
                prompt: "How much income came in this period?",
                category: .income,
                expectedRouting: .universal,
                expectedScenario: .incomeTotal,
                expectedLayer: .universalRouting,
                notes: "Current-period income total is already allowlisted.",
                request: semanticRequest(
                    entity: .income,
                    operation: .sum,
                    measure: .incomeAmount,
                    dateRangeToken: .currentPeriod,
                    incomeState: .all
                )
            ),
            MarinaManualQACase(
                id: "income.bySource.currentMonth",
                prompt: "Show income by source this month.",
                category: .income,
                expectedRouting: .universal,
                expectedScenario: .incomeBySource,
                expectedLayer: .universalRouting,
                notes: "All income grouped by source.",
                request: semanticRequest(
                    entity: .income,
                    operation: .group,
                    measure: .incomeAmount,
                    dimensions: [.incomeSource],
                    incomeState: .all,
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "income.bySource.currentPeriod",
                prompt: "Show income by source this period.",
                category: .income,
                expectedRouting: .universal,
                expectedScenario: .incomeBySource,
                expectedLayer: .universalRouting,
                notes: "Current-period income source groups are already allowlisted.",
                request: semanticRequest(
                    entity: .income,
                    operation: .group,
                    measure: .incomeAmount,
                    dimensions: [.incomeSource],
                    dateRangeToken: .currentPeriod,
                    incomeState: .all,
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "savings.explicitAccount.total",
                prompt: "What is my Savings Account balance?",
                category: .savings,
                expectedRouting: .universal,
                expectedScenario: .savingsTotalExplicitAccount,
                expectedLayer: .universalRouting,
                notes: "Explicit savings account total only.",
                request: savingsTotalRequest(targetName: "Savings Account")
            ),
            MarinaManualQACase(
                id: "reconciliation.explicitAccount.balance",
                prompt: "What is my Alejandro reconciliation balance?",
                category: .reconciliations,
                expectedRouting: .universal,
                expectedScenario: .reconciliationBalanceExplicitAccount,
                expectedLayer: .universalRouting,
                notes: "Explicit reconciliation account balance only.",
                request: reconciliationBalanceRequest(targetName: "Alejandro")
            ),
            MarinaManualQACase(
                id: "budget.remainingRoom.currentMonth",
                prompt: "How much room do I have left?",
                category: .budgets,
                expectedRouting: .universal,
                expectedScenario: .budgetRemainingRoom,
                expectedLayer: .universalRouting,
                notes: "Exact budget remaining-room formula shape.",
                request: semanticRequest(entity: .budget, operation: .forecast, measure: .remainingRoom)
            ),
            MarinaManualQACase(
                id: "budget.safeDailySpend.currentMonth",
                prompt: "What can I safely spend per day?",
                category: .budgets,
                expectedRouting: .universal,
                expectedScenario: .safeDailySpend,
                expectedLayer: .universalRouting,
                notes: "Exact safe daily spend formula shape.",
                request: semanticRequest(entity: .budget, operation: .forecast, measure: .safeDailySpend)
            ),
            MarinaManualQACase(
                id: "budget.burnRate.currentMonth",
                prompt: "What is my burn rate?",
                category: .budgets,
                expectedRouting: .universal,
                expectedScenario: .budgetBurnRate,
                expectedLayer: .universalRouting,
                notes: "Exact burn-rate formula shape.",
                request: semanticRequest(entity: .budget, operation: .average, measure: .burnRate)
            ),
            MarinaManualQACase(
                id: "budget.projectedSpend.currentMonth",
                prompt: "What am I projected to spend this period?",
                category: .budgets,
                expectedRouting: .universal,
                expectedScenario: .budgetProjectedSpend,
                expectedLayer: .universalRouting,
                notes: "Exact projected-spend formula shape.",
                request: semanticRequest(entity: .budget, operation: .forecast, measure: .projectedSpend)
            ),
            MarinaManualQACase(
                id: "budget.paceDifference.currentMonth",
                prompt: "Am I spending too fast?",
                category: .budgets,
                expectedRouting: .universal,
                expectedScenario: .budgetPaceDifference,
                expectedLayer: .universalRouting,
                notes: "Exact pace-difference comparison shape.",
                request: semanticRequest(
                    entity: .budget,
                    operation: .compare,
                    measure: .paceDifference,
                    expectedAnswerShape: .comparison
                )
            ),
            MarinaManualQACase(
                id: "budget.coverageRatio.currentMonth",
                prompt: "What is my coverage ratio?",
                category: .budgets,
                expectedRouting: .universal,
                expectedScenario: .budgetCoverageRatio,
                expectedLayer: .universalRouting,
                notes: "Exact budget coverage-ratio formula shape.",
                request: semanticRequest(entity: .budget, operation: .forecast, measure: .coverageRatio)
            ),
            MarinaManualQACase(
                id: "income.coverageRatio.currentMonth",
                prompt: "Does my income cover my budget?",
                category: .income,
                expectedRouting: .universal,
                expectedScenario: .incomeCoverageRatio,
                expectedLayer: .universalRouting,
                notes: "Exact income coverage-ratio formula shape.",
                request: semanticRequest(entity: .income, operation: .share, measure: .coverageRatio)
            ),
            MarinaManualQACase(
                id: "category.availability.currentMonth",
                prompt: "Show category availability.",
                category: .categories,
                expectedRouting: .universal,
                expectedScenario: .categoryAvailability,
                expectedLayer: .universalRouting,
                notes: "Metric summary only; filtered lists remain deferred.",
                request: semanticRequest(entity: .category, operation: .forecast, measure: .categoryAvailability)
            ),
            MarinaManualQACase(
                id: "category.concentration.currentMonth",
                prompt: "What is eating my budget?",
                category: .categories,
                expectedRouting: .universal,
                expectedScenario: .categoryConcentration,
                expectedLayer: .universalRouting,
                notes: "Exact category concentration metric shape.",
                request: semanticRequest(entity: .category, operation: .share, measure: .concentration)
            ),
            MarinaManualQACase(
                id: "preset.recurringBurden.currentMonth",
                prompt: "What is my recurring burden?",
                category: .presets,
                expectedRouting: .universal,
                expectedScenario: .presetRecurringBurden,
                expectedLayer: .universalRouting,
                notes: "Exact recurring-burden metric shape.",
                request: semanticRequest(entity: .preset, operation: .sum, measure: .recurringBurden)
            ),
            MarinaManualQACase(
                id: "savings.forecast.currentMonth",
                prompt: "Show my savings outlook.",
                category: .savings,
                expectedRouting: .universal,
                expectedScenario: .forecastSavings,
                expectedLayer: .universalRouting,
                notes: "Exact forecast-savings metric shape.",
                request: semanticRequest(entity: .savingsAccount, operation: .forecast, measure: .savingsTotal)
            )
        ]
    }

    private var fallbackCases: [MarinaManualQACase] {
        [
            MarinaManualQACase(
                id: "deferred.compareCategories.currentMonth",
                prompt: "Compare groceries and electronics.",
                category: .categories,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "General compare remains legacy-owned.",
                request: semanticRequest(
                    entity: .category,
                    operation: .compare,
                    measure: .budgetImpact,
                    dimensions: [.category],
                    targetName: "Groceries",
                    comparisonTargetName: "Electronics",
                    expenseScope: .unified,
                    expectedAnswerShape: .comparison
                )
            ),
            MarinaManualQACase(
                id: "deferred.whatIfSpend.currentMonth",
                prompt: "What if I spend $50 today?",
                category: .budgets,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "What-if is explicitly blocked from universal routing.",
                request: semanticRequest(
                    entity: .budget,
                    operation: .whatIf,
                    measure: .remainingRoom,
                    whatIfAmount: 50,
                    expectedAnswerShape: .comparison
                )
            ),
            MarinaManualQACase(
                id: "deferred.whatIfForecastSavings.currentMonth",
                prompt: "Forecast my savings if I spend $50.",
                category: .deferredFormula,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "What-if savings formulas remain legacy-owned and must not route universal.",
                request: semanticRequest(
                    entity: .savingsAccount,
                    operation: .whatIf,
                    measure: .savingsTotal,
                    whatIfAmount: 50,
                    expectedAnswerShape: .comparison
                )
            ),
            MarinaManualQACase(
                id: "deferred.categoryAvailability.overList",
                prompt: "Which categories are over limit?",
                category: .categories,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Filtered category availability lists are not allowlisted.",
                request: categoryAvailabilityListRequest(filter: .over)
            ),
            MarinaManualQACase(
                id: "deferred.categoryAvailability.nearList",
                prompt: "Which categories are near limit?",
                category: .categories,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Filtered category availability lists are not allowlisted.",
                request: categoryAvailabilityListRequest(filter: .near)
            ),
            MarinaManualQACase(
                id: "deferred.categoryAvailability.underList",
                prompt: "List categories under limit.",
                category: .categories,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Filtered category availability lists are not allowlisted.",
                request: categoryAvailabilityListRequest(filter: .underLimit)
            ),
            MarinaManualQACase(
                id: "deferred.forecastSavings.allTime",
                prompt: "Show projected savings all time.",
                category: .savings,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "All-time forecast savings remains deferred.",
                request: semanticRequest(
                    entity: .savingsAccount,
                    operation: .forecast,
                    measure: .savingsTotal,
                    dateRangeToken: .allTime
                )
            ),
            MarinaManualQACase(
                id: "deferred.budgetCoverageRatio.allTime",
                prompt: "What is my coverage ratio all time?",
                category: .deferredFormula,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "All-time budget coverage is not part of the allowlisted metric shape.",
                request: semanticRequest(
                    entity: .budget,
                    operation: .forecast,
                    measure: .coverageRatio,
                    dateRangeToken: .allTime
                )
            ),
            MarinaManualQACase(
                id: "deferred.incomeCoverageRatio.allTime",
                prompt: "Does my income cover my budget all time?",
                category: .deferredFormula,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "All-time income coverage is not part of the allowlisted metric shape.",
                request: semanticRequest(
                    entity: .income,
                    operation: .share,
                    measure: .coverageRatio,
                    dateRangeToken: .allTime
                )
            ),
            MarinaManualQACase(
                id: "deferred.categoryConcentration.allTime",
                prompt: "Which category has the biggest share all time?",
                category: .deferredFormula,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "All-time category concentration remains deferred.",
                request: semanticRequest(
                    entity: .category,
                    operation: .share,
                    measure: .concentration,
                    dateRangeToken: .allTime
                )
            ),
            MarinaManualQACase(
                id: "deferred.nextPlannedExpense.allTime",
                prompt: "What is my next planned expense ever?",
                category: .expenses,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "All-time next planned expense is not an allowlisted next-window shape.",
                request: semanticRequest(
                    entity: .plannedExpense,
                    operation: .next,
                    measure: .effectiveAmount,
                    dateRangeToken: .allTime,
                    expenseScope: .planned
                )
            ),
            MarinaManualQACase(
                id: "deferred.projectedSpend.byCard",
                prompt: "Show projected spend by card.",
                category: .deferredFormula,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Projected-spend grouping by card is not allowlisted.",
                request: semanticRequest(
                    entity: .budget,
                    operation: .forecast,
                    measure: .projectedSpend,
                    dimensions: [.card],
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "deferred.forecastSavings.targeted",
                prompt: "Forecast my Savings Account savings.",
                category: .savings,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Targeted forecast savings remains deferred.",
                request: semanticRequest(
                    entity: .savingsAccount,
                    operation: .forecast,
                    measure: .savingsTotal,
                    targetName: "Savings Account"
                )
            ),
            MarinaManualQACase(
                id: "deferred.forecastSavings.grouped",
                prompt: "Show projected savings by account.",
                category: .savings,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Grouped forecast savings remains deferred.",
                request: semanticRequest(
                    entity: .savingsAccount,
                    operation: .forecast,
                    measure: .savingsTotal,
                    dimensions: [.savingsAccount],
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "deferred.forecastSavings.sorted",
                prompt: "Show projected savings sorted by amount.",
                category: .savings,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Sorted forecast savings remains deferred.",
                request: semanticRequest(
                    entity: .savingsAccount,
                    operation: .forecast,
                    measure: .savingsTotal,
                    sort: .amountDescending
                )
            ),
            MarinaManualQACase(
                id: "deferred.recurringBurden.allTime",
                prompt: "Show fixed expenses all time.",
                category: .presets,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "All-time recurring burden remains deferred.",
                request: semanticRequest(
                    entity: .preset,
                    operation: .sum,
                    measure: .recurringBurden,
                    dateRangeToken: .allTime
                )
            ),
            MarinaManualQACase(
                id: "deferred.recurringBurden.targeted",
                prompt: "What is the recurring burden for Phone?",
                category: .presets,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Targeted recurring burden remains deferred.",
                request: semanticRequest(
                    entity: .preset,
                    operation: .sum,
                    measure: .recurringBurden,
                    targetName: "Phone"
                )
            ),
            MarinaManualQACase(
                id: "deferred.recurringBurden.grouped",
                prompt: "Show recurring burden by preset.",
                category: .presets,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Grouped recurring burden remains deferred.",
                request: semanticRequest(
                    entity: .preset,
                    operation: .sum,
                    measure: .recurringBurden,
                    dimensions: [.preset],
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "deferred.recurringBurden.sorted",
                prompt: "Show recurring burden sorted by amount.",
                category: .presets,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Sorted recurring burden remains deferred.",
                request: semanticRequest(
                    entity: .preset,
                    operation: .sum,
                    measure: .recurringBurden,
                    sort: .amountDescending
                )
            ),
            MarinaManualQACase(
                id: "deferred.incomeBySource.plannedOnly",
                prompt: "Show planned income by source.",
                category: .income,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Narrowed planned-only source groups remain deferred.",
                request: incomeBySourceRequest(state: .planned)
            ),
            MarinaManualQACase(
                id: "deferred.incomeBySource.actualOnly",
                prompt: "Show actual income by source.",
                category: .income,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "Narrowed actual-only source groups remain deferred.",
                request: incomeBySourceRequest(state: .actual)
            ),
            MarinaManualQACase(
                id: "deferred.incomeBySource.allTime",
                prompt: "Show income by source all time.",
                category: .income,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "All-time source groups remain deferred.",
                request: semanticRequest(
                    entity: .income,
                    operation: .group,
                    measure: .incomeAmount,
                    dimensions: [.incomeSource],
                    dateRangeToken: .allTime,
                    incomeState: .all,
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "deferred.unifiedCardGroups.allTime",
                prompt: "Show spending by card all time.",
                category: .cards,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .deferred,
                notes: "All-time unified card grouping remains deferred.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .group,
                    measure: .budgetImpact,
                    dimensions: [.card],
                    dateRangeToken: .allTime,
                    expenseScope: .unified,
                    expectedAnswerShape: .list
                )
            ),
            MarinaManualQACase(
                id: "guardrail.mutation.deleteCategory",
                prompt: "Delete my groceries category.",
                category: .mutationGuardrail,
                expectedRouting: .unsupportedOrClarification,
                expectedScenario: nil,
                expectedLayer: .guardrail,
                notes: "Mutation requests must not route through universal query execution.",
                request: semanticRequest(
                    entity: .workspace,
                    operation: .list,
                    expectedAnswerShape: .unsupported,
                    unsupportedReason: .readOnly
                )
            ),
            MarinaManualQACase(
                id: "guardrail.mutation.addExpense",
                prompt: "Add a $25 coffee expense.",
                category: .mutationGuardrail,
                expectedRouting: .unsupportedOrClarification,
                expectedScenario: nil,
                expectedLayer: .guardrail,
                notes: "Create-style mutation requests must not route through universal query execution.",
                request: readOnlyUnsupportedRequest()
            ),
            MarinaManualQACase(
                id: "guardrail.mutation.createBudget",
                prompt: "Create a July budget.",
                category: .mutationGuardrail,
                expectedRouting: .unsupportedOrClarification,
                expectedScenario: nil,
                expectedLayer: .guardrail,
                notes: "Budget creation remains outside universal query execution.",
                request: readOnlyUnsupportedRequest()
            ),
            MarinaManualQACase(
                id: "guardrail.mutation.updatePreset",
                prompt: "Change my Phone preset to $90.",
                category: .mutationGuardrail,
                expectedRouting: .unsupportedOrClarification,
                expectedScenario: nil,
                expectedLayer: .guardrail,
                notes: "Update-style mutation requests must stay behind read-only guardrails.",
                request: readOnlyUnsupportedRequest()
            ),
            MarinaManualQACase(
                id: "guardrail.mutation.moveSavings",
                prompt: "Move $50 to Savings Account.",
                category: .mutationGuardrail,
                expectedRouting: .unsupportedOrClarification,
                expectedScenario: nil,
                expectedLayer: .guardrail,
                notes: "Money movement requests must not route through universal query execution.",
                request: semanticRequest(
                    entity: .workspace,
                    operation: .list,
                    expectedAnswerShape: .unsupported,
                    unsupportedReason: .readOnly
                )
            ),
            MarinaManualQACase(
                id: "ambiguity.savings.genericTotal",
                prompt: "What is my savings total?",
                category: .savings,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .resolver,
                notes: "Generic savings totals must not guess an explicit account for universal routing.",
                request: savingsTotalRequest(targetName: nil)
            ),
            MarinaManualQACase(
                id: "ambiguity.reconciliation.genericBalance",
                prompt: "What is my reconciliation balance?",
                category: .reconciliations,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .resolver,
                notes: "Generic reconciliation balances must not guess an explicit account.",
                request: reconciliationBalanceRequest(targetName: nil)
            ),
            MarinaManualQACase(
                id: "ambiguity.apple.unresolvedTarget",
                prompt: "How much did I spend on Apple?",
                category: .ambiguity,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .resolver,
                notes: "Ambiguous Apple target should clarify or stay legacy-owned until resolved.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    targetName: "Apple",
                    expenseScope: .unified
                )
            ),
            MarinaManualQACase(
                id: "ambiguity.apple.terminalClarification",
                prompt: "How much did I spend on Apple?",
                category: .ambiguity,
                expectedRouting: .unsupportedOrClarification,
                expectedScenario: nil,
                expectedLayer: .resolver,
                notes: "Terminal clarification shapes must not be allowlisted.",
                request: semanticRequest(
                    entity: .workspace,
                    operation: .list,
                    targetName: "Apple",
                    textQuery: "Apple",
                    expectedAnswerShape: .clarification,
                    unsupportedReason: .ambiguousEntity
                )
            ),
            MarinaManualQACase(
                id: "ambiguity.categoryMerchant.groceriesUnresolvedTarget",
                prompt: "How much did I spend on Groceries?",
                category: .ambiguity,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .resolver,
                notes: "Category-vs-merchant target text must not be guessed into an allowlisted universal request.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    targetName: "Groceries",
                    expenseScope: .unified
                )
            ),
            MarinaManualQACase(
                id: "ambiguity.categoryMerchant.terminalClarification",
                prompt: "How much did I spend on Groceries?",
                category: .ambiguity,
                expectedRouting: .unsupportedOrClarification,
                expectedScenario: nil,
                expectedLayer: .resolver,
                notes: "Terminal category/merchant clarification shapes must not be allowlisted.",
                request: semanticRequest(
                    entity: .workspace,
                    operation: .list,
                    targetName: "Groceries",
                    textQuery: "Groceries",
                    expectedAnswerShape: .clarification,
                    unsupportedReason: .ambiguousEntity
                )
            ),
            MarinaManualQACase(
                id: "ambiguity.incomeMerchant.paycheckUnresolvedTarget",
                prompt: "How much came from Paycheck?",
                category: .ambiguity,
                expectedRouting: .legacyFallback,
                expectedScenario: nil,
                expectedLayer: .resolver,
                notes: "Income-source-vs-merchant target text must not route without a clear semantic dimension.",
                request: semanticRequest(
                    entity: .variableExpense,
                    operation: .sum,
                    measure: .budgetImpact,
                    targetName: "Paycheck",
                    expenseScope: .unified
                )
            ),
            MarinaManualQACase(
                id: "ambiguity.incomeMerchant.terminalClarification",
                prompt: "How much came from Paycheck?",
                category: .ambiguity,
                expectedRouting: .unsupportedOrClarification,
                expectedScenario: nil,
                expectedLayer: .resolver,
                notes: "Terminal income/merchant clarification shapes must not be allowlisted.",
                request: semanticRequest(
                    entity: .workspace,
                    operation: .list,
                    targetName: "Paycheck",
                    textQuery: "Paycheck",
                    expectedAnswerShape: .clarification,
                    unsupportedReason: .ambiguousEntity
                )
            )
        ]
    }

    private func semanticRequest(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dimensions: [MarinaSemanticDimension] = [],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentMonth,
        targetName: String? = nil,
        comparisonTargetName: String? = nil,
        textQuery: String? = nil,
        resultLimit: Int? = nil,
        sort: MarinaSemanticSort? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        incomeState: MarinaSemanticIncomeState? = nil,
        whatIfAmount: Double? = nil,
        categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
        expectedAnswerShape: MarinaSemanticAnswerShape = .metric,
        unsupportedReason: MarinaSemanticUnsupportedReason? = nil
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dimensions: dimensions,
            dateRangeToken: dateRangeToken,
            targetName: targetName,
            comparisonTargetName: comparisonTargetName,
            textQuery: textQuery,
            resultLimit: resultLimit,
            sort: sort,
            expenseScope: expenseScope,
            incomeState: incomeState,
            whatIfAmount: whatIfAmount,
            categoryAvailabilityFilter: categoryAvailabilityFilter,
            expectedAnswerShape: expectedAnswerShape,
            unsupportedReason: unsupportedReason
        )
    }

    private func categoryAvailabilityListRequest(filter: MarinaCategoryAvailabilityFilter) -> MarinaSemanticRequest {
        semanticRequest(
            entity: .category,
            operation: .list,
            measure: .categoryAvailability,
            dimensions: [.category],
            categoryAvailabilityFilter: filter,
            expectedAnswerShape: .list
        )
    }

    private func incomeBySourceRequest(state: MarinaSemanticIncomeState) -> MarinaSemanticRequest {
        semanticRequest(
            entity: .income,
            operation: .group,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            incomeState: state,
            expectedAnswerShape: .list
        )
    }

    private func savingsTotalRequest(targetName: String?) -> MarinaSemanticRequest {
        semanticRequest(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            dateRangeToken: .allTime,
            targetName: targetName
        )
    }

    private func reconciliationBalanceRequest(targetName: String?) -> MarinaSemanticRequest {
        semanticRequest(
            entity: .reconciliationAccount,
            operation: .sum,
            measure: .reconciliationBalance,
            dateRangeToken: .allTime,
            targetName: targetName
        )
    }

    private func readOnlyUnsupportedRequest() -> MarinaSemanticRequest {
        semanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: .readOnly
        )
    }

    private func expectNoVisibleDiagnostics(
        _ result: MarinaExecutionResult,
        testCase: MarinaManualQACase,
        policy: MarinaUniversalRoutingPolicy
    ) {
        let text = visibleText(in: result)
        let forbiddenMarkers = [
            "Universal:",
            "Scenario:",
            "Scenario=",
            "Diagnostics:",
            "Fallback:",
            "Bridge unsupported=",
            "Runner unsupported=",
            "Presentation unsupported="
        ]

        for marker in forbiddenMarkers {
            #expect(
                text.contains(marker) == false,
                "Visible diagnostics marker \(marker) leaked for \(testCase.id) with policy \(policy.isEnabled ? "enabled" : "disabled").\n\(text)"
            )
        }
    }

    private func visibleText(in result: MarinaExecutionResult) -> String {
        var fields = [
            result.title,
            result.subtitle,
            result.primaryValue,
            result.explanation
        ].compactMap { $0 }

        for row in result.rows {
            fields.append(row.title)
            fields.append(row.value)
        }

        return fields.joined(separator: "\n")
    }

    private func failureReport(
        for testCase: MarinaManualQACase,
        policy: MarinaUniversalRoutingPolicy,
        result: MarinaDualPathQueryResult
    ) -> String {
        let diagnostics: MarinaUniversalRoutingDiagnostics?
        let actualRouting: String
        switch result {
        case let .legacy(_, resultDiagnostics):
            actualRouting = "legacy"
            diagnostics = resultDiagnostics
        case let .universal(_, resultDiagnostics):
            actualRouting = "universal"
            diagnostics = resultDiagnostics
        }

        return """
        # Marina Manual QA Matrix Failure

        Case ID: \(testCase.id)
        Prompt: \(testCase.prompt)
        Expected routing: \(testCase.expectedRouting)
        Expected scenario: \(testCase.expectedScenario?.rawValue ?? "nil")
        Expected layer: \(testCase.expectedLayer)
        Actual routing: \(actualRouting)
        Routing policy: \(policy.isEnabled ? "enabled" : "disabled")
        Diagnostics: \(formatted(diagnostics))
        Notes: \(testCase.notes)
        """
    }

    private func formatted(_ diagnostics: MarinaUniversalRoutingDiagnostics?) -> String {
        guard let diagnostics else { return "nil" }
        return """
        usedUniversal=\(diagnostics.usedUniversal), scenario=\(diagnostics.scenario?.rawValue ?? "nil"), fallback=\(diagnostics.fallbackReason?.rawValue ?? "nil"), entity=\(diagnostics.requestEntity.rawValue), operation=\(diagnostics.operation.rawValue), measure=\(diagnostics.measure?.rawValue ?? "nil"), notes=\(diagnostics.notes.joined(separator: " | "))
        """
    }

    private func makeFixture() -> MarinaManualQAMatrixFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let phonePreset = Preset(title: "Phone", plannedAmount: 80, workspace: workspace, defaultCard: appleCard, defaultCategory: electronics)

        let appleStoreJune = VariableExpense(descriptionText: "Apple Store", amount: 120, transactionDate: date(2026, 6, 5), workspace: workspace, card: appleCard, category: electronics)
        let appleMarketJune = VariableExpense(descriptionText: "Apple Market", amount: 18, transactionDate: date(2026, 6, 20), workspace: workspace, card: appleCard, category: groceries)
        let krogerJune = VariableExpense(descriptionText: "Kroger", amount: 30, transactionDate: date(2026, 6, 10), workspace: workspace, card: chaseCard, category: groceries)
        let bestBuyJune = VariableExpense(descriptionText: "Best Buy", amount: 300, transactionDate: date(2026, 6, 12), workspace: workspace, card: chaseCard, category: electronics)
        let appleStoreMay = VariableExpense(descriptionText: "Apple Store", amount: 75, transactionDate: date(2026, 5, 8), workspace: workspace, card: appleCard, category: electronics)
        let krogerMay = VariableExpense(descriptionText: "Kroger", amount: 42, transactionDate: date(2026, 5, 18), workspace: workspace, card: chaseCard, category: groceries)

        let phoneBill = PlannedExpense(
            title: "Phone Bill",
            plannedAmount: 80,
            expenseDate: date(2026, 6, 16),
            workspace: workspace,
            card: appleCard,
            category: electronics,
            sourcePresetID: phonePreset.id,
            sourceBudgetID: budget.id
        )
        let rent = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: date(2026, 6, 25),
            workspace: workspace,
            card: chaseCard,
            category: nil,
            sourceBudgetID: budget.id
        )

        let actualPaycheck = Income(source: "Paycheck", amount: 2_000, date: date(2026, 6, 11), isPlanned: false, workspace: workspace, card: appleCard)
        let freelance = Income(source: "Freelance", amount: 650, date: date(2026, 6, 19), isPlanned: false, workspace: workspace, card: chaseCard)
        let plannedPaycheck = Income(source: "Paycheck", amount: 2_100, date: date(2026, 6, 25), isPlanned: true, workspace: workspace, card: appleCard)

        let savings = SavingsAccount(name: "Savings Account", total: 1_000, workspace: workspace)
        let alejandro = AllocationAccount(name: "Alejandro", workspace: workspace)
        let krogerAllocation = ExpenseAllocation(
            allocatedAmount: 10,
            preservesGrossAmount: true,
            workspace: workspace,
            account: alejandro,
            expense: krogerJune
        )
        let settlement = AllocationSettlement(
            date: date(2026, 6, 21),
            note: "Alejandro paid back",
            amount: -4,
            workspace: workspace,
            account: alejandro
        )
        krogerJune.allocation = krogerAllocation
        alejandro.expenseAllocations = [krogerAllocation]
        alejandro.settlements = [settlement]

        let variableExpenses = [appleStoreJune, appleMarketJune, krogerJune, bestBuyJune, appleStoreMay, krogerMay]
        let plannedExpenses = [phoneBill, rent]
        let incomes = [actualPaycheck, freelance, plannedPaycheck]
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [appleCard, chaseCard],
            categories: [groceries, electronics],
            presets: [phonePreset],
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            homePlannedExpenses: plannedExpenses,
            homeCalculationPlannedExpenses: plannedExpenses,
            homeCalculationVariableExpenses: variableExpenses,
            reconciliationAccounts: [alejandro],
            expenseAllocations: [krogerAllocation],
            allocationSettlements: [settlement],
            savingsAccounts: [savings],
            savingsEntries: [],
            incomes: incomes
        )

        return MarinaManualQAMatrixFixture(
            snapshot: snapshot,
            now: date(2026, 6, 15),
            calendar: calendar
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}

@MainActor
private struct MarinaManualQAMatrixFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let now: Date
    let calendar: Calendar

    var legacyExecutor: MarinaQueryExecutor {
        MarinaQueryExecutor(calendar: calendar)
    }

    func context() -> MarinaUniversalPlanningContext {
        MarinaUniversalPlanningContext(
            defaultBudgetingPeriod: .monthly,
            now: now,
            calendar: calendar
        )
    }

    func plan(for request: MarinaSemanticRequest) -> MarinaQueryPlan {
        MarinaQueryPlanner(calendar: calendar).plan(
            request: request,
            ambientDateRange: context().ambientDateRange,
            defaultBudgetingPeriod: context().defaultBudgetingPeriod,
            now: context().now
        )
    }

    func executor(policy: MarinaUniversalRoutingPolicy) -> MarinaDualPathQueryExecutor {
        MarinaDualPathQueryExecutor(
            legacyExecutor: legacyExecutor,
            universalHarness: harness(policy: policy),
            policy: policy
        )
    }

    private func harness(policy: MarinaUniversalRoutingPolicy) -> MarinaUniversalRoutingHarness {
        MarinaUniversalRoutingHarness(
            bridge: MarinaSemanticUniversalPlanBridge(formulaRegistry: MarinaFormulaRegistry(now: now, calendar: calendar)),
            runner: MarinaUniversalQueryRunner(formulaRegistry: MarinaFormulaRegistry(now: now, calendar: calendar)),
            presenter: MarinaUniversalResultPresenter(),
            policy: policy
        )
    }
}

private struct ManualQATestFailure: Error {}
