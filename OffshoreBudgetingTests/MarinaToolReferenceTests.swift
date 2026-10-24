import Foundation
import SwiftData
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels
/// Exercises the real tools and validating bridge without invoking the language model.
@MainActor
struct MarinaToolReferenceTests {
    @Test func financialLookupCannotInventANameOrBorrowAnUnrelatedRememberedName() async throws {
        let fixture = try Fixture()
        fixture.begin("How much have I spent this month?")
        fixture.bridge.requiresFreshRead = true
        #expect(try status(await fixture.lookup("Marina")) == "invalidRequest")
        #expect(fixture.bridge.requests.isEmpty && !fixture.bridge.hasGroundedAnswer)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "success")

        fixture.begin("How much did I spend on Blue Card this month?")
        #expect(try status(await fixture.lookup("Blue Card", kind: .card)) == "success")
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        _ = try await fixture.expenses(.references([card]), dates: .currentMonth)
        fixture.begin("What about last month?")
        #expect(try status(await fixture.lookup("Blue Card", kind: .card)) == "success")
        #expect(try status(await fixture.lookup("Rainy Day", kind: .savingsAccount)) == "invalidRequest")

        fixture.begin("How much have I spent this month across all cards?")
        #expect(try status(await fixture.lookup("Blue Card", kind: .card)) != "success")
        #expect(!fixture.bridge.requests.contains { $0.tool == .findRecords })
    }

    @Test func explicitlyNamedAndPendingLookupNamesRemainGrounded() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend at Apple last month?")
        fixture.bridge.requiresFreshRead = true
        #expect(try status(await fixture.lookup("Apple")) == "candidates")
        fixture.begin("I mean the merchant, not the card.")
        #expect(try status(await fixture.lookup("Apple", kind: .merchant)) == "success")
        #expect(fixture.bridge.requests.last?.recordKind == "merchant")

        fixture.begin("How much did I spend at the merchant named Marina this month?")
        #expect(try status(await fixture.lookup("Marina", kind: .merchant)) == "empty")
        #expect(fixture.bridge.hasGroundedAnswer)
    }

    @Test func resolvedNamedTargetCannotSilentlyBecomeWorkspaceSpending() async throws {
        let fixture = try Fixture()
        fixture.begin("What did I spend on Blue Card this month?")
        #expect(try status(await fixture.lookup("Blue Card", kind: .card)) == "success")
        let reference = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)

        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.bridge.hasInvalidRequest)
        #expect(!fixture.bridge.hasFinancialResults)
        #expect(fixture.financialRequests.isEmpty)
        #expect(fixture.answer.presentations?.isEmpty != false)

        #expect(try status(await fixture.expenses(.references([reference]), dates: .currentMonth)) == "success")
        #expect(!fixture.bridge.hasInvalidRequest)
        #expect(fixture.financialRequests.count == 1)
        #expect(fixture.financialRequests.allSatisfy { $0.cardID == fixture.blue.id.uuidString && $0.search == nil })
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 30 })
    }

    @Test func wrongKindReferenceFailureSurvivesAnotherSuccessfulLookup() async throws {
        let fixture = try Fixture()
        fixture.begin("Show Blue Card spending.")
        _ = try await fixture.lookup("Rainy Day", kind: .savingsAccount)
        let savings = try fixture.reference(kind: "savingsAccount", id: fixture.savings.id.uuidString)
        #expect(try status(await fixture.expenses(.references([savings]), dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.bridge.hasInvalidRequest)
        #expect(fixture.financialRequests.isEmpty)

        #expect(try status(await fixture.lookup("Blue Card", kind: .card)) == "success")
        #expect(fixture.bridge.hasInvalidRequest)
        #expect(!fixture.bridge.hasFinancialResults)
        #expect(fixture.answer.rows.contains { $0.role == .assumption && $0.title.contains("cannot select") })
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        #expect(try status(await fixture.expenses(.references([card]), dates: .currentMonth)) == "success")
        #expect(!fixture.bridge.hasInvalidRequest)
        #expect(fixture.financialRequests.count == 1)
        #expect(fixture.financialRequests.first?.cardID == fixture.blue.id.uuidString)
    }

    @Test func previousQueryDatesUseTheLatestFinancialReadInsteadOfTheLatestLookup() async throws {
        let fixture = try Fixture()
        fixture.begin("Blue Card spending during September 2026.")
        _ = try await fixture.lookup("Blue Card", kind: .card)
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        _ = try await fixture.expenses(.references([card]), dates: .dates(start: "2026-09-01", end: "2026-09-30"))
        #expect(fixture.memory.latestFinancialQuery?.period.startDate == "2026-09-01")
        #expect(fixture.memory.latestFinancialQuery?.period.endDate == "2026-09-30")

        fixture.begin("Show purchases for that card and that period.")
        var lookup = MarinaDataRequest(tool: .findRecords)
        lookup.recordKind = "card"
        lookup.search = "Blue Card"
        lookup.relativePeriod = .currentMonth
        _ = try fixture.bridge.call(lookup)
        #expect(fixture.memory.recentQueries.last?.period.startDate == "2026-10-01")
        #expect(fixture.memory.latestFinancialQuery?.period.startDate == "2026-09-01")
        #expect(try status(await fixture.expenses(.previous, dates: .previousQuery, operation: .transactions)) == "success")
        let request = try #require(fixture.financialRequests.last)
        #expect(request.cardID == fixture.blue.id.uuidString)
        #expect(request.startDate == "2026-09-01" && request.endDate == "2026-09-30")
        #expect(request.relativePeriod == nil && !request.allTime)
        #expect(fixture.answer.presentations?.contains { $0.records.map(\.id) == [fixture.septemberBlue.id.uuidString] } == true)
    }

    @Test func previousSelectionFromAnIncompatibleDomainRequiresAnExplicitSelection() async throws {
        let fixture = try Fixture()
        fixture.begin("What is my Rainy Day savings balance?")
        _ = try await fixture.lookup("Rainy Day", kind: .savingsAccount)
        let savings = try fixture.reference(kind: "savingsAccount", id: fixture.savings.id.uuidString)
        _ = try await fixture.accounts(.references([savings]), scope: .savings)
        #expect(fixture.memory.latestFinancialQuery?.tool == .accounts)

        fixture.begin("How much did I spend this month?")
        #expect(try status(await fixture.expenses(.previous, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
        #expect(!fixture.bridge.hasFinancialResults)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "success")
        let request = try #require(fixture.financialRequests.first)
        #expect(request.cardID == nil && request.categoryID == nil && request.budgetID == nil)
        #expect(request.accountID == nil && request.search == nil)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 243 })
        #expect(!fixture.bridge.hasInvalidRequest)
    }

    @Test func financialNarrationWaitsForAReadRatherThanAnInventoryOrNameLookup() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend on Blue Card this month?")
        fixture.bridge.requiresFreshRead = true
        func explanation() -> String? {
            fixture.bridge.answer(id: UUID(), prompt: "", narration: "You spent $999.00.").explanation
        }
        #expect(explanation() == "")
        _ = try fixture.bridge.call(.init(operation: .inventory, tool: .findRecords, recordKind: "card"))
        #expect(!fixture.bridge.hasGroundedAnswer && explanation() == "")
        _ = try await fixture.lookup("Blue Card", kind: .card)
        #expect(!fixture.bridge.hasGroundedAnswer && explanation() == "")
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        _ = try await fixture.expenses(.references([card]), dates: .currentMonth)
        #expect(fixture.bridge.hasGroundedAnswer)
        #expect(explanation()?.contains("$999.00") == false)
        #expect(explanation()?.isEmpty == false)
    }

    @Test func aVerifiedAnswerToTheSoleRequestedTopicClearsAnEarlierWrongToolArgumentError() async throws {
        let fixture = try Fixture()
        fixture.begin("Show my spending by category this month.")
        let malformed = try MarinaIncomeTool.Arguments(GeneratedContent(json:
            #"{"selection":"workspace","dates":"currentMonth","state":"actual","operation":"compareIncome"}"#))
        #expect(try status(await MarinaIncomeTool(bridge: fixture.bridge).call(arguments: malformed)) == "invalidRequest")
        #expect(fixture.bridge.hasInvalidRequest)
        _ = try fixture.bridge.call(.init(operation: .inventory, tool: .findRecords, recordKind: "category"))
        #expect(fixture.bridge.hasInvalidRequest, "An inventory alone cannot resolve the financial failure.")
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth, operation: .categoryTotals)) == "success")
        #expect(!fixture.bridge.hasInvalidRequest && fixture.bridge.hasGroundedAnswer)
        #expect(fixture.financialRequests.count == 1 && fixture.financialRequests.first?.tool == .expenses)
        #expect(fixture.answer.explanation?.isEmpty == false)
    }

    @Test func mixedTopicsRetainFailuresAndCorrectedTopicsNeverClearReferenceGuards() async throws {
        let mixed = try Fixture()
        mixed.begin("Show my spending and actual income this month.")
        let malformed = try MarinaIncomeTool.Arguments(GeneratedContent(json:
            #"{"selection":"workspace","dates":"currentMonth","state":"actual","operation":"compareIncome"}"#))
        #expect(try status(await MarinaIncomeTool(bridge: mixed.bridge).call(arguments: malformed)) == "invalidRequest")
        #expect(try status(await mixed.expenses(.workspace, dates: .currentMonth)) == "success")
        #expect(mixed.bridge.hasInvalidRequest)
        #expect(mixed.answer.explanation?.isEmpty != false)

        let single = try Fixture()
        single.begin("How much have I spent this month?")
        #expect(try status(await single.income(.references(["r999"]))) == "invalidRequest")
        #expect(try status(await single.expenses(.workspace, dates: .currentMonth)) == "success")
        #expect(!single.bridge.hasInvalidRequest)
        let count = single.bridge.requests.count
        #expect(try status(await single.income(.workspace)) == "invalidRequest")
        #expect(single.bridge.requests.count == count, "Clearing the wrong-tool notice must not release that tool's failed reference.")
    }

    @Test func incompleteOrUnrequestedFlatComparisonsReturnFeedbackWithoutFinancialReads() async throws {
        let fixture = try Fixture()
        fixture.begin("Compare this month versus last month.")
        for json in [
            #"{"selection":"workspace","dates":"currentMonth","operation":"compare"}"#,
            #"{"selection":"workspace","dates":"currentMonth","operation":"summary","comparison":{"selection":"workspace","dates":"previousMonth"}}"#
        ] {
            let arguments = try MarinaExpensesTool.Arguments(GeneratedContent(json: json))
            let output = try await MarinaExpensesTool(bridge: fixture.bridge).call(arguments: arguments)
            #expect(try status(output) == "invalidRequest")
        }
        for json in [
            #"{"selection":"workspace","dates":"currentMonth","state":"actual","operation":"compareIncome"}"#,
            #"{"selection":"workspace","dates":"currentMonth","state":"actual","operation":"summary","comparison":{"selection":"workspace","dates":"previousMonth"}}"#
        ] {
            let arguments = try MarinaIncomeTool.Arguments(GeneratedContent(json: json))
            let output = try await MarinaIncomeTool(bridge: fixture.bridge).call(arguments: arguments)
            #expect(try status(output) == "invalidRequest")
        }
        #expect(fixture.bridge.requests.isEmpty && !fixture.bridge.hasGroundedAnswer)
    }

    @Test func pairedPeriodComparisonRejectsSeparateReadsUntilTheCalculatedComparisonArrives() async throws {
        let fixture = try Fixture()
        fixture.begin("What did I spend on Blue Card this month?")
        _ = try await fixture.lookup("Blue Card", kind: .card)
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        _ = try await fixture.expenses(.references([card]), dates: .currentMonth)

        fixture.begin("Compare this month's spending on that card with last month.")
        fixture.bridge.requiresFreshRead = true
        for dates in [MarinaDateSelection.currentMonth, .previousMonth] {
            #expect(try status(await fixture.expenses(.previous, dates: dates, operation: .transactions)) == "invalidRequest")
        }
        #expect(fixture.financialRequests.isEmpty)
        #expect(!fixture.bridge.hasGroundedAnswer)
        #expect(fixture.memory.latestFinancialQuery?.period.startDate == "2026-10-01")
        #expect(fixture.answer.explanation?.isEmpty != false)

        #expect(try status(await fixture.expenses(.previous, dates: .currentMonth,
            operation: .compare(selection: .previous, dates: .previousMonth))) == "success")
        let request = try #require(fixture.financialRequests.first)
        #expect(fixture.financialRequests.count == 1)
        #expect(request.operation == .comparison && request.relativePeriod == .currentMonth)
        #expect(request.cardID == fixture.blue.id.uuidString)
        #expect(request.comparisonFilter?.cardID == fixture.blue.id.uuidString)
        #expect(request.comparisonPeriod == .previousMonth)
        #expect(request.scope == .variable && request.expenseMeasure == .spending)
        #expect(!fixture.bridge.hasInvalidRequest && fixture.bridge.hasGroundedAnswer)
        let presentation = try #require(fixture.answer.presentations?.first)
        #expect(presentation.operation == .comparison)
        #expect(presentation.metrics.contains { $0.label == "Total" && $0.value == 30 })
        #expect(presentation.metrics.contains { $0.label == "Comparison total" && $0.value == 70 })
        #expect(presentation.metrics.contains { $0.label == "Difference" && $0.value == -40 })
    }

    @Test func missingNamedTargetStopsWithAQuestionBeforeAnyFinancialRead() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend on Missing Card this month?")
        fixture.bridge.requiresFreshRead = true
        fixture.bridge.haltOnClarification = true
        do {
            _ = try await fixture.lookup("Missing Card", kind: .card)
            Issue.record("A missing target must stop inference for user clarification.")
        } catch is MarinaClarificationRequired { }
        #expect(fixture.financialRequests.isEmpty)
        #expect(fixture.bridge.hasGroundedAnswer)
        #expect(fixture.answer.explanation?.contains("couldn’t find “Missing Card”") == true)
        #expect(!fixture.answer.rows.contains { $0.title == "Total" })
    }

    @Test func aMissingNameClarificationIsVisibleAfterBadFinancialArgumentsWithoutAllowingWorkspaceFallback() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend on Missing Card this month?")
        fixture.bridge.requiresFreshRead = true
        #expect(try status(await fixture.expenses(.references(["r999"]), dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.bridge.hasInvalidRequest)
        #expect(try status(await fixture.lookup("Missing Card", kind: .card)) == "empty")
        #expect(fixture.bridge.hasGroundedAnswer && !fixture.bridge.hasInvalidRequest)
        #expect(fixture.answer.explanation?.contains("couldn’t find “Missing Card”") == true)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
    }

    @Test func anUnresolvedExplicitNameMustBeLookedUpBeforeWorkspaceDataCanBeRead() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend on the card named \"Missing Card\" this month?")
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
        #expect(try status(await fixture.lookup("Missing Card", kind: .card)) == "empty")
        #expect(fixture.answer.explanation?.contains("couldn’t find “Missing Card”") == true)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
    }

    @Test func genericLookupNounsDoNotEndFinancialQuestionsButExplicitlyNamedRecordsStillResolve() async throws {
        let fixture = try Fixture()
        fixture.begin("How much have I spent this month?")
        #expect(try status(await fixture.lookup("workspace", kind: .workspace)) == "scopeAlreadyResolved")
        #expect(fixture.bridge.requests.isEmpty && !fixture.bridge.hasGroundedAnswer)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "success")
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 243 })

        fixture.begin("Am I on track with my budget this month?")
        #expect(try status(await fixture.lookup("budget", kind: .budget)) == "scopeAlreadyResolved")
        #expect(fixture.bridge.requests.isEmpty && !fixture.bridge.hasInvalidRequest)

        let namedCard = Card(name: "Budget", workspace: fixture.workspace)
        fixture.context.insert(namedCard)
        try fixture.context.save()
        fixture.begin("How much did I spend on the card called \"Budget\" this month?")
        #expect(try status(await fixture.lookup("Budget", kind: .card)) == "success")
        #expect(fixture.memory.reference(forKind: "card", id: namedCard.id.uuidString) != nil)
        fixture.begin("List my cards.")
        #expect(try status(fixture.bridge.call(.init(operation: .inventory, tool: .findRecords, recordKind: "card"))) == "success")
        #expect(fixture.bridge.requests.count == 1)
    }

    @Test func protocolReferencesCannotBecomeInventedMissingNames() async throws {
        let fixture = try Fixture()
        fixture.begin("How much have I spent this month?")
        #expect(try status(await fixture.lookup("r1")) == "invalidRequest")
        #expect(fixture.bridge.requests.isEmpty && !fixture.bridge.hasGroundedAnswer)
        #expect(fixture.answer.explanation?.contains("couldn’t find") != true)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "success")
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 243 })

        fixture.begin("What did I spend on Blue Card this month?")
        _ = try await fixture.lookup("Blue Card", kind: .card)
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        _ = try await fixture.expenses(.references([card]), dates: .currentMonth)
        fixture.begin("Show spending for that card this month.")
        #expect(try status(await fixture.lookup(card)) == "invalidRequest")
        #expect(fixture.bridge.requests.isEmpty)
        #expect(try status(await fixture.expenses(.references([card]), dates: .currentMonth)) == "success")
        #expect(fixture.financialRequests.first?.cardID == fixture.blue.id.uuidString)

        fixture.begin("How much did I spend on the card named \"Missing Card\" this month?")
        #expect(try status(await fixture.lookup("r999")) == "invalidRequest")
        #expect(fixture.bridge.requests.isEmpty)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
    }

    @Test func toolAndOperationIdentifiersCannotBecomeInventedMissingNames() async throws {
        let fixture = try Fixture()
        fixture.begin("Show my upcoming preset expenses for the next seven days.")
        for identifier in ["upcomingPresets", "readExpenses", "compareIncome"] {
            #expect(try status(await fixture.lookup(identifier)) == "invalidRequest")
            #expect(fixture.bridge.requests.isEmpty && !fixture.bridge.hasGroundedAnswer)
        }
        let result = try status(await fixture.expenses(.workspace, dates: .nextSevenDays, operation: .upcomingPresets))
        #expect(["success", "empty"].contains(result))
        #expect(fixture.financialRequests.count == 1)
        #expect(fixture.financialRequests.first?.tool == .expenses)
        #expect(fixture.financialRequests.first?.relativePeriod == .nextSevenDays)
    }

    @Test func toolCallLimitIsNeverClassifiedAsAnArgumentDecodeRepair() async throws {
        let fixture = try Fixture()
        fixture.begin("How much have I spent this month?")
        for _ in 0..<8 {
            #expect(try status(await fixture.lookup("r999")) == "invalidRequest")
        }
        do {
            _ = try await fixture.lookup("r999")
            Issue.record("The ninth tool attempt must hit the existing limit.")
        } catch {
            #expect(MarinaToolBridge.argumentErrorFeedback(error) == nil)
            let wrapped = LanguageModelSession.ToolCallError(tool: MarinaFindRecordsTool(bridge: fixture.bridge), underlyingError: error)
            #expect(MarinaToolBridge.argumentErrorFeedback(wrapped) == nil)
        }
        #expect(fixture.bridge.requests.isEmpty)
    }

    @Test func recordsLiterallyNamedLikeProtocolValuesRemainSearchable() async throws {
        let fixture = try Fixture()
        for name in ["r1", "upcomingPresets", "readExpenses"] {
            let namedCard = Card(name: name, workspace: fixture.workspace)
            fixture.context.insert(namedCard)
            try fixture.context.save()
            fixture.begin("How much did I spend on the card named \(name) this month?")
            #expect(try status(await fixture.lookup(name, kind: .card)) == "success")
            #expect(fixture.bridge.requests.last?.search == name)
            let selection = try fixture.reference(kind: "card", id: namedCard.id.uuidString)
            let result = try status(await fixture.expenses(.references([selection]), dates: .currentMonth))
            #expect(["success", "empty"].contains(result))
            #expect(fixture.financialRequests.first?.cardID == namedCard.id.uuidString)
        }
    }

    @Test func anAmountForOneCardDoesNotBecomeARedundantRanking() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend on Blue Card this month?")
        _ = try await fixture.lookup("Blue Card", kind: .card)
        let reference = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        #expect(try status(await fixture.expenses(.references([reference]), dates: .currentMonth, operation: .cardTotals)) == "success")
        let total = try #require(fixture.financialRequests.first)
        #expect(total.operation == .summary && total.grouping == .none)
        #expect(total.cardID == fixture.blue.id.uuidString && total.relativePeriod == .currentMonth)
        #expect(total.expenseMeasure == .spending && total.scope == .variable)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 30 })

        fixture.begin("Show the spending ranking by card for Blue Card this month.")
        #expect(try status(await fixture.expenses(.references([reference]), dates: .currentMonth, operation: .cardTotals)) == "success")
        #expect(fixture.financialRequests.first?.operation == .ranking)
        #expect(fixture.financialRequests.first?.grouping == .card)
    }

    @Test func explicitWholeWorkspaceDoesNotReuseAnIncompatibleAccount() async throws {
        let fixture = try Fixture()
        fixture.begin("What is my Rainy Day savings balance?")
        _ = try await fixture.lookup("Rainy Day", kind: .savingsAccount)
        let savings = try fixture.reference(kind: "savingsAccount", id: fixture.savings.id.uuidString)
        _ = try await fixture.accounts(.references([savings]), scope: .savings)
        #expect(fixture.memory.latestFinancialQuery?.tool == .accounts)

        fixture.begin("How much did I spend this month across the whole workspace?")
        #expect(try status(await fixture.expenses(.previous, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "success")
        let request = try #require(fixture.financialRequests.first)
        #expect(request.tool == .expenses && fixture.financialRequests.count == 1)
        #expect(request.cardID == nil && request.categoryID == nil && request.budgetID == nil)
        #expect(request.accountID == nil && request.search == nil)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 243 })
        #expect(!fixture.bridge.hasInvalidRequest)
    }

    @Test func pendingAmbiguitySurvivesANewTurnAndRepeatedLookupUntilAnExplicitCandidate() async throws {
        let fixture = try Fixture()
        let originalPrompt = "How much did I spend at Apple last month?"
        fixture.begin(originalPrompt)
        #expect(try status(await fixture.lookup("Apple")) == "candidates")
        let merchant = try fixture.reference(kind: "merchant", id: "Apple")
        #expect(try status(await fixture.expenses(.references([merchant]), dates: .previousMonth)) == "needsClarification")
        #expect(fixture.financialRequests.isEmpty)
        #expect(fixture.memory.pendingClarification?.originatingPrompt == originalPrompt)
        // Restore persisted memory as a renewed session would; no transcript inference is involved.
        fixture.memory = try JSONDecoder().decode(MarinaConversationMemory.self,
            from: JSONEncoder().encode(fixture.memory))
        fixture.begin("I mean the merchant, not the card.")
        #expect(try status(await fixture.expenses(.workspace, dates: .previousMonth)) == "needsClarification")
        #expect(fixture.financialRequests.isEmpty)
        #expect(try status(await fixture.lookup("Apple")) == "candidates")
        #expect(fixture.memory.pendingClarification?.originatingPrompt == originalPrompt)
        #expect(try status(await fixture.lookup("Apple", kind: .merchant)) == "success")
        // The original question's explicit period remains required; previousQuery means a
        // validated financial range, not a guessed interpretation of a pending prompt.
        #expect(try status(await fixture.expenses(.references([merchant]), dates: .previousMonth)) == "success")
        let request = try #require(fixture.financialRequests.last)
        #expect(request.search == "Apple" && request.cardID == nil)
        #expect(request.startDate == "2026-09-01" && request.endDate == "2026-09-30")
        #expect(request.relativePeriod == nil && !request.allTime)
        #expect(fixture.memory.latestFinancialQuery?.period.startDate == "2026-09-01")
        #expect(fixture.memory.latestFinancialQuery?.period.endDate == "2026-09-30")
        #expect(fixture.memory.pendingClarification == nil)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 37 })
    }

    @Test func restoredClarificationUsesItsFrozenPeriodDespiteNewerLookupDates() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend on Blue Card this month?")
        _ = try await fixture.lookup("Blue Card", kind: .card)
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        _ = try await fixture.expenses(.references([card]), dates: .currentMonth)
        #expect(fixture.memory.latestFinancialQuery?.period.startDate == "2026-10-01")

        fixture.begin("How much did I spend at Apple last month?")
        #expect(try status(await fixture.lookup("Apple")) == "candidates")
        #expect(fixture.memory.pendingClarification?.period?.startDate == "2026-09-01")
        #expect(fixture.memory.pendingClarification?.period?.endDate == "2026-09-30")
        fixture.memory = try JSONDecoder().decode(MarinaConversationMemory.self,
            from: JSONEncoder().encode(fixture.memory))
        fixture.begin("I mean the merchant, not the card.")
        // A newer validated lookup may carry its own range; it must not replace the
        // pending financial question's frozen period or the latest financial query.
        var lookup = MarinaDataRequest(tool: .findRecords)
        lookup.search = "Apple"
        lookup.relativePeriod = .currentMonth
        #expect(try status(fixture.bridge.call(lookup)) == "candidates")
        #expect(fixture.memory.pendingClarification?.period?.startDate == "2026-09-01")
        #expect(fixture.memory.latestFinancialQuery?.period.startDate == "2026-10-01")
        _ = try await fixture.lookup("Apple", kind: .merchant)
        let merchant = try fixture.reference(kind: "merchant", id: "Apple")
        #expect(try status(await fixture.expenses(.references([merchant]), dates: .currentMonth)) == "success")
        let request = try #require(fixture.financialRequests.first)
        #expect(request.search == "Apple" && request.cardID == nil)
        #expect(request.startDate == "2026-09-01" && request.endDate == "2026-09-30")
        #expect(request.relativePeriod == nil && !request.allTime)
        #expect(fixture.memory.latestFinancialQuery?.period.startDate == "2026-09-01")
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 37 })
    }

    @Test func aNewExplicitFinancialTopicReleasesAnOlderPendingQuestion() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend at Apple last month?")
        _ = try await fixture.lookup("Apple")
        #expect(fixture.memory.pendingClarification != nil)

        fixture.begin("How much actual income did I receive this month?")
        let resultStatus = try status(await fixture.income(.workspace))
        #expect(["success", "empty"].contains(resultStatus))
        let request = try #require(fixture.financialRequests.first)
        #expect(request.tool == .income && request.relativePeriod == .currentMonth)
        #expect(request.search == nil && request.cardID == nil && request.state == .actual)
        #expect(fixture.memory.pendingClarification == nil)
        #expect(fixture.bridge.hasGroundedAnswer)
    }

    @Test func aNewFullQuestionAboutACandidateDoesNotInheritTheOldPendingPeriod() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend at Apple last month?")
        _ = try await fixture.lookup("Apple")
        #expect(fixture.memory.pendingClarification?.period?.startDate == "2026-09-01")
        let merchant = try fixture.reference(kind: "merchant", id: "Apple")

        fixture.begin("How much did I spend at the merchant Apple?")
        _ = try await fixture.lookup("Apple", kind: .merchant)
        #expect(try status(await fixture.expenses(.references([merchant]), dates: .currentMonth)) == "success")
        let request = try #require(fixture.financialRequests.first)
        #expect(request.search == "Apple" && request.cardID == nil)
        #expect(request.relativePeriod == .currentMonth)
        #expect(request.startDate == nil && request.endDate == nil)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 200 })
    }

    @Test func anUnconfirmedReplyCannotChooseAPendingReferenceForTheUser() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend at Apple last month?")
        _ = try await fixture.lookup("Apple")
        let merchant = try fixture.reference(kind: "merchant", id: "Apple")
        fixture.begin("Yes.")
        #expect(try status(await fixture.expenses(.references([merchant]), dates: .previousMonth)) == "needsClarification")
        #expect(fixture.financialRequests.isEmpty && fixture.memory.pendingClarification != nil)
        fixture.begin("I mean the merchant, not the card.")
        #expect(try status(await fixture.expenses(.references([merchant]), dates: .previousMonth)) == "success")
        #expect(fixture.financialRequests.first?.search == "Apple")
    }

    @Test func aCurrentAmbiguousLiteralCannotReuseAnEarlierCardReference() async throws {
        let fixture = try Fixture()
        fixture.begin("What did I spend on the Apple card this month?")
        _ = try await fixture.lookup("Apple", kind: .card)
        let apple = try #require(fixture.memory.confirmedEntities.first { $0.kind == "card" && $0.name == "Apple" })
        let card = try fixture.reference(kind: "card", id: apple.id)
        _ = try await fixture.expenses(.references([card]), dates: .currentMonth)

        fixture.begin("How much did I spend at Apple last month?")
        #expect(try status(await fixture.expenses(.references([card]), dates: .previousMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
        #expect(try status(await fixture.lookup("Apple")) == "candidates")
        #expect(fixture.memory.pendingClarification?.candidates.contains { $0.kind == "merchant" } == true)
        #expect(fixture.memory.pendingClarification?.candidates.contains { $0.kind == "card" } == true)
    }

    @Test func currentNamedCategoriesCannotUseOrRetainAnUnmentionedPreviousCard() async throws {
        for (name, prompt) in [("Hair Care", "How much did I spend in the Hair Care category this month?"),
                               ("Café 🍵", "¿Cuánto gasté en la categoría Café 🍵 este mes?")] {
            let fixture = try Fixture()
            let category = Category(name: name, hexColor: "#123456", workspace: fixture.workspace)
            let anotherCard = Card(name: "Everyday", workspace: fixture.workspace)
            fixture.context.insert(category)
            fixture.context.insert(anotherCard)
            fixture.context.insert(VariableExpense(descriptionText: "Category purchase", amount: 90,
                transactionDate: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))!,
                workspace: fixture.workspace, card: anotherCard, category: category))
            try fixture.context.save()
            fixture.begin("What did I spend on Blue Card this month?")
            _ = try await fixture.lookup("Blue Card", kind: .card)
            let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
            _ = try await fixture.expenses(.references([card]), dates: .currentMonth)

            fixture.begin(prompt)
            #expect(try status(await fixture.expenses(.references([card]), dates: .currentMonth)) == "invalidRequest")
            #expect(fixture.financialRequests.isEmpty)
            _ = try await fixture.lookup(name, kind: .category)
            let categoryReference = try fixture.reference(kind: "category", id: category.id.uuidString)
            #expect(try status(await fixture.expenses(.references([card, categoryReference]), dates: .currentMonth)) == "invalidRequest")
            #expect(fixture.financialRequests.isEmpty)
            #expect(try status(await fixture.expenses(.references([categoryReference]), dates: .currentMonth)) == "success")
            let request = try #require(fixture.financialRequests.first)
            #expect(request.categoryID == category.id.uuidString && request.cardID == nil)
            #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 90 })
        }
    }

    @Test func explicitNewRelativePeriodOverridesThePendingClarificationPeriod() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend at Apple last month?")
        _ = try await fixture.lookup("Apple")
        #expect(fixture.memory.pendingClarification?.period?.startDate == "2026-09-01")
        fixture.begin("I mean the merchant, for this month instead.")
        _ = try await fixture.lookup("Apple", kind: .merchant)
        let merchant = try fixture.reference(kind: "merchant", id: "Apple")
        // The user's new explicit cue overrides even a stale model-supplied period.
        #expect(try status(await fixture.expenses(.references([merchant]), dates: .previousMonth)) == "success")
        #expect(fixture.financialRequests.count == 1)
        #expect(fixture.financialRequests.first?.search == "Apple")
        #expect(fixture.memory.latestFinancialQuery?.period.startDate == "2026-10-01")
        #expect(fixture.memory.latestFinancialQuery?.period.endDate == "2026-10-31")
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 200 })
    }

    @Test func explicitNewDateRangeOverridesThePendingClarificationPeriod() async throws {
        let fixture = try Fixture()
        fixture.context.insert(VariableExpense(descriptionText: "Apple", amount: 400,
            transactionDate: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 18))!,
            workspace: fixture.workspace, card: fixture.blue))
        try fixture.context.save()
        fixture.begin("How much did I spend at Apple last month?")
        _ = try await fixture.lookup("Apple")
        fixture.begin("I mean the merchant, only on October 17, 2026.")
        _ = try await fixture.lookup("Apple", kind: .merchant)
        let merchant = try fixture.reference(kind: "merchant", id: "Apple")
        #expect(try status(await fixture.expenses(.references([merchant]),
            dates: .dates(start: "2026-10-17", end: "2026-10-17"))) == "success")
        let request = try #require(fixture.financialRequests.first)
        #expect(request.search == "Apple" && request.cardID == nil)
        #expect(request.startDate == "2026-10-17" && request.endDate == "2026-10-17")
        #expect(fixture.memory.latestFinancialQuery?.period.startDate == "2026-10-17")
        #expect(fixture.memory.latestFinancialQuery?.period.endDate == "2026-10-17")
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 200 })
    }

    @Test func onlyFirstUnnamedTotalsCanCorrectInventedReferencesToExplicitWorkspace() async throws {
        let expenses = try Fixture()
        expenses.begin("How much have I spent this month?")
        #expect(try status(await expenses.expenses(.references(["r999"]), dates: .currentMonth)) == "invalidRequest")
        #expect(expenses.bridge.requests.isEmpty)
        #expect(try status(await expenses.expenses(.workspace, dates: .currentMonth)) == "success")
        #expect(expenses.financialRequests.count == 1 && expenses.financialRequests.first?.cardID == nil)
        #expect(expenses.answer.rows.contains { $0.title == "Total" && $0.amount == 243 })

        let income = try Fixture()
        income.begin("How much actual income did I receive this month?")
        #expect(try status(await income.income(.references(["r999"]))) == "invalidRequest")
        #expect(income.bridge.requests.isEmpty)
        #expect(["success", "empty"].contains(try status(await income.income(.workspace))))
        #expect(income.financialRequests.count == 1 && income.financialRequests.first?.search == nil)

        for prompt in ["How much did I spend on Blue Card this month?", "How much did I spend on Missing Card this month?", "How much did I spend on that card this month?"] {
            let named = try Fixture()
            named.begin(prompt)
            #expect(try status(await named.expenses(.references(["r999"]), dates: .currentMonth)) == "invalidRequest")
            #expect(try status(await named.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
            #expect(named.bridge.requests.isEmpty)
        }
    }

    @Test func knownForeignAndPreviousTargetsNeverUseTheUnnamedReferenceRepair() async throws {
        let fixture = try Fixture()
        let foreign = fixture.memory.reference(for: .init(kind: "card", id: fixture.foreignCard.id.uuidString, name: fixture.foreignCard.name))
        fixture.begin("How much have I spent this month?")
        #expect(try status(await fixture.expenses(.references([foreign]), dates: .currentMonth)) == "invalidRequest")
        let count = fixture.bridge.requests.count
        #expect(try status(await fixture.expenses(.references(["r999"]), dates: .currentMonth)) == "invalidRequest")
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.bridge.requests.count == count && !fixture.bridge.hasFinancialResults)

        fixture.begin("What did I spend on Blue Card this month?")
        _ = try await fixture.lookup("Blue Card", kind: .card)
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        _ = try await fixture.expenses(.references([card]), dates: .currentMonth)
        fixture.begin("How much have I spent this month?")
        #expect(try status(await fixture.expenses(.references(["r999"]), dates: .currentMonth)) == "invalidRequest")
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.bridge.requests.isEmpty)
    }

    @Test func unknownEvictedAndForeignReferencesCannotReadFinancialData() async throws {
        let fixture = try Fixture()
        fixture.begin("Read the selected card.")
        #expect(try status(await fixture.expenses(.references(["missing-ref"]), dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
        #expect(!fixture.bridge.hasFinancialResults)

        let evicted = fixture.memory.reference(for: .init(kind: "card", id: fixture.blue.id.uuidString, name: fixture.blue.name))
        for index in 0..<MarinaConversationMemory.maxReferences {
            _ = fixture.memory.reference(for: .init(kind: "card", id: UUID().uuidString, name: "Old reference \(index)"))
        }
        #expect(fixture.memory.entity(forReference: evicted) == nil)
        fixture.begin("Read the old selected card.")
        #expect(try status(await fixture.expenses(.references([evicted]), dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)

        // Even a structurally valid reference carrying a foreign ID must fail at the data boundary.
        let foreign = fixture.memory.reference(for: .init(kind: "card", id: fixture.foreignCard.id.uuidString, name: fixture.foreignCard.name))
        fixture.begin("Read this card.")
        #expect(try status(await fixture.expenses(.references([foreign]), dates: .currentMonth)) == "invalidRequest")
        #expect(!fixture.bridge.hasFinancialResults)
        #expect(fixture.bridge.hasInvalidRequest)
        #expect(fixture.answer.presentations?.isEmpty != false)
        #expect(!fixture.answer.rows.contains { $0.title == "Total" })
        #expect(fixture.memory.latestFinancialQuery == nil)
        #expect(fixture.financialRequests.count == 1)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        // The rejected fallback must never reach the data service as a second financial read.
        #expect(fixture.financialRequests.count == 1)
        #expect(!fixture.bridge.hasFinancialResults)
        _ = try await fixture.lookup("Blue Card", kind: .card)
        let corrected = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        #expect(try status(await fixture.expenses(.references([corrected]), dates: .currentMonth)) == "success")
        #expect(!fixture.bridge.hasInvalidRequest)
        #expect(fixture.financialRequests.count == 2)
        #expect(fixture.financialRequests.last?.cardID == fixture.blue.id.uuidString)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 30 })
    }

    @Test func deletedEntityReferenceCannotFallBackToWorkspaceAndCanBeCorrected() async throws {
        let fixture = try Fixture()
        let removed = Card(name: "Removed card", workspace: fixture.workspace)
        fixture.context.insert(removed)
        try fixture.context.save()
        let stale = fixture.memory.reference(for: .init(kind: "card", id: removed.id.uuidString, name: removed.name))
        fixture.context.delete(removed)
        try fixture.context.save()
        fixture.begin("What did I spend on the selected card?")
        #expect(try status(await fixture.expenses(.references([stale]), dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.count == 1)
        #expect(try status(await fixture.expenses(.workspace, dates: .currentMonth)) == "invalidRequest")
        #expect(fixture.financialRequests.count == 1)
        #expect(!fixture.bridge.hasFinancialResults)
        #expect(fixture.memory.latestFinancialQuery == nil)
        _ = try await fixture.lookup("Blue Card", kind: .card)
        let corrected = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        #expect(try status(await fixture.expenses(.references([corrected]), dates: .currentMonth)) == "success")
        #expect(!fixture.bridge.hasInvalidRequest)
        #expect(fixture.financialRequests.count == 2)
        #expect(fixture.financialRequests.last?.cardID == fixture.blue.id.uuidString)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 30 })
    }

    @Test func priorPendingClarificationCanMoveToANewUniquelyNamedTopic() async throws {
        let fixture = try Fixture()
        fixture.context.insert(SavingsLedgerEntry(
            date: Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 17))!,
            amount: 40, note: "Earlier savings", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: fixture.workspace, account: fixture.savings))
        try fixture.context.save()
        fixture.begin("What did I spend at Apple last month?")
        #expect(try status(await fixture.lookup("Apple")) == "candidates")
        #expect(fixture.memory.pendingClarification != nil)
        #expect(fixture.memory.pendingClarification?.period?.startDate == "2026-09-01")
        #expect(fixture.financialRequests.isEmpty)

        fixture.begin("Switch topics: what is my Rainy Day savings account balance?")
        #expect(try status(await fixture.lookup("Rainy Day", kind: .savingsAccount)) == "success")
        let reference = try fixture.reference(kind: "savingsAccount", id: fixture.savings.id.uuidString)
        #expect(try status(await fixture.accounts(.references([reference]), scope: .savings)) == "success")
        #expect(fixture.memory.pendingClarification == nil)
        #expect(!fixture.bridge.hasInvalidRequest)
        #expect(fixture.financialRequests.count == 1)
        let request = try #require(fixture.financialRequests.first)
        #expect(request.tool == .accounts && request.scope == .savings)
        #expect(request.accountID == fixture.savings.id.uuidString)
        #expect(request.cardID == nil && request.search == nil)
        #expect(request.allTime && request.relativePeriod == nil && request.startDate == nil && request.endDate == nil)
        #expect(fixture.memory.latestFinancialQuery?.period.allTime == true)
        #expect(fixture.answer.rows.contains { $0.title == "Selected period activity total" && $0.amount == 120 })
        #expect(fixture.answer.presentations?.contains {
            $0.metrics.contains { $0.label == "Rainy Day current balance" && $0.value == 120 }
        } == true)
    }

    @Test func allTransactionsOnANamedCardRetainTheCardSelection() async throws {
        let fixture = try Fixture()
        fixture.begin("Show all transactions on Blue Card this month.")
        #expect(try status(await fixture.lookup("Blue Card", kind: .card)) == "success")
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        #expect(try status(await fixture.expenses(.references([card]), dates: .currentMonth, operation: .transactions)) == "success")
        let request = try #require(fixture.financialRequests.first)
        #expect(request.cardID == fixture.blue.id.uuidString && request.operation == .transactions)
        #expect(fixture.answer.presentations?.contains {
            $0.records.count == 1 && $0.records.first?.amount == 30
        } == true)
    }

    @Test func explicitAllCardsCorrectsTheOldNamedCardSelection() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend on Blue Card this month?")
        _ = try await fixture.lookup("Blue Card", kind: .card)
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        _ = try await fixture.expenses(.references([card]), dates: .currentMonth)

        fixture.begin("How much did I spend this month across all cards?")
        #expect(try status(await fixture.lookup("Blue Card", kind: .card)) == "scopeAlreadyResolved")
        #expect(fixture.financialRequests.isEmpty)
        #expect(!fixture.bridge.hasFinancialResults)
        #expect(try status(await fixture.expenses(.references([card]), dates: .currentMonth)) == "success")
        #expect(fixture.financialRequests.count == 1)
        let request = try #require(fixture.financialRequests.first)
        #expect(request.cardID == nil && request.search == nil && request.categoryID == nil && request.budgetID == nil)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 243 })
        #expect(!fixture.bridge.hasInvalidRequest)
    }

    @Test func explicitAllCardsPreservesCategoryDatesAndFinancialMeasure() async throws {
        let fixture = try Fixture()
        let food = Offshore.Category(name: "Food", hexColor: "#00FF00", workspace: fixture.workspace)
        let other = Card(name: "Other card", workspace: fixture.workspace)
        fixture.context.insert(food); fixture.context.insert(other)
        let september = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 17))!
        let october = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17))!
        for (card, amount, date, category) in [
            (fixture.blue, 5.0, september, Optional(food)),
            (other, 7.0, september, Optional(food)),
            (other, 100.0, october, Optional(food)),
            (other, 900.0, september, nil)
        ] {
            fixture.context.insert(VariableExpense(descriptionText: "Category fixture", amount: amount,
                transactionDate: date, workspace: fixture.workspace, card: card, category: category))
        }
        try fixture.context.save()
        fixture.begin("Resolve Blue Card and the Food category.")
        _ = try await fixture.lookup("Blue Card", kind: .card)
        _ = try await fixture.lookup("Food", kind: .category)
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        let category = try fixture.reference(kind: "category", id: food.id.uuidString)
        fixture.begin("Show Food category spending across all cards from September 1 through September 30, 2026.")
        #expect(try status(await fixture.expenses(.references([card, category]),
            dates: .dates(start: "2026-09-01", end: "2026-09-30"))) == "success")
        let request = try #require(fixture.financialRequests.first)
        #expect(request.cardID == nil && request.categoryID == food.id.uuidString)
        #expect(request.startDate == "2026-09-01" && request.endDate == "2026-09-30")
        #expect(request.scope == .variable && request.expenseMeasure == .spending)
        #expect(request.search == nil && request.budgetID == nil)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 12 })
        #expect(fixture.memory.latestFinancialQuery?.selection?.categoryID == food.id.uuidString)
        #expect(fixture.memory.latestFinancialQuery?.selection?.cardID == nil)
    }

    @Test func explicitAllReconciliationAccountsCorrectsTheOldAccountSelection() async throws {
        let fixture = try Fixture()
        let alex = AllocationAccount(name: "Alex", workspace: fixture.workspace)
        let pat = AllocationAccount(name: "Pat", workspace: fixture.workspace)
        fixture.context.insert(alex); fixture.context.insert(pat)
        fixture.context.insert(AllocationSettlement(date: Date(), note: "Alex activity", amount: 25,
            workspace: fixture.workspace, account: alex))
        fixture.context.insert(AllocationSettlement(date: Date(), note: "Pat activity", amount: 10,
            workspace: fixture.workspace, account: pat))
        try fixture.context.save()
        fixture.begin("What is my reconciliation balance with Alex?")
        _ = try await fixture.lookup("Alex", kind: .reconciliationAccount)
        let reference = try fixture.reference(kind: "reconciliationAccount", id: alex.id.uuidString)
        _ = try await fixture.accounts(.references([reference]), scope: .reconciliation)

        fixture.begin("Show the current balances of all my reconciliation accounts.")
        #expect(try status(await fixture.lookup("Alex", kind: .reconciliationAccount)) == "scopeAlreadyResolved")
        #expect(fixture.financialRequests.isEmpty)
        #expect(try status(await fixture.accounts(.references([reference]), scope: .reconciliation)) == "success")
        let request = try #require(fixture.financialRequests.first)
        #expect(request.scope == .reconciliation && request.accountID == nil)
        #expect(fixture.financialRequests.count == 1)
        // Paging the account rows must retain the complete set of verified balance metrics.
        #expect(fixture.answer.presentations?.contains {
            $0.totalCount == 2 && $0.metrics.count == 2
                && $0.metrics.contains { $0.label == "Alex current reconciliation balance" && $0.value == 25 }
                && $0.metrics.contains { $0.label == "Pat current reconciliation balance" && $0.value == 10 }
        } == true)
        #expect(!fixture.bridge.hasInvalidRequest)
    }

    @Test func modelSuppliedMerchantKindDoesNotResolveAmbiguousUserWording() async throws {
        let fixture = try Fixture()
        fixture.begin("How much did I spend at Apple this month?")
        #expect(try status(await fixture.lookup("Apple", kind: .merchant)) == "candidates")
        #expect(fixture.bridge.requests.last?.recordKind == nil)
        #expect(Set(fixture.memory.pendingClarification?.candidates.map(\.kind) ?? []) == ["card", "merchant"])
        let merchant = try fixture.reference(kind: "merchant", id: "Apple")
        #expect(try status(await fixture.expenses(.references([merchant]), dates: .currentMonth)) == "needsClarification")
        #expect(fixture.financialRequests.isEmpty)

        fixture.begin("I mean the merchant, not the card.")
        #expect(try status(await fixture.lookup("Apple", kind: .merchant)) == "success")
        #expect(fixture.bridge.requests.last?.recordKind == "merchant")
        #expect(try status(await fixture.expenses(.references([merchant]), dates: .currentMonth)) == "success")
        let request = try #require(fixture.financialRequests.first)
        #expect(request.search == "Apple" && request.cardID == nil)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 200 })
    }

    @Test func previousExpenseCardDoesNotBecomeAnImplicitIncomeSelection() async throws {
        let fixture = try Fixture()
        fixture.context.insert(Income(source: "Salary", amount: 500,
            date: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17))!,
            isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Card income", amount: 100,
            date: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17))!,
            isPlanned: false, workspace: fixture.workspace, card: fixture.blue))
        try fixture.context.save()
        fixture.begin("How much did I spend on Blue Card this month?")
        _ = try await fixture.lookup("Blue Card", kind: .card)
        let card = try fixture.reference(kind: "card", id: fixture.blue.id.uuidString)
        _ = try await fixture.expenses(.references([card]), dates: .currentMonth)

        fixture.begin("How much actual income have I received this month?")
        #expect(try status(await fixture.income(.previous)) == "invalidRequest")
        #expect(fixture.financialRequests.isEmpty)
        #expect(try status(await fixture.income(.workspace)) == "success")
        #expect(fixture.financialRequests.count == 1)
        #expect(fixture.financialRequests.first?.cardID == nil)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 600 })
        fixture.begin("How much actual income did Blue Card receive this month?")
        #expect(try status(await fixture.income(.references([card]))) == "success")
        #expect(fixture.financialRequests.first?.cardID == fixture.blue.id.uuidString)
        #expect(fixture.answer.rows.contains { $0.title == "Total" && $0.amount == 100 })
    }

    @Test func genericAccountFollowUpsKeepSavingsAndReconciliationScopesSeparate() async throws {
        let fixture = try Fixture()
        let account = AllocationAccount(name: "Alex", hexColor: "#123456", workspace: fixture.workspace)
        fixture.context.insert(account)
        try fixture.context.save()
        fixture.begin("Show all savings account balances.")
        #expect(try status(await fixture.accounts(.workspace, scope: .savings)) == "success")
        #expect(fixture.memory.latestFinancialQuery?.scope == .savings)

        fixture.begin("And last month?")
        #expect(try status(await fixture.accounts(.previous, scope: .all)) == "success")
        let followUp = try #require(fixture.financialRequests.first)
        #expect(followUp.scope == .savings && followUp.accountID == nil)
        let presentation = try #require(fixture.answer.presentations?.first)
        #expect(presentation.records.map(\.title) == ["Rainy Day"])
        #expect(!presentation.records.contains { $0.title == "Alex" })

        fixture.begin("Show all reconciliation account balances.")
        #expect(try status(await fixture.accounts(.workspace, scope: .reconciliation)) == "success")
        #expect(fixture.financialRequests.first?.scope == .reconciliation)
        #expect(fixture.answer.presentations?.first?.records.map(\.title) == ["Alex"])
    }

    private func status(_ output: String) throws -> String {
        let object = try #require(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        return try #require(object["status"] as? String)
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        let workspace: Workspace
        let blue: Card
        let foreignCard: Card
        let savings: SavingsAccount
        let septemberBlue: VariableExpense
        let service: MarinaReadOnlyDataService
        let bridge = MarinaToolBridge()
        var memory: MarinaConversationMemory
        private var prompt = ""
        private var answerID = UUID()

        init() throws {
            let schema = Schema([Workspace.self, Budget.self, Card.self, BudgetCardLink.self, Category.self, Preset.self, BudgetPresetLink.self, BudgetCategoryLimit.self, PlannedExpense.self, VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, IncomeSeries.self, Income.self, MarinaChatSession.self])
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(
                "MarinaReferenceFixture-\(UUID().uuidString)", isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            context = ModelContext(container)
            workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
            let foreignWorkspace = Workspace(name: "Other", hexColor: "#000000")
            blue = Card(name: "Blue Card", workspace: workspace)
            let apple = Card(name: "Apple", workspace: workspace)
            let checking = Card(name: "Checking", workspace: workspace)
            foreignCard = Card(name: "Blue Card", workspace: foreignWorkspace)
            savings = SavingsAccount(name: "Rainy Day", workspace: workspace)
            let september = Self.date(month: 9, day: 17)
            let october = Self.date(month: 10, day: 17)
            septemberBlue = VariableExpense(descriptionText: "Blue September", amount: 70, transactionDate: september, workspace: workspace, card: blue)
            context.insert(workspace); context.insert(foreignWorkspace)
            context.insert(blue); context.insert(apple); context.insert(checking); context.insert(foreignCard); context.insert(savings)
            context.insert(septemberBlue)
            context.insert(VariableExpense(descriptionText: "Apple", amount: 37, transactionDate: september, workspace: workspace, card: checking))
            context.insert(VariableExpense(descriptionText: "September card purchase", amount: 11, transactionDate: september, workspace: workspace, card: apple))
            context.insert(VariableExpense(descriptionText: "Blue October", amount: 30, transactionDate: october, workspace: workspace, card: blue))
            context.insert(VariableExpense(descriptionText: "Apple", amount: 200, transactionDate: october, workspace: workspace, card: checking))
            context.insert(VariableExpense(descriptionText: "October card purchase", amount: 13, transactionDate: october, workspace: workspace, card: apple))
            context.insert(VariableExpense(descriptionText: "Foreign expense", amount: 900001, transactionDate: october, workspace: foreignWorkspace, card: foreignCard))
            context.insert(SavingsLedgerEntry(date: october, amount: 80, note: "Saved", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace, account: savings))
            try context.save()
            service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: Self.date(month: 10, day: 23))
            memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
        }

        func begin(_ prompt: String) {
            bridge.end()
            self.prompt = prompt
            answerID = UUID()
            bridge.conversationMemory = { [weak self] in self?.memory }
            bridge.onValidatedResult = { [weak self] request, result in
                guard let self else { return }
                self.memory.record(request: request, result: result, answerID: self.answerID, prompt: self.prompt)
            }
            bridge.begin(service: service, prompt: prompt, memory: memory, onResult: {})
        }

        var financialRequests: [MarinaDataRequest] { bridge.requests.filter { $0.tool != .findRecords } }
        var answer: HomeAnswer { bridge.answer(id: answerID, prompt: prompt, narration: "") }

        func reference(kind: String, id: String) throws -> String {
            try #require(memory.reference(forKind: kind, id: id))
        }

        func lookup(_ name: String, kind: MarinaRecordKind? = nil) async throws -> String {
            try await MarinaFindRecordsTool(bridge: bridge).call(arguments: .init(showVisual: nil,
                lookup: .resolveName(name: name, kind: kind)))
        }

        func expenses(_ selection: MarinaSelection, dates: MarinaDateSelection,
                      operation: MarinaExpenseOperation = .summary) async throws -> String {
            try await MarinaExpensesTool(bridge: bridge).call(arguments: .init(showVisual: nil, selection: selection,
                dates: dates, operation: operation, sort: nil, periodUnit: nil, offset: nil,
                scope: .variable, measure: .spending, includeFuture: nil))
        }

        func accounts(_ selection: MarinaSelection, scope: MarinaAccountScope) async throws -> String {
            try await MarinaAccountsTool(bridge: bridge).call(arguments: .init(selection: selection,
                showVisual: nil, scope: scope, dates: .allTime, offset: nil))
        }

        func income(_ selection: MarinaSelection) async throws -> String {
            try await MarinaIncomeTool(bridge: bridge).call(arguments: .init(showVisual: nil, selection: selection,
                dates: .currentMonth, state: .actual, operation: .summary))
        }

        private static func date(month: Int, day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }
    }
}
#endif
