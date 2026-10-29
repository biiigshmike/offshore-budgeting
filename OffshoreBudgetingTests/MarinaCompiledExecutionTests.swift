import Foundation
import SwiftData
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels

/// Exercises app-owned compilation and execution without asking the native model.
@MainActor
struct MarinaCompiledExecutionTests {
    @Test func compiledEntryRequiresExplicitModeAndFreshWorkspaceValidation() throws {
        let fixture = try Fixture()
        fixture.bridge.begin(service: fixture.service, prompt: "Show spending.", onResult: {})
        #expect(throws: (any Error).self) { try fixture.bridge.executeCompiledRead(fixture.request) }
        fixture.bridge.begin(service: fixture.service, prompt: "Show spending.", compiled: true, onResult: {})
        var foreign = fixture.request
        foreign.cardID = fixture.foreignCard.id.uuidString
        let result = try fixture.bridge.executeCompiledRead(foreign)
        #expect(result.status == "invalidRequest")
        #expect(!fixture.bridge.hasFinancialResults && fixture.bridge.selectCompiledResult() == nil)
    }

    @Test func discoveryDoesNotBecomeAnAnswerAndFinalReadKeepsCanonicalScope() throws {
        let fixture = try Fixture()
        fixture.bridge.begin(service: fixture.service, prompt: "Show Parcel expenses on Blue Card.", compiled: true, onResult: {})
        let lookup = try fixture.bridge.executeCompiledRead(.init(tool: .findRecords, allTime: true, search: "Parcel"))
        #expect(lookup.status == "candidates")
        #expect(fixture.bridge.selectCompiledResult() == nil)
        var request = fixture.request
        request.merchantName = "Parcel - Corner!"
        let result = try fixture.bridge.executeCompiledRead(request)
        #expect(result.status == "success")
        #expect(result.metrics.first { $0.label == "Total" }?.value == 35)
        #expect(fixture.bridge.selectCompiledResult() == "q0")
        #expect(fixture.bridge.selectedEvidence.allSatisfy { $0.id.hasPrefix("q0f") })
        let answer = fixture.bridge.answer(id: UUID(), prompt: "Show Parcel expenses on Blue Card.", narration: "")
        #expect(answer.presentations?.count == 1)
        #expect(result.resolvedRequest?.cardID == fixture.blue.id.uuidString)
        #expect(result.resolvedRequest?.merchantName == "Parcel - Corner!")
    }

    @Test func compiledReadUsesFreshDataAndDeletedIdentityCannotBroaden() throws {
        let fixture = try Fixture()
        fixture.bridge.begin(service: fixture.service, prompt: "Show spending.", compiled: true, onResult: {})
        let request = fixture.request
        let first = try fixture.bridge.executeCompiledRead(request)
        #expect(first.metrics.first { $0.label == "Total" }?.value == 95)
        fixture.context.insert(VariableExpense(descriptionText: "Another purchase", amount: 7,
            transactionDate: Fixture.date(month: 9, day: 30), workspace: fixture.workspace, card: fixture.blue))
        try fixture.context.save()
        let second = try fixture.bridge.executeCompiledRead(request)
        #expect(second.metrics.first { $0.label == "Total" }?.value == 102)
        fixture.context.delete(fixture.blue)
        try fixture.context.save()
        let missing = try fixture.bridge.executeCompiledRead(request)
        #expect(missing.status == "invalidRequest")
        #expect(fixture.bridge.selectCompiledResult() == nil)
    }

    @Test func datePreparationFreezesBothPeriodsWithoutChangingFilters() throws {
        let fixture = try Fixture()
        var request = fixture.request
        request.startDate = nil; request.endDate = nil; request.relativePeriod = .currentMonth
        request.operation = .comparison; request.comparisonPeriod = .previousPeriod
        request.comparisonFilter = .init(cardID: fixture.otherCard.id.uuidString, merchantName: "Parcel - Corner!")
        let result = try fixture.service.prepareCompiledDates(request)
        let frozen = try #require(result.resolvedRequest)
        #expect(result.status == "ready")
        #expect(frozen.relativePeriod == nil && frozen.comparisonPeriod == nil)
        #expect(frozen.startDate == "2026-10-01" && frozen.endDate == "2026-10-31")
        #expect(frozen.comparisonStartDate != nil && frozen.comparisonEndDate != nil)
        #expect(frozen.cardID == request.cardID && frozen.comparisonFilter == request.comparisonFilter)
        #expect(frozen.expenseMeasure == .spending && frozen.scope == .variable)
    }

    @Test func exactPendingCandidateRunsWithoutTranslationAndCommitsOneVerifiedFrame() async throws {
        let fixture = try Fixture()
        let original = try fixture.pendingMerchant()
        fixture.context.insert(VariableExpense(descriptionText: "Parcel - Corner!", amount: 7,
            transactionDate: Fixture.date(month: 9, day: 30), workspace: fixture.workspace, card: fixture.blue))
        try fixture.context.save()
        var narratedQuestion = ""
        let turn = fixture.turn(memory: original, prompt: "Parcel - Corner!") { act, question, _ in
            narratedQuestion = question
            return .init(act: act, introduction: "", claims: [], question: "")
        }
        let outcome = await turn.run()
        let committed = try #require(outcome.memory)
        let frame = try #require(committed.latestCompletedFrame)
        #expect(outcome.error == nil && outcome.primaryReference == "q0")
        #expect(frame.request.cardID == fixture.blue.id.uuidString && frame.request.merchantName == "Parcel - Corner!")
        #expect(frame.request.startDate == "2026-09-01" && frame.request.endDate == "2026-09-30")
        #expect(frame.request.scope == .variable && frame.request.expenseMeasure == .spending)
        #expect(committed.pendingClarification == nil && committed.completedFrames.count == 1)
        #expect(original.pendingClarification != nil && original.completedFrames.isEmpty)
        #expect(narratedQuestion == "Show Parcel expenses on Blue Card in September.")
        #expect(outcome.answer.presentations?.first?.metrics.first { $0.label == "Total" }?.value == 42)
        #expect(outcome.answer.completedFrame == frame)
    }

    @Test func changedExactCandidateCannotSilentlyUseRenamedRecord() async throws {
        let fixture = try Fixture()
        let original = try fixture.pendingCard()
        fixture.blue.name = "Renamed card"
        try fixture.context.save()
        var narrationCalled = false
        let turn = fixture.turn(memory: original, prompt: "Blue Card") { act, _, _ in
            narrationCalled = true
            return .init(act: act, introduction: "", claims: [], question: "")
        }
        let outcome = await turn.run()
        #expect(!narrationCalled && outcome.primaryReference == nil)
        #expect(outcome.answer.explanation?.contains("changed") == true)
        #expect(outcome.memory?.pendingClarification == original.pendingClarification)
        #expect(outcome.memory?.completedFrames.isEmpty == true)
    }

    @Test func cancellationAfterVerifiedReadDoesNotCommitWorkingMemory() async throws {
        let fixture = try Fixture()
        let original = try fixture.pendingMerchant()
        let task = Task { @MainActor in
            let turn = fixture.turn(memory: original, prompt: "Parcel - Corner!") { act, _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
                return .init(act: act, introduction: "", claims: [], question: "")
            }
            let outcome = await turn.run()
            return outcome.memory == nil && outcome.answer.completedFrame == nil
        }
        #expect(await task.value)
        #expect(original.pendingClarification != nil && original.completedFrames.isEmpty)
    }

    @Test(arguments: [true, false])
    func overlongResolvedMerchantOrCardCannotReplacePriorContext(merchant: Bool) async throws {
        let fixture = try Fixture()
        let name = "Oversized " + String(repeating: "é", count: 128)
        #expect(name.utf8.count > 256)
        var original: MarinaConversationMemory
        let choice: String
        if merchant {
            fixture.context.insert(VariableExpense(descriptionText: name, amount: 15,
                transactionDate: Fixture.date(month: 9, day: 17), workspace: fixture.workspace, card: fixture.blue))
            original = try fixture.pendingCard(includePriorFrame: true)
            choice = "Blue Card"
        } else {
            fixture.context.insert(Card(name: name, workspace: fixture.workspace))
            original = try fixture.pendingMerchant(includePriorFrame: true)
            choice = "Parcel - Corner!"
        }
        try fixture.context.save()
        var compilation = try #require(original.pendingClarification?.compilation)
        compilation.unresolvedTargets.append(.init(id: "oversized", field: merchant ? .merchant : .card,
            name: "Oversized", isComparison: false, source: .userText("Oversized")))
        let saved = original.setPendingCompilation(compilation)
        #expect(saved)
        let previousFrame = try #require(original.latestCompletedFrame)
        var narrationCalled = false
        let outcome = await fixture.turn(memory: original, prompt: choice) { act, _, _ in
            narrationCalled = true
            return .init(act: act, introduction: "", claims: [], question: "")
        }.run()
        #expect(outcome.memory == nil && outcome.answer.completedFrame == nil)
        #expect(outcome.answer.responseState == .invalidRequest && outcome.error != nil)
        #expect(outcome.answer.explanation?.contains("saved context") == true)
        #expect(!narrationCalled && outcome.primaryReference == nil)
        #expect(fixture.bridge.requests.count == 1 && fixture.bridge.requests.first?.tool == .findRecords)
        #expect(original.latestCompletedFrame == previousFrame && original.pendingClarification?.compilation == compilation)
    }

    @Test func invalidAllocatedReferenceCannotReachFinancialRead() async throws {
        let fixture = try Fixture()
        var original = try fixture.pendingCard(includePriorFrame: true)
        var compilation = try #require(original.pendingClarification?.compilation)
        compilation.unresolvedTargets.append(.init(id: "merchant", field: .merchant,
            name: "Parcel - Corner!", isComparison: false, source: .userText("Parcel - Corner!")))
        let saved = original.setPendingCompilation(compilation)
        #expect(saved)
        original = try memory(original, settingSequence: "nextReferenceNumber", to: Int.max - 1)
        var narrationCalled = false
        let outcome = await fixture.turn(memory: original, prompt: "Blue Card") { act, _, _ in
            narrationCalled = true
            return .init(act: act, introduction: "", claims: [], question: "")
        }.run()
        #expect(outcome.memory == nil && outcome.answer.completedFrame == nil)
        #expect(outcome.answer.responseState == .invalidRequest && !narrationCalled)
        #expect(fixture.bridge.requests.count == 1 && fixture.bridge.requests.first?.tool == .findRecords)
        #expect(original.latestCompletedFrame != nil && original.pendingClarification != nil)
    }

    @Test func rejectedCompletedFramePreservesPriorContextAndVerifiedVisual() async throws {
        let fixture = try Fixture()
        let original = try memory(fixture.pendingMerchant(includePriorFrame: true), settingSequence: "nextFrameNumber", to: Int.max - 1)
        let previousFrame = try #require(original.latestCompletedFrame)
        var narrationCalled = false
        let outcome = await fixture.turn(memory: original, prompt: "Parcel - Corner!") { act, _, _ in
            narrationCalled = true
            return .init(act: act, introduction: "", claims: [], question: "")
        }.run()
        #expect(narrationCalled && outcome.primaryReference != nil)
        #expect(outcome.memory == nil && outcome.answer.completedFrame == nil)
        #expect(outcome.answer.responseState == .invalidRequest && outcome.error != nil)
        #expect(outcome.answer.explanation?.contains("saved context limit") == true)
        #expect(outcome.answer.explanation?.contains("start a new chat") == true)
        #expect(outcome.answer.presentations?.first?.metrics.first { $0.label == "Total" }?.value == 35)
        #expect(original.latestCompletedFrame == previousFrame && original.pendingClarification != nil)
    }

    @Test func patchRepairKeepsSelectedGoalAndReceivesItsCompilerFeedback() async throws {
        let choice = MarinaRequestTranslator.Choice(goals: ["smallestExpense"], base: "active", source: "And the lowest?",
            requestedAnswer: "Find the lowest expense in the current card period.")
        let compiled = MarinaRequestCompiler.Compilation(capability: .smallestExpense,
            request: .init(operation: .transactions, tool: .expenses, sort: .smallest, limit: 1), dateOrigin: .explicit)
        var selections: [String] = []
        var patches: [(MarinaRequestTranslator.Choice, String)] = []
        var repairs: [MarinaCompiledTurn.InterpretationStage] = []
        var durations: [Duration] = []
        let result = try await MarinaCompiledTurn.interpret(select: { feedback in
            selections.append(feedback)
            return choice
        }, patchAndCompile: { selected, feedback in
            patches.append((selected, feedback))
            if patches.count == 1 {
                throw MarinaRequestCompiler.Failure(code: .invalidSource, message: "Use the user's exact date quote.")
            }
            return compiled
        }, onRepair: { stage, _ in repairs.append(stage) }, onDuration: { durations.append($0) })
        #expect(selections == [""] && patches.count == 2)
        #expect(patches.allSatisfy { $0.0.goal == choice.goal && $0.0.base == choice.base
            && $0.0.source == choice.source && $0.0.requestedAnswer == choice.requestedAnswer })
        #expect(patches.first?.1 == "" && patches.last?.1.contains("Use the user's exact date quote.") == true)
        #expect(repairs == [.patch] && durations.count == 3)
        #expect(result.choice.goal == choice.goal && result.compilation == compiled)
    }

    @Test func selectionRepairDoesNotLeakFeedbackIntoSuccessfulPatchStage() async throws {
        let choice = MarinaRequestTranslator.Choice(goals: ["expenses"], base: "newQuestion", source: "Show spending.")
        let compiled = MarinaRequestCompiler.Compilation(capability: .expenses, request: .init(tool: .expenses), dateOrigin: .appDefault)
        var selections: [String] = []
        var patches: [String] = []
        var repairs: [MarinaCompiledTurn.InterpretationStage] = []
        let result = try await MarinaCompiledTurn.interpret(select: { feedback in
            selections.append(feedback)
            if selections.count == 1 { throw MarinaRequestTranslator.Failure.invalidOutput("Choose an available base.") }
            return choice
        }, patchAndCompile: { _, feedback in
            patches.append(feedback)
            return compiled
        }, onRepair: { stage, _ in repairs.append(stage) })
        #expect(selections.count == 2 && selections.first == "")
        #expect(selections.last?.contains("Choose an available base.") == true)
        #expect(patches == [""] && repairs == [.selection])
        #expect(result.compilation == compiled)
    }

    @Test func selectionAndPatchShareOneRepairAllowance() async {
        var selectionCalls = 0
        var patchCalls = 0
        var repairs: [MarinaCompiledTurn.InterpretationStage] = []
        var measuredStages = 0
        var failed = false
        do {
            _ = try await MarinaCompiledTurn.interpret(select: { _ in
                selectionCalls += 1
                if selectionCalls == 1 { throw MarinaRequestTranslator.Failure.invalidOutput("Invalid goal.") }
                return .init(goals: ["expenses"], base: "newQuestion", source: "Show spending.")
            }, patchAndCompile: { _, feedback in
                patchCalls += 1
                #expect(feedback.isEmpty)
                throw MarinaRequestCompiler.Failure(code: .invalidSource, message: "Invalid patch source.")
            }, onRepair: { stage, _ in repairs.append(stage) }, onDuration: { _ in measuredStages += 1 })
        } catch {
            failed = true
            #expect((error as? MarinaRequestCompiler.Failure)?.code == .invalidSource)
        }
        #expect(failed && selectionCalls == 2 && patchCalls == 1)
        #expect(repairs == [.selection] && measuredStages == 3)
    }

    @Test func repeatedPatchFailureStopsWithoutReselectingGoal() async {
        var selectionCalls = 0
        var patchCalls = 0
        var repairCalls = 0
        var failed = false
        do {
            _ = try await MarinaCompiledTurn.interpret(select: { _ in
                selectionCalls += 1
                return .init(goals: ["income"], base: "pending", source: "Received income")
            }, patchAndCompile: { _, _ in
                patchCalls += 1
                throw MarinaRequestTranslator.Failure.invalidOutput("Malformed patch.")
            }, onRepair: { _, _ in repairCalls += 1 })
        } catch { failed = true }
        #expect(failed && selectionCalls == 1 && patchCalls == 2 && repairCalls == 1)
    }

    @Test(arguments: [false, true])
    func conversationalOrMultiReportChoiceSkipsPatchAndFinishesTimingBeforeReturn(multipleReports: Bool) async throws {
        let choice = MarinaRequestTranslator.Choice(goals: [multipleReports ? "expenses" : "greeting"],
            base: "newQuestion", source: "Current question", hasAdditionalGoals: multipleReports)
        var patchCalls = 0
        var measuredStages = 0
        let result = try await MarinaCompiledTurn.interpret(select: { _ in choice }, patchAndCompile: { _, _ in
            patchCalls += 1
            throw MarinaRequestTranslator.Failure.invalidOutput("Patch should not run.")
        }, onDuration: { _ in measuredStages += 1 })
        #expect(result.compilation == nil && result.choice.goal == choice.goal)
        #expect(patchCalls == 0 && measuredStages == 1)
    }

    @Test(arguments: [false, true])
    func cancellationInEitherInterpretationStageNeverRepairs(cancelSelection: Bool) async {
        var selectionCalls = 0
        var patchCalls = 0
        var repairCalls = 0
        var measuredStages = 0
        var cancelled = false
        do {
            _ = try await MarinaCompiledTurn.interpret(select: { _ in
                selectionCalls += 1
                if cancelSelection { throw CancellationError() }
                return .init(goals: ["expenses"], base: "active", source: "Current question")
            }, patchAndCompile: { _, _ in
                patchCalls += 1
                throw CancellationError()
            }, onRepair: { _, _ in repairCalls += 1 }, onDuration: { _ in measuredStages += 1 })
        } catch { cancelled = error is CancellationError }
        #expect(cancelled && selectionCalls == 1 && patchCalls == (cancelSelection ? 0 : 1))
        #expect(repairCalls == 0 && measuredStages == (cancelSelection ? 1 : 2))
    }

    private func memory(_ value: MarinaConversationMemory, settingSequence key: String, to number: Int) throws -> MarinaConversationMemory {
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object[key] = number
        return try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        let workspace: Workspace
        let blue: Card
        let otherCard: Card
        let foreignCard: Card
        let service: MarinaReadOnlyDataService
        let bridge = MarinaToolBridge()
        var request: MarinaDataRequest {
            .init(operation: .transactions, tool: .expenses, expenseMeasure: .spending,
                  startDate: "2026-09-01", endDate: "2026-09-30", cardID: blue.id.uuidString, scope: .variable)
        }
        init() throws {
            let schema = Schema([Workspace.self, Budget.self, Card.self, BudgetCardLink.self, Category.self, Preset.self,
                BudgetPresetLink.self, BudgetCategoryLimit.self, PlannedExpense.self, VariableExpense.self,
                AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
                SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, IncomeSeries.self,
                Income.self, MarinaChatSession.self])
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(
                "MarinaCompiled-\(UUID().uuidString)", isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            context = ModelContext(container)
            workspace = Workspace(name: "Personal", hexColor: "#FFFFFF")
            let otherWorkspace = Workspace(name: "Other", hexColor: "#000000")
            blue = Card(name: "Blue Card", workspace: workspace)
            otherCard = Card(name: "Blue Other", workspace: workspace)
            foreignCard = Card(name: "Blue Card", workspace: otherWorkspace)
            context.insert(workspace); context.insert(otherWorkspace)
            context.insert(blue); context.insert(otherCard); context.insert(foreignCard)
            context.insert(VariableExpense(descriptionText: "Parcel - Corner!", amount: 35,
                transactionDate: Self.date(month: 9, day: 17), workspace: workspace, card: blue))
            context.insert(VariableExpense(descriptionText: "Parcel - Market", amount: 60,
                transactionDate: Self.date(month: 9, day: 18), workspace: workspace, card: blue))
            context.insert(VariableExpense(descriptionText: "Parcel - Corner!", amount: 800,
                transactionDate: Self.date(month: 9, day: 17), workspace: workspace, card: otherCard))
            context.insert(VariableExpense(descriptionText: "Parcel - Corner!", amount: 900001,
                transactionDate: Self.date(month: 9, day: 17), workspace: otherWorkspace, card: foreignCard))
            try context.save()
            service = MarinaReadOnlyDataService(workspace: workspace, modelContext: context, now: Self.date(month: 10, day: 23))
        }
        func pendingMerchant(includePriorFrame: Bool = false) throws -> MarinaConversationMemory {
            try pending(field: .merchant, name: "Parcel", includePriorFrame: includePriorFrame)
        }
        func pendingCard(includePriorFrame: Bool = false) throws -> MarinaConversationMemory {
            try pending(field: .card, name: "Blue", includePriorFrame: includePriorFrame)
        }
        private func pending(field: MarinaTurnPatch.TargetField, name: String, includePriorFrame: Bool) throws -> MarinaConversationMemory {
            var memory = MarinaConversationMemory(workspaceID: workspace.id, chatID: UUID())
            if includePriorFrame {
                let result = try service.execute(request)
                let frame = memory.commitCompletedFrame(request: request, result: result, answerID: UUID(), prompt: "Previous spending question")
                #expect(frame != nil)
            }
            var pendingRequest = request
            if field == .card { pendingRequest.cardID = nil }
            let compilation = MarinaRequestCompiler.Compilation(capability: .transactions, request: pendingRequest, dateOrigin: .explicit,
                unresolvedTargets: [.init(id: "target", field: field, name: name, isComparison: false, source: .userText(name))])
            let lookup = MarinaDataRequest(tool: .findRecords, allTime: true, search: name)
            var result = try service.execute(lookup)
            result.pendingRequest = pendingRequest
            #expect(result.status == "candidates")
            memory.record(request: lookup, result: result, answerID: UUID(), prompt: "Show Parcel expenses on Blue Card in September.")
            let saved = memory.setPendingCompilation(compilation)
            #expect(saved)
            return memory
        }
        func turn(memory: MarinaConversationMemory, prompt: String,
                  narrate: @escaping (MarinaNarrationAct, String, [MarinaNarrationEvidence]) async -> MarinaNarrationDraft) -> MarinaCompiledTurn {
            MarinaCompiledTurn(service: service, bridge: bridge, memory: memory, history: [], prompt: prompt,
                answerID: UUID(), now: Self.date(month: 10, day: 23), budget: .init(capacity: 4096), onUpdate: { _ in }, narrate: narrate)
        }
        static func date(month: Int, day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day))!
        }
    }
}
#endif
