//
//  MarinaConversationStoreTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaConversationStoreTests {

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

    @Test func saveAnswers_withInlineCreateAttachment_preservesAttachmentPayload() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        let expected = [
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "Create Expense",
                subtitle: nil,
                attachment: .inlineCreateForm(
                    MarinaInlineCreateForm(
                        entity: .expense,
                        summary: "Prefilled from your message.",
                        amountText: "18",
                        date: Date(timeIntervalSince1970: 1_234),
                        notesText: "Coffee",
                        selectedCardID: UUID(),
                        selectedCategoryID: UUID(),
                        showsValidation: true
                    )
                )
            )
        ]

        setup.store.saveAnswers(expected, workspaceID: workspaceID)
        let loaded = setup.store.loadAnswers(workspaceID: workspaceID)

        #expect(loaded == expected)
    }

    @Test func saveAnswers_withCardSummaryAttachment_preservesAttachmentPayload() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        let cardID = UUID()
        let summary = CardSummaryPresentationModel(
            cardID: cardID,
            title: "Apple Card",
            themeRaw: CardThemeOption.ruby.rawValue,
            effectRaw: CardEffectOption.plastic.rawValue,
            startDate: Date(timeIntervalSince1970: 1_776_729_600),
            endDate: Date(timeIntervalSince1970: 1_779_321_599),
            plannedTotal: 579.45,
            variableTotal: 909.06,
            total: 1_488.51
        )
        let expected = [
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                userPrompt: "show Apple Card",
                title: "I found Apple Card.",
                subtitle: "Here's your Apple Card.",
                rows: [
                    HomeAnswerRow(title: "Total", value: "$1,488.51")
                ],
                attachment: .cardSummary(summary)
            )
        ]

        setup.store.saveAnswers(expected, workspaceID: workspaceID)
        let loaded = setup.store.loadAnswers(workspaceID: workspaceID)

        #expect(loaded == expected)
    }

    @Test func saveAnswers_withEntitySummaryAttachment_preservesAttachmentPayload() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        let summary = MarinaEntitySummaryPresentationModel(
            sourceID: UUID(),
            objectType: .reconciliationAccount,
            title: "Roommate",
            subtitle: "Reconciliation account",
            primaryValue: "$125.00",
            systemImage: "person.2.fill",
            tintHex: "#6366F1",
            rows: [
                .init(title: "Ledger rows", value: "4")
            ]
        )
        let expected = [
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "I found Roommate.",
                attachment: .entitySummary(summary)
            )
        ]

        setup.store.saveAnswers(expected, workspaceID: workspaceID)
        let loaded = setup.store.loadAnswers(workspaceID: workspaceID)

        #expect(loaded == expected)
    }

    @Test func saveAnswers_withRowListAttachment_preservesAttachmentPayload() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        let rowList = MarinaRowListPresentationModel(
            title: "Apple Card expenses",
            subtitle: "2 rows",
            family: .expenses,
            rows: [
                .init(
                    sourceID: UUID(),
                    objectType: .variableExpense,
                    title: "Coffee",
                    subtitle: "May 1, 2026",
                    value: "$6.50",
                    amount: 6.5,
                    date: Date(timeIntervalSince1970: 1_777_593_600),
                    systemImage: "creditcard.fill",
                    tintHex: "#14B8A6"
                )
            ]
        )
        let expected = [
            HomeAnswer(
                queryID: UUID(),
                kind: .list,
                title: "Apple Card expenses",
                attachment: .rowList(rowList)
            )
        ]

        setup.store.saveAnswers(expected, workspaceID: workspaceID)
        let loaded = setup.store.loadAnswers(workspaceID: workspaceID)

        #expect(loaded == expected)
    }

    @Test func saveAnswers_withPolishedFormulaAttachment_preservesAttachmentPayload() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        let summary = MarinaMetricSummaryPresentationModel(
            title: "Safe Spend Remaining",
            subtitle: "May 2026",
            primaryValue: "$450.00",
            rows: [
                MarinaDisplayRow(title: "Days left", value: "9", role: .result),
                MarinaDisplayRow(title: "Formula", value: "deterministic safe-spend", role: .trace)
            ]
        )
        let expected = [
            HomeAnswer(
                queryID: UUID(),
                kind: .list,
                title: "Safe Spend Remaining",
                attachment: .metricSummary(summary)
            )
        ]

        setup.store.saveAnswers(expected, workspaceID: workspaceID)
        let loaded = setup.store.loadAnswers(workspaceID: workspaceID)

        #expect(loaded == expected)
    }

    @Test func saveAnswers_thenLoadAnswers_preservesInlineCreateFormDrafts() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceID = UUID()
        let expected = [
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "Create Card",
                subtitle: nil,
                attachment: .inlineCreateForm(
                    MarinaInlineCreateForm(
                        entity: .card,
                        summary: nil,
                        nameText: "Travel Card",
                        cardThemeRaw: CardThemeOption.sunset.rawValue,
                        cardEffectRaw: CardEffectOption.glass.rawValue,
                        showsValidation: true
                    )
                )
            )
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
        let total = MarinaConversationStore.maxStoredAnswers + 12
        let input = (1...total).map { makeAnswer(index: $0) }

        setup.store.saveAnswers(input, workspaceID: workspaceID)
        let loaded = setup.store.loadAnswers(workspaceID: workspaceID)

        #expect(loaded.count == MarinaConversationStore.maxStoredAnswers)
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

    @Test func saveLastCheckIn_keepsSeparateTimestampPerWorkspace() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let workspaceA = UUID()
        let workspaceB = UUID()
        let checkInA = Date(timeIntervalSince1970: 1_000)
        let checkInB = Date(timeIntervalSince1970: 2_000)

        #expect(setup.store.loadLastCheckIn(workspaceID: workspaceA) == nil)

        setup.store.saveLastCheckIn(checkInA, workspaceID: workspaceA)
        setup.store.saveLastCheckIn(checkInB, workspaceID: workspaceB)

        #expect(setup.store.loadLastCheckIn(workspaceID: workspaceA) == checkInA)
        #expect(setup.store.loadLastCheckIn(workspaceID: workspaceB) == checkInB)
    }

    // MARK: - Helpers

    private func makeStore() -> (store: MarinaConversationStore, suiteName: String) {
        let suiteName = "MarinaConversationStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard

        return (
            store: MarinaConversationStore(
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
