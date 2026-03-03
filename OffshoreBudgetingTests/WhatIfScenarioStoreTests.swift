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
}
