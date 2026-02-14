//
//  HomePinnedStoresTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 1/31/26.
//

import Foundation
import SwiftUI
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

    @Test func layoutCapabilities_phoneNeverSupportsMultiColumn() throws {
        let supports = HomeLayoutCapabilities.supportsMultiColumnLayout(
            usableWidth: 900,
            isPhone: true,
            voiceOverEnabled: false,
            dynamicTypeSize: .large,
            gridSpacing: 12
        )

        #expect(supports == false)
    }

    @Test func layoutCapabilities_nonPhoneWideWidthSupportsMultiColumn() throws {
        let supports = HomeLayoutCapabilities.supportsMultiColumnLayout(
            usableWidth: 700,
            isPhone: false,
            voiceOverEnabled: false,
            dynamicTypeSize: .large,
            gridSpacing: 12
        )

        #expect(supports)
    }

    @Test func layoutCapabilities_nonPhoneNarrowWidthDoesNotSupportMultiColumn() throws {
        let supports = HomeLayoutCapabilities.supportsMultiColumnLayout(
            usableWidth: 500,
            isPhone: false,
            voiceOverEnabled: false,
            dynamicTypeSize: .large,
            gridSpacing: 12
        )

        #expect(supports == false)
    }

    @Test func layoutCapabilities_accessibilityAndVoiceOverDisableControls() throws {
        let accessibilityType = HomeLayoutCapabilities.supportsTileSizeControl(
            usableWidth: 900,
            isPhone: false,
            voiceOverEnabled: false,
            dynamicTypeSize: .accessibility2,
            gridSpacing: 12
        )
        let voiceOver = HomeLayoutCapabilities.supportsTileSizeControl(
            usableWidth: 900,
            isPhone: false,
            voiceOverEnabled: true,
            dynamicTypeSize: .large,
            gridSpacing: 12
        )

        #expect(accessibilityType == false)
        #expect(voiceOver == false)
    }
}
