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

    private func pinnedWidgetsKey(workspaceID: UUID) -> String {
        "home_pinnedWidgets_\(workspaceID.uuidString)"
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "HomePinnedStoresTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create test UserDefaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func clearKeys(workspaceID: UUID) {
        UserDefaults.standard.removeObject(forKey: pinnedItemsKey(workspaceID: workspaceID))
        UserDefaults.standard.removeObject(forKey: pinnedCardsKey(workspaceID: workspaceID))
        UserDefaults.standard.removeObject(forKey: pinnedWidgetsKey(workspaceID: workspaceID))
    }

    private func itemDescriptor(_ item: HomePinnedItem) -> String {
        switch item {
        case .widget(let widget, let size):
            return "widget:\(widget.rawValue):\(size.rawValue)"
        case .card(let id, let size):
            return "card:\(id.uuidString):\(size.rawValue)"
        }
    }

    private func descriptors(_ items: [HomePinnedItem]) -> [String] {
        items.map(itemDescriptor)
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
        #expect(descriptors(loaded).contains("widget:\(HomeWidgetID.income.rawValue):\(HomeTileSize.small.rawValue)"))
        #expect(descriptors(loaded).contains("card:\(cardID2.uuidString):\(HomeTileSize.wide.rawValue)"))
        #expect(descriptors(loaded).contains("card:\(cardID1.uuidString):\(HomeTileSize.small.rawValue)") == false)
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

    @Test func bootstrapPinnedItems_prefersUnifiedStore() {
        let defaults = makeDefaults()
        let workspaceID = UUID()
        let unifiedStore = HomePinnedItemsStore(workspaceID: workspaceID, defaults: defaults)
        let legacyWidgetsStore = HomePinnedWidgetsStore(workspaceID: workspaceID, defaults: defaults)
        let legacyCardsStore = HomePinnedCardsStore(workspaceID: workspaceID, defaults: defaults)

        unifiedStore.save([
            .widget(.income, .wide),
            .card(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, .small)
        ])
        legacyWidgetsStore.save([.savingsOutlook, .spendTrends])
        legacyCardsStore.save([UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!])

        let pinnedItems = HomeViewBootstrap.initialPinnedItems(
            workspaceID: workspaceID,
            fallbackCardIDs: [UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!],
            defaults: defaults
        )

        #expect(
            descriptors(pinnedItems) == [
                "widget:\(HomeWidgetID.income.rawValue):\(HomeTileSize.wide.rawValue)",
                "card:AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA:\(HomeTileSize.small.rawValue)"
            ]
        )
    }

    @Test func bootstrapPinnedItems_migratesLegacyStoresInOrder() {
        let defaults = makeDefaults()
        let workspaceID = UUID()
        let legacyWidgetsStore = HomePinnedWidgetsStore(workspaceID: workspaceID, defaults: defaults)
        let legacyCardsStore = HomePinnedCardsStore(workspaceID: workspaceID, defaults: defaults)

        legacyWidgetsStore.save([.income, .whatIf])
        legacyCardsStore.save([
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        ])

        let pinnedItems = HomeViewBootstrap.initialPinnedItems(
            workspaceID: workspaceID,
            fallbackCardIDs: [],
            defaults: defaults
        )

        #expect(
            descriptors(pinnedItems) == [
                "widget:\(HomeWidgetID.income.rawValue):\(HomeTileSize.small.rawValue)",
                "widget:\(HomeWidgetID.whatIf.rawValue):\(HomeTileSize.small.rawValue)",
                "card:11111111-1111-1111-1111-111111111111:\(HomeTileSize.small.rawValue)",
                "card:22222222-2222-2222-2222-222222222222:\(HomeTileSize.small.rawValue)"
            ]
        )
    }

    @Test func bootstrapPinnedItems_usesFallbackCardsWhenLegacyCardsAreEmpty() {
        let defaults = makeDefaults()
        let workspaceID = UUID()
        let legacyWidgetsStore = HomePinnedWidgetsStore(workspaceID: workspaceID, defaults: defaults)
        legacyWidgetsStore.save([.income])

        let fallbackCards = [
            UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        ]

        let pinnedItems = HomeViewBootstrap.initialPinnedItems(
            workspaceID: workspaceID,
            fallbackCardIDs: fallbackCards,
            defaults: defaults
        )

        #expect(
            descriptors(pinnedItems) == [
                "widget:\(HomeWidgetID.income.rawValue):\(HomeTileSize.small.rawValue)",
                "card:33333333-3333-3333-3333-333333333333:\(HomeTileSize.small.rawValue)",
                "card:44444444-4444-4444-4444-444444444444:\(HomeTileSize.small.rawValue)"
            ]
        )
    }

    @Test func bootstrapPinnedItems_returnsDefaultWidgetsWhenNoSourcesExist() {
        let defaults = makeDefaults()
        let workspaceID = UUID()

        let pinnedItems = HomeViewBootstrap.initialPinnedItems(
            workspaceID: workspaceID,
            fallbackCardIDs: [],
            defaults: defaults
        )

        #expect(
            descriptors(pinnedItems) == [
                "widget:\(HomeWidgetID.income.rawValue):\(HomeTileSize.small.rawValue)",
                "widget:\(HomeWidgetID.savingsOutlook.rawValue):\(HomeTileSize.small.rawValue)",
                "widget:\(HomeWidgetID.whatIf.rawValue):\(HomeTileSize.small.rawValue)",
                "widget:\(HomeWidgetID.nextPlannedExpense.rawValue):\(HomeTileSize.small.rawValue)",
                "widget:\(HomeWidgetID.categorySpotlight.rawValue):\(HomeTileSize.small.rawValue)",
                "widget:\(HomeWidgetID.spendTrends.rawValue):\(HomeTileSize.small.rawValue)"
            ]
        )
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
