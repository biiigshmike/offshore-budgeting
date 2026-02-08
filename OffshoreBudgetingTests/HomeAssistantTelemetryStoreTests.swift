//
//  HomeAssistantTelemetryStoreTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeAssistantTelemetryStoreTests {

    @Test func loadEvents_returnsEmptyWhenNoDataExists() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let loaded = setup.store.loadEvents(workspaceID: UUID())

        #expect(loaded.isEmpty)
    }

    @Test func appendEvent_thenLoadEvents_preservesOrderAndPayload() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        let first = makeEvent(index: 1)
        let second = makeEvent(index: 2)

        setup.store.appendEvent(first, workspaceID: workspaceID)
        setup.store.appendEvent(second, workspaceID: workspaceID)
        let loaded = setup.store.loadEvents(workspaceID: workspaceID)

        #expect(loaded.count == 2)
        #expect(loaded[0] == first)
        #expect(loaded[1] == second)
    }

    @Test func appendEvent_trimsToMaxStoredEventsKeepingMostRecent() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        let total = HomeAssistantTelemetryStore.maxStoredEvents + 7

        for index in 1...total {
            setup.store.appendEvent(makeEvent(index: index), workspaceID: workspaceID)
        }

        let loaded = setup.store.loadEvents(workspaceID: workspaceID)

        #expect(loaded.count == HomeAssistantTelemetryStore.maxStoredEvents)
        #expect(loaded.first?.prompt == "Prompt 8")
        #expect(loaded.last?.prompt == "Prompt \(total)")
    }

    @Test func appendEvent_keepsSeparateEventsPerWorkspace() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceA = UUID()
        let workspaceB = UUID()

        setup.store.appendEvent(makeEvent(index: 1), workspaceID: workspaceA)
        setup.store.appendEvent(makeEvent(index: 9), workspaceID: workspaceB)

        let loadedA = setup.store.loadEvents(workspaceID: workspaceA)
        let loadedB = setup.store.loadEvents(workspaceID: workspaceB)

        #expect(loadedA.count == 1)
        #expect(loadedB.count == 1)
        #expect(loadedA.first?.prompt == "Prompt 1")
        #expect(loadedB.first?.prompt == "Prompt 9")
    }

    @Test func clearEvents_removesAllForWorkspace() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        setup.store.appendEvent(makeEvent(index: 1), workspaceID: workspaceID)
        setup.store.clearEvents(workspaceID: workspaceID)

        let loaded = setup.store.loadEvents(workspaceID: workspaceID)
        #expect(loaded.isEmpty)
    }

    // MARK: - Helpers

    private func makeStore() -> (store: HomeAssistantTelemetryStore, suiteName: String) {
        let suiteName = "HomeAssistantTelemetryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard

        return (
            store: HomeAssistantTelemetryStore(
                userDefaults: defaults,
                storageKeyPrefix: "test.assistant.telemetry"
            ),
            suiteName: suiteName
        )
    }

    private func clearDefaults(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func makeEvent(index: Int) -> HomeAssistantTelemetryEvent {
        HomeAssistantTelemetryEvent(
            id: UUID(uuidString: String(format: "90000000-0000-0000-0000-%012d", index)) ?? UUID(),
            timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
            prompt: "Prompt \(index)",
            normalizedPrompt: "prompt \(index)",
            outcome: .resolved,
            source: "parser",
            intentRawValue: HomeQueryIntent.spendThisMonth.rawValue,
            confidenceRawValue: HomeQueryConfidenceBand.high.rawValue,
            targetName: index % 2 == 0 ? "Groceries" : nil,
            notes: index % 2 == 0 ? "note \(index)" : nil
        )
    }
}
