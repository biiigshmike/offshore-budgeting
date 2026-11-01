import Foundation
import Testing
@testable import Offshore

@MainActor
struct CategoryGoalAutoConfigurationDraftTests {
    private let categoryID = UUID()

    private var suggestion: CategoryGoalSuggestion {
        CategoryGoalSuggestion(averageAmount: 200, cushionPercent: 10, samples: [])
    }

    @Test func regeneratingExistingGoalsRestoresSnapshotAndPreservesSubsequentEdits() {
        var drafts = [categoryID: CategoryGoalDraft(minimum: 900, maximum: 1000)]
        let original = drafts
        var configuration = CategoryGoalAutoConfigurationDraft()
        configuration.apply(to: &drafts, categoryIDs: [categoryID],
                            plannedContributions: [categoryID: 100], suggestions: [categoryID: suggestion],
                            replacesExistingGoals: true)
        #expect(drafts[categoryID]?.minimum == 100)
        #expect(drafts[categoryID]?.maximum == 220)
        configuration.restore(in: &drafts)
        #expect(drafts == original)
        configuration.apply(to: &drafts, categoryIDs: [categoryID],
                            plannedContributions: [categoryID: 100], suggestions: [categoryID: suggestion],
                            replacesExistingGoals: true)
        drafts[categoryID]?.maximumText = "300"
        configuration.restore(in: &drafts)
        #expect(drafts[categoryID]?.minimum == 900)
        #expect(drafts[categoryID]?.maximum == 300)
    }

    @Test func regenerationWithoutEvidencePreservesExistingGoals() {
        var drafts = [categoryID: CategoryGoalDraft(minimum: 900, maximum: 1000)]
        let original = drafts
        var configuration = CategoryGoalAutoConfigurationDraft()
        configuration.apply(to: &drafts, categoryIDs: [categoryID], plannedContributions: [:],
                            suggestions: [:], replacesExistingGoals: true)
        #expect(drafts == original)
    }

    @Test(arguments: [0.0, 75])
    func fillsBlankMinimumFromLowestHistoryIncludingZero(lowest: Double) {
        let history = CategoryGoalSuggestion(averageAmount: 100, cushionPercent: 10, samples: [
            CategoryGoalHistorySample(budgetID: UUID(), name: "Low", startDate: .now, endDate: .now, amount: lowest),
            CategoryGoalHistorySample(budgetID: UUID(), name: "High", startDate: .now, endDate: .now, amount: 200)
        ])
        var drafts: [UUID: CategoryGoalDraft] = [:]
        var configuration = CategoryGoalAutoConfigurationDraft()
        configuration.apply(to: &drafts, categoryIDs: [categoryID], plannedContributions: [:], suggestions: [categoryID: history])
        #expect(drafts[categoryID]?.minimum == lowest)
        #expect(drafts[categoryID]?.isValid == true)
        configuration.restore(in: &drafts)
        #expect(drafts[categoryID]?.minimum == nil)
        #expect(drafts[categoryID]?.maximum == nil)

        drafts = [categoryID: CategoryGoalDraft(minimum: 25, maximum: nil)]
        configuration.apply(to: &drafts, categoryIDs: [categoryID], plannedContributions: [:], suggestions: [categoryID: history])
        #expect(drafts[categoryID]?.minimum == 25)
        configuration.restore(in: &drafts)
        drafts = [:]
        configuration.apply(to: &drafts, categoryIDs: [categoryID], plannedContributions: [categoryID: 50], suggestions: [categoryID: history])
        #expect(drafts[categoryID]?.minimum == 50)
        configuration.restore(in: &drafts)
        drafts = [categoryID: CategoryGoalDraft(minimum: nil, maximum: 50)]
        configuration.apply(to: &drafts, categoryIDs: [categoryID], plannedContributions: [:], suggestions: [categoryID: history])
        #expect(drafts[categoryID]?.minimum == (lowest <= 50 ? lowest : nil))
        #expect(drafts[categoryID]?.maximum == 50)
        #expect(drafts[categoryID]?.isValid == true)
    }

    @Test func generatesBothFieldsAndRestoresPreviousValues() {
        var drafts = [categoryID: CategoryGoalDraft(minimum: 25, maximum: nil)]
        let original = drafts
        var configuration = CategoryGoalAutoConfigurationDraft()
        configuration.apply(to: &drafts, categoryIDs: [categoryID],
                            plannedContributions: [categoryID: 100], suggestions: [categoryID: suggestion])
        #expect(drafts[categoryID]?.minimum == 100)
        #expect(drafts[categoryID]?.maximum == 220)
        configuration.restore(in: &drafts)
        #expect(drafts == original)
    }

    @Test func fillsOnlyBlankMaximumsAndFloorsAtOriginalEnteredMinimum() {
        var drafts = [categoryID: CategoryGoalDraft(minimum: 500, maximum: nil)]
        var configuration = CategoryGoalAutoConfigurationDraft()
        configuration.apply(to: &drafts, categoryIDs: [categoryID],
                            plannedContributions: [categoryID: 100], suggestions: [categoryID: suggestion])
        #expect(drafts[categoryID]?.maximum == 500)
        configuration.restore(in: &drafts)
        drafts[categoryID]?.maximumText = "750"
        configuration.apply(to: &drafts, categoryIDs: [categoryID],
                            plannedContributions: [categoryID: 100], suggestions: [categoryID: suggestion])
        #expect(drafts[categoryID]?.maximumText == "750")
    }

    @Test func restoringEachFieldPreservesManualEditsIndependently() {
        var drafts: [UUID: CategoryGoalDraft] = [:]
        var configuration = CategoryGoalAutoConfigurationDraft()
        configuration.apply(to: &drafts, categoryIDs: [categoryID],
                            plannedContributions: [categoryID: 100], suggestions: [categoryID: suggestion])
        drafts[categoryID]?.maximumText = "300"
        configuration.restore(in: &drafts)
        #expect(drafts[categoryID]?.minimum == nil)
        #expect(drafts[categoryID]?.maximumText == "300")

        drafts = [:]
        configuration.apply(to: &drafts, categoryIDs: [categoryID],
                            plannedContributions: [categoryID: 100], suggestions: [categoryID: suggestion])
        drafts[categoryID]?.minimumText = "50"
        configuration.restore(in: &drafts)
        #expect(drafts[categoryID]?.minimumText == "50")
        #expect(drafts[categoryID]?.maximum == nil)
    }

    @Test func noHistoryOrDisabledMaximumsPreservesMinimumOnlyBehavior() {
        var drafts: [UUID: CategoryGoalDraft] = [:]
        var configuration = CategoryGoalAutoConfigurationDraft()
        configuration.apply(to: &drafts, categoryIDs: [categoryID],
                            plannedContributions: [categoryID: 100], suggestions: [:])
        #expect(drafts[categoryID]?.minimum == 100)
        #expect(drafts[categoryID]?.maximum == nil)
        #expect(drafts[categoryID]?.isValid == true)
    }

    @Test func toggleCyclesUseFreshSuggestionsAndNeverChangeParentDrafts() {
        let parent = [categoryID: CategoryGoalDraft()]
        var local = parent
        var configuration = CategoryGoalAutoConfigurationDraft()
        configuration.apply(to: &local, categoryIDs: [categoryID],
                            plannedContributions: [:], suggestions: [categoryID: suggestion])
        #expect(parent[categoryID]?.maximum == nil)
        configuration.restore(in: &local)
        let newer = CategoryGoalSuggestion(averageAmount: 400, cushionPercent: 0, samples: [])
        configuration.apply(to: &local, categoryIDs: [categoryID],
                            plannedContributions: [:], suggestions: [categoryID: newer])
        #expect(local[categoryID]?.maximum == 400)
        #expect(parent[categoryID]?.maximum == nil)
    }
}
