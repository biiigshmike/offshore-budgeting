import Foundation
import SwiftData
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels

@Suite(.serialized)
@MainActor
struct MarinaFoundationModelSemanticCompilerTests {
    typealias Generated = MarinaFoundationModelGeneratedOutcomeV3

    @Test func contextualCompilerFailuresExposeStableCodes() {
        expectInvalid(
            .emptyNamedBudget,
            outcome: .query(.category(.init(action: .availabilitySummary(.init(
                selection: selection(boundary: .explicitNamedBudget("   "))
            )))))
        )
        expectInvalid(
            .emptyTarget,
            outcome: .query(.card(.init(action: .count(.init(selection: selection(
                target: Generated.NamedTarget(wording: "\n", classification: .unresolved)
            ))))))
        )
        expectInvalid(
            .emptyComparisonTarget,
            outcome: .query(.income(.init(action: .compare(.init(
                measure: .incomeAmount,
                state: .actual,
                selection: .init(
                    selection: selection(),
                    comparisonTarget: Generated.NamedTarget(
                        wording: " ",
                        classification: .inferred(.incomeSource)
                    )
                )
            )))))
        )
        expectInvalid(
            .emptyNamedFilter,
            outcome: .query(.category(.init(action: .count(.init(selection: selection(filters: [
                Generated.NamedFilter(kind: .category, value: " ", evidence: .explicit)
            ]))))))
        )
        expectInvalid(
            .invalidResultLimit,
            outcome: .query(variableExpenseList(resultLimit: HomeQuery.maxResultLimit + 1))
        )
        expectInvalid(
            .dateContextWithoutPriorRequest,
            outcome: .query(variableExpenseList(date: .conversationContext(.currentMonth)))
        )
        expectInvalid(
            .continuationWithoutContext,
            outcome: .query(variableExpenseList(continuation: .showMore))
        )
        expectInvalid(
            .continuationWithoutOffset,
            outcome: .query(variableExpenseList(continuation: .showMore)),
            conversationContext: priorConversationContext(nextOffset: nil)
        )
        expectInvalid(
            .clarificationSelectionWithoutContext,
            outcome: .clarificationSelection(Generated.ClarificationSelection(index: 0))
        )
        let nonExecutableFollowUp = MarinaFollowUpSuggestion(
            title: "Narrow it down",
            prompt: "Narrow it down.",
            reason: .breakdown,
            executionMode: .clarificationRequired
        )
        expectInvalid(
            .followUpAcceptanceWithoutExecutableRequest,
            outcome: .followUpDecision(Generated.FollowUpDecision(decision: .accept)),
            conversationContext: followUpConversationContext(followUp: nonExecutableFollowUp)
        )
    }

    @Test func clarificationSelectionUsesExactExecutableChoicePatch() throws {
        let workspaceID = UUID()
        let first = clarificationChoice(
            title: "Apple Store",
            entity: .variableExpense,
            sourceID: UUID(),
            workspaceID: workspaceID
        )
        let secondID = UUID()
        let second = clarificationChoice(
            title: "Apple Card",
            entity: .card,
            sourceID: secondID,
            workspaceID: workspaceID
        )
        let context = clarificationConversationContext(choices: [first, second])
        let turn = MarinaSemanticCompilerTurnV3(userInput: "the second one", conversationContext: context)

        let request = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: .clarificationSelection(Generated.ClarificationSelection(index: 1)),
            turn: turn
        ).request

        #expect(request == second.executableRequest)
        #expect(request.resolvedTarget?.id == secondID)
        #expect(request.resolvedTarget?.provenance == .clarificationChoice)
        #expect(request.resolvedScope == .workspace(workspaceID))
    }

    @Test func clarificationSelectionOutOfBoundsIsTypedFailure() {
        let choice = clarificationChoice(
            title: "Apple Card",
            entity: .card,
            sourceID: UUID(),
            workspaceID: UUID()
        )
        let turn = MarinaSemanticCompilerTurnV3(
            userInput: "option six",
            conversationContext: clarificationConversationContext(choices: [choice])
        )

        do {
            _ = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
                from: .clarificationSelection(Generated.ClarificationSelection(index: 5)),
                turn: turn
            )
            Issue.record("Expected an out-of-bounds clarification selection failure.")
        } catch let error as MarinaFoundationModelInterpretationError {
            #expect(error == .invalidGeneratedOutcome(.clarificationSelectionOutOfBounds))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func followUpAcceptanceUsesExactStoredRequestWithoutExposingIdentifiers() throws {
        let privateID = UUID()
        let storedRequest = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: .previousMonth,
            targetName: "Food & Drink",
            resolvedTarget: MarinaResolvedEntityReference(
                entity: .category,
                id: privateID,
                displayName: "Food & Drink",
                provenance: .candidateResolver
            ),
            resolvedScope: .workspace(privateID),
            continuationIntent: .showMore,
            resultLimit: 5,
            resultOffset: 5,
            expenseScope: .unified,
            expectedAnswerShape: .list
        )
        let followUp = MarinaFollowUpSuggestion(
            title: "Show more",
            prompt: "SECRET STORED PROMPT",
            reason: .showMore,
            executionMode: .executable,
            semanticRequest: storedRequest,
            remainingResultCount: 3
        )
        let turn = MarinaSemanticCompilerTurnV3(
            userInput: "yes",
            conversationContext: followUpConversationContext(followUp: followUp)
        )

        let interpreted = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: .followUpDecision(Generated.FollowUpDecision(decision: .accept)),
            turn: turn
        )

        #expect(interpreted.request == storedRequest)
        #expect(interpreted.request.resolvedTarget?.id == privateID)
        #expect(interpreted.source == .foundationModel)
        #expect(turn.offeredFollowUp == followUp)
        #expect(turn.prompt.contains("Trusted offered follow-up:"))
        #expect(turn.prompt.contains("decisionOptions=accept,decline"))
        #expect(turn.prompt.contains("Want to see the remaining 3?"))
        #expect(turn.prompt.contains(privateID.uuidString) == false)
        #expect(turn.prompt.contains("SECRET STORED PROMPT") == false)
    }

    @Test func followUpDeclineCompilesToInternalAcknowledgement() throws {
        let followUp = MarinaFollowUpSuggestion(
            title: "Show more",
            prompt: "Show more.",
            reason: .showMore,
            executionMode: .executable,
            semanticRequest: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .list,
                measure: .budgetImpact,
                expectedAnswerShape: .list
            )
        )
        let turn = MarinaSemanticCompilerTurnV3(
            userInput: "no",
            conversationContext: followUpConversationContext(followUp: followUp)
        )

        let interpreted = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: .followUpDecision(Generated.FollowUpDecision(decision: .decline)),
            turn: turn
        )

        #expect(interpreted.request.entity == .workspace)
        #expect(interpreted.request.expectedAnswerShape == .acknowledgement)
        #expect(interpreted.request.unsupportedReason == nil)
        #expect(interpreted.diagnosticNotes.contains("FoundationModels V3 followUpDecision=decline."))
    }

    @Test func followUpDecisionWithoutTrustedOfferIsTypedFailure() {
        let turn = MarinaSemanticCompilerTurnV3(userInput: "yes", conversationContext: .empty)

        do {
            _ = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
                from: .followUpDecision(Generated.FollowUpDecision(decision: .accept)),
                turn: turn
            )
            Issue.record("Expected a follow-up decision without context failure.")
        } catch let error as MarinaFoundationModelInterpretationError {
            #expect(error == .invalidGeneratedOutcome(.followUpDecisionWithoutContext))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func promptContextIsBoundedSemanticDataWithoutIDsOrRawHistory() {
        let privateID = UUID()
        let request = MarinaSemanticRequest(
            entity: .card,
            operation: .list,
            measure: .budgetImpact,
            projection: .records,
            constraints: [MarinaSemanticConstraint(dimension: .budget, value: "Summer Budget")],
            dateRangeToken: .currentMonth,
            dateRangeSource: .explicit,
            targetName: "Apple Card",
            resolvedTarget: MarinaResolvedEntityReference(
                entity: .card,
                id: privateID,
                displayName: "Apple Card",
                provenance: .candidateResolver
            ),
            resolvedScope: .budget(privateID),
            continuationIntent: .none,
            resultLimit: 5,
            expectedAnswerShape: .list
        )
        let semanticContext = MarinaAnswerSemanticContext(
            request: request,
            dateRange: HomeQueryDateRange(startDate: date(2026, 7, 1), endDate: date(2026, 7, 31)),
            comparisonDateRange: nil,
            answerKind: .list,
            answerTitle: "Do not include this answer title",
            answerSubtitle: "Do not include this subtitle",
            primaryValue: "$private",
            rowReferences: [],
            displayedRowCount: 5,
            totalRowCount: 12,
            hasMore: true,
            nextOffset: 5
        )
        let conversation = MarinaConversationContext(recentTurns: [
            MarinaConversationTurn(
                userPrompt: "SECRET RAW PRIOR USER HISTORY",
                title: "Do not include this turn title",
                kind: .list,
                subtitle: nil,
                primaryValue: nil,
                rowTitles: ["Private row"],
                semanticContext: semanticContext,
                recommendedFollowUp: nil
            )
        ])

        let turn = MarinaSemanticCompilerTurnV3(userInput: "show more", conversationContext: conversation)

        #expect(turn.prompt.contains("entity=card"))
        #expect(turn.prompt.contains("resolvedDate=2026-07-01...2026-07-31"))
        #expect(turn.prompt.contains("nextOffset=5"))
        #expect(turn.prompt.contains("show more"))
        #expect(turn.prompt.contains(privateID.uuidString) == false)
        #expect(turn.prompt.contains("SECRET RAW PRIOR USER HISTORY") == false)
        #expect(turn.prompt.contains("Private row") == false)
        #expect(turn.continuationOffset == 5)
    }

    @Test func showMoreOffsetComesOnlyFromTrustedConversationContext() throws {
        let request = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: .query(variableExpenseList(resultLimit: 5, continuation: .showMore)),
            turn: MarinaSemanticCompilerTurnV3(
                userInput: "show more",
                conversationContext: priorConversationContext(nextOffset: 5)
            )
        ).request

        #expect(request.continuationIntent == .showMore)
        #expect(request.resultOffset == 5)
        #expect(request.resultLimit == 5)
    }

    @Test func clarificationPromptContainsOnlyBoundedDisplayMetadata() {
        let sourceID = UUID()
        let workspaceID = UUID()
        let choices = (0..<8).map { index in
            clarificationChoice(
                title: "Choice \(index)",
                entity: .card,
                sourceID: index == 0 ? sourceID : UUID(),
                workspaceID: workspaceID
            )
        }

        let turn = MarinaSemanticCompilerTurnV3(
            userInput: "the first one",
            conversationContext: clarificationConversationContext(choices: choices)
        )

        #expect(turn.clarificationChoices.count == 6)
        #expect(turn.prompt.contains("0: Choice 0 | Card | Exact workspace match"))
        #expect(turn.prompt.contains("5: Choice 5 | Card | Exact workspace match"))
        #expect(turn.prompt.contains("Choice 6") == false)
        #expect(turn.prompt.contains(sourceID.uuidString) == false)
        #expect(turn.prompt.contains(workspaceID.uuidString) == false)
    }

    @Test func injectableRuntimeReceivesOnlyNormalizedPromptAndLocale() async throws {
        let query = runtimeVariableExpenseMetric(
            target: MarinaFoundationModelGeneratedOutcomeV3.NamedTarget(
                wording: "Apple Card",
                classification: .explicit(.card)
            ),
            dateSelection: .explicit(.currentMonth)
        )
        let runtime = RecordingRuntime(result: .generated(.query(query), diagnosticNotes: ["fixture"]))
        let context = try brainContext()
        let userInput = "  UNIQUE\tUSER TEXT: show Cafe\u{301} Card  "
        let normalizedInput = MarinaPromptNormalizer.normalize(userInput)

        let interpreted = try await MarinaFoundationModelsInterpreter(
            runtime: runtime,
            localeConfiguration: MarinaFoundationModelLocaleConfiguration(locale: Locale(identifier: "en_US"))
        ).interpretedSemanticRequest(for: userInput, context: context)
        let recordedCall = runtime.lastCall()
        let call = try #require(recordedCall)

        #expect(interpreted.request.entity == .variableExpense)
        #expect(interpreted.source == .foundationModel)
        #expect(call.prompt.contains(normalizedInput))
        #expect(call.prompt.contains(userInput) == false)
        #expect(call.localeIdentifier == "en_US")
        #expect(
            Mirror(reflecting: call).children.compactMap(\.label)
                == ["prompt", "localeIdentifier"]
        )
    }

    @Test func injectedDecodingFailureReturnsTypedGenerationFailure() async throws {
        let runtime = RecordingRuntime(
            result: .generationFailure(.decodingFailure, diagnosticNotes: ["fixture decode failure"])
        )

        let interpreted = try await MarinaFoundationModelsInterpreter(runtime: runtime)
            .interpretedSemanticRequest(for: "show spending", context: brainContext())

        #expect(interpreted.request.expectedAnswerShape == .unsupported)
        #expect(interpreted.request.unsupportedReason == .modelGenerationFailed)
        #expect(interpreted.source == .unavailableFallback)
        #expect(runtime.callCount == 2)
        #expect(interpreted.attemptDiagnostics.map(\.status) == [.rejected, .terminal])
        #expect(interpreted.attemptDiagnostics.map(\.rejectionCode) == [
            "generation.decodingFailure",
            "generation.decodingFailure"
        ])
    }

    @Test func compilerInvalidOutcomeRetriesOnceThenAcceptsFreshGeneratedOutcome() async throws {
        let invalid = runtimeVariableExpenseMetric(
            target: MarinaFoundationModelGeneratedOutcomeV3.NamedTarget(
                wording: "   ",
                classification: .explicit(.card)
            )
        )
        let valid = runtimeVariableExpenseMetric(
            target: MarinaFoundationModelGeneratedOutcomeV3.NamedTarget(
                wording: "Apple Card",
                classification: .explicit(.card)
            ),
            dateSelection: .explicit(.currentMonth)
        )
        let runtime = RecordingRuntime(results: [
            .generated(.query(invalid), diagnosticNotes: ["attempt one"]),
            .generated(.query(valid), diagnosticNotes: ["attempt two"])
        ])

        let interpreted = try await MarinaFoundationModelsInterpreter(runtime: runtime)
            .interpretedSemanticRequest(for: "Apple Card this month", context: brainContext())

        #expect(interpreted.source == .foundationModel)
        #expect(interpreted.request.targetName == "Apple Card")
        #expect(runtime.callCount == 2)
        #expect(interpreted.attemptDiagnostics.map(\.status) == [.rejected, .accepted])
        #expect(interpreted.attemptDiagnostics.first?.rejectionCode == "compiler.emptyTarget")
        let calls = runtime.allCalls()
        #expect(calls[1].prompt.contains("rejectionCode=compiler.emptyTarget"))
        #expect(calls[1].prompt.contains("Apple Card") == true)
    }

    @Test func decodingFailureRetriesOnceThenAcceptsFreshGeneratedOutcome() async throws {
        let runtime = RecordingRuntime(results: [
            .generationFailure(.decodingFailure, diagnosticNotes: ["attempt one"]),
            .generated(.query(runtimeVariableExpenseList()), diagnosticNotes: ["attempt two"])
        ])

        let interpreted = try await MarinaFoundationModelsInterpreter(runtime: runtime)
            .interpretedSemanticRequest(for: "show spending", context: brainContext())

        #expect(interpreted.source == .foundationModel)
        #expect(runtime.callCount == 2)
        #expect(interpreted.attemptDiagnostics.map(\.stage) == [.generation, .alignment])
        #expect(interpreted.attemptDiagnostics.map(\.status) == [.rejected, .accepted])
        #expect(runtime.allCalls()[1].prompt.contains("rejectionCode=generation.decodingFailure"))
    }

    @Test func retryPromptNeverContainsRejectedGeneratedOutput() async throws {
        let rejectedOnlyValue = "REJECTED-OUTPUT-ONLY-7F32A9"
        let invalid = Generated.Query.variableExpense(.init(action: .sum(.init(
            measure: .budgetImpact,
            selection: selection(
                target: .init(
                    wording: rejectedOnlyValue,
                    classification: .explicit(.merchantText)
                ),
                filters: [
                    .init(kind: .category, value: "   ", evidence: .explicit)
                ]
            ),
            expenseScope: .variable
        ))))
        let valid = runtimeVariableExpenseMetric(
            target: .init(wording: "Apple Card", classification: .explicit(.card))
        )
        let runtime = RecordingRuntime(results: [
            .generated(.query(invalid), diagnosticNotes: []),
            .generated(.query(valid), diagnosticNotes: [])
        ])

        _ = try await MarinaFoundationModelsInterpreter(runtime: runtime)
            .interpretedSemanticRequest(for: "Apple Card spending", context: brainContext())

        let retryPrompt = try #require(runtime.allCalls().last?.prompt)
        #expect(retryPrompt.contains("rejectionCode=compiler.emptyNamedFilter"))
        #expect(retryPrompt.contains(rejectedOnlyValue) == false)
    }

    @Test func inconclusiveAlignmentReturnsExactlyTheModelCompiledRequestWithoutSynthesis() async throws {
        let prompt = "Could you take a look at this activity?"
        let generated = runtimeVariableExpenseMetric(
            operation: .average,
            measure: .ledgerSignedAmount,
            target: MarinaFoundationModelGeneratedOutcomeV3.NamedTarget(
                wording: "Private Card F5A2",
                classification: .inferred(.card)
            ),
            dateSelection: .explicit(.yearToDate),
            expenseScope: .variable
        )
        let turn = MarinaSemanticCompilerTurnV3(
            userInput: prompt,
            conversationContext: .empty
        )
        let expected = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: .query(generated),
            turn: turn
        ).request
        let runtime = RecordingRuntime(
            result: .generated(.query(generated), diagnosticNotes: ["fixture"])
        )

        let interpreted = try await MarinaFoundationModelsInterpreter(runtime: runtime)
            .interpretedSemanticRequest(for: prompt, context: brainContext())

        #expect(interpreted.request == expected)
        #expect(interpreted.attemptDiagnostics.count == 1)
        #expect(interpreted.attemptDiagnostics.first?.alignmentVerdict == .inconclusive)
        #expect(interpreted.attemptDiagnostics.first?.generatedIntent != nil)
        #expect(interpreted.attemptDiagnostics.first?.compiledRequest == MarinaFoundationModelCompiledRequestDigest(request: expected))
        #expect(interpreted.attemptDiagnostics.first?.diagnosticNote.contains("Private Card F5A2") == false)
    }

    @Test func unrelatedValidStarterOutcomeRetriesThenAcceptsAlignedOutcome() async throws {
        let unrelated = MarinaFoundationModelGeneratedOutcomeV3.Query.workspaceMetadata(
            .init(action: .name(.init()))
        )
        let aligned = runtimeCategoryAvailabilitySummary()
        let runtime = RecordingRuntime(results: [
            .generated(.query(unrelated), diagnosticNotes: ["unrelated"]),
            .generated(.query(aligned), diagnosticNotes: ["aligned"])
        ])

        let interpreted = try await MarinaFoundationModelsInterpreter(runtime: runtime)
            .interpretedSemanticRequest(for: "Show category availability.", context: brainContext())

        #expect(interpreted.source == .foundationModel)
        #expect(interpreted.request.entity == .category)
        #expect(interpreted.request.measure == .categoryAvailability)
        #expect(interpreted.attemptDiagnostics.map(\.stage) == [.alignment, .alignment])
        #expect(interpreted.attemptDiagnostics.map(\.status) == [.rejected, .accepted])
        #expect(interpreted.attemptDiagnostics.first?.rejectionCode == "alignment.entityMismatch")
        let calls = runtime.allCalls()
        #expect(calls[1].prompt.contains("rejectionCode=alignment.entityMismatch"))
        #expect(calls[1].prompt.contains("expected={") == false)
        #expect(calls[1].prompt.contains("actual={") == false)
        #expect(calls[1].prompt.contains("entity=category") == false)
        #expect(calls[1].prompt.contains("measure=categoryAvailability") == false)
        let expected = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: .query(aligned),
            turn: MarinaSemanticCompilerTurnV3(
                userInput: "Show category availability.",
                conversationContext: .empty
            )
        ).request
        #expect(interpreted.request == expected)
    }

    @Test func twoUnrelatedValidStarterOutcomesTerminateWithoutExecutionRequest() async throws {
        let unrelated = MarinaFoundationModelGeneratedOutcomeV3.Query.workspaceMetadata(
            .init(action: .name(.init()))
        )
        let runtime = RecordingRuntime(result: .generated(.query(unrelated), diagnosticNotes: ["unrelated"]))

        let interpreted = try await MarinaFoundationModelsInterpreter(runtime: runtime)
            .interpretedSemanticRequest(for: "Show category availability.", context: brainContext())

        #expect(interpreted.request.expectedAnswerShape == .unsupported)
        #expect(interpreted.request.unsupportedReason == .modelGenerationFailed)
        #expect(interpreted.source == .unavailableFallback)
        #expect(runtime.callCount == 2)
        #expect(interpreted.attemptDiagnostics.map(\.status) == [.rejected, .terminal])
        #expect(interpreted.attemptDiagnostics.map(\.rejectionCode) == [
            "alignment.entityMismatch",
            "alignment.entityMismatch"
        ])
    }

    @Test func unsupportedGuideCancellationAndAvailabilityDoNotRetry() async throws {
        let results: [MarinaFoundationModelRuntimeResult] = [
            .generationFailure(.unsupportedGuide, diagnosticNotes: []),
            .generationFailure(.cancelled, diagnosticNotes: []),
            .unsupported(.unavailableModel, diagnosticNotes: [])
        ]

        for result in results {
            let runtime = RecordingRuntime(result: result)
            _ = try await MarinaFoundationModelsInterpreter(runtime: runtime)
                .interpretedSemanticRequest(for: "show spending", context: brainContext())
            #expect(runtime.callCount == 1)
        }
    }

    @Test func validReadOnlyOutcomeDoesNotRetry() async throws {
        let runtime = RecordingRuntime(result: .generated(
            .unsupported(MarinaFoundationModelGeneratedOutcomeV3.Unsupported(
                reason: .readOnly,
                subject: .card,
                attemptedOperation: .list,
                attemptedMeasure: .name
            )),
            diagnosticNotes: ["read-only fixture"]
        ))

        let interpreted = try await MarinaFoundationModelsInterpreter(runtime: runtime)
            .interpretedSemanticRequest(for: "Delete my Apple Card.", context: brainContext())

        #expect(runtime.callCount == 1)
        #expect(interpreted.source == .foundationModel)
        #expect(interpreted.request.expectedAnswerShape == .unsupported)
        #expect(interpreted.request.unsupportedReason == .readOnly)
        #expect(interpreted.attemptDiagnostics.map(\.status) == [.accepted])
    }

    @Test func injectedOutOfBoundsSelectionReturnsTypedGenerationFailure() async throws {
        let choice = clarificationChoice(
            title: "Apple Card",
            entity: .card,
            sourceID: UUID(),
            workspaceID: UUID()
        )
        let runtime = RecordingRuntime(
            result: .generated(
                .clarificationSelection(MarinaFoundationModelGeneratedOutcomeV3.ClarificationSelection(index: 5)),
                diagnosticNotes: ["fixture selection"]
            )
        )

        let interpreted = try await MarinaFoundationModelsInterpreter(runtime: runtime)
            .interpretedSemanticRequest(
                for: "option six",
                context: brainContext(
                    conversationContext: clarificationConversationContext(choices: [choice])
                )
            )

        #expect(interpreted.request.expectedAnswerShape == .unsupported)
        #expect(interpreted.request.unsupportedReason == .modelGenerationFailed)
        #expect(interpreted.source == .unavailableFallback)
        #expect(runtime.callCount == 2)
        #expect(interpreted.attemptDiagnostics.map(\.rejectionCode) == [
            "compiler.clarificationSelectionOutOfBounds",
            "compiler.clarificationSelectionOutOfBounds"
        ])
        #expect(interpreted.diagnosticNotes.contains { note in
            note.contains("rejectionCode=compiler.clarificationSelectionOutOfBounds")
        })
    }

    @Test func injectableRuntimePreservesAvailabilityLocaleAndGuardrailReasons() async throws {
        let context = try brainContext()
        let reasons: [MarinaSemanticUnsupportedReason] = [
            .unavailableModel,
            .unsupportedLanguageOrLocale,
            .modelGuardrail,
            .modelContextLimit
        ]

        for reason in reasons {
            let runtime = RecordingRuntime(
                result: .unsupported(reason, diagnosticNotes: ["fixture \(reason.rawValue)"])
            )
            let interpreted = try await MarinaFoundationModelsInterpreter(runtime: runtime)
                .interpretedSemanticRequest(for: "show spending", context: context)

            #expect(interpreted.request.expectedAnswerShape == .unsupported)
            #expect(interpreted.request.unsupportedReason == reason)
            #expect(interpreted.source == .unavailableFallback)
            #expect(runtime.callCount == 1)
        }
    }

    @Test func typedUnsupportedPreservesGeneratedSubjectAndAttemptedOperation() throws {
        let unsupported = Generated.Unsupported(
            reason: .readOnly,
            subject: .category,
            attemptedOperation: .list,
            attemptedMeasure: .name
        )

        let request = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: .unsupported(unsupported),
            turn: MarinaSemanticCompilerTurnV3(userInput: "rename Groceries", conversationContext: .empty)
        ).request

        #expect(request.entity == .category)
        #expect(request.operation == .list)
        #expect(request.measure == .name)
        #expect(request.expectedAnswerShape == .unsupported)
        #expect(request.unsupportedReason == .readOnly)
    }

    private func runtimeVariableExpenseMetric(
        operation: MarinaSemanticOperation = .sum,
        measure: MarinaFoundationModelGeneratedOutcomeV3.VariableExpenseMeasure = .budgetImpact,
        target: MarinaFoundationModelGeneratedOutcomeV3.NamedTarget? = nil,
        dateSelection: MarinaFoundationModelGeneratedOutcomeV3.DateSelection = .defaultCurrentPeriod,
        expenseScope: MarinaFoundationModelGeneratedOutcomeV3.ExpenseScope = .variable
    ) -> MarinaFoundationModelGeneratedOutcomeV3.Query {
        let metric = MarinaFoundationModelGeneratedOutcomeV3.VariableExpenseMetric(
            measure: measure,
            selection: selection(target: target, date: dateSelection),
            expenseScope: expenseScope
        )
        let action: MarinaFoundationModelGeneratedOutcomeV3.VariableExpenseAction = switch operation {
        case .sum: .sum(metric)
        case .average: .average(metric)
        default: .sum(metric)
        }
        return .variableExpense(.init(action: action))
    }

    private func runtimeVariableExpenseList() -> MarinaFoundationModelGeneratedOutcomeV3.Query {
        .variableExpense(.init(action: .list(.init(
            measure: .budgetImpact,
            selection: selection(),
            modifiers: .init(sort: nil, resultLimit: nil, continuation: .none),
            expenseScope: .variable
        ))))
    }

    private func runtimeCategoryAvailabilitySummary() -> MarinaFoundationModelGeneratedOutcomeV3.Query {
        .category(.init(action: .availabilitySummary(.init(
            selection: selection()
        ))))
    }

    private func selection(
        boundary: Generated.DataBoundary = .activeWorkspace,
        target: MarinaFoundationModelGeneratedOutcomeV3.NamedTarget? = nil,
        filters: [Generated.NamedFilter] = [],
        date: MarinaFoundationModelGeneratedOutcomeV3.DateSelection = .defaultCurrentPeriod
    ) -> MarinaFoundationModelGeneratedOutcomeV3.Selection {
        .init(
            dataBoundary: boundary,
            target: target,
            namedFilters: filters,
            dateSelection: date
        )
    }

    private func variableExpenseList(
        date: Generated.DateSelection = .defaultCurrentPeriod,
        resultLimit: Int? = nil,
        continuation: Generated.Continuation = .none,
        sort: Generated.Sort? = .amountDescending
    ) -> Generated.Query {
        .variableExpense(.init(action: .list(.init(
            measure: .budgetImpact,
            selection: selection(date: date),
            modifiers: .init(
                sort: sort,
                resultLimit: resultLimit,
                continuation: continuation
            ),
            expenseScope: .unified
        ))))
    }

    private func expectInvalid(
        _ expected: MarinaFoundationModelInvalidOutcome,
        outcome: Generated,
        conversationContext: MarinaConversationContext = .empty
    ) {
        do {
            _ = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
                from: outcome,
                turn: MarinaSemanticCompilerTurnV3(
                    userInput: "fixture",
                    conversationContext: conversationContext
                )
            )
            Issue.record("Expected compiler rejection \(expected.rejectionCode).")
        } catch let error as MarinaFoundationModelInterpretationError {
            #expect(error == .invalidGeneratedOutcome(expected))
            #expect(error.rejectionCode == expected.rejectionCode)
            #expect(error.localizedDescription.contains(expected.rejectionCode))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func clarificationChoice(
        title: String,
        entity: MarinaSemanticEntity,
        sourceID: UUID,
        workspaceID: UUID
    ) -> MarinaClarificationChoice {
        let reference = MarinaResolvedEntityReference(
            entity: entity,
            id: sourceID,
            displayName: title,
            provenance: .clarificationChoice
        )
        let request = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            targetName: title,
            expectedAnswerShape: .metric
        )
        return MarinaClarificationChoice(
            title: title,
            kindLabel: "Card",
            subtitle: "Exact workspace match",
            aliases: [title],
            targetPatch: MarinaClarificationTargetPatch(
                slot: .primary,
                reference: reference,
                scope: .workspace(workspaceID)
            ),
            request: request
        )
    }

    private func clarificationConversationContext(
        choices: [MarinaClarificationChoice]
    ) -> MarinaConversationContext {
        let request = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            targetName: "Apple",
            expectedAnswerShape: .clarification,
            clarificationQuestion: "Which Apple did you mean?"
        )
        let semanticContext = MarinaAnswerSemanticContext(
            request: request,
            dateRange: nil,
            comparisonDateRange: nil,
            answerKind: .message,
            answerTitle: "Can you clarify?",
            answerSubtitle: "Which Apple did you mean?",
            primaryValue: nil,
            rowReferences: []
        )
        return MarinaConversationContext(recentTurns: [
            MarinaConversationTurn(
                userPrompt: "Apple spending",
                title: "Can you clarify?",
                kind: .message,
                subtitle: "Which Apple did you mean?",
                primaryValue: nil,
                rowTitles: [],
                semanticContext: semanticContext,
                recommendedFollowUp: nil,
                clarificationOptions: choices
            )
        ])
    }

    private func followUpConversationContext(
        followUp: MarinaFollowUpSuggestion
    ) -> MarinaConversationContext {
        let request = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dateRangeToken: .previousMonth,
            resultLimit: 5,
            resultOffset: 0,
            expenseScope: .unified,
            expectedAnswerShape: .list
        )
        let semanticContext = MarinaAnswerSemanticContext(
            request: request,
            dateRange: nil,
            comparisonDateRange: nil,
            answerKind: .list,
            answerTitle: "Expenses",
            answerSubtitle: nil,
            primaryValue: nil,
            rowReferences: [],
            displayedRowCount: 5,
            totalRowCount: 8,
            hasMore: true,
            nextOffset: 5
        )
        return MarinaConversationContext(recentTurns: [
            MarinaConversationTurn(
                userPrompt: "Show expenses",
                title: "Expenses",
                kind: .list,
                subtitle: nil,
                primaryValue: nil,
                rowTitles: [],
                semanticContext: semanticContext,
                recommendedFollowUp: followUp
            )
        ])
    }

    private func priorConversationContext(nextOffset: Int?) -> MarinaConversationContext {
        let request = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            resultLimit: 5,
            expectedAnswerShape: .list
        )
        let semanticContext = MarinaAnswerSemanticContext(
            request: request,
            dateRange: nil,
            comparisonDateRange: nil,
            answerKind: .list,
            answerTitle: "Expenses",
            answerSubtitle: nil,
            primaryValue: nil,
            rowReferences: [],
            displayedRowCount: 5,
            totalRowCount: 5,
            hasMore: nextOffset != nil,
            nextOffset: nextOffset
        )
        return MarinaConversationContext(recentTurns: [
            MarinaConversationTurn(
                userPrompt: "Show expenses",
                title: "Expenses",
                kind: .list,
                subtitle: nil,
                primaryValue: nil,
                rowTitles: [],
                semanticContext: semanticContext,
                recommendedFollowUp: nil
            )
        ])
    }

    private func brainContext(
        conversationContext: MarinaConversationContext = .empty
    ) throws -> MarinaBrainContext {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            BudgetCategoryLimit.self,
            Card.self,
            BudgetCardLink.self,
            BudgetPresetLink.self,
            Category.self,
            Preset.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            MarinaChatSession.self,
            IncomeSeries.self,
            Income.self
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let workspace = Workspace(name: "Personal", hexColor: "#2563EB")
        context.insert(workspace)
        return MarinaBrainContext(
            workspace: workspace,
            modelContext: context,
            ambientDateRange: HomeQueryDateRange(
                startDate: date(2026, 7, 1),
                endDate: date(2026, 7, 31)
            ),
            defaultBudgetingPeriod: .monthly,
            now: date(2026, 7, 13),
            conversationContext: conversationContext
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        ) ?? .now
    }
}

@MainActor
private final class RecordingRuntime: MarinaFoundationModelGenerating {
    struct Call: Equatable, Sendable {
        let prompt: String
        let localeIdentifier: String
    }

    private let results: [MarinaFoundationModelRuntimeResult]
    private var calls: [Call] = []

    init(result: MarinaFoundationModelRuntimeResult) {
        results = [result]
    }

    init(results: [MarinaFoundationModelRuntimeResult]) {
        self.results = results
    }

    func generateOutcome(
        for prompt: String,
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async -> MarinaFoundationModelRuntimeResult {
        calls.append(Call(
            prompt: prompt,
            localeIdentifier: localeConfiguration.identifier
        ))
        let resultIndex = min(calls.count - 1, results.count - 1)
        return results[resultIndex]
    }

    func lastCall() -> Call? {
        calls.last
    }

    func allCalls() -> [Call] {
        calls
    }

    var callCount: Int {
        calls.count
    }
}
#endif
