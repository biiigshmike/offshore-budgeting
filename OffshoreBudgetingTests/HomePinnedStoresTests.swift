//
//  HomePinnedStoresTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 1/31/26.
//

import Foundation
import Testing
@testable import Offshore

struct HomePinnedStoresTests {

    // MARK: - Helpers

    private func pinnedItemsKey(workspaceID: UUID) -> String {
        "home_pinnedItems_\(workspaceID.uuidString)"
    }

    private func pinnedCardsKey(workspaceID: UUID) -> String {
        "home_pinnedCardIDs_\(workspaceID.uuidString)"
    }

    private func clearKeys(workspaceID: UUID) {
        UserDefaults.standard.removeObject(forKey: pinnedItemsKey(workspaceID: workspaceID))
        UserDefaults.standard.removeObject(forKey: pinnedCardsKey(workspaceID: workspaceID))
    }

    // MARK: - Tests

    @Test func pinnedItems_removePinnedCard_removesOnlyThatCard() throws {
        let workspaceID = UUID()
        clearKeys(workspaceID: workspaceID)
        defer { clearKeys(workspaceID: workspaceID) }

        let cardID1 = UUID()
        let cardID2 = UUID()

        let store = HomePinnedItemsStore(workspaceID: workspaceID)
        store.save([
            .widget(.income, .small),
            .card(cardID1, .small),
            .card(cardID2, .wide)
        ])

        store.removePinnedCard(id: cardID1)

        let loaded = store.load()
        #expect(loaded.contains(.widget(.income, .small)))
        #expect(loaded.contains(.card(cardID2, .wide)))
        #expect(loaded.contains(.card(cardID1, .small)) == false)
    }

    @Test func pinnedCards_removePinnedCardID_removesThatID() throws {
        let workspaceID = UUID()
        clearKeys(workspaceID: workspaceID)
        defer { clearKeys(workspaceID: workspaceID) }

        let id1 = UUID()
        let id2 = UUID()

        let store = HomePinnedCardsStore(workspaceID: workspaceID)
        store.save([id1, id2])

        store.removePinnedCardID(id1)

        #expect(store.load() == [id2])
    }
}

