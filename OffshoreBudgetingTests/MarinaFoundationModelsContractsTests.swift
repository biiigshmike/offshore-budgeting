import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaFoundationModelsContractsTests {
    @Test func routeIntent_mapsRawRoutes() {
        #expect(route("read_query") == .readQuery)
        #expect(route("analytics") == .readQuery)
        #expect(route("databaseLookup") == .lookup)
        #expect(route("clarify") == .clarification)
        #expect(route("what_if") == .scenario)
        #expect(route("capabilities") == .help)
        #expect(route("createExpense") == .unsupported)
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test func clarificationIntent_mapsFieldsToStructuredClarification() {
        let intent = MarinaFoundationClarificationIntent(
            reasoning: "Groceries may be a category or merchant.",
            kindRaw: "ambiguousTarget",
            message: "Which Groceries did you mean?",
            missingFieldRaws: ["date_range"],
            ambiguousFieldRaws: ["target"],
            patchSlotRaw: "targetName",
            shouldRunBestEffort: false
        )

        let clarification = intent.structuredClarification

        #expect(clarification.subtitle == "Which Groceries did you mean?")
        #expect(clarification.missingFields == [.dateRange])
        #expect(clarification.ambiguities.map(\.field) == [.targetName])
        #expect(clarification.shouldRunBestEffort == false)
    }

    @Test func evalCorpus_stubbedRouteContractsMatchExpectedRoutes() {
        let corpus: [(prompt: String, routeRaw: String, expected: MarinaFoundationRouteKind)] = [
            (
                "How much did I spend on groceries this month?",
                "readQuery",
                .readQuery
            ),
            (
                "Show me the Apple Card details",
                "lookup",
                .lookup
            ),
            (
                "Add a $25 coffee expense",
                "unsupported",
                .unsupported
            ),
            (
                "What if I spend $200 less on dining?",
                "scenario",
                .scenario
            ),
            (
                "What can Marina answer?",
                "help",
                .help
            )
        ]

        for item in corpus {
            #expect(
                MarinaFoundationRouteKind(routeRaw: item.routeRaw) == item.expected,
                "Prompt '\(item.prompt)' should route to \(item.expected.rawValue)"
            )
        }
    }

    @Test func runtimeTraceSummary_includesFoundationPromptVersioning() {
        let settings = MarinaRuntimeSettings.resolve(
            nlqV1Fallback: false,
            sharedPipelineFallback: true,
            aiOptInFallback: true,
            defaults: UserDefaults(suiteName: "MarinaFoundationModelsContractsTests")!,
            arguments: [],
            environment: [:]
        )

        #expect(settings.traceSummary.contains(MarinaFoundationPromptVersion.interpretationV3.rawValue))
        #expect(settings.traceSummary.contains(MarinaFoundationPromptVersion.presentationV1.rawValue))
        #expect(settings.traceSummary.contains("foundationModelBand="))
        #expect(settings.traceSummary.contains("foundationLocale="))
    }

    @Test func v2ReadQuery_bridgesToLegacySemanticCommand() {
        let intent = MarinaAIIntentV2.readQuery(
            MarinaAIReadQueryIntentV2(
                reasoning: "Total card spend.",
                subjectRaw: "variableExpenses",
                operationRaw: "sum",
                measureRaw: "spend",
                includeMentions: [
                    MarinaAIEntityMentionV2(
                        roleRaw: "filter",
                        rawText: "Apple Card",
                        typeRaw: "card",
                        allowedTypeRaws: []
                    )
                ],
                excludeMentions: [],
                primaryDateRange: MarinaAIDateRangeV2(
                    startISO8601: "2026-05-01",
                    endISO8601: "2026-05-31",
                    rawText: "May",
                    periodUnitRaw: "month"
                ),
                comparisonDateRange: nil,
                groupingRaw: nil,
                rankingRaw: nil,
                requestedDetailRaw: nil,
                limit: nil,
                incomeStatusRaw: nil,
                insightIntentRaw: nil,
                softTimeHintRaw: nil,
                confidenceRaw: "high"
            )
        )

        guard case .semanticCommand(let command) = intent.structuredIntent else {
            Issue.record("Expected V2 read query to bridge to semantic command.")
            return
        }

        #expect(intent.kind == .readQuery)
        #expect(command.family == .analytics)
        #expect(command.action == .total)
        #expect(command.datasets == [.variableExpenses])
        #expect(command.measure == .spend)
        #expect(command.includeFilters.first?.rawText == "Apple Card")
        #expect(command.includeFilters.first?.allowedTypes == [.card])
        #expect(command.periodUnit == .month)
    }

    @Test func v2ReadQuery_treatsLiteralNullAndNonePlaceholdersAsMissing() {
        let intent = MarinaAIIntentV2.readQuery(
            MarinaAIReadQueryIntentV2(
                reasoning: "Live model placeholder cleanup.",
                subjectRaw: "income",
                operationRaw: "sum",
                measureRaw: "income",
                includeMentions: [
                    MarinaAIEntityMentionV2(
                        roleRaw: "primaryTarget",
                        rawText: "null",
                        typeRaw: "none",
                        allowedTypeRaws: ["null"]
                    )
                ],
                excludeMentions: [],
                primaryDateRange: MarinaAIDateRangeV2(
                    startISO8601: "null",
                    endISO8601: "none",
                    rawText: "n/a",
                    periodUnitRaw: "month"
                ),
                comparisonDateRange: nil,
                groupingRaw: "none",
                rankingRaw: "null",
                requestedDetailRaw: "unknown",
                limit: nil,
                incomeStatusRaw: "actual",
                insightIntentRaw: "none",
                softTimeHintRaw: "null",
                confidenceRaw: "medium"
            )
        )

        guard case .semanticCommand(let command) = intent.structuredIntent else {
            Issue.record("Expected placeholder-cleaned intent to produce a semantic command.")
            return
        }

        #expect(command.includeFilters.isEmpty)
        #expect(command.dateRange == nil)
        #expect(command.grouping == nil)
        #expect(command.sort == nil)
        #expect(command.requestedDetail == nil)
        #expect(command.incomeStatusScope == .actual)
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test func foundationEnvelopeV2_bridgesAllRuntimeRoutesToV2Intents() {
        let read = envelope(
            routeRaw: "readQuery",
            subjectRaw: "variableExpenses",
            operationRaw: "sum",
            measureRaw: "spend",
            targetText: "Groceries",
            targetTypeRaw: "category",
            startISO8601: "2026-05-01",
            endISO8601: "2026-05-31",
            periodUnitRaw: "month"
        ).aiIntent
        let lookup = envelope(
            routeRaw: "lookup",
            subjectRaw: "cards",
            targetText: "Apple Card",
            targetTypeRaw: "card",
            requestedDetailRaw: "balance"
        ).aiIntent
        let scenario = envelope(
            routeRaw: "scenario",
            targetText: "Dining",
            targetTypeRaw: "category",
            scenarioAmountRaw: "200"
        ).aiIntent
        let clarification = envelope(
            routeRaw: "clarification",
            clarificationKindRaw: "ambiguousTarget",
            clarificationMessage: "Which Groceries?",
            clarificationFieldRaw: "target",
            clarificationPatchSlotRaw: "targetName"
        ).aiIntent
        let unsupported = envelope(
            routeRaw: "unsupported",
            unsupportedReasonRaw: "crud",
            unsupportedMessage: "CRUD is deferred."
        ).aiIntent

        #expect(read.kind == .readQuery)
        #expect(lookup.kind == .lookup)
        #expect(scenario.kind == .scenario)
        #expect(clarification.kind == .clarification)
        #expect(unsupported.kind == .unsupported)

        guard case .readQuery(let readIntent) = read else {
            Issue.record("Expected read intent.")
            return
        }
        #expect(readIntent.includeMentions.first?.rawText == "Groceries")
        #expect(readIntent.includeMentions.first?.allowedTypeRaws == ["category"])
        #expect(readIntent.primaryDateRange?.periodUnitRaw == "month")

        guard case .lookup(let lookupIntent) = lookup else {
            Issue.record("Expected lookup intent.")
            return
        }
        #expect(lookupIntent.objectTypeRaws.contains("card"))
        #expect(lookupIntent.searchText == "Apple Card")

        guard case .scenario(let scenarioIntent) = scenario else {
            Issue.record("Expected scenario intent.")
            return
        }
        #expect(scenarioIntent.amount == 200)

        guard case .clarification(let clarificationIntent) = clarification else {
            Issue.record("Expected clarification intent.")
            return
        }
        #expect(clarificationIntent.ambiguousFieldRaws == ["target"])
    }

    @Test func v2Scenario_bridgesToBudgetForecastSemanticCommand() {
        let scenario = MarinaAIIntentV2.scenario(
            MarinaAIScenarioIntentV2(
                reasoning: "Hypothetical scenario.",
                scenarioRaw: "whatIf",
                targetTypeRaw: "category",
                targetName: "Dining",
                valueModeRaw: "decreaseByAmount",
                amount: 200,
                percent: nil,
                dateRange: nil,
                confidenceRaw: "medium"
            )
        )

        #expect(scenario.kind == .scenario)
        guard case .semanticCommand(let command) = scenario.structuredIntent else {
            Issue.record("Expected scenario to bridge to semantic command.")
            return
        }
        #expect(command.family == .planning)
        #expect(command.action == .simulate)
        #expect(command.datasets == [.budgets])
        #expect(command.measure == .remainingBudget)
        #expect(command.includeFilters.first?.rawText == "Dining")
        #expect(command.includeFilters.first?.allowedTypes == [.category])
    }

    @Test func v2Unsupported_bridgesToUnresolvedForLegacyPipeline() {
        let unsupported = MarinaAIIntentV2.unsupported(
            MarinaAIUnsupportedIntentV2(
                reasoning: "CRUD is outside this contract.",
                reasonRaw: "crud",
                message: "I cannot do that here."
            )
        )

        #expect(unsupported.kind == .unsupported)
        #expect(unsupported.structuredIntent == .unresolved)
    }

    @Test func fakeAIInterpreter_returnsScriptedIntentDeterministically() async throws {
        let scriptedIntent = MarinaAIIntentV2.lookup(
            MarinaAILookupIntentV2(
                reasoning: "Find card details.",
                objectTypeRaws: ["card"],
                searchText: "Apple Card",
                requestedDetailRaw: "balance",
                dateRange: nil,
                limit: 1,
                confidenceRaw: "high"
            )
        )
        let fake = MarinaFakeAIInterpreter(
            scriptedIntents: ["show Apple Card": scriptedIntent]
        )

        let result = try await fake.interpretAI(
            prompt: "show Apple Card",
            context: routerContext()
        )

        #expect(result == scriptedIntent)
        #expect(await fake.receivedPrompts == ["show Apple Card"])
    }

    private func route(_ raw: String) -> MarinaFoundationRouteKind {
        MarinaFoundationRouteKind(routeRaw: raw)
    }

    private func routerContext() -> MarinaLanguageRouterContext {
        MarinaLanguageRouterContext(
            workspaceName: "Personal",
            defaultPeriodUnit: .month,
            sessionContext: HomeAssistantSessionContext(),
            priorQueryContext: .empty,
            cardNames: ["Apple Card"],
            categoryNames: ["Dining"],
            incomeSourceNames: ["Salary"],
            presetTitles: [],
            budgetNames: [],
            aliasSummaries: [],
            now: Date(timeIntervalSince1970: 1_779_465_600)
        )
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func envelope(
        routeRaw: String,
        subjectRaw: String? = nil,
        operationRaw: String? = nil,
        measureRaw: String? = nil,
        targetText: String? = nil,
        targetTypeRaw: String? = nil,
        secondaryTargetText: String? = nil,
        secondaryTargetTypeRaw: String? = nil,
        excludeTargetText: String? = nil,
        excludeTargetTypeRaw: String? = nil,
        startISO8601: String? = nil,
        endISO8601: String? = nil,
        comparisonStartISO8601: String? = nil,
        comparisonEndISO8601: String? = nil,
        dateRawText: String? = nil,
        periodUnitRaw: String? = nil,
        groupingRaw: String? = nil,
        rankingRaw: String? = nil,
        requestedDetailRaw: String? = nil,
        limitRaw: String? = nil,
        incomeStatusRaw: String? = nil,
        insightIntentRaw: String? = nil,
        softTimeHintRaw: String? = nil,
        scenarioRaw: String? = nil,
        scenarioAmountRaw: String? = nil,
        scenarioPercentRaw: String? = nil,
        scenarioValueModeRaw: String? = nil,
        clarificationKindRaw: String? = nil,
        clarificationMessage: String? = nil,
        clarificationFieldRaw: String? = nil,
        clarificationPatchSlotRaw: String? = nil,
        unsupportedReasonRaw: String? = nil,
        unsupportedMessage: String? = nil,
        confidenceRaw: String? = "high"
    ) -> MarinaFoundationIntentEnvelopeV2 {
        MarinaFoundationIntentEnvelopeV2(
            routeRaw: routeRaw,
            subjectRaw: subjectRaw,
            operationRaw: operationRaw,
            measureRaw: measureRaw,
            targetText: targetText,
            targetTypeRaw: targetTypeRaw,
            secondaryTargetText: secondaryTargetText,
            secondaryTargetTypeRaw: secondaryTargetTypeRaw,
            excludeTargetText: excludeTargetText,
            excludeTargetTypeRaw: excludeTargetTypeRaw,
            startISO8601: startISO8601,
            endISO8601: endISO8601,
            comparisonStartISO8601: comparisonStartISO8601,
            comparisonEndISO8601: comparisonEndISO8601,
            dateRawText: dateRawText,
            periodUnitRaw: periodUnitRaw,
            groupingRaw: groupingRaw,
            rankingRaw: rankingRaw,
            requestedDetailRaw: requestedDetailRaw,
            limitRaw: limitRaw,
            incomeStatusRaw: incomeStatusRaw,
            insightIntentRaw: insightIntentRaw,
            softTimeHintRaw: softTimeHintRaw,
            scenarioRaw: scenarioRaw,
            scenarioAmountRaw: scenarioAmountRaw,
            scenarioPercentRaw: scenarioPercentRaw,
            scenarioValueModeRaw: scenarioValueModeRaw,
            clarificationKindRaw: clarificationKindRaw,
            clarificationMessage: clarificationMessage,
            clarificationFieldRaw: clarificationFieldRaw,
            clarificationPatchSlotRaw: clarificationPatchSlotRaw,
            unsupportedReasonRaw: unsupportedReasonRaw,
            unsupportedMessage: unsupportedMessage,
            confidenceRaw: confidenceRaw
        )
    }
}
