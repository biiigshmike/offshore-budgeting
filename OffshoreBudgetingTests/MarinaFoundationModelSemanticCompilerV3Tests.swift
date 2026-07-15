import Foundation
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels

@Suite(.serialized)
@MainActor
struct MarinaFoundationModelSemanticCompilerV3Tests {
    typealias Generated = MarinaFoundationModelGeneratedOutcomeV3

    @Test func clarificationSelectionDiagnosticRetainsOnlyItsBoundedIndex() {
        let digest = Generated.clarificationSelection(.init(index: 1)).generatedIntentDigest

        #expect(digest.intent == .clarificationSelection)
        #expect(digest.clarificationSelectionIndex == 1)
    }

    @Test func generatedSchemaIsDomainFirstAndRemovesV2Contradictions() {
        let outcomeSchema = Generated.generationSchema.debugDescription
        let querySchema = Generated.Query.generationSchema.debugDescription
        let selectionSchema = Generated.Selection.generationSchema.debugDescription

        for domain in [
            "workspaceMetadata", "budget", "card", "plannedExpense", "variableExpense",
            "reconciliationAccount", "savingsAccount", "income", "incomeSeries", "category", "preset"
        ] {
            #expect(querySchema.contains(domain))
        }
        #expect(outcomeSchema.contains("clarificationSelection"))
        #expect(outcomeSchema.contains("followUpDecision"))
        #expect(outcomeSchema.contains("unsupported"))
        #expect(selectionSchema.contains("dataBoundary"))
        #expect(selectionSchema.contains("dateSelection"))
        #expect(selectionSchema.contains("namedFilters"))
        #expect(selectionSchema.contains("entity") == false)
        #expect(Generated.DataBoundary.generationSchema.debugDescription.contains("activeWorkspace"))
        #expect(Generated.DataBoundary.generationSchema.debugDescription.contains("explicitNamedBudget"))
        #expect(Generated.FilterKind.generationSchema.debugDescription.contains("workspace") == false)
        #expect(Generated.FilterKind.generationSchema.debugDescription.contains("date") == false)
        #expect(outcomeSchema.contains("resultOffset") == false)
    }

    @Test func canonicalSchemaFootprintIsReportedSeparatelyFromProductionPhases() {
        let schema = Generated.generationSchema.debugDescription

        print("Marina V3 canonical schemaBytes=\(schema.utf8.count)")
        #expect(schema.isEmpty == false)
        #expect(MarinaSemanticCompilerInstructionsV3.version == "marina.semantic-compiler.v3")
        #expect(MarinaFoundationModelInstructionCatalogV3.instructionVersion == "marina.semantic-generation.v3.1")
        // Production never generates this monolithic schema. Per-phase schema
        // and instruction ceilings are enforced by the staged-generation tests.
        #expect(schema.utf8.count < 80_000)
    }

    @Test func everyDomainFirstQueryDispatchesToItsExactSemanticSubject() throws {
        let selection = selection()
        let list = listModifiers()
        let fixtures: [(Generated.Query, MarinaSemanticEntity)] = [
            (.workspaceMetadata(.init(action: .name(.init()))), .workspace),
            (.budget(.init(action: .list(.init(
                projection: .records,
                selection: selection,
                modifiers: list
            )))), .budget),
            (.card(.init(action: .count(.init(selection: selection)))), .card),
            (.plannedExpense(.init(action: .count(.init(
                selection: selection,
                expenseScope: .planned
            )))), .plannedExpense),
            (.variableExpense(.init(action: .count(.init(
                selection: selection,
                expenseScope: .variable
            )))), .variableExpense),
            (.reconciliationAccount(.init(action: .count(.init(selection: selection)))), .reconciliationAccount),
            (.savingsAccount(.init(action: .count(.init(selection: selection)))), .savingsAccount),
            (.income(.init(action: .count(.init(state: .actual, selection: selection)))), .income),
            (.incomeSeries(.init(action: .count(.init(
                projection: .records,
                selection: selection
            )))), .incomeSeries),
            (.category(.init(action: .count(.init(selection: selection)))), .category),
            (.preset(.init(action: .list(.init(
                projection: .records,
                measure: .name,
                selection: selection,
                modifiers: list
            )))), .preset)
        ]

        for (query, expectedEntity) in fixtures {
            let request = try compile(.query(query))
            #expect(request.entity == expectedEntity)
        }
    }

    @Test func observedCategoryAvailabilityFailureHasOneExactV3Path() throws {
        let outcome = Generated.query(.category(Generated.CategoryQuery(
            action: .availabilityList(Generated.CategoryAvailabilityList(
                status: .over,
                selection: selection(date: .explicit(.previousMonth)),
                modifiers: listModifiers()
            ))
        )))

        let request = try compile(outcome)

        #expect(request.entity == .category)
        #expect(request.operation == .list)
        #expect(request.measure == .categoryAvailability)
        #expect(request.projection == .records)
        #expect(request.dateRangeToken == .previousMonth)
        #expect(request.dateRangeSource == .explicit)
        #expect(request.categoryAvailabilityFilter == .over)
        #expect(request.expectedAnswerShape == .list)
        #expect(request.entity != .workspace)
    }

    @Test func observedCurrentIncomeFailureCannotOmitMeasureOrState() throws {
        let outcome = Generated.query(.income(Generated.IncomeQuery(
            action: .sum(Generated.IncomeMetric(
                measure: .incomeAmount,
                state: .actual,
                selection: selection(date: .explicit(.currentPeriod))
            ))
        )))

        let request = try compile(outcome)

        #expect(request.entity == .income)
        #expect(request.operation == .sum)
        #expect(request.measure == .incomeAmount)
        #expect(request.incomeState == .actual)
        #expect(request.dateRangeToken == .currentPeriod)
        #expect(request.dateRangeSource == .explicit)
        #expect(request.expectedAnswerShape == .metric)
    }

    @Test func starterSpecificActionsBindTheirSemanticContracts() throws {
        let safeSpend = try compile(.query(.budget(Generated.BudgetQuery(
            action: .forecast(Generated.BudgetForecast(
                measure: .safeDailySpend,
                selection: selection()
            ))
        ))))
        #expect(safeSpend.entity == .budget)
        #expect(safeSpend.operation == .forecast)
        #expect(safeSpend.measure == .safeDailySpend)
        #expect(safeSpend.projection == .summary)
        #expect(safeSpend.expectedAnswerShape == .metric)

        let progress = try compile(.query(.income(Generated.IncomeQuery(
            action: .progress(Generated.IncomeProgress(selection: selection()))
        ))))
        #expect(progress.entity == .income)
        #expect(progress.operation == .share)
        #expect(progress.measure == .incomeAmount)
        #expect(progress.incomeState == .all)

        let trends = try compile(.query(.category(Generated.CategoryQuery(
            action: .groupedSpend(Generated.CategoryGroupedSpend(
                selection: selection(),
                dimension: .category,
                sort: .amountDescending,
                resultLimit: 3,
                continuation: .none,
                expenseScope: .unified
            ))
        ))))
        #expect(trends.entity == .category)
        #expect(trends.operation == .group)
        #expect(trends.measure == .budgetImpact)
        #expect(trends.dimensions == [.category])
        #expect(trends.resultLimit == 3)
        #expect(trends.expenseScope == .unified)
        #expect(trends.expectedAnswerShape == .list)
    }

    @Test func namedBoundaryFiltersAndMerchantTargetMapWithoutPromptInspection() throws {
        let outcome = Generated.query(.variableExpense(Generated.VariableExpenseQuery(
            action: .sum(Generated.VariableExpenseMetric(
                measure: .budgetImpact,
                selection: Generated.Selection(
                    dataBoundary: .explicitNamedBudget(" July Budget "),
                    target: Generated.NamedTarget(
                        wording: " Grocery Outlet ",
                        classification: .explicit(.merchantText)
                    ),
                    namedFilters: [
                        Generated.NamedFilter(kind: .category, value: " Groceries ", evidence: .explicit),
                        Generated.NamedFilter(kind: .card, value: " Apple Card ", evidence: .inferred)
                    ],
                    dateSelection: .explicit(.currentMonth)
                ),
                expenseScope: .variable
            ))
        )))

        let request = try compile(outcome, prompt: "text deliberately unrelated to mapping")

        #expect(request.entity == .variableExpense)
        #expect(request.targetName == "Grocery Outlet")
        #expect(request.textQuery == "Grocery Outlet")
        #expect(request.targetKindSource == .explicit)
        #expect(request.constraints.map(\.dimension) == [.category, .card, .budget])
        #expect(request.constraints.map(\.value) == ["Groceries", "Apple Card", "July Budget"])
        #expect(request.constraints.map(\.kindSource) == [.explicit, .inferred, .explicit])
        #expect(request.dimensions == [.category, .card, .budget, .merchantText])
    }

    @Test func contextualFailuresRemainTypedAndStable() {
        expectInvalid(
            .emptyNamedBudget,
            .query(.category(Generated.CategoryQuery(
                action: .availabilitySummary(Generated.CategoryAvailabilitySummary(
                    selection: selection(boundary: .explicitNamedBudget("  "))
                ))
            )))
        )
        expectInvalid(
            .emptyTarget,
            .query(.card(Generated.CardQuery(
                action: .count(Generated.CardCount(selection: selection(
                    target: Generated.NamedTarget(wording: "\n", classification: .explicit(.card))
                )))
            )))
        )
        expectInvalid(
            .emptyNamedFilter,
            .query(.income(Generated.IncomeQuery(
                action: .count(Generated.IncomeCount(
                    state: nil,
                    selection: selection(filters: [
                        Generated.NamedFilter(kind: .incomeSource, value: " ", evidence: .explicit)
                    ])
                ))
            )))
        )
        expectInvalid(
            .dateContextWithoutPriorRequest,
            .query(.savingsAccount(Generated.SavingsAccountQuery(
                action: .sum(Generated.SavingsMetric(
                    measure: .savingsTotal,
                    selection: selection(date: .conversationContext(.currentMonth))
                ))
            )))
        )
        expectInvalid(
            .continuationWithoutContext,
            .query(.variableExpense(Generated.VariableExpenseQuery(
                action: .list(Generated.VariableExpenseList(
                    measure: .budgetImpact,
                    selection: selection(),
                    modifiers: listModifiers(continuation: .showMore),
                    expenseScope: .variable
                ))
            )))
        )
    }

    @Test func v3TurnOwnsVersionedRedactedContextAndRetryContainsOnlyCode() {
        let secretID = UUID()
        let prior = MarinaSemanticRequest(
            entity: .card,
            operation: .sum,
            measure: .budgetImpact,
            targetName: "Apple Card",
            resolvedTarget: MarinaResolvedEntityReference(
                entity: .card,
                id: secretID,
                displayName: "Apple Card",
                provenance: .candidateResolver
            ),
            resultLimit: 5,
            expectedAnswerShape: .metric
        )
        let context = MarinaConversationContext(recentTurns: [
            MarinaConversationTurn(
                userPrompt: "SECRET RAW HISTORY",
                title: "Private title",
                kind: .metric,
                subtitle: nil,
                primaryValue: "$999",
                rowTitles: [],
                semanticContext: MarinaAnswerSemanticContext(
                    request: prior,
                    dateRange: nil,
                    comparisonDateRange: nil,
                    answerKind: .metric,
                    answerTitle: "Private title",
                    answerSubtitle: nil,
                    primaryValue: "$999",
                    rowReferences: []
                ),
                recommendedFollowUp: nil
            )
        ])

        let turn = MarinaSemanticCompilerTurnV3(userInput: "show it", conversationContext: context)
        let retry = turn.promptForRetry(rejectionCode: "alignment.entityMismatch")

        #expect(turn.prompt.contains(MarinaSemanticCompilerInstructionsV3.version))
        #expect(turn.prompt.contains("marina.semantic-compiler.v2") == false)
        #expect(turn.prompt.contains(secretID.uuidString) == false)
        #expect(turn.prompt.contains("SECRET RAW HISTORY") == false)
        #expect(turn.prompt.contains("$999") == false)
        #expect(retry.contains("rejectionCode=alignment.entityMismatch"))
        #expect(retry.contains("expected=") == false)
        #expect(retry.contains("previousSemantic") == false)
    }

    private func compile(
        _ outcome: Generated,
        prompt: String = "fixture"
    ) throws -> MarinaSemanticRequest {
        try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: outcome,
            turn: MarinaSemanticCompilerTurnV3(userInput: prompt, conversationContext: .empty)
        ).request
    }

    private func expectInvalid(
        _ expected: MarinaFoundationModelInvalidOutcome,
        _ outcome: Generated
    ) {
        do {
            _ = try compile(outcome)
            Issue.record("Expected compiler rejection \(expected.rejectionCode).")
        } catch let error as MarinaFoundationModelInterpretationError {
            #expect(error == .invalidGeneratedOutcome(expected))
            #expect(error.rejectionCode == expected.rejectionCode)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func selection(
        boundary: Generated.DataBoundary = .activeWorkspace,
        target: Generated.NamedTarget? = nil,
        filters: [Generated.NamedFilter] = [],
        date: Generated.DateSelection = .defaultCurrentPeriod
    ) -> Generated.Selection {
        Generated.Selection(
            dataBoundary: boundary,
            target: target,
            namedFilters: filters,
            dateSelection: date
        )
    }

    private func listModifiers(
        sort: Generated.Sort? = nil,
        resultLimit: Int? = nil,
        continuation: Generated.Continuation = .none
    ) -> Generated.ListModifiers {
        Generated.ListModifiers(
            sort: sort,
            resultLimit: resultLimit,
            continuation: continuation
        )
    }
}
#endif
