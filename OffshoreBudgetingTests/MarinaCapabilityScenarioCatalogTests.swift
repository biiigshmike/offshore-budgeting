import Foundation
import Testing
@testable import Offshore

struct MarinaCapabilityScenarioCatalogTests {
    @Test func catalog_coversAllSwiftDataModelsAndCoreDerivedConcepts() {
        let requiredModels: Set<String> = [
            "Workspace",
            "Budget",
            "BudgetCategoryLimit",
            "Card",
            "BudgetCardLink",
            "BudgetPresetLink",
            "Category",
            "Preset",
            "PlannedExpense",
            "VariableExpense",
            "AllocationAccount",
            "ExpenseAllocation",
            "AllocationSettlement",
            "SavingsAccount",
            "SavingsLedgerEntry",
            "ImportMerchantRule",
            "AssistantAliasRule",
            "IncomeSeries",
            "Income"
        ]
        let actualModels = Set(
            MarinaCapabilityScenarioCatalog.modelScenarios.map(\.coverageTarget)
        )

        #expect(actualModels == requiredModels)
        #expect(MarinaCapabilityScenarioCatalog.modelScenarios.count == 19)

        let requiredDerived: Set<String> = [
            "merchant",
            "income-source",
            "uncategorized",
            "effective-planned-amount",
            "actual-savings",
            "budget-impact",
            "ledger-signed",
            "reconciliation-balance"
        ]
        let actualDerived = Set(
            MarinaCapabilityScenarioCatalog.derivedConceptScenarios.map(\.coverageTarget)
        )

        #expect(requiredDerived.isSubset(of: actualDerived))
    }

    @Test func catalog_declaresComputationFamiliesWithEvidenceAndShapes() {
        let requiredFamilies: Set<String> = [
            "totals",
            "averages",
            "counts",
            "rankings",
            "comparisons",
            "grouped-breakdowns",
            "recent-rows",
            "active-budget",
            "category-limits",
            "linked-cards",
            "linked-presets",
            "membership",
            "savings-status",
            "savings-activity",
            "reconciliation-balances",
            "allocation-rows",
            "settlement-rows",
            "planned-vs-actual-income",
            "safe-spend",
            "budget-forecast-what-if"
        ]
        let actualFamilies = Set(
            MarinaCapabilityScenarioCatalog.computationScenarios.map(\.coverageTarget)
        )

        #expect(requiredFamilies.isSubset(of: actualFamilies))

        for scenario in MarinaCapabilityScenarioCatalog.allScenarios where scenario.intentionallyUnsupported == false {
            #expect(scenario.expectedRoute.isEmpty == false)
            #expect(scenario.expectedResponseShape.isEmpty == false)
            #expect(scenario.requiredEvidenceRowType.isEmpty == false)
        }
    }
}
