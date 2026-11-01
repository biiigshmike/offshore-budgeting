import Foundation
import SwiftData

@MainActor
enum WorkspaceProgressService {
    static func completedSteps(in workspace: Workspace) -> Set<WorkspaceProgressStep> {
        Set(WorkspaceProgressStep.allCases.filter { workspace[keyPath: $0.milestoneKeyPath] })
    }

    static func percentage(in workspace: Workspace) -> Int {
        completedSteps(in: workspace).count * 20
    }

    static func canHideProgress(in workspace: Workspace) -> Bool {
        completedSteps(in: workspace).count == WorkspaceProgressStep.allCases.count
    }

    static func settingsSymbol(in workspace: Workspace) -> String {
        switch percentage(in: workspace) {
        case 0: "gauge.with.dots.needle.0percent"
        case 20: "gauge.with.dots.needle.33percent"
        case 40: "gauge.with.dots.needle.50percent"
        case 60, 80: "gauge.with.dots.needle.67percent"
        default: "gauge.with.dots.needle.100percent"
        }
    }

    @discardableResult
    static func markCompleted(_ step: WorkspaceProgressStep, in workspace: Workspace) -> Bool {
        guard !workspace[keyPath: step.milestoneKeyPath] else { return false }
        workspace[keyPath: step.milestoneKeyPath] = true
        return true
    }

    /// Keep milestone updates in the record's save transaction. Failed attempts restore only
    /// their newly earned steps; unrelated context edits and prior progress remain intact.
    static func saveCompleting(
        _ steps: Set<WorkspaceProgressStep>,
        in workspace: Workspace,
        save: () throws -> Void
    ) rethrows {
        let newlyCompleted = steps.subtracting(completedSteps(in: workspace))
        for step in newlyCompleted { markCompleted(step, in: workspace) }
        do {
            try save()
        } catch {
            for step in newlyCompleted { workspace[keyPath: step.milestoneKeyPath] = false }
            throw error
        }
    }

    /// Existence checks include archived records and all dates because setup is historical.
    /// Callers explicitly provide a workspace; nothing is inferred from another workspace.
    static func inferredSteps(
        in workspace: Workspace,
        modelContext: ModelContext,
        includesPendingChanges: Bool = true
    ) throws -> Set<WorkspaceProgressStep> {
        let workspaceID = workspace.id
        var steps = Set<WorkspaceProgressStep>()
        if try exists(Card.self, predicate: #Predicate { $0.workspace?.id == workspaceID }, in: modelContext, includesPendingChanges: includesPendingChanges) { steps.insert(.card) }
        if try exists(Category.self, predicate: #Predicate { $0.workspace?.id == workspaceID }, in: modelContext, includesPendingChanges: includesPendingChanges) { steps.insert(.category) }
        if try exists(Preset.self, predicate: #Predicate { $0.workspace?.id == workspaceID }, in: modelContext, includesPendingChanges: includesPendingChanges) { steps.insert(.preset) }
        if try exists(Income.self, predicate: #Predicate { $0.workspace?.id == workspaceID }, in: modelContext, includesPendingChanges: includesPendingChanges) { steps.insert(.income) }
        if try exists(Budget.self, predicate: #Predicate { $0.workspace?.id == workspaceID }, in: modelContext, includesPendingChanges: includesPendingChanges) { steps.insert(.budget) }
        return steps
    }

    static func backfill(in workspace: Workspace, modelContext: ModelContext) throws {
        let completed = completedSteps(in: workspace)
        guard completed.count < WorkspaceProgressStep.allCases.count else { return }
        // Failed or uncommitted form attempts must not be credited by a refresh.
        let newSteps = try inferredSteps(in: workspace, modelContext: modelContext, includesPendingChanges: false)
            .subtracting(completed)
        guard !newSteps.isEmpty else { return }
        try saveCompleting(newSteps, in: workspace) { try modelContext.save() }
    }

    private static func exists<T: PersistentModel>(
        _ type: T.Type,
        predicate: Predicate<T>,
        in context: ModelContext,
        includesPendingChanges: Bool
    ) throws -> Bool {
        var descriptor = FetchDescriptor<T>(predicate: predicate)
        descriptor.fetchLimit = 1
        descriptor.includePendingChanges = includesPendingChanges
        return try !context.fetch(descriptor).isEmpty
    }
}
