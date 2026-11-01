import Foundation
import Testing
@testable import Offshore

@MainActor
struct CategoryGoalAutoConfigurationDraftTests {
    private let categoryID = UUID()

    private var suggestion: CategoryGoalSuggestion {
        CategoryGoalSuggestion(averageAmount: 200, cushionPercent: 10, samples: [])
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
