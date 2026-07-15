import Foundation
import Testing
@testable import Offshore

@Suite(.serialized)
@MainActor
struct MarinaFoundationModelReleaseCorpusV1Tests {
    private typealias Corpus = MarinaFoundationModelReleaseCorpusV1

    @Test func inventoryHasExactReleaseCounts() {
        let inventory = Corpus.inventory

        #expect(inventory.version == Corpus.version)
        #expect(inventory.englishSingleTurnCount == 120)
        #expect(inventory.multiTurnCount == 40)
        #expect(inventory.safetyNegativeCount == 40)
        #expect(inventory.localizedCount == 72)
        #expect(inventory.totalCount == 272)
        #expect(inventory.localizedCountsByLocale == [
            "es": 12,
            "fr": 12,
            "de": 12,
            "ar": 12,
            "pt-BR": 12,
            "zh-Hans": 12
        ])
    }

    @Test func everyReleaseTopicIsCoveredAndIdentifiersAreUnique() {
        let coveredTopics = Set(Corpus.allCases.flatMap(\.topics))
        let identifiers = Corpus.allCases.map(\.id)

        #expect(coveredTopics == Set(Corpus.Topic.allCases))
        #expect(Set(identifiers).count == Corpus.allCases.count)
        #expect(Corpus.allCases.allSatisfy { $0.turns.isEmpty == false })
        #expect(Corpus.allCases.allSatisfy { $0.turns.allSatisfy { $0.isEmpty == false } })
        #expect(Corpus.safetyNegative.allSatisfy {
            if case .unsupported = $0.expectedOutcome { return true }
            return false
        })
    }

    @Test func blockingEnglishInventoryContainsEveryStarterAndUniqueTraceRegression() throws {
        #expect(Corpus.blockingEnglish.count == 10)
        #expect(Set(Corpus.blockingEnglish.map(\.id)).count == 10)

        let prompts = Set(Corpus.blockingEnglish.map(\.currentPrompt))
        #expect(prompts == Set(MarinaStarterPromptCatalog.baseEntries.map(\.defaultValue) + [
            "Summarize my Evaluation Card.",
            "Which categories were over the limit for last month?",
            "What is my income for the current period?"
        ]))

        for testCase in Corpus.blockingEnglish.prefix(8) {
            let match = try #require(MarinaStarterPromptCatalog.match(
                prompt: testCase.currentPrompt,
                localeIdentifier: "en"
            ))
            guard case let .semantic(tuple) = testCase.expectedOutcome else {
                Issue.record("Blocking starter \(testCase.id) must remain semantic.")
                continue
            }
            #expect(tuple == Corpus.starterSemanticTuple(from: match.contract))
        }

        let safeSpend = try #require(Corpus.blockingEnglish.first {
            $0.currentPrompt == "What is my safe spend today?"
        })
        guard case let .semantic(tuple) = safeSpend.expectedOutcome else {
            Issue.record("Safe-spend starter must retain a semantic expectation.")
            return
        }
        #expect(tuple.entity == .budget)
        #expect(tuple.projection == .summary)
        #expect(tuple.operation == .forecast)
        #expect(tuple.measure == .safeDailySpend)
        #expect(tuple.dateRange == .currentPeriod)
        #expect(tuple.dateRangeSource == .defaulted)
    }

    @Test func localizedSafeSpendCasesUseTheProductionStarterAndDailyMeasure() throws {
        let safeSpendEntry = try #require(MarinaStarterPromptCatalog.baseEntries.first { $0.id == .safeSpend })
        for locale in ["ar", "de", "es", "fr", "pt-BR", "zh-Hans"] {
            let localizedCase = try #require(Corpus.localized.first {
                $0.localeIdentifier == locale && $0.currentPrompt == safeSpendEntry.prompt(localeIdentifier: locale)
            })
            guard case let .semantic(tuple) = localizedCase.expectedOutcome else {
                Issue.record("Localized safe-spend case must remain semantic for \(locale).")
                continue
            }
            #expect(tuple.measure == .safeDailySpend)
        }
    }

    @Test func corpusFixturesRoundTripThroughJSONWithoutLosingTypedExpectations() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Corpus.allCases)
        let decoded = try JSONDecoder().decode([Corpus.Case].self, from: data)

        #expect(decoded == Corpus.allCases)
        #expect(decoded.contains {
            if case .semantic = $0.expectedOutcome { return true }
            return false
        })
        #expect(decoded.contains {
            if case .unsupported(.readOnly) = $0.expectedOutcome { return true }
            return false
        })
    }

    @Test func highRiskCorpusCasesRetainTheCompleteSemanticContract() throws {
        let appleCard = try #require(Corpus.allCases.first { $0.id == "en-single-006-1" })
        let targetPurchase = try #require(Corpus.allCases.first { $0.id == "en-single-008-1" })
        let safeSpendWhatIf = try #require(Corpus.allCases.first { $0.id == "en-single-035-1" })
        let namedBudget = try #require(Corpus.allCases.first { $0.id == "en-single-037-1" })

        guard case let .semantic(appleTuple) = appleCard.expectedOutcome,
              case let .semantic(targetTuple) = targetPurchase.expectedOutcome,
              case let .semantic(whatIfTuple) = safeSpendWhatIf.expectedOutcome,
              case let .semantic(budgetTuple) = namedBudget.expectedOutcome else {
            Issue.record("High-risk release cases must remain semantic expectations.")
            return
        }

        #expect(appleTuple.target == .init("Apple Card", kind: .card, kindSource: .explicit))
        #expect(appleTuple.dateRange == .currentMonth)
        #expect(appleTuple.dateRangeSource == .explicit)
        #expect(appleTuple.expenseScope == .unified)

        #expect(targetTuple.target == .init("Target", kind: .merchantText, kindSource: .explicit))
        #expect(targetTuple.expenseScope == .variable)

        #expect(whatIfTuple.whatIfAmount == 50)
        #expect(whatIfTuple.target?.wording == "Target")
        #expect(whatIfTuple.answerShape == .comparison)

        #expect(budgetTuple.scope == .namedBudget("Vacation"))
        #expect(budgetTuple.constraints == [.init(.budget, "Vacation", kindSource: .explicit)])
    }

    @Test func corpusMatchingCanonicalizesOnlyWordingAndKeepsTypedValuesExact() {
        let expected = Corpus.ExpectedOutcome.semantic(.init(
            .category,
            .whatIf,
            .projectedSavings,
            target: .init("Groceries", kind: .category, kindSource: .inferred),
            dateRange: .currentMonth,
            dateRangeSource: .explicit,
            whatIfAmount: 200
        ))
        let canonicallyEquivalent = Corpus.ExpectedOutcome.semantic(.init(
            .category,
            .whatIf,
            .projectedSavings,
            target: .init("grocery", kind: .category, kindSource: .inferred),
            dateRange: .currentMonth,
            dateRangeSource: .explicit,
            whatIfAmount: 200
        ))
        let wrongAmount = Corpus.ExpectedOutcome.semantic(.init(
            .category,
            .whatIf,
            .projectedSavings,
            target: .init("grocery", kind: .category, kindSource: .inferred),
            dateRange: .currentMonth,
            dateRangeSource: .explicit,
            whatIfAmount: 201
        ))

        #expect(Corpus.outcomesMatch(expected: expected, actual: canonicallyEquivalent))
        #expect(Corpus.outcomesMatch(expected: expected, actual: wrongAmount) == false)
        #expect(Corpus.multiTurn.contains { $0.expectedOutcome == .followUpDecision(.accept) })
        #expect(Corpus.multiTurn.contains { $0.expectedOutcome == .followUpDecision(.decline) })
    }

    @Test func everySemanticExpectationIsBackedByThePublicCapabilityCatalog() {
        let catalog = MarinaEntityCatalog()

        for testCase in Corpus.allCases {
            guard case let .semantic(tuple) = testCase.expectedOutcome else { continue }

            if catalog.supports(entity: tuple.entity, projection: tuple.projection) != .supported {
                Issue.record("\(testCase.id) uses unsupported projection \(tuple.entity.rawValue).\(tuple.projection.rawValue).")
            }
            if catalog.supports(entity: tuple.entity, operation: tuple.operation) != .supported {
                Issue.record("\(testCase.id) uses unsupported operation \(tuple.entity.rawValue).\(tuple.operation.rawValue).")
            }
            if let measure = tuple.measure,
               catalog.supports(entity: tuple.entity, measure: measure) != .supported {
                Issue.record("\(testCase.id) uses unsupported measure \(tuple.entity.rawValue).\(measure.rawValue).")
            }
        }
    }

    @Test func realModelEvaluationScaffoldIsOptIn() async {
        var evaluationCalls = 0
        let disabled = await Corpus.evaluateWithRealModelIfEnabled(environment: [:]) { testCase in
            evaluationCalls += 1
            return Corpus.EvaluationObservation(
                caseID: testCase.id,
                actualOutcome: testCase.expectedOutcome,
                diagnosticNotes: []
            )
        }

        #expect(disabled == nil)
        #expect(evaluationCalls == 0)

        let enabled = await Corpus.evaluateWithRealModelIfEnabled(
            environment: [Corpus.realModelEvaluationEnvironmentKey: "1"]
        ) { testCase in
            evaluationCalls += 1
            return Corpus.EvaluationObservation(
                caseID: testCase.id,
                actualOutcome: testCase.expectedOutcome,
                diagnosticNotes: ["Injected fixture; no model invocation."]
            )
        }

        #expect(enabled?.corpusVersion == Corpus.version)
        #expect(enabled?.evaluatedCaseCount == 272)
        #expect(enabled?.exactMatchCount == 272)
        #expect(evaluationCalls == 272)
    }
}

#if canImport(FoundationModels)
import FoundationModels

@Suite(.serialized)
@MainActor
struct MarinaFoundationModelReleaseCorpusGeneratedFixtureTests {
    private typealias Corpus = MarinaFoundationModelReleaseCorpusV1
    private typealias Generated = MarinaFoundationModelGeneratedOutcomeV3

    @Test func typedGeneratedFixtureCompilesToCorpusSemanticTupleWithoutModelAccess() throws {
        let fixture = Generated.Query.workspaceMetadata(
            Generated.WorkspaceMetadataQuery(
                action: .name(Generated.WorkspaceMetadataValue())
            )
        )
        let interpreted = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: .query(fixture),
            turn: MarinaSemanticCompilerTurnV3(
                userInput: "What workspace am I in?",
                conversationContext: .empty
            )
        )
        let expected = try #require(Corpus.englishSingleTurn.first?.expectedOutcome)
        let expectedTuple: Corpus.SemanticTuple
        if case let .semantic(tuple) = expected {
            expectedTuple = tuple
        } else {
            Issue.record("The first English fixture must be semantic.")
            return
        }

        #expect(interpreted.request.entity == expectedTuple.entity)
        #expect(interpreted.request.projection == expectedTuple.projection)
        #expect(interpreted.request.operation == expectedTuple.operation)
        #expect(interpreted.request.measure == expectedTuple.measure)
        #expect(interpreted.request.dimensions == expectedTuple.dimensions)
        #expect(interpreted.request.expectedAnswerShape == expectedTuple.answerShape)
        #expect(interpreted.request.targetName == expectedTuple.target?.wording)
        #expect(interpreted.request.comparisonTargetName == expectedTuple.comparisonTarget?.wording)
        #expect(interpreted.request.dateRangeToken == expectedTuple.dateRange)
        #expect(interpreted.request.dateRangeSource == expectedTuple.dateRangeSource)
        #expect(interpreted.request.sort == expectedTuple.sort)
        #expect(interpreted.request.resultLimit == expectedTuple.requestedCount)
        #expect(interpreted.request.resultOffset == expectedTuple.resultOffset)
        #expect(interpreted.request.continuationIntent == expectedTuple.continuation)
        #expect(interpreted.request.expenseScope == expectedTuple.expenseScope)
        #expect(interpreted.request.incomeState == expectedTuple.incomeState)
        #expect(interpreted.request.whatIfAmount == expectedTuple.whatIfAmount)
        #expect(interpreted.request.categoryAvailabilityFilter == expectedTuple.categoryAvailabilityFilter)
    }
}
#endif
