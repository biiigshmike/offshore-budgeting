import Foundation

/// Workspace-scoped query results and controls used to prepare Home's dashboard.
struct HomeDashboardData {
    let workspaceID: UUID
    let budgets: [Budget]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date
    let excludeFuturePlannedExpenses: Bool
    let excludeFutureVariableExpenses: Bool

    struct Signature: Equatable {
        let workspaceID: UUID
        let startDate: Date
        let endDate: Date
        let excludeFuturePlannedExpenses: Bool
        let excludeFutureVariableExpenses: Bool
        let budgets: Int
        let plannedExpenses: Int
        let variableExpenses: Int
    }

    var signature: Signature {
        Signature(
            workspaceID: workspaceID, startDate: startDate, endDate: endDate,
            excludeFuturePlannedExpenses: excludeFuturePlannedExpenses,
            excludeFutureVariableExpenses: excludeFutureVariableExpenses,
            budgets: SnapshotContentSignature.budgets(budgets),
            plannedExpenses: SnapshotContentSignature.plannedExpenses(plannedExpenses),
            variableExpenses: SnapshotContentSignature.variableExpenses(variableExpenses)
        )
    }

    var cacheKey: String {
        let signature = signature
        return [
            "home-dashboard", workspaceID.uuidString,
            String(Int64(startDate.timeIntervalSince1970)), String(Int64(endDate.timeIntervalSince1970)),
            excludeFuturePlannedExpenses ? "1" : "0", excludeFutureVariableExpenses ? "1" : "0",
            String(signature.budgets), String(signature.plannedExpenses), String(signature.variableExpenses)
        ].joined(separator: "|")
    }
}
