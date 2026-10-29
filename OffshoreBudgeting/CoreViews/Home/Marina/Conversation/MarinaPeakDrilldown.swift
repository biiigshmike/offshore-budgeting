import Foundation
import SwiftData

/// A transient read from a workspace-bound chat, never an update to its saved answer.
struct MarinaPeakDrilldown: Identifiable {
    let id = UUID()
    let workspaceID: UUID
    let presentation: MarinaPresentation

    func request(for workspaceID: UUID) -> MarinaDataRequest? {
        guard self.workspaceID == workspaceID,
              presentation.pagination.map({ $0.workspaceID == workspaceID }) ?? true,
              presentation.identityKey.map({ $0.hasPrefix(workspaceID.uuidString + ":") }) ?? true,
              presentation.purpose == .spendingPatterns,
              let peak = presentation.report?.peak, let request = peak.drilldownRequest,
              request.tool == .expenses, request.operation == .transactions, request.purpose == nil,
              request.startDate == peak.startDate, request.endDate == peak.endDate,
              !request.allTime, request.relativePeriod == nil,
              request.comparisonFilter == nil, request.comparisonStartDate == nil,
              request.comparisonEndDate == nil, request.comparisonPeriod == nil, !request.comparisonAllTime,
              request.grouping == .none, request.periodUnit == nil else { return nil }
        return request
    }

    @MainActor
    func read(workspace: Workspace, modelContext: ModelContext, homeContext: MarinaPanelHomeContext?,
              defaultBudgetingPeriod: BudgetingPeriod, now: Date = .now) throws -> MarinaDataResult {
        guard let request = request(for: workspace.id) else {
            return .init(status: "invalidRequest", scope: workspace.name,
                         explanation: "This saved period cannot be opened in the current workspace. Please ask Marina for a new spending report.")
        }
        let policy = presentation.report?.policy
        let context = MarinaPanelHomeContext(dateRange: nil,
            excludeFuturePlannedExpensesFromCalculations: policy?.excludesFuturePlanned ?? homeContext?.excludeFuturePlannedExpensesFromCalculations ?? false,
            excludeFutureVariableExpensesFromCalculations: policy?.excludesFutureVariable ?? homeContext?.excludeFutureVariableExpensesFromCalculations ?? false)
        return try MarinaReadOnlyDataService(workspace: workspace, modelContext: modelContext,
            homeContext: context, now: now, defaultBudgetingPeriod: defaultBudgetingPeriod).execute(request)
    }
}
