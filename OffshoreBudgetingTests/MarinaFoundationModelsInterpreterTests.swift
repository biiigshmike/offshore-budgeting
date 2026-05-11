import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaFoundationModelsInterpreterTests {
    @Test func modelLookupPrompt_badMetricStaysTypedCandidateWithoutDatabaseBypass() {
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "card_name",
                    targetName: "Litter Robot",
                    targetTypeRaw: "entity",
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: nil,
                    confidenceRaw: "medium",
                    clarification: nil
                )
            ),
            prompt: "When did I purchase Litter Robot",
            defaultPeriodUnit: .month
        )

        #expect(candidate.requestFamily == .analytics)
        #expect(candidate.databaseLookupRequest == nil)
        #expect(candidate.rawPrompt == "When did I purchase Litter Robot")
        #expect(candidate.source == .foundationModels)
    }

    @Test func foundationModels_totalSpendOnAppleCard_emitsUnresolvedCardCandidate() {
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "cardSpendTotal",
                    targetName: "Apple Card",
                    targetTypeRaw: "card",
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            ),
            prompt: "total spend on my Apple Card",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .foundationModels)
        #expect(candidate.rawPrompt == "total spend on my Apple Card")
        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.count == 1)

        let mention = candidate.entityMentions[0]
        #expect(mention.role == .filter)
        #expect(mention.rawText == "Apple Card")
        #expect(mention.typeHint == .card)
        #expect(mention.confidence == .high)
        #expect(candidate.responseShapeHint == .scalarCurrency)
        #expect(candidate.unsupportedHint == nil)
    }

    @Test func foundationModels_averageFoodAndDrinkLastThreeMonths_emitsAverageCandidateWithDateHints() {
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "spendAveragePerPeriod",
                    targetName: "Food & Drink",
                    targetTypeRaw: "category",
                    dateStartISO8601: "2026-02-01",
                    dateEndISO8601: "2026-04-30",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            ),
            prompt: "average Food & Drink for the last 3 months",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .average)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.role == .primaryTarget)
        #expect(candidate.entityMentions.first?.rawText == "Food & Drink")
        #expect(candidate.entityMentions.first?.typeHint == .category)
        #expect(candidate.timeScopes.count == 1)
        #expect(candidate.timeScopes.first?.role == .lookbackWindow)
        #expect(candidate.timeScopes.first?.periodUnitHint == .month)
        assertDateRange(
            candidate.timeScopes.first?.resolvedRangeHint,
            start: date(2026, 2, 1),
            end: date(2026, 4, 30)
        )
        #expect(candidate.responseShapeHint == .scalarCurrency)
    }

    @Test func foundationModels_compareGroceriesThisMonthToLastMonth_emitsComparisonCandidate() {
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "categoryMonthComparison",
                    targetName: "groceries",
                    targetTypeRaw: "category",
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: "2026-04-01",
                    comparisonDateEndISO8601: "2026-04-30",
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "medium",
                    clarification: nil
                )
            ),
            prompt: "compare groceries this month to last month",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.map(\.role) == [.primaryTarget])
        #expect(candidate.entityMentions.first?.rawText == "groceries")
        #expect(candidate.timeScopes.map(\.role) == [.primary, .comparison])
        assertDateRange(
            candidate.timeScopes.first?.resolvedRangeHint,
            start: date(2026, 5, 1),
            end: date(2026, 5, 31)
        )
        assertDateRange(
            candidate.timeScopes.last?.resolvedRangeHint,
            start: date(2026, 4, 1),
            end: date(2026, 4, 30)
        )
        #expect(candidate.responseShapeHint == .comparison)
    }

    @Test func foundationModels_whereIsMyMoneyGoing_emitsGroupedRankingWithoutSpecificEntityTruth() {
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "topCategories",
                    targetName: nil,
                    targetTypeRaw: nil,
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: 5,
                    periodUnitRaw: "month",
                    confidenceRaw: "medium",
                    clarification: nil
                )
            ),
            prompt: "where is my money going?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .foundationModels)
        #expect(candidate.operation == .rank)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.isEmpty)
        #expect(candidate.grouping?.dimension == .category)
        #expect(candidate.ranking?.direction == .top)
        #expect(candidate.ranking?.limit == 5)
        #expect(candidate.limit == 5)
        #expect(candidate.responseShapeHint == .rankedList)
    }

    @Test func semanticCommand_listLastFiveCannabisPurchases_buildsFilteredRowList() {
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .listRows,
            datasets: [.variableExpenses, .plannedExpenses],
            measure: nil,
            includeFilters: [
                MarinaSemanticCommandFilter(
                    rawText: "Cannabis",
                    allowedTypes: [.category, .merchant, .expense]
                )
            ],
            excludeFilters: [],
            grouping: .transaction,
            sort: .newest,
            dateRange: nil,
            comparisonDateRange: nil,
            periodUnit: nil,
            limit: 5,
            requestedDetail: nil
        )

        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .semanticCommand(command),
            prompt: "List my last 5 Cannabis purchases",
            defaultPeriodUnit: .month
        )

        #expect(candidate.semanticCommand == command)
        #expect(candidate.operation == .listRows)
        #expect(candidate.measure == .transactionAmount)
        #expect(candidate.grouping?.dimension == .transaction)
        #expect(candidate.ranking?.direction == .newest)
        #expect(candidate.limit == 5)
        #expect(candidate.entityMentions.first?.rawText == "Cannabis")
        #expect(candidate.entityMentions.first?.allowedTypeHints == [.category, .merchant, .expense])
    }

    @Test func semanticCommand_exclusionFilter_buildsIncludeAndExcludeMentions() {
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .total,
            datasets: [.variableExpenses, .plannedExpenses],
            measure: .spend,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "Apple Card", allowedTypes: [.card])
            ],
            excludeFilters: [
                MarinaSemanticCommandFilter(rawText: "Food & Drink", allowedTypes: [.category])
            ],
            grouping: nil,
            sort: nil,
            dateRange: nil,
            comparisonDateRange: nil,
            periodUnit: .month,
            limit: nil,
            requestedDetail: nil
        )

        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .semanticCommand(command),
            prompt: "What did I spend on Apple Card outside of Food & Drink?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.map(\.role) == [.filter, .excludeFilter])
        #expect(candidate.entityMentions.map(\.rawText) == ["Apple Card", "Food & Drink"])
        #expect(candidate.entityMentions[0].typeHint == .card)
        #expect(candidate.entityMentions[1].typeHint == .category)
    }

    @Test func semanticCommand_simulation_buildsDeterministicSimulationCandidate() {
        let command = MarinaSemanticCommand(
            family: .planning,
            action: .simulate,
            datasets: [.variableExpenses],
            measure: nil,
            includeFilters: [
                MarinaSemanticCommandFilter(rawText: "Groceries", allowedTypes: [.category])
            ],
            excludeFilters: [],
            grouping: nil,
            sort: nil,
            dateRange: nil,
            comparisonDateRange: nil,
            periodUnit: .month,
            limit: nil,
            requestedDetail: nil
        )

        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .semanticCommand(command),
            prompt: "If I spend $50 on Groceries, how will that affect my budget?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.requestFamily == .planning)
        #expect(candidate.operation == .simulate)
        #expect(candidate.measure == .remainingBudget)
        #expect(candidate.entityMentions.first?.role == .simulationInput)
        #expect(candidate.responseShapeHint == .summaryCard)
    }

    @Test func semanticCommand_lookupDetails_remainsTypedCandidateWithoutDatabaseBypass() {
        let cases: [(MarinaSemanticCommandDataset, MarinaLookupObjectType, String)] = [
            (.budgets, .budget, "May"),
            (.cards, .card, "Apple Card"),
            (.categories, .category, "Groceries"),
            (.presets, .preset, "Rent"),
            (.income, .income, "Salary"),
            (.incomeSeries, .incomeSeries, "Salary"),
            (.savingsLedger, .savingsLedgerEntry, "Manual adjustment"),
            (.reconciliation, .reconciliationAccount, "Roommate"),
            (.expenseAllocations, .expenseAllocation, "Dinner"),
            (.importMerchantRules, .importMerchantRule, "amzn"),
            (.assistantAliasRules, .assistantAliasRule, "groc")
        ]

        for (dataset, _, searchText) in cases {
            let command = MarinaSemanticCommand(
                family: .databaseLookup,
                action: .lookupDetails,
                datasets: [dataset],
                measure: nil,
                includeFilters: [
                    MarinaSemanticCommandFilter(rawText: searchText, allowedTypes: [])
                ],
                excludeFilters: [],
                grouping: nil,
                sort: nil,
                dateRange: nil,
                comparisonDateRange: nil,
                periodUnit: nil,
                limit: 5,
                requestedDetail: .general
            )

            let candidate = MarinaFoundationModelsInterpreter().candidate(
                from: .semanticCommand(command),
                prompt: "show \(searchText)",
                defaultPeriodUnit: .month
            )

            #expect(candidate.requestFamily == .databaseLookup)
            #expect(candidate.operation == .lookupDetails)
            #expect(candidate.databaseLookupRequest == nil)
            #expect(candidate.entityMentions.first?.rawText == searchText)
            #expect(candidate.semanticCommand == command)
        }
    }

    @Test func foundationModels_whatIfPromptDoesNotSolveMultiEntityExtraction() {
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "whatIfSimulation",
                    targetName: "Shopping",
                    targetTypeRaw: "category",
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "medium",
                    clarification: nil
                )
            ),
            prompt: "If I increase Shopping by $100, what will I have left for Transportation?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .foundationModels)
        #expect(candidate.unsupportedHint == .unsupportedOperation)
        #expect(candidate.entityMentions.count <= 1)
        #expect(candidate.entityMentions.map(\.role).contains(.simulationInput) == false)
        #expect(candidate.entityMentions.map(\.role).contains(.simulationOutput) == false)
        #expect(candidate.responseShapeHint == .unsupported)
    }

    @Test func foundationModelsCandidateTrace_summarizesAdapterOutput() {
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "topCategories",
                    targetName: nil,
                    targetTypeRaw: nil,
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: 3,
                    periodUnitRaw: "month",
                    confidenceRaw: "medium",
                    clarification: nil
                )
            ),
            prompt: "where is my money going?",
            defaultPeriodUnit: .month
        )
        let trace = MarinaCandidateTrace(candidate: candidate)

        #expect(trace.interpreterSource == .foundationModels)
        #expect(trace.operation == candidate.operation)
        #expect(trace.measure == candidate.measure)
        #expect(trace.compactSummary.contains("source=foundationModels"))
        #expect(trace.executablePlanSummary == nil)
        #expect(trace.validatorOutcomeSummary == nil)
    }

    @Test func foundationModelsAsyncAdapter_usesInjectedStructuredInterpreterOnly() async throws {
        let structuredIntent = MarinaStructuredIntent.query(
            MarinaStructuredQueryIntent(
                metricRaw: "spendTotal",
                targetName: nil,
                targetTypeRaw: nil,
                dateStartISO8601: nil,
                dateEndISO8601: nil,
                comparisonDateStartISO8601: nil,
                comparisonDateEndISO8601: nil,
                resultLimit: nil,
                periodUnitRaw: "month",
                confidenceRaw: "high",
                clarification: nil
            )
        )
        let interpreter = MarinaFoundationModelsInterpreter(
            structuredInterpreter: StubStructuredIntentInterpreter(structuredIntent: structuredIntent)
        )

        let candidate = try await interpreter.interpret(
            prompt: "what did I spend this month?",
            context: makeRouterContext()
        )

        #expect(candidate.source == .foundationModels)
        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .spend)
    }

    @Test func foundationModels_lowConfidenceModelOutput_returnsUnsupportedCandidate() async throws {
        let structuredIntent = MarinaStructuredIntent.query(
            MarinaStructuredQueryIntent(
                metricRaw: "spendTotal",
                targetName: nil,
                targetTypeRaw: nil,
                dateStartISO8601: nil,
                dateEndISO8601: nil,
                comparisonDateStartISO8601: nil,
                comparisonDateEndISO8601: nil,
                resultLimit: nil,
                periodUnitRaw: "month",
                confidenceRaw: "low",
                clarification: nil
            )
        )
        let candidate = try await MarinaFoundationModelsInterpreter(
            structuredInterpreter: StubStructuredIntentInterpreter(structuredIntent: structuredIntent)
        ).interpret(prompt: "maybe spending?", context: makeRouterContext())

        #expect(candidate.confidence == .low)
        #expect(candidate.unsupportedHint == .lowConfidence)
        #expect(candidate.responseShapeHint == .unsupported)
    }

    @Test func foundationModels_unresolvedModelOutput_returnsUnsupportedCandidate() async throws {
        let candidate = try await MarinaFoundationModelsInterpreter(
            structuredInterpreter: StubStructuredIntentInterpreter(structuredIntent: .unresolved)
        ).interpret(prompt: "hmm", context: makeRouterContext())

        #expect(candidate.source == .foundationModels)
        #expect(candidate.confidence == .low)
        #expect(candidate.unsupportedHint == .lowConfidence)
        #expect(candidate.responseShapeHint == .unsupported)
    }

    @Test func foundationModels_commandModelOutput_returnsUnsupportedCandidate() async throws {
        let command = MarinaStructuredCommandIntent(
            intentRaw: "addExpense",
            confidenceRaw: "high",
            amount: nil,
            originalAmount: nil,
            dateISO8601: nil,
            dateRangeStartISO8601: nil,
            dateRangeEndISO8601: nil,
            notes: nil,
            source: nil,
            cardName: nil,
            categoryName: nil,
            entityName: nil,
            updatedEntityName: nil,
            isPlannedIncome: nil,
            categoryColorHex: nil,
            categoryColorName: nil,
            cardThemeRaw: nil,
            cardEffectRaw: nil,
            recurrenceFrequencyRaw: nil,
            recurrenceInterval: nil,
            weeklyWeekday: nil,
            monthlyDayOfMonth: nil,
            monthlyIsLastDay: nil,
            yearlyMonth: nil,
            yearlyDayOfMonth: nil,
            recurrenceEndDateISO8601: nil,
            plannedExpenseAmountTargetRaw: nil,
            attachAllCards: nil,
            attachAllPresets: nil,
            selectedCardNames: [],
            selectedPresetTitles: [],
            clarification: nil
        )
        let candidate = try await MarinaFoundationModelsInterpreter(
            structuredInterpreter: StubStructuredIntentInterpreter(structuredIntent: .command(command))
        ).interpret(prompt: "add coffee", context: makeRouterContext())

        #expect(candidate.unsupportedHint == .unsupportedOperation)
        #expect(candidate.responseShapeHint == .unsupported)
    }

    @Test func foundationModels_clarificationModelOutput_usesGenericHintUnlessTargetIsSpecified() async throws {
        let genericClarification = MarinaStructuredClarification(
            subtitle: "I need one more detail.",
            missingFields: [.dateRange],
            ambiguities: [],
            shouldRunBestEffort: false
        )
        let genericCandidate = try await MarinaFoundationModelsInterpreter(
            structuredInterpreter: StubStructuredIntentInterpreter(structuredIntent: .clarification(genericClarification))
        ).interpret(prompt: "compare this", context: makeRouterContext())

        #expect(genericCandidate.responseShapeHint == .clarification)
        #expect(genericCandidate.unsupportedHint == .unsupportedOperation)

        let targetClarification = MarinaStructuredClarification(
            subtitle: "Which card?",
            missingFields: [.targetName],
            ambiguities: [],
            shouldRunBestEffort: false
        )
        let targetCandidate = try await MarinaFoundationModelsInterpreter(
            structuredInterpreter: StubStructuredIntentInterpreter(structuredIntent: .clarification(targetClarification))
        ).interpret(prompt: "spend on card", context: makeRouterContext())

        #expect(targetCandidate.responseShapeHint == .clarification)
        #expect(targetCandidate.unsupportedHint == .missingRequiredTarget)
    }

    @Test func foundationModels_missingMetric_returnsUnsupportedOperationNotMissingTarget() {
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: nil,
                    targetName: "Groceries",
                    targetTypeRaw: "category",
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "medium",
                    clarification: nil
                )
            ),
            prompt: "groceries?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == nil)
        #expect(candidate.unsupportedHint == .unsupportedOperation)
        #expect(candidate.unsupportedHint != .missingRequiredTarget)
    }

    @Test func foundationModels_serviceFailureStillThrows() async {
        let interpreter = MarinaFoundationModelsInterpreter(
            structuredInterpreter: ThrowingStructuredIntentInterpreter()
        )

        do {
            _ = try await interpreter.interpret(prompt: "what did I spend?", context: makeRouterContext())
            Issue.record("Expected service failure to throw")
        } catch {
            #expect(error is StubStructuredIntentError)
        }
    }

    private func assertDateRange(
        _ actual: HomeQueryDateRange?,
        start: Date,
        end: Date
    ) {
        guard let actual else {
            Issue.record("Expected date range")
            return
        }

        #expect(actual.startDate == start)
        #expect(actual.endDate == end)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeRouterContext() -> MarinaLanguageRouterContext {
        MarinaLanguageRouterContext(
            workspaceName: "Test Workspace",
            defaultPeriodUnit: .month,
            sessionContext: HomeAssistantSessionContext(),
            priorQueryContext: MarinaPriorQueryContext(
                lastQueryPlan: nil,
                lastMetric: nil,
                lastTargetName: nil,
                lastTargetType: nil,
                lastDateRange: nil,
                lastResultLimit: nil,
                lastPeriodUnit: nil
            ),
            cardNames: [],
            categoryNames: [],
            incomeSourceNames: [],
            presetTitles: [],
            budgetNames: [],
            aliasSummaries: [],
            now: date(2026, 5, 1)
        )
    }
}

private struct StubStructuredIntentInterpreter: MarinaStructuredIntentInterpreting {
    let structuredIntent: MarinaStructuredIntent

    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent {
        structuredIntent
    }
}

private struct ThrowingStructuredIntentInterpreter: MarinaStructuredIntentInterpreting {
    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent {
        throw StubStructuredIntentError()
    }
}

private struct StubStructuredIntentError: Error {}
