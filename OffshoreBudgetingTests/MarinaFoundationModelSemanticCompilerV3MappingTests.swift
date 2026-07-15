import Foundation
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels

@Suite(.serialized)
@MainActor
struct MarinaFoundationModelSemanticCompilerV3MappingTests {
    typealias Generated = MarinaFoundationModelGeneratedOutcomeV3

    private struct Fixture {
        let name: String
        let outcome: Generated
        let expected: MarinaSemanticRequest
    }

    @Test func everyDomainActionCompilesToItsExactRequest() throws {
        let selection = selection()
        let list = listModifiers(sort: .dateDescending, resultLimit: 4)
        let group = groupModifiers(
            dimension: .category,
            sort: .amountDescending,
            resultLimit: 3
        )
        let comparison = comparisonSelection(selection: selection, kind: .card)

        let fixtures: [Fixture] = [
            fixture(
                "workspace.list",
                .workspaceMetadata(.init(action: .list(.init(modifiers: list)))),
                entity: .workspace,
                operation: .list,
                sort: .dateDescending,
                resultLimit: 4,
                shape: .list
            ),
            fixture(
                "workspace.count",
                .workspaceMetadata(.init(action: .count(.init()))),
                entity: .workspace,
                operation: .count,
                shape: .metric
            ),
            fixture(
                "workspace.name",
                .workspaceMetadata(.init(action: .name(.init()))),
                entity: .workspace,
                operation: .list,
                measure: .name,
                shape: .metric
            ),
            fixture(
                "workspace.color",
                .workspaceMetadata(.init(action: .color(.init()))),
                entity: .workspace,
                operation: .list,
                measure: .color,
                shape: .metric
            ),

            fixture(
                "budget.list",
                .budget(.init(action: .list(.init(
                    projection: .linkedCards,
                    selection: selection,
                    modifiers: list
                )))),
                entity: .budget,
                operation: .list,
                projection: .linkedCards,
                sort: .dateDescending,
                resultLimit: 4,
                shape: .list
            ),
            fixture(
                "budget.sum",
                .budget(.init(action: .sum(.init(
                    measure: .budgetImpact,
                    selection: selection
                )))),
                entity: .budget,
                operation: .sum,
                measure: .budgetImpact,
                projection: .summary,
                shape: .metric
            ),
            fixture(
                "budget.average",
                .budget(.init(action: .average(.init(
                    measure: .projectedBudgetImpact,
                    selection: selection
                )))),
                entity: .budget,
                operation: .average,
                measure: .projectedBudgetImpact,
                projection: .summary,
                shape: .metric
            ),
            fixture(
                "budget.compare",
                .budget(.init(action: .compare(.init(
                    measure: .actualSavings,
                    selection: comparison
                )))),
                entity: .budget,
                operation: .compare,
                measure: .actualSavings,
                projection: .summary,
                dimensions: [.card],
                comparisonTargetName: "Comparison",
                comparisonTargetKindSource: .explicit,
                shape: .comparison
            ),
            fixture(
                "budget.forecast",
                .budget(.init(action: .forecast(.init(
                    measure: .safeDailySpend,
                    selection: selection
                )))),
                entity: .budget,
                operation: .forecast,
                measure: .safeDailySpend,
                projection: .summary,
                shape: .metric
            ),
            fixture(
                "budget.whatIf",
                .budget(.init(action: .whatIf(.init(
                    measure: .remainingRoom,
                    selection: selection,
                    amount: 12.5
                )))),
                entity: .budget,
                operation: .whatIf,
                measure: .remainingRoom,
                projection: .summary,
                whatIfAmount: 12.5,
                shape: .comparison
            ),

            fixture(
                "card.list",
                .card(.init(action: .list(.init(
                    measure: .name,
                    selection: selection,
                    modifiers: list,
                    expenseScope: .unified
                )))),
                entity: .card,
                operation: .list,
                measure: .name,
                sort: .dateDescending,
                resultLimit: 4,
                expenseScope: .unified,
                shape: .list
            ),
            fixture(
                "card.count",
                .card(.init(action: .count(.init(selection: selection)))),
                entity: .card,
                operation: .count,
                shape: .metric
            ),
            fixture(
                "card.sum",
                .card(.init(action: .sum(.init(
                    measure: .budgetImpact,
                    selection: selection,
                    expenseScope: .variable
                )))),
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                expenseScope: .variable,
                shape: .metric
            ),
            fixture(
                "card.compare",
                .card(.init(action: .compare(.init(
                    measure: .name,
                    selection: comparison,
                    expenseScope: .planned
                )))),
                entity: .card,
                operation: .compare,
                measure: .name,
                dimensions: [.card],
                comparisonTargetName: "Comparison",
                comparisonTargetKindSource: .explicit,
                expenseScope: .planned,
                shape: .comparison
            ),
            fixture(
                "card.group",
                .card(.init(action: .group(.init(
                    measure: .budgetImpact,
                    selection: selection,
                    modifiers: group,
                    expenseScope: .unified
                )))),
                entity: .card,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category],
                sort: .amountDescending,
                resultLimit: 3,
                expenseScope: .unified,
                shape: .list
            ),

            fixture(
                "plannedExpense.list",
                .plannedExpense(.init(action: .list(.init(
                    measure: .effectiveAmount,
                    selection: selection,
                    modifiers: list,
                    expenseScope: .planned
                )))),
                entity: .plannedExpense,
                operation: .list,
                measure: .effectiveAmount,
                sort: .dateDescending,
                resultLimit: 4,
                expenseScope: .planned,
                shape: .list
            ),
            fixture(
                "plannedExpense.count",
                .plannedExpense(.init(action: .count(.init(
                    selection: selection,
                    expenseScope: .planned
                )))),
                entity: .plannedExpense,
                operation: .count,
                expenseScope: .planned,
                shape: .metric
            ),
            fixture(
                "plannedExpense.sum",
                .plannedExpense(.init(action: .sum(.init(
                    measure: .plannedAmount,
                    selection: selection,
                    expenseScope: .planned
                )))),
                entity: .plannedExpense,
                operation: .sum,
                measure: .plannedAmount,
                expenseScope: .planned,
                shape: .metric
            ),
            fixture(
                "plannedExpense.average",
                .plannedExpense(.init(action: .average(.init(
                    measure: .actualAmount,
                    selection: selection,
                    expenseScope: .planned
                )))),
                entity: .plannedExpense,
                operation: .average,
                measure: .actualAmount,
                expenseScope: .planned,
                shape: .metric
            ),
            fixture(
                "plannedExpense.last",
                .plannedExpense(.init(action: .last(.init(
                    measure: .amount,
                    selection: selection,
                    sort: .dateDescending,
                    expenseScope: .planned
                )))),
                entity: .plannedExpense,
                operation: .last,
                measure: .amount,
                sort: .dateDescending,
                resultLimit: 1,
                expenseScope: .planned,
                shape: .metric
            ),
            fixture(
                "plannedExpense.next",
                .plannedExpense(.init(action: .next(.init(
                    measure: .effectiveAmount,
                    selection: selection,
                    sort: .dateAscending,
                    expenseScope: .planned
                )))),
                entity: .plannedExpense,
                operation: .next,
                measure: .effectiveAmount,
                sort: .dateAscending,
                resultLimit: 1,
                expenseScope: .planned,
                shape: .metric
            ),
            fixture(
                "plannedExpense.group",
                .plannedExpense(.init(action: .group(.init(
                    measure: .projectedBudgetImpact,
                    selection: selection,
                    modifiers: group,
                    expenseScope: .planned
                )))),
                entity: .plannedExpense,
                operation: .group,
                measure: .projectedBudgetImpact,
                dimensions: [.category],
                sort: .amountDescending,
                resultLimit: 3,
                expenseScope: .planned,
                shape: .list
            ),

            fixture(
                "variableExpense.list",
                .variableExpense(.init(action: .list(.init(
                    measure: .ledgerSignedAmount,
                    selection: selection,
                    modifiers: list,
                    expenseScope: .variable
                )))),
                entity: .variableExpense,
                operation: .list,
                measure: .ledgerSignedAmount,
                sort: .dateDescending,
                resultLimit: 4,
                expenseScope: .variable,
                shape: .list
            ),
            fixture(
                "variableExpense.count",
                .variableExpense(.init(action: .count(.init(
                    selection: selection,
                    expenseScope: .variable
                )))),
                entity: .variableExpense,
                operation: .count,
                expenseScope: .variable,
                shape: .metric
            ),
            fixture(
                "variableExpense.sum",
                .variableExpense(.init(action: .sum(.init(
                    measure: .budgetImpact,
                    selection: selection,
                    expenseScope: .variable
                )))),
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                expenseScope: .variable,
                shape: .metric
            ),
            fixture(
                "variableExpense.average",
                .variableExpense(.init(action: .average(.init(
                    measure: .amount,
                    selection: selection,
                    expenseScope: .variable
                )))),
                entity: .variableExpense,
                operation: .average,
                measure: .amount,
                expenseScope: .variable,
                shape: .metric
            ),
            fixture(
                "variableExpense.last",
                .variableExpense(.init(action: .last(.init(
                    measure: .ledgerSignedAmount,
                    selection: selection,
                    sort: .dateDescending,
                    expenseScope: .variable
                )))),
                entity: .variableExpense,
                operation: .last,
                measure: .ledgerSignedAmount,
                sort: .dateDescending,
                resultLimit: 1,
                expenseScope: .variable,
                shape: .metric
            ),
            fixture(
                "variableExpense.group",
                .variableExpense(.init(action: .group(.init(
                    measure: .budgetImpact,
                    selection: selection,
                    modifiers: group,
                    expenseScope: .variable
                )))),
                entity: .variableExpense,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category],
                sort: .amountDescending,
                resultLimit: 3,
                expenseScope: .variable,
                shape: .list
            ),

            fixture(
                "reconciliation.list",
                .reconciliationAccount(.init(action: .list(.init(
                    projection: .activity,
                    measure: .name,
                    selection: selection,
                    modifiers: list
                )))),
                entity: .reconciliationAccount,
                operation: .list,
                measure: .name,
                projection: .activity,
                sort: .dateDescending,
                resultLimit: 4,
                shape: .list
            ),
            fixture(
                "reconciliation.count",
                .reconciliationAccount(.init(action: .count(.init(selection: selection)))),
                entity: .reconciliationAccount,
                operation: .count,
                shape: .metric
            ),
            fixture(
                "reconciliation.sum",
                .reconciliationAccount(.init(action: .sum(.init(
                    measure: .reconciliationBalance,
                    selection: selection
                )))),
                entity: .reconciliationAccount,
                operation: .sum,
                measure: .reconciliationBalance,
                shape: .metric
            ),
            fixture(
                "reconciliation.group",
                .reconciliationAccount(.init(action: .group(.init(
                    measure: .color,
                    selection: selection,
                    modifiers: group
                )))),
                entity: .reconciliationAccount,
                operation: .group,
                measure: .color,
                dimensions: [.category],
                sort: .amountDescending,
                resultLimit: 3,
                shape: .list
            ),

            fixture(
                "savings.list",
                .savingsAccount(.init(action: .list(.init(
                    projection: .activity,
                    measure: .name,
                    selection: selection,
                    modifiers: list
                )))),
                entity: .savingsAccount,
                operation: .list,
                measure: .name,
                projection: .activity,
                sort: .dateDescending,
                resultLimit: 4,
                shape: .list
            ),
            fixture(
                "savings.count",
                .savingsAccount(.init(action: .count(.init(selection: selection)))),
                entity: .savingsAccount,
                operation: .count,
                shape: .metric
            ),
            fixture(
                "savings.sum",
                .savingsAccount(.init(action: .sum(.init(
                    measure: .savingsTotal,
                    selection: selection
                )))),
                entity: .savingsAccount,
                operation: .sum,
                measure: .savingsTotal,
                shape: .metric
            ),
            fixture(
                "savings.last",
                .savingsAccount(.init(action: .last(.init(
                    measure: .savingsTotal,
                    selection: selection
                )))),
                entity: .savingsAccount,
                operation: .last,
                measure: .savingsTotal,
                shape: .metric
            ),
            fixture(
                "savings.group",
                .savingsAccount(.init(action: .group(.init(
                    measure: .savingsTotal,
                    selection: selection,
                    modifiers: group
                )))),
                entity: .savingsAccount,
                operation: .group,
                measure: .savingsTotal,
                dimensions: [.category],
                sort: .amountDescending,
                resultLimit: 3,
                shape: .list
            ),
            fixture(
                "savings.forecast",
                .savingsAccount(.init(action: .forecast(.init(
                    measure: .savingsTotal,
                    selection: selection
                )))),
                entity: .savingsAccount,
                operation: .forecast,
                measure: .savingsTotal,
                shape: .metric
            ),

            fixture(
                "income.list",
                .income(.init(action: .list(.init(
                    measure: .incomeAmount,
                    state: .planned,
                    selection: selection,
                    modifiers: list
                )))),
                entity: .income,
                operation: .list,
                measure: .incomeAmount,
                sort: .dateDescending,
                resultLimit: 4,
                incomeState: .planned,
                shape: .list
            ),
            fixture(
                "income.count",
                .income(.init(action: .count(.init(
                    state: .actual,
                    selection: selection
                )))),
                entity: .income,
                operation: .count,
                incomeState: .actual,
                shape: .metric
            ),
            fixture(
                "income.sum",
                .income(.init(action: .sum(.init(
                    measure: .incomeAmount,
                    state: .actual,
                    selection: selection
                )))),
                entity: .income,
                operation: .sum,
                measure: .incomeAmount,
                incomeState: .actual,
                shape: .metric
            ),
            fixture(
                "income.average",
                .income(.init(action: .average(.init(
                    measure: .amount,
                    state: .all,
                    selection: selection
                )))),
                entity: .income,
                operation: .average,
                measure: .amount,
                incomeState: .all,
                shape: .metric
            ),
            fixture(
                "income.compare",
                .income(.init(action: .compare(.init(
                    measure: .incomeAmount,
                    state: .planned,
                    selection: comparison
                )))),
                entity: .income,
                operation: .compare,
                measure: .incomeAmount,
                dimensions: [.card],
                comparisonTargetName: "Comparison",
                comparisonTargetKindSource: .explicit,
                incomeState: .planned,
                shape: .comparison
            ),
            fixture(
                "income.group",
                .income(.init(action: .group(.init(
                    measure: .incomeAmount,
                    state: .all,
                    selection: selection,
                    modifiers: group
                )))),
                entity: .income,
                operation: .group,
                measure: .incomeAmount,
                dimensions: [.category],
                sort: .amountDescending,
                resultLimit: 3,
                incomeState: .all,
                shape: .list
            ),
            fixture(
                "income.progress",
                .income(.init(action: .progress(.init(selection: selection)))),
                entity: .income,
                operation: .share,
                measure: .incomeAmount,
                incomeState: .all,
                shape: .metric
            ),
            fixture(
                "income.coverage",
                .income(.init(action: .coverage(.init(selection: selection)))),
                entity: .income,
                operation: .share,
                measure: .coverageRatio,
                shape: .metric
            ),
            fixture(
                "income.forecast",
                .income(.init(action: .forecast(.init(
                    measure: .coverageRatio,
                    state: .planned,
                    selection: selection
                )))),
                entity: .income,
                operation: .forecast,
                measure: .coverageRatio,
                incomeState: .planned,
                shape: .metric
            ),

            fixture(
                "incomeSeries.list",
                .incomeSeries(.init(action: .list(.init(
                    projection: .occurrences,
                    measure: .incomeAmount,
                    selection: selection,
                    modifiers: list
                )))),
                entity: .incomeSeries,
                operation: .list,
                measure: .incomeAmount,
                projection: .occurrences,
                sort: .dateDescending,
                resultLimit: 4,
                shape: .list
            ),
            fixture(
                "incomeSeries.count",
                .incomeSeries(.init(action: .count(.init(
                    projection: .occurrences,
                    selection: selection
                )))),
                entity: .incomeSeries,
                operation: .count,
                projection: .occurrences,
                shape: .metric
            ),
            fixture(
                "incomeSeries.last",
                .incomeSeries(.init(action: .last(.init(
                    projection: .records,
                    measure: .incomeAmount,
                    selection: selection,
                    sort: .dateDescending
                )))),
                entity: .incomeSeries,
                operation: .last,
                measure: .incomeAmount,
                sort: .dateDescending,
                resultLimit: 1,
                shape: .metric
            ),
            fixture(
                "incomeSeries.next",
                .incomeSeries(.init(action: .next(.init(
                    projection: .occurrences,
                    measure: .amount,
                    selection: selection,
                    sort: .dateAscending
                )))),
                entity: .incomeSeries,
                operation: .next,
                measure: .amount,
                projection: .occurrences,
                sort: .dateAscending,
                resultLimit: 1,
                shape: .metric
            ),

            fixture(
                "category.list",
                .category(.init(action: .list(.init(
                    measure: .color,
                    selection: selection,
                    modifiers: list
                )))),
                entity: .category,
                operation: .list,
                measure: .color,
                sort: .dateDescending,
                resultLimit: 4,
                shape: .list
            ),
            fixture(
                "category.count",
                .category(.init(action: .count(.init(selection: selection)))),
                entity: .category,
                operation: .count,
                shape: .metric
            ),
            fixture(
                "category.sum",
                .category(.init(action: .sum(.init(
                    measure: .budgetImpact,
                    selection: selection,
                    expenseScope: .unified
                )))),
                entity: .category,
                operation: .sum,
                measure: .budgetImpact,
                expenseScope: .unified,
                shape: .metric
            ),
            fixture(
                "category.average",
                .category(.init(action: .average(.init(
                    measure: .concentration,
                    selection: selection,
                    expenseScope: .planned
                )))),
                entity: .category,
                operation: .average,
                measure: .concentration,
                expenseScope: .planned,
                shape: .metric
            ),
            fixture(
                "category.compare",
                .category(.init(action: .compare(.init(
                    measure: .color,
                    selection: comparison,
                    expenseScope: .variable
                )))),
                entity: .category,
                operation: .compare,
                measure: .color,
                dimensions: [.card],
                comparisonTargetName: "Comparison",
                comparisonTargetKindSource: .explicit,
                expenseScope: .variable,
                shape: .comparison
            ),
            fixture(
                "category.groupedSpend",
                .category(.init(action: .groupedSpend(.init(
                    selection: selection,
                    dimension: .category,
                    sort: .amountDescending,
                    resultLimit: 3,
                    continuation: .none,
                    expenseScope: .unified
                )))),
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category],
                sort: .amountDescending,
                resultLimit: 3,
                expenseScope: .unified,
                shape: .list
            ),
            fixture(
                "category.share",
                .category(.init(action: .share(.init(
                    measure: .concentration,
                    selection: selection,
                    expenseScope: .unified
                )))),
                entity: .category,
                operation: .share,
                measure: .concentration,
                expenseScope: .unified,
                shape: .metric
            ),
            fixture(
                "category.forecast",
                .category(.init(action: .forecast(.init(
                    measure: .concentration,
                    selection: selection
                )))),
                entity: .category,
                operation: .forecast,
                measure: .concentration,
                shape: .metric
            ),
            fixture(
                "category.availabilitySummary",
                .category(.init(action: .availabilitySummary(.init(selection: selection)))),
                entity: .category,
                operation: .forecast,
                measure: .categoryAvailability,
                shape: .metric
            ),
            fixture(
                "category.availabilityList",
                .category(.init(action: .availabilityList(.init(
                    status: .near,
                    selection: selection,
                    modifiers: list
                )))),
                entity: .category,
                operation: .list,
                measure: .categoryAvailability,
                sort: .dateDescending,
                resultLimit: 4,
                categoryAvailabilityFilter: .near,
                shape: .list
            ),

            fixture(
                "preset.list",
                .preset(.init(action: .list(.init(
                    projection: .linkedBudgets,
                    measure: .name,
                    selection: selection,
                    modifiers: list
                )))),
                entity: .preset,
                operation: .list,
                measure: .name,
                projection: .linkedBudgets,
                sort: .dateDescending,
                resultLimit: 4,
                shape: .list
            ),
            fixture(
                "preset.sum",
                .preset(.init(action: .sum(.init(
                    measure: .recurringBurden,
                    selection: selection
                )))),
                entity: .preset,
                operation: .sum,
                measure: .recurringBurden,
                shape: .metric
            ),
            fixture(
                "preset.next",
                .preset(.init(action: .next(.init(
                    measure: .plannedAmount,
                    selection: selection,
                    sort: .dateAscending
                )))),
                entity: .preset,
                operation: .next,
                measure: .plannedAmount,
                sort: .dateAscending,
                resultLimit: 1,
                shape: .metric
            ),
            fixture(
                "preset.group",
                .preset(.init(action: .group(.init(
                    measure: .actualAmount,
                    selection: selection,
                    modifiers: group
                )))),
                entity: .preset,
                operation: .group,
                measure: .actualAmount,
                dimensions: [.category],
                sort: .amountDescending,
                resultLimit: 3,
                shape: .list
            )
        ]

        #expect(fixtures.count == 65)
        for fixture in fixtures {
            let actual = try compile(fixture.outcome)
            #expect(actual == fixture.expected, "V3 action mapping: \(fixture.name)")
        }
    }

    @Test func everyBudgetMeasureVariantMapsExactly() throws {
        let selection = selection()
        let comparison = comparisonSelection(selection: selection, kind: .budget)
        let metricCases: [(Generated.BudgetMetricMeasure, MarinaSemanticMeasure)] = [
            (.budgetImpact, .budgetImpact),
            (.projectedBudgetImpact, .projectedBudgetImpact),
            (.plannedIncomeTotal, .plannedIncomeTotal),
            (.actualIncomeTotal, .actualIncomeTotal),
            (.plannedExpenseProjectedTotal, .plannedExpenseProjectedTotal),
            (.plannedExpenseActualTotal, .plannedExpenseActualTotal),
            (.plannedExpenseEffectiveTotal, .plannedExpenseEffectiveTotal),
            (.variableExpenseTotal, .variableExpenseTotal),
            (.unifiedExpenseTotal, .unifiedExpenseTotal),
            (.maximumSavings, .maximumSavings),
            (.projectedSavings, .projectedSavings),
            (.actualSavings, .actualSavings),
            (.remainingRoom, .remainingRoom),
            (.burnRate, .burnRate),
            (.projectedSpend, .projectedSpend),
            (.safeDailySpend, .safeDailySpend),
            (.paceDifference, .paceDifference),
            (.coverageRatio, .coverageRatio)
        ]
        for (generated, semantic) in metricCases {
            let actual = try compile(.query(.budget(.init(action: .sum(.init(
                measure: generated,
                selection: selection
            ))))))
            #expect(actual == request(
                entity: .budget,
                operation: .sum,
                measure: semantic,
                projection: .summary,
                shape: .metric
            ))
        }

        let comparisonCases: [(Generated.BudgetComparisonMeasure, MarinaSemanticMeasure)] = [
            (.budgetImpact, .budgetImpact),
            (.projectedBudgetImpact, .projectedBudgetImpact),
            (.plannedIncomeTotal, .plannedIncomeTotal),
            (.actualIncomeTotal, .actualIncomeTotal),
            (.plannedExpenseProjectedTotal, .plannedExpenseProjectedTotal),
            (.plannedExpenseActualTotal, .plannedExpenseActualTotal),
            (.plannedExpenseEffectiveTotal, .plannedExpenseEffectiveTotal),
            (.variableExpenseTotal, .variableExpenseTotal),
            (.unifiedExpenseTotal, .unifiedExpenseTotal),
            (.maximumSavings, .maximumSavings),
            (.projectedSavings, .projectedSavings),
            (.actualSavings, .actualSavings),
            (.remainingRoom, .remainingRoom),
            (.burnRate, .burnRate),
            (.projectedSpend, .projectedSpend),
            (.safeDailySpend, .safeDailySpend),
            (.paceDifference, .paceDifference),
            (.coverageRatio, .coverageRatio)
        ]
        for (generated, semantic) in comparisonCases {
            let actual = try compile(.query(.budget(.init(action: .compare(.init(
                measure: generated,
                selection: comparison
            ))))))
            #expect(actual == request(
                entity: .budget,
                operation: .compare,
                measure: semantic,
                projection: .summary,
                dimensions: [.budget],
                comparisonTargetName: "Comparison",
                comparisonTargetKindSource: .explicit,
                shape: .comparison
            ))
        }

        let forecastCases: [(Generated.BudgetForecastMeasure, MarinaSemanticMeasure)] = [
            (.projectedBudgetImpact, .projectedBudgetImpact),
            (.projectedSpend, .projectedSpend),
            (.projectedSavings, .projectedSavings),
            (.maximumSavings, .maximumSavings),
            (.remainingRoom, .remainingRoom),
            (.burnRate, .burnRate),
            (.safeDailySpend, .safeDailySpend),
            (.paceDifference, .paceDifference),
            (.coverageRatio, .coverageRatio)
        ]
        for (generated, semantic) in forecastCases {
            let actual = try compile(.query(.budget(.init(action: .forecast(.init(
                measure: generated,
                selection: selection
            ))))))
            #expect(actual == request(
                entity: .budget,
                operation: .forecast,
                measure: semantic,
                projection: .summary,
                shape: .metric
            ))
        }

        let whatIfCases: [(Generated.BudgetWhatIfMeasure, MarinaSemanticMeasure)] = [
            (.remainingRoom, .remainingRoom),
            (.projectedSavings, .projectedSavings),
            (.projectedSpend, .projectedSpend),
            (.safeDailySpend, .safeDailySpend)
        ]
        for (generated, semantic) in whatIfCases {
            let actual = try compile(.query(.budget(.init(action: .whatIf(.init(
                measure: generated,
                selection: selection,
                amount: 42
            ))))))
            #expect(actual == request(
                entity: .budget,
                operation: .whatIf,
                measure: semantic,
                projection: .summary,
                whatIfAmount: 42,
                shape: .comparison
            ))
        }
    }

    @Test func everyDomainSpecificMeasureVariantMapsExactly() throws {
        let selection = selection()

        let cardCases: [(Generated.CardMeasure, MarinaSemanticMeasure)] = [
            (.budgetImpact, .budgetImpact), (.name, .name)
        ]
        for (generated, semantic) in cardCases {
            let actual = try compile(.query(.card(.init(action: .sum(.init(
                measure: generated,
                selection: selection,
                expenseScope: nil
            ))))))
            #expect(actual == request(entity: .card, operation: .sum, measure: semantic, shape: .metric))
        }

        let plannedCases: [(Generated.PlannedExpenseMeasure, MarinaSemanticMeasure)] = [
            (.amount, .amount),
            (.plannedAmount, .plannedAmount),
            (.actualAmount, .actualAmount),
            (.effectiveAmount, .effectiveAmount),
            (.budgetImpact, .budgetImpact),
            (.projectedBudgetImpact, .projectedBudgetImpact)
        ]
        for (generated, semantic) in plannedCases {
            let actual = try compile(.query(.plannedExpense(.init(action: .sum(.init(
                measure: generated,
                selection: selection,
                expenseScope: nil
            ))))))
            #expect(actual == request(entity: .plannedExpense, operation: .sum, measure: semantic, shape: .metric))
        }

        let variableCases: [(Generated.VariableExpenseMeasure, MarinaSemanticMeasure)] = [
            (.amount, .amount),
            (.budgetImpact, .budgetImpact),
            (.ledgerSignedAmount, .ledgerSignedAmount)
        ]
        for (generated, semantic) in variableCases {
            let actual = try compile(.query(.variableExpense(.init(action: .sum(.init(
                measure: generated,
                selection: selection,
                expenseScope: nil
            ))))))
            #expect(actual == request(entity: .variableExpense, operation: .sum, measure: semantic, shape: .metric))
        }

        let reconciliationCases: [(Generated.ReconciliationMeasure, MarinaSemanticMeasure)] = [
            (.name, .name), (.color, .color), (.reconciliationBalance, .reconciliationBalance)
        ]
        for (generated, semantic) in reconciliationCases {
            let actual = try compile(.query(.reconciliationAccount(.init(action: .sum(.init(
                measure: generated,
                selection: selection
            ))))))
            #expect(actual == request(entity: .reconciliationAccount, operation: .sum, measure: semantic, shape: .metric))
        }

        let savingsCases: [(Generated.SavingsMeasure, MarinaSemanticMeasure)] = [
            (.name, .name), (.savingsTotal, .savingsTotal)
        ]
        for (generated, semantic) in savingsCases {
            let actual = try compile(.query(.savingsAccount(.init(action: .sum(.init(
                measure: generated,
                selection: selection
            ))))))
            #expect(actual == request(entity: .savingsAccount, operation: .sum, measure: semantic, shape: .metric))
        }

        let incomeCases: [(Generated.IncomeAmountMeasure, MarinaSemanticMeasure)] = [
            (.amount, .amount), (.incomeAmount, .incomeAmount)
        ]
        for (generated, semantic) in incomeCases {
            let actual = try compile(.query(.income(.init(action: .sum(.init(
                measure: generated,
                state: .all,
                selection: selection
            ))))))
            #expect(actual == request(
                entity: .income,
                operation: .sum,
                measure: semantic,
                incomeState: .all,
                shape: .metric
            ))
        }

        let incomeForecastCases: [(Generated.IncomeForecastMeasure, MarinaSemanticMeasure)] = [
            (.incomeAmount, .incomeAmount), (.coverageRatio, .coverageRatio)
        ]
        for (generated, semantic) in incomeForecastCases {
            let actual = try compile(.query(.income(.init(action: .forecast(.init(
                measure: generated,
                state: .planned,
                selection: selection
            ))))))
            #expect(actual == request(
                entity: .income,
                operation: .forecast,
                measure: semantic,
                incomeState: .planned,
                shape: .metric
            ))
        }

        let categoryMetadataCases: [(Generated.CategoryMetadataMeasure, MarinaSemanticMeasure)] = [
            (.name, .name), (.color, .color)
        ]
        for (generated, semantic) in categoryMetadataCases {
            let actual = try compile(.query(.category(.init(action: .list(.init(
                measure: generated,
                selection: selection,
                modifiers: listModifiers()
            ))))))
            #expect(actual == request(entity: .category, operation: .list, measure: semantic, shape: .list))
        }

        let categoryMetricCases: [(Generated.CategoryMetricMeasure, MarinaSemanticMeasure)] = [
            (.budgetImpact, .budgetImpact),
            (.concentration, .concentration),
            (.name, .name),
            (.color, .color)
        ]
        for (generated, semantic) in categoryMetricCases {
            let actual = try compile(.query(.category(.init(action: .sum(.init(
                measure: generated,
                selection: selection,
                expenseScope: nil
            ))))))
            #expect(actual == request(entity: .category, operation: .sum, measure: semantic, shape: .metric))
        }

        let categoryForecast = try compile(.query(.category(.init(action: .forecast(.init(
            measure: .concentration,
            selection: selection
        ))))))
        #expect(categoryForecast == request(
            entity: .category,
            operation: .forecast,
            measure: .concentration,
            shape: .metric
        ))

        let presetCases: [(Generated.PresetMeasure, MarinaSemanticMeasure)] = [
            (.plannedAmount, .plannedAmount),
            (.actualAmount, .actualAmount),
            (.recurringBurden, .recurringBurden),
            (.name, .name)
        ]
        for (generated, semantic) in presetCases {
            let actual = try compile(.query(.preset(.init(action: .sum(.init(
                measure: generated,
                selection: selection
            ))))))
            #expect(actual == request(entity: .preset, operation: .sum, measure: semantic, shape: .metric))
        }
    }

    @Test func everySelectionEnumVariantMapsExactly() throws {
        let filterCases: [(Generated.FilterKind, MarinaSemanticDimension)] = [
            (.category, .category),
            (.card, .card),
            (.merchantText, .merchantText),
            (.budget, .budget),
            (.incomeSource, .incomeSource),
            (.incomeSeries, .incomeSeries),
            (.preset, .preset),
            (.savingsAccount, .savingsAccount),
            (.reconciliationAccount, .reconciliationAccount)
        ]
        for (index, fixture) in filterCases.enumerated() {
            let evidence: Generated.Evidence = index.isMultiple(of: 2) ? .explicit : .inferred
            let source: MarinaSemanticTargetKindSource = index.isMultiple(of: 2) ? .explicit : .inferred
            let actual = try compile(categoryCount(selection: selection(filters: [
                .init(kind: fixture.0, value: " Filter ", evidence: evidence)
            ])))
            #expect(actual == request(
                entity: .category,
                operation: .count,
                dimensions: [fixture.1],
                constraints: [.init(dimension: fixture.1, value: "Filter", kindSource: source)],
                textQuery: fixture.1 == .merchantText ? "Filter" : nil,
                shape: .metric
            ))
        }

        let targetCases: [(Generated.TargetKind, MarinaSemanticDimension)] = [
            (.budget, .budget),
            (.card, .card),
            (.category, .category),
            (.merchantText, .merchantText),
            (.incomeSource, .incomeSource),
            (.incomeSeries, .incomeSeries),
            (.preset, .preset),
            (.savingsAccount, .savingsAccount),
            (.reconciliationAccount, .reconciliationAccount)
        ]
        for fixture in targetCases {
            let actual = try compile(categoryCount(selection: selection(target: .init(
                wording: " Target ",
                classification: .explicit(fixture.0)
            ))))
            #expect(actual == request(
                entity: .category,
                operation: .count,
                dimensions: [fixture.1],
                targetName: "Target",
                textQuery: fixture.1 == .merchantText ? "Target" : nil,
                targetKindSource: .explicit,
                shape: .metric
            ))
        }

        let inferred = try compile(categoryCount(selection: selection(target: .init(
            wording: "Target",
            classification: .inferred(.card)
        ))))
        #expect(inferred == request(
            entity: .category,
            operation: .count,
            dimensions: [.card],
            targetName: "Target",
            targetKindSource: .inferred,
            shape: .metric
        ))

        let unresolved = try compile(categoryCount(selection: selection(target: .init(
            wording: "Target",
            classification: .unresolved
        ))))
        #expect(unresolved == request(
            entity: .category,
            operation: .count,
            targetName: "Target",
            shape: .metric
        ))

        let namedBudget = try compile(categoryCount(selection: selection(
            boundary: .explicitNamedBudget(" July ")
        )))
        #expect(namedBudget == request(
            entity: .category,
            operation: .count,
            dimensions: [.budget],
            constraints: [.init(dimension: .budget, value: "July", kindSource: .explicit)],
            shape: .metric
        ))
    }

    @Test func everyDateSourceAndRangeMapsExactly() throws {
        let explicitCases: [(Generated.DateRange, MarinaSemanticDateRangeToken)] = [
            (.currentPeriod, .currentPeriod),
            (.previousPeriod, .previousPeriod),
            (.currentMonth, .currentMonth),
            (.previousMonth, .previousMonth),
            (.yearToDate, .yearToDate),
            (.nextSevenDays, .nextSevenDays),
            (.allTime, .allTime)
        ]
        for (generated, semantic) in explicitCases {
            let actual = try compile(categoryCount(selection: selection(date: .explicit(generated))))
            #expect(actual == request(
                entity: .category,
                operation: .count,
                dateRangeToken: semantic,
                dateRangeSource: .explicit,
                shape: .metric
            ))
        }

        let defaulted = try compile(categoryCount(selection: selection(date: .defaultCurrentPeriod)))
        #expect(defaulted == request(entity: .category, operation: .count, shape: .metric))

        let contextual = try compile(
            categoryCount(selection: selection(date: .conversationContext(.currentMonth))),
            conversationContext: priorConversationContext(nextOffset: nil)
        )
        #expect(contextual == request(
            entity: .category,
            operation: .count,
            dateRangeToken: .currentMonth,
            dateRangeSource: .conversationContext,
            shape: .metric
        ))
    }

    @Test func everyProjectionSortScopeStateGroupingStatusAndContinuationMapsExactly() throws {
        let selection = selection()

        let budgetProjections: [(Generated.BudgetListProjection, MarinaSemanticProjection)] = [
            (.records, .records),
            (.summary, .summary),
            (.income, .income),
            (.expenses, .expenses),
            (.linkedCards, .linkedCards),
            (.linkedPresets, .linkedPresets)
        ]
        for (generated, semantic) in budgetProjections {
            let actual = try compile(.query(.budget(.init(action: .list(.init(
                projection: generated,
                selection: selection,
                modifiers: listModifiers()
            ))))))
            #expect(actual == request(
                entity: .budget,
                operation: .list,
                projection: semantic,
                shape: .list
            ))
        }

        let accountProjections: [(Generated.AccountProjection, MarinaSemanticProjection)] = [
            (.records, .records), (.activity, .activity)
        ]
        for (generated, semantic) in accountProjections {
            let actual = try compile(.query(.savingsAccount(.init(action: .list(.init(
                projection: generated,
                measure: nil,
                selection: selection,
                modifiers: listModifiers()
            ))))))
            #expect(actual == request(
                entity: .savingsAccount,
                operation: .list,
                projection: semantic,
                shape: .list
            ))
        }

        let seriesProjections: [(Generated.IncomeSeriesProjection, MarinaSemanticProjection)] = [
            (.records, .records), (.occurrences, .occurrences)
        ]
        for (generated, semantic) in seriesProjections {
            let actual = try compile(.query(.incomeSeries(.init(action: .count(.init(
                projection: generated,
                selection: selection
            ))))))
            #expect(actual == request(
                entity: .incomeSeries,
                operation: .count,
                projection: semantic,
                shape: .metric
            ))
        }

        let presetProjections: [(Generated.PresetProjection, MarinaSemanticProjection)] = [
            (.records, .records), (.linkedBudgets, .linkedBudgets)
        ]
        for (generated, semantic) in presetProjections {
            let actual = try compile(.query(.preset(.init(action: .list(.init(
                projection: generated,
                measure: nil,
                selection: selection,
                modifiers: listModifiers()
            ))))))
            #expect(actual == request(
                entity: .preset,
                operation: .list,
                projection: semantic,
                shape: .list
            ))
        }

        let sortCases: [(Generated.Sort, MarinaSemanticSort)] = [
            (.dateAscending, .dateAscending),
            (.dateDescending, .dateDescending),
            (.amountAscending, .amountAscending),
            (.amountDescending, .amountDescending),
            (.nameAscending, .nameAscending)
        ]
        for (generated, semantic) in sortCases {
            let actual = try compile(.query(.category(.init(action: .list(.init(
                measure: nil,
                selection: selection,
                modifiers: listModifiers(sort: generated)
            ))))))
            #expect(actual == request(
                entity: .category,
                operation: .list,
                sort: semantic,
                shape: .list
            ))
        }

        let scopeCases: [(Generated.ExpenseScope, MarinaSemanticExpenseScope)] = [
            (.planned, .planned), (.variable, .variable), (.unified, .unified)
        ]
        for (generated, semantic) in scopeCases {
            let actual = try compile(.query(.variableExpense(.init(action: .sum(.init(
                measure: .amount,
                selection: selection,
                expenseScope: generated
            ))))))
            #expect(actual == request(
                entity: .variableExpense,
                operation: .sum,
                measure: .amount,
                expenseScope: semantic,
                shape: .metric
            ))
        }

        let incomeStates: [(Generated.IncomeState, MarinaSemanticIncomeState)] = [
            (.planned, .planned), (.actual, .actual), (.all, .all)
        ]
        for (generated, semantic) in incomeStates {
            let actual = try compile(.query(.income(.init(action: .sum(.init(
                measure: .incomeAmount,
                state: generated,
                selection: selection
            ))))))
            #expect(actual == request(
                entity: .income,
                operation: .sum,
                measure: .incomeAmount,
                incomeState: semantic,
                shape: .metric
            ))
        }

        let groupDimensions: [(Generated.GroupDimension, MarinaSemanticDimension)] = [
            (.category, .category),
            (.card, .card),
            (.incomeSource, .incomeSource),
            (.incomeSeries, .incomeSeries),
            (.preset, .preset),
            (.budget, .budget)
        ]
        for (generated, semantic) in groupDimensions {
            let actual = try compile(.query(.card(.init(action: .group(.init(
                measure: .budgetImpact,
                selection: selection,
                modifiers: groupModifiers(dimension: generated),
                expenseScope: nil
            ))))))
            #expect(actual == request(
                entity: .card,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [semantic],
                shape: .list
            ))
        }

        let availabilityCases: [(Generated.CategoryAvailabilityStatus, MarinaCategoryAvailabilityFilter)] = [
            (.over, .over), (.near, .near), (.underLimit, .underLimit)
        ]
        for (generated, semantic) in availabilityCases {
            let actual = try compile(.query(.category(.init(action: .availabilityList(.init(
                status: generated,
                selection: selection,
                modifiers: listModifiers()
            ))))))
            #expect(actual == request(
                entity: .category,
                operation: .list,
                measure: .categoryAvailability,
                categoryAvailabilityFilter: semantic,
                shape: .list
            ))
        }

        let continued = try compile(
            .query(.variableExpense(.init(action: .list(.init(
                measure: .budgetImpact,
                selection: selection,
                modifiers: listModifiers(resultLimit: 5, continuation: .showMore),
                expenseScope: .variable
            ))))),
            conversationContext: priorConversationContext(nextOffset: 5)
        )
        #expect(continued == request(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            continuationIntent: .showMore,
            resultLimit: 5,
            resultOffset: 5,
            expenseScope: .variable,
            shape: .list
        ))
    }

    @Test func everyUnsupportedMappingVariantCompilesExactly() throws {
        let subjectCases: [(Generated.Subject, MarinaSemanticEntity)] = [
            (.workspaceMetadata, .workspace),
            (.budget, .budget),
            (.card, .card),
            (.plannedExpense, .plannedExpense),
            (.variableExpense, .variableExpense),
            (.reconciliationAccount, .reconciliationAccount),
            (.savingsAccount, .savingsAccount),
            (.income, .income),
            (.incomeSeries, .incomeSeries),
            (.category, .category),
            (.preset, .preset)
        ]
        for (generated, semantic) in subjectCases {
            let actual = try compile(.unsupported(.init(
                reason: .readOnly,
                subject: generated,
                attemptedOperation: .list,
                attemptedMeasure: nil
            )))
            #expect(actual == request(
                entity: semantic,
                operation: .list,
                shape: .unsupported,
                unsupportedReason: .readOnly
            ))
        }

        let operationCases: [(Generated.AttemptedOperation, MarinaSemanticOperation)] = [
            (.list, .list),
            (.count, .count),
            (.sum, .sum),
            (.average, .average),
            (.compare, .compare),
            (.last, .last),
            (.next, .next),
            (.group, .group),
            (.share, .share),
            (.forecast, .forecast),
            (.whatIf, .whatIf)
        ]
        for (generated, semantic) in operationCases {
            let actual = try compile(.unsupported(.init(
                reason: .unsupportedCombination,
                subject: .budget,
                attemptedOperation: generated,
                attemptedMeasure: nil
            )))
            #expect(actual == request(
                entity: .budget,
                operation: semantic,
                shape: .unsupported,
                unsupportedReason: .unsupportedCombination
            ))
        }

        let measureCases: [(Generated.AttemptedMeasure, MarinaSemanticMeasure)] = [
            (.amount, .amount),
            (.plannedAmount, .plannedAmount),
            (.actualAmount, .actualAmount),
            (.effectiveAmount, .effectiveAmount),
            (.budgetImpact, .budgetImpact),
            (.projectedBudgetImpact, .projectedBudgetImpact),
            (.ledgerSignedAmount, .ledgerSignedAmount),
            (.plannedIncomeTotal, .plannedIncomeTotal),
            (.actualIncomeTotal, .actualIncomeTotal),
            (.plannedExpenseProjectedTotal, .plannedExpenseProjectedTotal),
            (.plannedExpenseActualTotal, .plannedExpenseActualTotal),
            (.plannedExpenseEffectiveTotal, .plannedExpenseEffectiveTotal),
            (.variableExpenseTotal, .variableExpenseTotal),
            (.unifiedExpenseTotal, .unifiedExpenseTotal),
            (.savingsTotal, .savingsTotal),
            (.maximumSavings, .maximumSavings),
            (.projectedSavings, .projectedSavings),
            (.actualSavings, .actualSavings),
            (.incomeAmount, .incomeAmount),
            (.reconciliationBalance, .reconciliationBalance),
            (.categoryAvailability, .categoryAvailability),
            (.remainingRoom, .remainingRoom),
            (.burnRate, .burnRate),
            (.projectedSpend, .projectedSpend),
            (.safeDailySpend, .safeDailySpend),
            (.paceDifference, .paceDifference),
            (.coverageRatio, .coverageRatio),
            (.recurringBurden, .recurringBurden),
            (.concentration, .concentration),
            (.color, .color),
            (.name, .name)
        ]
        for (generated, semantic) in measureCases {
            let actual = try compile(.unsupported(.init(
                reason: .incomeSavingsWhatIfUnsupported,
                subject: .income,
                attemptedOperation: .whatIf,
                attemptedMeasure: generated
            )))
            #expect(actual == request(
                entity: .income,
                operation: .whatIf,
                measure: semantic,
                shape: .unsupported,
                unsupportedReason: .incomeSavingsWhatIfUnsupported
            ))
        }
    }

    private func fixture(
        _ name: String,
        _ query: Generated.Query,
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        projection: MarinaSemanticProjection = .records,
        dimensions: [MarinaSemanticDimension] = [],
        constraints: [MarinaSemanticConstraint] = [],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod,
        dateRangeSource: MarinaSemanticDateRangeSource = .defaulted,
        targetName: String? = nil,
        comparisonTargetName: String? = nil,
        textQuery: String? = nil,
        targetKindSource: MarinaSemanticTargetKindSource = .unspecified,
        comparisonTargetKindSource: MarinaSemanticTargetKindSource = .unspecified,
        continuationIntent: MarinaSemanticContinuationIntent = .none,
        sort: MarinaSemanticSort? = nil,
        resultLimit: Int? = nil,
        resultOffset: Int? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        incomeState: MarinaSemanticIncomeState? = nil,
        whatIfAmount: Double? = nil,
        categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
        shape: MarinaSemanticAnswerShape,
        unsupportedReason: MarinaSemanticUnsupportedReason? = nil
    ) -> Fixture {
        Fixture(
            name: name,
            outcome: .query(query),
            expected: request(
                entity: entity,
                operation: operation,
                measure: measure,
                projection: projection,
                dimensions: dimensions,
                constraints: constraints,
                dateRangeToken: dateRangeToken,
                dateRangeSource: dateRangeSource,
                targetName: targetName,
                comparisonTargetName: comparisonTargetName,
                textQuery: textQuery,
                targetKindSource: targetKindSource,
                comparisonTargetKindSource: comparisonTargetKindSource,
                continuationIntent: continuationIntent,
                resultLimit: resultLimit,
                resultOffset: resultOffset,
                sort: sort,
                expenseScope: expenseScope,
                incomeState: incomeState,
                whatIfAmount: whatIfAmount,
                categoryAvailabilityFilter: categoryAvailabilityFilter,
                shape: shape,
                unsupportedReason: unsupportedReason
            )
        )
    }

    private func request(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        projection: MarinaSemanticProjection = .records,
        dimensions: [MarinaSemanticDimension] = [],
        constraints: [MarinaSemanticConstraint] = [],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod,
        dateRangeSource: MarinaSemanticDateRangeSource = .defaulted,
        targetName: String? = nil,
        comparisonTargetName: String? = nil,
        textQuery: String? = nil,
        targetKindSource: MarinaSemanticTargetKindSource = .unspecified,
        comparisonTargetKindSource: MarinaSemanticTargetKindSource = .unspecified,
        continuationIntent: MarinaSemanticContinuationIntent = .none,
        resultLimit: Int? = nil,
        resultOffset: Int? = nil,
        sort: MarinaSemanticSort? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        incomeState: MarinaSemanticIncomeState? = nil,
        whatIfAmount: Double? = nil,
        categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
        shape: MarinaSemanticAnswerShape,
        unsupportedReason: MarinaSemanticUnsupportedReason? = nil
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            projection: projection,
            dimensions: dimensions,
            constraints: constraints,
            dateRangeToken: dateRangeToken,
            dateRangeSource: dateRangeSource,
            targetName: targetName,
            comparisonTargetName: comparisonTargetName,
            textQuery: textQuery,
            targetKindSource: targetKindSource,
            comparisonTargetKindSource: comparisonTargetKindSource,
            continuationIntent: continuationIntent,
            resultLimit: resultLimit,
            resultOffset: resultOffset,
            sort: sort,
            expenseScope: expenseScope,
            incomeState: incomeState,
            whatIfAmount: whatIfAmount,
            categoryAvailabilityFilter: categoryAvailabilityFilter,
            expectedAnswerShape: shape,
            unsupportedReason: unsupportedReason
        )
    }

    private func compile(
        _ outcome: Generated,
        conversationContext: MarinaConversationContext = .empty
    ) throws -> MarinaSemanticRequest {
        try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: outcome,
            turn: MarinaSemanticCompilerTurnV3(
                userInput: "mapping fixture",
                conversationContext: conversationContext
            )
        ).request
    }

    private func categoryCount(selection: Generated.Selection) -> Generated {
        .query(.category(.init(action: .count(.init(selection: selection)))))
    }

    private func selection(
        boundary: Generated.DataBoundary = .activeWorkspace,
        target: Generated.NamedTarget? = nil,
        filters: [Generated.NamedFilter] = [],
        date: Generated.DateSelection = .defaultCurrentPeriod
    ) -> Generated.Selection {
        Generated.Selection(
            dataBoundary: boundary,
            target: target,
            namedFilters: filters,
            dateSelection: date
        )
    }

    private func comparisonSelection(
        selection: Generated.Selection,
        kind: Generated.TargetKind
    ) -> Generated.ComparisonSelection {
        Generated.ComparisonSelection(
            selection: selection,
            comparisonTarget: .init(
                wording: "Comparison",
                classification: .explicit(kind)
            )
        )
    }

    private func listModifiers(
        sort: Generated.Sort? = nil,
        resultLimit: Int? = nil,
        continuation: Generated.Continuation = .none
    ) -> Generated.ListModifiers {
        .init(sort: sort, resultLimit: resultLimit, continuation: continuation)
    }

    private func groupModifiers(
        dimension: Generated.GroupDimension,
        sort: Generated.Sort? = nil,
        resultLimit: Int? = nil,
        continuation: Generated.Continuation = .none
    ) -> Generated.GroupModifiers {
        .init(
            dimension: dimension,
            sort: sort,
            resultLimit: resultLimit,
            continuation: continuation
        )
    }

    private func priorConversationContext(nextOffset: Int?) -> MarinaConversationContext {
        let prior = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            resultLimit: 5,
            expectedAnswerShape: .list
        )
        let semanticContext = MarinaAnswerSemanticContext(
            request: prior,
            dateRange: nil,
            comparisonDateRange: nil,
            answerKind: .list,
            answerTitle: "Expenses",
            answerSubtitle: nil,
            primaryValue: nil,
            rowReferences: [],
            displayedRowCount: 5,
            totalRowCount: 8,
            hasMore: nextOffset != nil,
            nextOffset: nextOffset
        )
        return MarinaConversationContext(recentTurns: [
            MarinaConversationTurn(
                userPrompt: "Show expenses",
                title: "Expenses",
                kind: .list,
                subtitle: nil,
                primaryValue: nil,
                rowTitles: [],
                semanticContext: semanticContext,
                recommendedFollowUp: nil
            )
        ])
    }
}
#endif
