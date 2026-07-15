import Foundation
import Testing
@testable import Offshore

@Suite(.serialized)
@MainActor
struct MarinaSemanticPromptAlignmentValidatorTests {
    private let validator = MarinaSemanticPromptAlignmentValidator()

    @Test func everyEnglishStarterHasOneSharedContractAndAcceptsItsExactRequest() throws {
        #expect(MarinaStarterPromptCatalog.baseEntries.count == 7)
        #expect(Set(MarinaStarterPromptCatalog.baseEntries.map(\.id)).count == 7)

        for entry in MarinaStarterPromptCatalog.baseEntries {
            let prompt = entry.prompt(localeIdentifier: "en")
            let match = try #require(MarinaStarterPromptCatalog.match(
                prompt: prompt,
                localeIdentifier: "en"
            ))
            #expect(match.id == entry.id)
            #expect(validator.validate(
                userInput: prompt,
                request: request(for: match.contract),
                localeIdentifier: "en"
            ) == .accepted(anchorID: "starter.\(entry.id.rawValue)"))
        }

        let cardPrompt = "Summarize my Evaluation Card."
        let cardMatch = try #require(MarinaStarterPromptCatalog.match(
            prompt: cardPrompt,
            localeIdentifier: "en"
        ))
        #expect(cardMatch.id == .cardSummary)
        #expect(cardMatch.contract.dimensions == [.card])
        #expect(validator.validate(
            userInput: cardPrompt,
            request: request(for: cardMatch.contract),
            localeIdentifier: "en"
        ) == .accepted(anchorID: "starter.cardSummary"))
    }

    @Test func starterFactoryConsumesTheSharedCatalog() {
        let expected = MarinaStarterPromptCatalog.baseEntries.map { $0.defaultValue }
        #expect(MarinaStarterPromptFactory.basePromptPool == expected)
        #expect(MarinaStarterPromptFactory.promptPool(cardNames: ["Evaluation Card"]) == expected + [
            "Summarize my Evaluation Card."
        ])
    }

    @Test func validButUnrelatedWorkspaceListIsRejectedForCategoryAvailability() throws {
        let result = validator.validate(
            userInput: "Show category availability.",
            request: MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                measure: .name,
                expectedAnswerShape: .metric
            ),
            localeIdentifier: "en"
        )

        let rejection = try #require(extractRejection(from: result))
        #expect(rejection.code == .entityMismatch)
        #expect(rejection.expectedAnchor.contains("entity=category"))
        #expect(rejection.actualDigest.contains("entity=workspace"))
    }

    @Test func starterRejectsAdditionalTargetOrFilterInsteadOfNarrowingTheAnswer() throws {
        let result = validator.validate(
            userInput: "Show category availability.",
            request: MarinaSemanticRequest(
                entity: .category,
                operation: .forecast,
                measure: .categoryAvailability,
                dimensions: [.category],
                constraints: [
                    MarinaSemanticConstraint(
                        dimension: .category,
                        value: "Groceries",
                        kindSource: .explicit
                    )
                ],
                expectedAnswerShape: .metric
            ),
            localeIdentifier: "en"
        )

        let rejection = try #require(extractRejection(from: result))
        #expect(rejection.code == .dimensionMismatch || rejection.code == .targetMismatch)
        #expect(rejection.actualDigest.contains("Groceries") == false)
    }

    @Test func starterContractsRejectUnanchoredOptionalSemantics() throws {
        let prompt = "Show category availability."
        let match = try #require(MarinaStarterPromptCatalog.match(
            prompt: prompt,
            localeIdentifier: "en"
        ))
        let exactRequest = request(for: match.contract)

        var withSort = exactRequest
        withSort.sort = .amountDescending
        #expect(try rejectionCode(prompt: prompt, request: withSort) == .sortMismatch)

        var withLimit = exactRequest
        withLimit.resultLimit = 3
        #expect(try rejectionCode(prompt: prompt, request: withLimit) == .countMismatch)

        var withExpenseScope = exactRequest
        withExpenseScope.expenseScope = .unified
        #expect(try rejectionCode(prompt: prompt, request: withExpenseScope) == .expenseScopeMismatch)

        var withIncomeState = exactRequest
        withIncomeState.incomeState = .actual
        #expect(try rejectionCode(prompt: prompt, request: withIncomeState) == .incomeStateMismatch)

        var withCategoryFilter = exactRequest
        withCategoryFilter.categoryAvailabilityFilter = .over
        #expect(try rejectionCode(prompt: prompt, request: withCategoryFilter) == .categoryFilterMismatch)

        var withContinuation = exactRequest
        withContinuation.continuationIntent = .showMore
        withContinuation.resultOffset = 3
        #expect(try rejectionCode(prompt: prompt, request: withContinuation) == .continuationMismatch)

        var withScenario = exactRequest
        withScenario.whatIfAmount = 20
        #expect(try rejectionCode(prompt: prompt, request: withScenario) == .scenarioMismatch)

        var withTerminalReason = exactRequest
        withTerminalReason.unsupportedReason = .unsupportedCombination
        #expect(try rejectionCode(prompt: prompt, request: withTerminalReason) == .safetyMismatch)
    }

    @Test func localizedSafeSpendStartersUseSafeDailySpendAcrossEveryShippedLocale() throws {
        let entry = try #require(MarinaStarterPromptCatalog.baseEntries.first { $0.id == .safeSpend })
        let inconclusivePrompts = [
            "ar": "ساعدني في مراجعة الأمور.",
            "de-DE": "Hilf mir, die Dinge zu überprüfen.",
            "es": "Ayúdame a revisar las cosas.",
            "fr-FR": "Aide-moi à faire le point.",
            "pt_BR": "Ajude-me a revisar as coisas.",
            "zh-Hans-CN": "帮我看看情况。"
        ]
        for locale in ["ar", "de-DE", "es", "fr-FR", "pt_BR", "zh-Hans-CN"] {
            let prompt = entry.prompt(localeIdentifier: locale)
            let match = try #require(MarinaStarterPromptCatalog.match(
                prompt: prompt,
                localeIdentifier: locale
            ))
            #expect(match.contract.measure == .safeDailySpend)
            let acceptedRequest = request(for: match.contract)
            #expect(validator.validate(
                userInput: prompt,
                request: acceptedRequest,
                localeIdentifier: locale
            ) == .accepted(anchorID: "starter.safeSpend"))

            var wrongMeasure = acceptedRequest
            wrongMeasure.measure = .remainingRoom
            let rejection = try #require(extractRejection(from: validator.validate(
                userInput: prompt,
                request: wrongMeasure,
                localeIdentifier: locale
            )))
            #expect(rejection.code == .measureMismatch)

            let inconclusivePrompt = try #require(inconclusivePrompts[locale])
            #expect(validator.validate(
                userInput: inconclusivePrompt,
                request: acceptedRequest,
                localeIdentifier: locale
            ) == .inconclusive)
        }
    }

    @Test func localizedCardSummaryPreservesTheExplicitTarget() throws {
        let prompt = "Résume mon Carte Voyage."
        let match = try #require(MarinaStarterPromptCatalog.match(
            prompt: prompt,
            localeIdentifier: "fr-FR"
        ))
        #expect(match.id == .cardSummary)

        let acceptedRequest = request(for: match.contract)
        #expect(validator.validate(
            userInput: prompt,
            request: acceptedRequest,
            localeIdentifier: "fr-FR"
        ) == .accepted(anchorID: "starter.cardSummary"))

        var wrongTarget = acceptedRequest
        wrongTarget.targetName = "Carte Débit"
        let rejection = try #require(extractRejection(from: validator.validate(
            userInput: prompt,
            request: wrongTarget,
            localeIdentifier: "fr-FR"
        )))
        #expect(rejection.code == .targetMismatch)
        #expect(rejection.actualDigest.contains("Carte Débit") == false)
    }

    @Test func qaTraceRegressionsAnchorDateFilterAndIncomeState() throws {
        let overLimit = validator.validate(
            userInput: "Which categories were over the limit for last month?",
            request: MarinaSemanticRequest(
                entity: .category,
                operation: .list,
                measure: .categoryAvailability,
                dateRangeToken: .previousMonth,
                dateRangeSource: .explicit,
                categoryAvailabilityFilter: .over,
                expectedAnswerShape: .list
            ),
            localeIdentifier: "en-US"
        )
        #expect(overLimit == .accepted(anchorID: "regression.categoryOverLimitPreviousMonth"))

        let income = validator.validate(
            userInput: "What is my income for the current period?",
            request: MarinaSemanticRequest(
                entity: .income,
                operation: .sum,
                measure: .incomeAmount,
                dateRangeSource: .explicit,
                incomeState: .actual,
                expectedAnswerShape: .metric
            ),
            localeIdentifier: "en"
        )
        #expect(income == .accepted(anchorID: "regression.actualIncomeCurrentPeriod"))
    }

    @Test func unknownPromptIsInconclusiveAndNeverSynthesized() {
        let request = MarinaSemanticRequest(
            entity: .card,
            operation: .count,
            expectedAnswerShape: .metric
        )
        #expect(validator.validate(
            userInput: "Could you take a look at things?",
            request: request,
            localeIdentifier: "en"
        ) == .inconclusive)
    }

    @Test func explicitMutationMustRemainReadOnly() throws {
        let incorrectQuery = MarinaSemanticRequest(
            entity: .card,
            operation: .list,
            expectedAnswerShape: .list
        )
        let rejection = try #require(extractRejection(from: validator.validate(
            userInput: "Delete my Apple Card.",
            request: incorrectQuery,
            localeIdentifier: "en"
        )))
        #expect(rejection.code == .safetyMismatch)

        let readOnly = MarinaSemanticRequest(
            entity: .card,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: .readOnly
        )
        #expect(validator.validate(
            userInput: "Delete my Apple Card.",
            request: readOnly,
            localeIdentifier: "en"
        ) == .accepted(anchorID: "safety.readOnlyMutation"))
    }

    private func request(
        for contract: MarinaStarterPromptCatalog.Contract
    ) -> MarinaSemanticRequest {
        let targetName: String?
        let targetSource: MarinaSemanticTargetKindSource
        switch contract.target {
        case .absent:
            targetName = nil
            targetSource = .unspecified
        case let .named(name, _, source):
            targetName = name
            targetSource = source
        }

        return MarinaSemanticRequest(
            entity: contract.entity,
            operation: contract.operation,
            measure: contract.measure,
            projection: contract.projection,
            dimensions: contract.dimensions,
            dateRangeToken: contract.dateRange,
            dateRangeSource: contract.dateRangeSource,
            targetName: targetName,
            targetKindSource: targetSource,
            resultLimit: contract.resultLimit,
            sort: contract.sort,
            expenseScope: contract.expenseScope,
            incomeState: contract.incomeState,
            categoryAvailabilityFilter: contract.categoryAvailabilityFilter,
            expectedAnswerShape: contract.answerShape
        )
    }

    private func extractRejection(
        from result: MarinaSemanticPromptAlignmentResult
    ) -> MarinaSemanticPromptAlignmentRejection? {
        guard case let .rejected(rejection) = result else { return nil }
        return rejection
    }

    private func rejectionCode(
        prompt: String,
        request: MarinaSemanticRequest
    ) throws -> MarinaSemanticPromptAlignmentRejectionCode {
        try #require(extractRejection(from: validator.validate(
            userInput: prompt,
            request: request,
            localeIdentifier: "en"
        ))).code
    }
}
