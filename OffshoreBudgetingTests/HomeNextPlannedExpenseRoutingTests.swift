import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeNextPlannedExpenseRoutingTests {
    @Test func resolvesActiveAndArchivedPresetsByID() {
        let workspace = makeWorkspace()
        let active = Preset(title: "Rent", plannedAmount: 100, workspace: workspace)
        let archived = Preset(title: "Rent", plannedAmount: 200, workspace: workspace, isArchived: true)
        let expense = makeExpense(workspace: workspace, presetID: archived.id)

        #expect(resolve(workspace, expense, [active, archived]) === archived)
        expense.sourcePresetID = active.id
        #expect(resolve(workspace, expense, [archived, active]) === active)
    }

    @Test func missingOrNilSourceUsesFallbackInsteadOfMatchingTitle() {
        let workspace = makeWorkspace()
        let preset = Preset(title: "Rent", plannedAmount: 100, workspace: workspace)
        let expense = makeExpense(workspace: workspace, presetID: nil)

        #expect(resolve(workspace, expense, [preset]) == nil)
        expense.sourcePresetID = UUID()
        #expect(resolve(workspace, expense, [preset]) == nil)
        expense.sourcePresetID = preset.id
        #expect(resolve(workspace, expense, []) == nil)
    }

    @Test func rejectsExpenseFromAnotherWorkspaceOrWithoutWorkspace() {
        let workspace = makeWorkspace()
        let other = makeWorkspace()
        let preset = Preset(title: "Rent", plannedAmount: 100, workspace: workspace)
        let expense = makeExpense(workspace: other, presetID: preset.id)

        #expect(resolve(workspace, expense, [preset]) == nil)
        expense.workspace = nil
        #expect(resolve(workspace, expense, [preset]) == nil)
    }

    @Test func rejectsSourcePresetFromAnotherWorkspaceOrWithoutWorkspace() {
        let workspace = makeWorkspace()
        let other = makeWorkspace()
        let preset = Preset(title: "Rent", plannedAmount: 100, workspace: other)
        let expense = makeExpense(workspace: workspace, presetID: preset.id)

        #expect(resolve(workspace, expense, [preset]) == nil)
        preset.workspace = nil
        #expect(resolve(workspace, expense, [preset]) == nil)
    }

    @Test func matchingForeignIDDoesNotShadowWorkspacePreset() {
        let workspace = makeWorkspace()
        let other = makeWorkspace()
        let id = UUID()
        let foreign = Preset(id: id, title: "Foreign", plannedAmount: 100, workspace: other)
        let local = Preset(id: id, title: "Local", plannedAmount: 100, workspace: workspace)
        let expense = makeExpense(workspace: workspace, presetID: id)

        #expect(resolve(workspace, expense, [foreign, local]) === local)
    }

    private func resolve(_ workspace: Workspace, _ expense: PlannedExpense, _ presets: [Preset]) -> Preset? {
        HomeNextPlannedExpenseTile.resolveSourcePreset(workspaceID: workspace.id, expense: expense, presets: presets)
    }

    private func makeWorkspace() -> Workspace {
        Workspace(name: "Workspace", hexColor: "#123456")
    }

    private func makeExpense(workspace: Workspace, presetID: UUID?) -> PlannedExpense {
        PlannedExpense(title: "Rent", plannedAmount: 100, expenseDate: .now,
                       workspace: workspace, sourcePresetID: presetID)
    }
}
