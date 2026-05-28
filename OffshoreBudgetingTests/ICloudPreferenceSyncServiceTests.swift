//
//  ICloudPreferenceSyncServiceTests.swift
//  OffshoreBudgetingTests
//
//  Created by Codex on 5/28/26.
//

import Foundation
import Testing
@testable import Offshore

struct ICloudPreferenceSyncServiceTests {
    private final class FakeICloudKeyValueStore: ICloudKeyValueStoring {
        var storage: [String: Data] = [:]
        var synchronizeCount: Int = 0

        func data(forKey aKey: String) -> Data? {
            storage[aKey]
        }

        func set(_ anObject: Any?, forKey aKey: String) {
            storage[aKey] = anObject as? Data
        }

        func synchronize() -> Bool {
            synchronizeCount += 1
            return true
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ICloudPreferenceSyncServiceTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create test UserDefaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(true, forKey: ICloudPreferenceSyncService.activeICloudKey)
        return defaults
    }

    @Test func homeLayoutEnvelope_roundTripsThroughJSON() throws {
        let workspaceID = UUID()
        let cardID = UUID()
        let envelope = HomeLayoutSyncEnvelope(
            schemaVersion: 1,
            workspaceID: workspaceID,
            updatedAt: 123,
            deviceID: "device-a",
            pinnedItems: [
                .widget(.income, .wide),
                .card(cardID, .small)
            ]
        )

        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(HomeLayoutSyncEnvelope.self, from: data)

        #expect(decoded == envelope)
    }

    @Test func homeLayout_enable_appliesNewerRemoteSnapshot() throws {
        let defaults = makeDefaults()
        let kvs = FakeICloudKeyValueStore()
        let workspaceID = UUID()
        let localStore = HomePinnedItemsStore(workspaceID: workspaceID, defaults: defaults)
        localStore.save([.widget(.income, .small)])

        let remote = HomeLayoutSyncEnvelope(
            schemaVersion: 1,
            workspaceID: workspaceID,
            updatedAt: 200,
            deviceID: "remote",
            pinnedItems: [.widget(.whatIf, .wide)]
        )
        kvs.storage[ICloudPreferenceSyncService.homeLayoutKey(workspaceID: workspaceID)] =
            try JSONEncoder().encode(remote)

        let service = ICloudPreferenceSyncService(
            keyValueStore: kvs,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 100) },
            deviceIDProvider: { "local" }
        )

        let result = service.synchronizeHomeLayoutOnEnable(workspaceID: workspaceID)

        #expect(result == .appliedRemote)
        #expect(localStore.load() == [.widget(.whatIf, .wide)])
    }

    @Test func homeLayout_pullWithMatchingTimestamp_keepsLocalSnapshot() throws {
        let defaults = makeDefaults()
        let kvs = FakeICloudKeyValueStore()
        let workspaceID = UUID()
        let localStore = HomePinnedItemsStore(workspaceID: workspaceID, defaults: defaults)
        localStore.save([.widget(.income, .small)])
        defaults.set(true, forKey: ICloudPreferenceSyncService.homeLayoutSyncEnabledKey)

        let service = ICloudPreferenceSyncService(
            keyValueStore: kvs,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 100) },
            deviceIDProvider: { "local" }
        )
        service.pushHomeLayoutIfEnabled(workspaceID: workspaceID)

        let tiedRemote = HomeLayoutSyncEnvelope(
            schemaVersion: 1,
            workspaceID: workspaceID,
            updatedAt: 100,
            deviceID: "remote",
            pinnedItems: [.widget(.whatIf, .wide)]
        )
        kvs.storage[ICloudPreferenceSyncService.homeLayoutKey(workspaceID: workspaceID)] =
            try JSONEncoder().encode(tiedRemote)

        service.pullEnabledSnapshots(workspaceIDs: [workspaceID])

        #expect(localStore.load() == [.widget(.income, .small)])
    }

    @Test func whatIfScenarios_enable_appliesNewerRemoteSnapshot() throws {
        let defaults = makeDefaults()
        let kvs = FakeICloudKeyValueStore()
        let workspaceID = UUID()
        let categoryID = UUID()
        let scenarioID = UUID()
        let localStore = WhatIfScenarioStore(
            workspaceID: workspaceID,
            defaults: defaults,
            syncOnMutation: false
        )
        _ = localStore.createGlobalScenario(name: "Local")

        let scenarioInfo = WhatIfScenarioStore.GlobalScenarioInfo(
            id: scenarioID,
            name: "Remote",
            lastAccessed: 200,
            createdAt: 150
        )
        let payload = WhatIfGlobalScenariosSyncPayload(
            scenarios: [scenarioInfo],
            selectedScenarioID: scenarioID,
            pinnedScenarioIDs: [scenarioID],
            overridesByScenarioID: [
                scenarioID: .init(
                    overridesByCategoryID: [
                        categoryID: .init(min: 10, max: 20, scenarioSpend: 15)
                    ],
                    plannedIncomeOverride: 800,
                    actualIncomeOverride: 700
                )
            ]
        )
        let remote = WhatIfGlobalScenariosSyncEnvelope(
            schemaVersion: 1,
            workspaceID: workspaceID,
            updatedAt: 300,
            deviceID: "remote",
            payload: payload
        )
        kvs.storage[ICloudPreferenceSyncService.whatIfScenariosKey(workspaceID: workspaceID)] =
            try JSONEncoder().encode(remote)

        let service = ICloudPreferenceSyncService(
            keyValueStore: kvs,
            defaults: defaults,
            now: { Date(timeIntervalSince1970: 100) },
            deviceIDProvider: { "local" }
        )

        let result = service.synchronizeWhatIfScenariosOnEnable(workspaceID: workspaceID)

        #expect(result == .appliedRemote)
        #expect(localStore.loadSelectedGlobalScenarioID() == scenarioID)
        #expect(localStore.loadPinnedGlobalScenarioIDs() == [scenarioID])

        let loaded = localStore.loadGlobalScenario(scenarioID: scenarioID, touchAccessTime: false)
        #expect(loaded?.plannedIncomeOverride == 800)
        #expect(loaded?.actualIncomeOverride == 700)
        #expect(loaded?.overridesByCategoryID[categoryID]?.scenarioSpend == 15)
    }
}
