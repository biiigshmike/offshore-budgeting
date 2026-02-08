//
//  HomeAssistantConversationStoreTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeAssistantConversationStoreTests {

    // MARK: - Load/Save

    @Test func loadAnswers_returnsEmptyWhenNoDataExists() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let loaded = setup.store.loadAnswers(workspaceID: UUID())

        #expect(loaded.isEmpty)
    }

    @Test func saveAnswers_thenLoadAnswers_preservesOrderAndPayload() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        let expected = [
            makeAnswer(index: 1),
            makeAnswer(index: 2),
            makeAnswer(index: 3)
        ]

        setup.store.saveAnswers(expected, workspaceID: workspaceID)
        let loaded = setup.store.loadAnswers(workspaceID: workspaceID)

        #expect(loaded == expected)
    }

    // MARK: - Limit

    @Test func saveAnswers_trimsToMaxStoredAnswersKeepingMostRecent() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        let total = HomeAssistantConversationStore.maxStoredAnswers + 12
        let input = (1...total).map { makeAnswer(index: $0) }

        setup.store.saveAnswers(input, workspaceID: workspaceID)
        let loaded = setup.store.loadAnswers(workspaceID: workspaceID)

        #expect(loaded.count == HomeAssistantConversationStore.maxStoredAnswers)
        #expect(loaded.first?.title == "Answer 13")
        #expect(loaded.last?.title == "Answer \(total)")
    }

    // MARK: - Workspace Isolation

    @Test func saveAnswers_keepsSeparateHistoryPerWorkspace() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceA = UUID()
        let workspaceB = UUID()

        let answersA = [makeAnswer(index: 1), makeAnswer(index: 2)]
        let answersB = [makeAnswer(index: 9)]

        setup.store.saveAnswers(answersA, workspaceID: workspaceA)
        setup.store.saveAnswers(answersB, workspaceID: workspaceB)

        let loadedA = setup.store.loadAnswers(workspaceID: workspaceA)
        let loadedB = setup.store.loadAnswers(workspaceID: workspaceB)

        #expect(loadedA == answersA)
        #expect(loadedB == answersB)
    }

    // MARK: - Helpers

    private func makeStore() -> (store: HomeAssistantConversationStore, suiteName: String) {
        let suiteName = "HomeAssistantConversationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard

        return (
            store: HomeAssistantConversationStore(
                userDefaults: defaults,
                storageKeyPrefix: "test.assistant.answers"
            ),
            suiteName: suiteName
        )
    }

    private func clearDefaults(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func makeAnswer(index: Int) -> HomeAnswer {
        HomeAnswer(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index)) ?? UUID(),
            queryID: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index)) ?? UUID(),
            kind: .message,
            title: "Answer \(index)",
            subtitle: "Subtitle \(index)",
            primaryValue: "Value \(index)",
            rows: [
                HomeAnswerRow(title: "Row \(index)", value: "Amount \(index)")
            ],
            generatedAt: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }
}
