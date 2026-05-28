//
//  WhatIfScenarioStoreTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 3/2/26.
//

import Foundation
import Testing
@testable import Offshore

struct WhatIfScenarioStoreTests {

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suiteName = "WhatIfScenarioStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create test UserDefaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Tests

    @Test func globalScenario_roundTrip_persistsIncomeOverrides() {
        let store = WhatIfScenarioStore(workspaceID: UUID())
        let categoryID = UUID()

        let created = store.createGlobalScenario(
            name: "Scenario A",
            overrides: .init(
                overridesByCategoryID: [
                    categoryID: .init(min: 120, max: 180, scenarioSpend: 150)
                ],
                plannedIncomeOverride: 4200,
                actualIncomeOverride: 3900
            )
        )

        let loaded = store.loadGlobalScenario(scenarioID: created.id)

        #expect(loaded?.plannedIncomeOverride == 4200)
        #expect(loaded?.actualIncomeOverride == 3900)
        #expect(loaded?.overridesByCategoryID[categoryID]?.min == 120)
        #expect(loaded?.overridesByCategoryID[categoryID]?.max == 180)
        #expect(loaded?.overridesByCategoryID[categoryID]?.scenarioSpend == 150)
    }

    @Test func globalScenario_save_sanitizesIncomeAndCategoryBounds() {
        let store = WhatIfScenarioStore(workspaceID: UUID())
        let categoryID = UUID()

        let created = store.createGlobalScenario(name: "Scenario B")
        store.saveGlobalScenario(
            .init(
                overridesByCategoryID: [
                    categoryID: .init(min: -100, max: -50, scenarioSpend: -20)
                ],
                plannedIncomeOverride: -12,
                actualIncomeOverride: -1
            ),
            scenarioID: created.id
        )

        let loaded = store.loadGlobalScenario(scenarioID: created.id)

        #expect(loaded?.plannedIncomeOverride == 0)
        #expect(loaded?.actualIncomeOverride == 0)
        #expect(loaded?.overridesByCategoryID[categoryID]?.min == 0)
        #expect(loaded?.overridesByCategoryID[categoryID]?.max == 0)
        #expect(loaded?.overridesByCategoryID[categoryID]?.scenarioSpend == 0)
    }

    @Test func globalScenario_duplicate_copiesIncomeOverrides() {
        let store = WhatIfScenarioStore(workspaceID: UUID())
        let categoryID = UUID()

        let created = store.createGlobalScenario(
            name: "Base",
            overrides: .init(
                overridesByCategoryID: [
                    categoryID: .init(min: 50, max: 75, scenarioSpend: 60)
                ],
                plannedIncomeOverride: 2500,
                actualIncomeOverride: 1800
            )
        )

        let duplicate = store.duplicateGlobalScenario(scenarioID: created.id, newName: "Base Copy")

        #expect(duplicate != nil)

        if let duplicateID = duplicate?.id {
            let loaded = store.loadGlobalScenario(scenarioID: duplicateID)
            #expect(loaded?.plannedIncomeOverride == 2500)
            #expect(loaded?.actualIncomeOverride == 1800)
            #expect(loaded?.overridesByCategoryID[categoryID]?.min == 50)
            #expect(loaded?.overridesByCategoryID[categoryID]?.max == 75)
            #expect(loaded?.overridesByCategoryID[categoryID]?.scenarioSpend == 60)
        }
    }

    @Test func globalScenario_syncSnapshot_roundTripsSelectionPinsAndOverrides() {
        let sourceDefaults = makeDefaults()
        let destinationDefaults = makeDefaults()
        let sourceWorkspaceID = UUID()
        let destinationWorkspaceID = UUID()
        let categoryID = UUID()
        let sourceStore = WhatIfScenarioStore(
            workspaceID: sourceWorkspaceID,
            defaults: sourceDefaults,
            syncOnMutation: false
        )
        let destinationStore = WhatIfScenarioStore(
            workspaceID: destinationWorkspaceID,
            defaults: destinationDefaults,
            syncOnMutation: false
        )

        let created = sourceStore.createGlobalScenario(
            name: "Cross-device Plan",
            overrides: .init(
                overridesByCategoryID: [
                    categoryID: .init(min: 75, max: 125, scenarioSpend: 90)
                ],
                plannedIncomeOverride: 5_000,
                actualIncomeOverride: 4_500
            )
        )
        sourceStore.setPinnedGlobalScenarioIDs([created.id])
        sourceStore.setSelectedGlobalScenarioID(created.id)

        let snapshot = sourceStore.exportGlobalSyncSnapshot()
        destinationStore.importGlobalSyncSnapshot(snapshot)

        #expect(destinationStore.loadSelectedGlobalScenarioID() == created.id)
        #expect(destinationStore.loadPinnedGlobalScenarioIDs() == [created.id])
        #expect(destinationStore.listGlobalScenarios().map(\.id).contains(created.id))

        let loaded = destinationStore.loadGlobalScenario(scenarioID: created.id, touchAccessTime: false)
        #expect(loaded?.plannedIncomeOverride == 5_000)
        #expect(loaded?.actualIncomeOverride == 4_500)
        #expect(loaded?.overridesByCategoryID[categoryID]?.min == 75)
        #expect(loaded?.overridesByCategoryID[categoryID]?.max == 125)
        #expect(loaded?.overridesByCategoryID[categoryID]?.scenarioSpend == 90)
    }

    @Test func plannerDraft_overrides_keepExplicitScenarioSpendOutsideRange() {
        let categoryID = UUID()
        let baseline: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [
            categoryID: .init(min: 100, max: 300, scenarioSpend: 180)
        ]
        let edited: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [
            categoryID: .init(min: 125, max: 150, scenarioSpend: 260)
        ]

        let overrides = WhatIfScenarioPlannerDraft.overridesByCategoryID(
            scenarioBoundsByCategoryID: edited,
            baselineBoundsByCategoryID: baseline
        )

        #expect(overrides[categoryID]?.min == 125)
        #expect(overrides[categoryID]?.max == 150)
        #expect(overrides[categoryID]?.scenarioSpend == 260)
    }

    @Test func plannerDraft_uiBounds_leaveScenarioBlankWhenNoOverrideExists() {
        let categoryID = UUID()
        let baseline: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [
            categoryID: .init(min: 100, max: 300, scenarioSpend: 180)
        ]

        let uiBounds = WhatIfScenarioPlannerDraft.uiBoundsByCategoryID(
            overrides: [:],
            baselineBoundsByCategoryID: baseline,
            categories: [categoryID]
        )

        #expect(uiBounds[categoryID]?.min == 100)
        #expect(uiBounds[categoryID]?.max == 300)
        #expect(uiBounds[categoryID]?.scenarioSpend == nil)
    }

    @Test func plannerDraft_overrides_dropBaselineMatchedCategory() {
        let categoryID = UUID()
        let baselineBounds = WhatIfScenarioStore.WhatIfCategoryBounds(min: 80, max: 120, scenarioSpend: 100)
        let baseline: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [
            categoryID: baselineBounds
        ]
        let edited: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [
            categoryID: baselineBounds
        ]

        let overrides = WhatIfScenarioPlannerDraft.overridesByCategoryID(
            scenarioBoundsByCategoryID: edited,
            baselineBoundsByCategoryID: baseline
        )

        #expect(overrides.isEmpty)
    }

    @Test func plannerDraft_overrides_keepMinMaxOverrideWhenScenarioIsBlank() {
        let categoryID = UUID()
        let baseline: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [
            categoryID: .init(min: 80, max: 120, scenarioSpend: 100)
        ]
        let edited: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [
            categoryID: .init(min: 90, max: 140, scenarioSpend: nil)
        ]

        let overrides = WhatIfScenarioPlannerDraft.overridesByCategoryID(
            scenarioBoundsByCategoryID: edited,
            baselineBoundsByCategoryID: baseline
        )

        #expect(overrides[categoryID]?.min == 90)
        #expect(overrides[categoryID]?.max == 140)
        #expect(overrides[categoryID]?.scenarioSpend == nil)
    }

    @Test func plannerDraft_incomeOverride_onlyPersistsWhenDifferentFromBaseline() {
        #expect(WhatIfScenarioPlannerDraft.incomeOverrideValue(scenarioValue: 4200, baselineValue: 4000) == 4200)
        #expect(WhatIfScenarioPlannerDraft.incomeOverrideValue(scenarioValue: 4000, baselineValue: 4000) == nil)
        #expect(WhatIfScenarioPlannerDraft.incomeOverrideValue(scenarioValue: nil, baselineValue: 4000) == nil)
    }

    @Test func plannerDraft_effectiveFallbacks_useBaselineWhenInputsAreBlank() {
        let categoryID = UUID()
        let baseline: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [
            categoryID: .init(min: 100, max: 300, scenarioSpend: 180)
        ]
        let edited: [UUID: WhatIfScenarioStore.WhatIfCategoryBounds] = [
            categoryID: .init(min: 100, max: 300, scenarioSpend: nil)
        ]

        #expect(
            WhatIfScenarioPlannerDraft.effectiveScenarioSpend(
                categoryID: categoryID,
                scenarioBoundsByCategoryID: edited,
                baselineBoundsByCategoryID: baseline
            ) == 180
        )
        #expect(WhatIfScenarioPlannerDraft.effectiveIncomeTotal(scenarioValue: nil, baselineValue: 4000) == 4000)
    }
}
