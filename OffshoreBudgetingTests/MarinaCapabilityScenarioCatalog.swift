import Foundation

struct MarinaCapabilityScenario: Codable, Equatable, Sendable {
    enum CoverageKind: String, Codable, Equatable, Sendable {
        case swiftDataModel
        case derivedConcept
        case computationFamily
    }

    let id: String
    let coverageKind: CoverageKind
    let coverageTarget: String
    let prompt: String
    let expectedRoute: String
    let expectedAmountBasis: String?
    let expectedResponseShape: String
    let requiredEvidenceRowType: String
    let intentionallyUnsupported: Bool
}

enum MarinaCapabilityScenarioCatalog {
    static let modelScenarios: [MarinaCapabilityScenario] = [
        model("workspace", "Workspace", "What workspace am I in?", route: "lookup", shape: "summaryCard", evidence: "Workspace"),
        model("budget", "Budget", "Show May Budget details", route: "lookup", shape: "summaryCard", evidence: "Budget"),
        model("budget-category-limit", "BudgetCategoryLimit", "Show my Groceries budget limit", route: "lookupDetails", amountBasis: "budgetImpact", shape: "relationshipList", evidence: "BudgetCategoryLimit"),
        model("card", "Card", "Show Apple Card details", route: "lookup", shape: "summaryCard", evidence: "Card"),
        model("budget-card-link", "BudgetCardLink", "Which cards are linked to May Budget?", route: "lookupDetails", shape: "relationshipList", evidence: "BudgetCardLink"),
        model("budget-preset-link", "BudgetPresetLink", "Which presets are linked to May Budget?", route: "lookupDetails", shape: "relationshipList", evidence: "BudgetPresetLink"),
        model("category", "Category", "Show Groceries category details", route: "lookup", shape: "summaryCard", evidence: "Category"),
        model("preset", "Preset", "Show Rent preset details", route: "lookup", amountBasis: "plannedEffective", shape: "summaryCard", evidence: "Preset"),
        model("planned-expense", "PlannedExpense", "Show upcoming planned expenses", route: "listRows", amountBasis: "plannedEffective", shape: "chartRows", evidence: "PlannedExpense"),
        model("variable-expense", "VariableExpense", "Show recent transactions", route: "listRows", amountBasis: "budgetImpact", shape: "chartRows", evidence: "VariableExpense"),
        model("allocation-account", "AllocationAccount", "Show Roommate balance", route: "lookupDetails", amountBasis: "reconciliationBalance", shape: "summaryCard", evidence: "AllocationAccount"),
        model("expense-allocation", "ExpenseAllocation", "Show Roommate allocation rows", route: "listRows", amountBasis: "allocated", shape: "chartRows", evidence: "ExpenseAllocation"),
        model("allocation-settlement", "AllocationSettlement", "Show Roommate settlement rows", route: "listRows", amountBasis: "reconciliationBalance", shape: "chartRows", evidence: "AllocationSettlement"),
        model("savings-account", "SavingsAccount", "Show my savings account status", route: "lookupDetails", amountBasis: "savingsMovement", shape: "summaryCard", evidence: "SavingsAccount"),
        model("savings-ledger-entry", "SavingsLedgerEntry", "Show savings activity", route: "listRows", amountBasis: "savingsMovement", shape: "chartRows", evidence: "SavingsLedgerEntry"),
        model("import-merchant-rule", "ImportMerchantRule", "Show merchant import rules for Starbucks", route: "lookup", shape: "summaryCard", evidence: "ImportMerchantRule"),
        model("assistant-alias-rule", "AssistantAliasRule", "Show Marina aliases for Apple", route: "lookup", shape: "summaryCard", evidence: "AssistantAliasRule"),
        model("income-series", "IncomeSeries", "Show Salary income schedule", route: "lookupDetails", amountBasis: "income", shape: "summaryCard", evidence: "IncomeSeries"),
        model("income", "Income", "What is my actual income this month?", route: "total", amountBasis: "gross", shape: "scalarCurrency", evidence: "Income")
    ]

    static let derivedConceptScenarios: [MarinaCapabilityScenario] = [
        derived("merchant", "What did I spend at Apple this month?", route: "total", amountBasis: "budgetImpact", shape: "scalarCurrency", evidence: "VariableExpense"),
        derived("income-source", "How much did Salary pay this month?", route: "total", amountBasis: "gross", shape: "scalarCurrency", evidence: "Income"),
        derived("uncategorized", "How much uncategorized spending do I have?", route: "total", amountBasis: "budgetImpact", shape: "scalarCurrency", evidence: "VariableExpense"),
        derived("effective-planned-amount", "What planned expenses are still effective this month?", route: "total", amountBasis: "plannedEffective", shape: "summaryCard", evidence: "PlannedExpense"),
        derived("actual-savings", "How much did I actually save this month?", route: "total", amountBasis: "savingsMovement", shape: "scalarCurrency", evidence: "SavingsLedgerEntry"),
        derived("budget-impact", "What is my budget impact this month?", route: "total", amountBasis: "budgetImpact", shape: "scalarCurrency", evidence: "VariableExpense"),
        derived("ledger-signed", "What is my Apple Card signed ledger total?", route: "total", amountBasis: "ledgerSigned", shape: "scalarCurrency", evidence: "VariableExpense"),
        derived("reconciliation-balance", "What is Roommate's balance?", route: "lookupDetails", amountBasis: "reconciliationBalance", shape: "summaryCard", evidence: "AllocationAccount")
    ]

    static let computationScenarios: [MarinaCapabilityScenario] = [
        computation("totals", "How much did I spend this month?", route: "total", amountBasis: "budgetImpact", shape: "scalarCurrency", evidence: "VariableExpense"),
        computation("averages", "What is my average grocery transaction?", route: "average", amountBasis: "budgetImpact", shape: "scalarCurrency", evidence: "VariableExpense"),
        computation("counts", "How many transactions did I make this month?", route: "count", shape: "summaryCard", evidence: "VariableExpense"),
        computation("rankings", "What are my top categories this month?", route: "rank", amountBasis: "budgetImpact", shape: "rankedList", evidence: "VariableExpense"),
        computation("comparisons", "Compare groceries to last month", route: "compare", amountBasis: "budgetImpact", shape: "comparison", evidence: "VariableExpense"),
        computation("grouped-breakdowns", "Break spending down by category", route: "group", amountBasis: "budgetImpact", shape: "groupedBreakdown", evidence: "VariableExpense"),
        computation("recent-rows", "Show recent transactions", route: "listRows", amountBasis: "budgetImpact", shape: "chartRows", evidence: "VariableExpense"),
        computation("active-budget", "What is my active budget?", route: "lookupDetails", shape: "summaryCard", evidence: "Budget"),
        computation("category-limits", "Show my Groceries budget limit", route: "lookupDetails", amountBasis: "budgetImpact", shape: "relationshipList", evidence: "BudgetCategoryLimit"),
        computation("linked-cards", "Which cards are linked to May Budget?", route: "lookupDetails", shape: "relationshipList", evidence: "BudgetCardLink"),
        computation("linked-presets", "Which presets are linked to May Budget?", route: "lookupDetails", shape: "relationshipList", evidence: "BudgetPresetLink"),
        computation("membership", "Is Apple Card linked to May Budget?", route: "lookupDetails", shape: "membershipStatus", evidence: "BudgetCardLink"),
        computation("savings-status", "Show savings status", route: "lookupDetails", amountBasis: "savingsMovement", shape: "summaryCard", evidence: "SavingsAccount"),
        computation("savings-activity", "Show savings activity", route: "listRows", amountBasis: "savingsMovement", shape: "chartRows", evidence: "SavingsLedgerEntry"),
        computation("reconciliation-balances", "Show reconciliation balances", route: "lookupDetails", amountBasis: "reconciliationBalance", shape: "summaryCard", evidence: "AllocationAccount"),
        computation("allocation-rows", "Show allocation rows", route: "listRows", amountBasis: "allocated", shape: "chartRows", evidence: "ExpenseAllocation"),
        computation("settlement-rows", "Show settlement rows", route: "listRows", amountBasis: "reconciliationBalance", shape: "chartRows", evidence: "AllocationSettlement"),
        computation("planned-vs-actual-income", "Compare planned vs actual income", route: "compare", amountBasis: "gross", shape: "comparison", evidence: "Income"),
        computation("safe-spend", "How much safe spend is left?", route: "total", amountBasis: "budgetImpact", shape: "scalarCurrency", evidence: "Budget"),
        computation("budget-forecast-what-if", "What if I spend 200 less on dining?", route: "scenario", amountBasis: "budgetImpact", shape: "summaryCard", evidence: "BudgetForecast")
    ]

    static var allScenarios: [MarinaCapabilityScenario] {
        modelScenarios + derivedConceptScenarios + computationScenarios
    }

    private static func model(
        _ id: String,
        _ target: String,
        _ prompt: String,
        route: String,
        amountBasis: String? = nil,
        shape: String,
        evidence: String
    ) -> MarinaCapabilityScenario {
        scenario(
            id: id,
            kind: .swiftDataModel,
            target: target,
            prompt: prompt,
            route: route,
            amountBasis: amountBasis,
            shape: shape,
            evidence: evidence
        )
    }

    private static func derived(
        _ target: String,
        _ prompt: String,
        route: String,
        amountBasis: String?,
        shape: String,
        evidence: String
    ) -> MarinaCapabilityScenario {
        scenario(
            id: target,
            kind: .derivedConcept,
            target: target,
            prompt: prompt,
            route: route,
            amountBasis: amountBasis,
            shape: shape,
            evidence: evidence
        )
    }

    private static func computation(
        _ target: String,
        _ prompt: String,
        route: String,
        amountBasis: String? = nil,
        shape: String,
        evidence: String
    ) -> MarinaCapabilityScenario {
        scenario(
            id: target,
            kind: .computationFamily,
            target: target,
            prompt: prompt,
            route: route,
            amountBasis: amountBasis,
            shape: shape,
            evidence: evidence
        )
    }

    private static func scenario(
        id: String,
        kind: MarinaCapabilityScenario.CoverageKind,
        target: String,
        prompt: String,
        route: String,
        amountBasis: String?,
        shape: String,
        evidence: String
    ) -> MarinaCapabilityScenario {
        MarinaCapabilityScenario(
            id: "\(kind.rawValue).\(id)",
            coverageKind: kind,
            coverageTarget: target,
            prompt: prompt,
            expectedRoute: route,
            expectedAmountBasis: amountBasis,
            expectedResponseShape: shape,
            requiredEvidenceRowType: evidence,
            intentionallyUnsupported: false
        )
    }
}
