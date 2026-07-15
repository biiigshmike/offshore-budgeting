import Foundation
import SwiftData
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels

@Suite(.serialized)
@MainActor
struct MarinaFoundationModelStagedGenerationV3Tests {
    private typealias Generated = MarinaFoundationModelGeneratedOutcomeV3
    private typealias OutcomeRoute = MarinaFoundationModelGeneratedOutcomeRouteV3
    private typealias OutcomePayload = MarinaFoundationModelOutcomePayloadSchemaV3
    private typealias FinancialDomain = MarinaFoundationModelGeneratedFinancialDomainV3
    private typealias QueryDomain = MarinaFoundationModelQueryDomainV3
    private typealias ActionRoute = MarinaFoundationModelGeneratedActionRouteV3
    private typealias AuthoredAction = MarinaFoundationModelAuthoredActionRouteV3
    private typealias ActionPayload = MarinaFoundationModelActionPayloadSchemaV3

    @Test func everyV31PhaseDefinitionFitsTheMeasuredRegressionCeiling() {
        let locale = MarinaFoundationModelLocaleConfiguration(
            locale: Locale(identifier: "en_US")
        )
        let catalog = MarinaFoundationModelInstructionCatalogV3.production
        var oversizedDefinitions: [String] = []
        var largestDefinitionBytes = definitionBytes(
            schema: OutcomeRoute.generationSchema.debugDescription,
            instructions: catalog.outcomeRouteText(localeConfiguration: locale)
        )
        print("Marina V3.1 phase=outcomeRoute definitionBytes=\(largestDefinitionBytes)")
        if largestDefinitionBytes >= MarinaFoundationModelInstructionCatalogV3.maximumPhaseDefinitionBytes {
            oversizedDefinitions.append("outcomeRoute=\(largestDefinitionBytes)")
        }

        let financialDomainBytes = definitionBytes(
            schema: FinancialDomain.generationSchema.debugDescription,
            instructions: catalog.financialDomainText(localeConfiguration: locale)
        )
        largestDefinitionBytes = max(largestDefinitionBytes, financialDomainBytes)
        print("Marina V3.1 phase=financialDomain definitionBytes=\(financialDomainBytes)")
        if financialDomainBytes >= MarinaFoundationModelInstructionCatalogV3.maximumPhaseDefinitionBytes {
            oversizedDefinitions.append("financialDomain=\(financialDomainBytes)")
        }

        for domain in queryDomains {
            let bytes = definitionBytes(
                schema: actionRouteSchemaDescription(domain),
                instructions: catalog.actionRouteText(
                    for: domain,
                    localeConfiguration: locale
                )
            )
            largestDefinitionBytes = max(largestDefinitionBytes, bytes)
            print("Marina V3.1 phase=actionRoute domain=\(domain) definitionBytes=\(bytes)")
            if bytes >= MarinaFoundationModelInstructionCatalogV3.maximumPhaseDefinitionBytes {
                oversizedDefinitions.append("actionRoute.\(domain)=\(bytes)")
            }
        }

        for action in ActionPayload.allCases {
            let bytes = definitionBytes(
                schema: actionPayloadSchemaDescription(action),
                instructions: catalog.actionPayloadText(
                    for: action,
                    localeConfiguration: locale
                )
            )
            largestDefinitionBytes = max(largestDefinitionBytes, bytes)
            print("Marina V3.1 phase=actionPayload action=\(action.rawValue) definitionBytes=\(bytes)")
            if bytes >= MarinaFoundationModelInstructionCatalogV3.maximumPhaseDefinitionBytes {
                oversizedDefinitions.append("actionPayload.\(action.rawValue)=\(bytes)")
            }
        }

        for terminal in [OutcomePayload.clarificationSelection, .followUpDecision, .unsupported] {
            let bytes = definitionBytes(
                schema: terminalPayloadSchemaDescription(terminal),
                instructions: catalog.terminalPayloadText(
                    for: terminal,
                    localeConfiguration: locale
                )
            )
            largestDefinitionBytes = max(largestDefinitionBytes, bytes)
            print("Marina V3.1 phase=terminalPayload route=\(terminal) definitionBytes=\(bytes)")
            if bytes >= MarinaFoundationModelInstructionCatalogV3.maximumPhaseDefinitionBytes {
                oversizedDefinitions.append("terminalPayload.\(terminal)=\(bytes)")
            }
        }

        let monolithicBytes = Generated.generationSchema.debugDescription.utf8.count
        #expect(
            oversizedDefinitions.isEmpty,
            "Staged definitions exceeded the measured regression ceiling: \(oversizedDefinitions.joined(separator: ", "))"
        )
        #expect(largestDefinitionBytes < monolithicBytes)
        #expect(largestDefinitionBytes * 4 < monolithicBytes)
        #expect(monolithicBytes > MarinaFoundationModelInstructionCatalogV3.maximumPhaseDefinitionBytes)
    }

    @Test func outcomeSchemaSelectionIsOnlyTheModelAuthoredRoute() {
        for (route, expectedPayload) in outcomeRoutesAndPayloads {
            let plan = MarinaFoundationModelOutcomeGenerationPlanV3(
                modelAuthoredRoute: route
            )
            #expect(plan.payloadSchema == expectedPayload)
            #expect(Mirror(reflecting: plan).children.compactMap(\.label) == ["payloadSchema"])
        }
    }

    @Test func everyFinancialDomainSelectsExactlyOneNonWorkspaceQueryDomain() {
        #expect(financialDomainsAndQueries.count == 10)
        #expect(financialDomainsAndQueries.map(\.1).contains(.workspaceMetadata) == false)

        for (domain, expectedQueryDomain) in financialDomainsAndQueries {
            let plan = MarinaFoundationModelFinancialDomainGenerationPlanV3(
                modelAuthoredDomain: domain
            )
            #expect(plan.queryDomain == expectedQueryDomain)
            #expect(Mirror(reflecting: plan).children.compactMap(\.label) == ["queryDomain"])
        }
    }

    @Test func financialDomainGenerationCannotExpressWorkspaceMetadata() {
        let definition = FinancialDomain.generationSchema.debugDescription
        #expect(definition.contains("workspaceMetadata") == false)
        #expect(definition.contains("financialQuery") == false)
        #expect(financialDomainsAndQueries.map(\.1) == financialQueryDomains)
    }

    @Test func outcomeAndFinancialRoutesRetainOnlyTypedAuthoredPath() {
        let financialRoute = OutcomeRoute.financialQuery.generatedIntentDigest
        #expect(financialRoute.intent == .query)
        #expect(financialRoute.entity == nil)

        let workspaceRoute = OutcomeRoute.workspaceMetadata.generatedIntentDigest
        #expect(workspaceRoute.intent == .workspaceMetadata)
        #expect(workspaceRoute.entity == .workspace)

        let incomeDomain = FinancialDomain.income.generatedIntentDigest
        #expect(incomeDomain.intent == .query)
        #expect(incomeDomain.entity == .income)
        #expect(incomeDomain.operation == nil)
    }

    @Test func everyActionSchemaSelectionIsOnlyTheModelAuthoredActionRoute() {
        #expect(actionRoutesAndPayloads.count == ActionPayload.allCases.count)
        #expect(Set(actionRoutesAndPayloads.map { $0.1 }) == Set(ActionPayload.allCases))

        for (route, expectedPayload) in actionRoutesAndPayloads {
            let plan = MarinaFoundationModelActionGenerationPlanV3(
                modelAuthoredActionRoute: route
            )
            #expect(plan.payloadSchema == expectedPayload)
            #expect(Mirror(reflecting: plan).children.compactMap(\.label) == ["payloadSchema"])
        }
    }

    @Test func actionRouteDigestPreservesExactModelAuthoredPath() {
        let availability = AuthoredAction.category(.availabilityList).generatedIntentDigest
        #expect(availability.entity == .category)
        #expect(availability.operation == .list)
        #expect(availability.intent == .categoryAvailability)

        let summary = AuthoredAction.category(.availabilitySummary).generatedIntentDigest
        #expect(summary.entity == .category)
        #expect(summary.operation == .forecast)
        #expect(summary.intent == .categoryAvailability)
    }

    @Test func stagedDefinitionsContainNoRequestOrExpectedTupleData() {
        let privateRequest = "Merchant Secret 123.45 11111111-2222-3333-4444-555555555555"
        let locale = MarinaFoundationModelLocaleConfiguration(locale: Locale(identifier: "en_US"))
        let catalog = MarinaFoundationModelInstructionCatalogV3.production
        expectNoPrivateOrSynthesisData(
            catalog.outcomeRouteText(localeConfiguration: locale)
                + OutcomeRoute.generationSchema.debugDescription,
            privateRequest: privateRequest
        )
        expectNoPrivateOrSynthesisData(
            catalog.financialDomainText(localeConfiguration: locale)
                + FinancialDomain.generationSchema.debugDescription,
            privateRequest: privateRequest
        )

        for domain in queryDomains {
            let definition = catalog.actionRouteText(for: domain, localeConfiguration: locale)
                + actionRouteSchemaDescription(domain)
            expectNoPrivateOrSynthesisData(definition, privateRequest: privateRequest)
        }
        for action in ActionPayload.allCases {
            let definition = catalog.actionPayloadText(for: action, localeConfiguration: locale)
                + actionPayloadSchemaDescription(action)
            expectNoPrivateOrSynthesisData(definition, privateRequest: privateRequest)
        }
        for terminal in [OutcomePayload.clarificationSelection, .followUpDecision, .unsupported] {
            let definition = catalog.terminalPayloadText(for: terminal, localeConfiguration: locale)
                + terminalPayloadSchemaDescription(terminal)
            expectNoPrivateOrSynthesisData(definition, privateRequest: privateRequest)
        }
    }

    @Test func productionInstructionCatalogOwnsEveryPhaseAndObservedExamples() {
        let locale = MarinaFoundationModelLocaleConfiguration(locale: Locale(identifier: "en_US"))
        let catalog = MarinaFoundationModelInstructionCatalogV3.production
        let outcomeRoute = catalog.outcomeRouteText(localeConfiguration: locale)
        #expect(MarinaFoundationModelInstructionCatalogV3.compilerVersion == "marina.semantic-compiler.v3")
        #expect(MarinaFoundationModelInstructionCatalogV3.instructionVersion == "marina.semantic-generation.v3.1")
        #expect(MarinaSemanticCompilerInstructionsV3.version == MarinaFoundationModelInstructionCatalogV3.compilerVersion)
        #expect(outcomeRoute.contains("Which categories were over the limit for last month?"))
        #expect(outcomeRoute.contains("What is my income for the current period?"))
        #expect(outcomeRoute.contains("chooses financialQuery"))
        #expect(outcomeRoute.contains("workspaceMetadata is only"))
        #expect(outcomeRoute.contains("alignment.entityMismatch"))

        let financialDomain = catalog.financialDomainText(localeConfiguration: locale)
        #expect(financialDomain.contains("chooses category"))
        #expect(financialDomain.contains("chooses income"))
        #expect(financialDomain.contains("workspaceMetadata") == false)

        let categoryRoute = catalog.actionRouteText(for: .category, localeConfiguration: locale)
        #expect(categoryRoute.contains("categoryFilterMismatch"))
        #expect(categoryRoute.contains("availabilityList"))
        #expect(categoryRoute.contains("groupedSpend"))

        let categoryPayload = catalog.actionPayloadText(
            for: .categoryAvailabilityList,
            localeConfiguration: locale
        )
        #expect(categoryPayload.contains("over, near, or underLimit"))
        #expect(categoryPayload.contains("explicit(previousMonth)"))

        let incomePayload = catalog.actionPayloadText(
            for: .incomeSum,
            localeConfiguration: locale
        )
        #expect(incomePayload.contains("actual and explicit(currentPeriod)"))

        let allPhaseInstructions = [outcomeRoute, financialDomain]
            + queryDomains.map { catalog.actionRouteText(for: $0, localeConfiguration: locale) }
            + ActionPayload.allCases.map {
                catalog.actionPayloadText(for: $0, localeConfiguration: locale)
            }
            + [OutcomePayload.clarificationSelection, .followUpDecision, .unsupported].map {
                catalog.terminalPayloadText(for: $0, localeConfiguration: locale)
            }
        #expect(allPhaseInstructions.allSatisfy {
            $0.contains(MarinaFoundationModelInstructionCatalogV3.compilerVersion)
                && $0.contains(MarinaFoundationModelInstructionCatalogV3.instructionVersion)
        })
    }

    @Test func periodOnlyComparisonDoesNotSynthesizeANamedTarget() throws {
        let selection = Generated.Selection(
            dataBoundary: .activeWorkspace,
            target: nil,
            namedFilters: [],
            dateSelection: .explicit(.currentMonth)
        )
        let comparison = Generated.IncomeComparison(
            measure: .incomeAmount,
            state: .actual,
            selection: Generated.ComparisonSelection(
                selection: selection,
                comparisonTarget: nil
            )
        )
        let outcome = Generated.query(.income(Generated.IncomeQuery(
            action: .compare(comparison)
        )))

        let request = try MarinaFoundationModelOutcomeCompilerV3().interpretedRequest(
            from: outcome,
            turn: MarinaSemanticCompilerTurnV3(
                userInput: "Compare my income this month with last month",
                conversationContext: .empty
            )
        ).request

        #expect(request.entity == .income)
        #expect(request.operation == .compare)
        #expect(request.measure == .incomeAmount)
        #expect(request.incomeState == .actual)
        #expect(request.comparisonTargetName == nil)
        #expect(request.comparisonTargetKindSource == .unspecified)
    }

    @Test func payloadFailureRetainsOnlyTheTypedModelAuthoredRouteDigest() async throws {
        let routeDigest = AuthoredAction.income(.sum).generatedIntentDigest
        let routePath = MarinaFoundationModelGeneratedRoutePathDigest(
            outcome: .financialQuery,
            financialDomain: .income,
            actionRoute: .incomeSum,
            actionPayload: .incomeSum
        )
        let phaseDurations = [
            MarinaFoundationModelGenerationPhaseDuration(
                phase: .outcomeRoute,
                milliseconds: 7
            ),
            MarinaFoundationModelGenerationPhaseDuration(
                phase: .financialDomain,
                milliseconds: 5
            ),
            MarinaFoundationModelGenerationPhaseDuration(
                phase: .actionRoute,
                milliseconds: 3
            ),
            MarinaFoundationModelGenerationPhaseDuration(
                phase: .actionPayload,
                milliseconds: 11
            )
        ]
        let runtime = StagedFailureRuntime(result: .stagedFailure(
            .generation(.unsupportedGuide),
            generatedIntent: routeDigest,
            generationMetadata: MarinaFoundationModelGenerationDiagnosticMetadata(
                phase: .actionPayload,
                phaseCount: .four,
                routePath: routePath,
                phaseDurations: phaseDurations
            ),
            diagnosticNotes: []
        ))
        let interpreter = MarinaFoundationModelsInterpreter(
            runtime: runtime,
            localeConfiguration: MarinaFoundationModelLocaleConfiguration(
                locale: Locale(identifier: "en_US")
            )
        )

        let interpreted = try await interpreter.interpretedSemanticRequest(
            for: "Private Merchant 123.45",
            context: try brainContext()
        )

        #expect(interpreted.request.unsupportedReason == .modelGenerationFailed)
        #expect(interpreted.attemptDiagnostics.count == 1)
        #expect(interpreted.attemptDiagnostics[0].generatedIntent == routeDigest)
        #expect(interpreted.attemptDiagnostics[0].generatedIntent?.entity == .income)
        #expect(interpreted.attemptDiagnostics[0].generatedIntent?.operation == .sum)
        #expect(interpreted.attemptDiagnostics[0].instructionVersion == "marina.semantic-generation.v3.1")
        #expect(interpreted.attemptDiagnostics[0].generationPhase == .actionPayload)
        #expect(interpreted.attemptDiagnostics[0].generationPhaseCount == .four)
        #expect(interpreted.attemptDiagnostics[0].generatedRoutePath == routePath)
        #expect(interpreted.attemptDiagnostics[0].generationPhaseDurations == phaseDurations)
        #expect(interpreted.attemptDiagnostics[0].diagnosticNote.contains("generationDurationMilliseconds=26"))
        #expect(interpreted.attemptDiagnostics[0].diagnosticNote.contains("Private Merchant") == false)
    }

    private var queryDomains: [QueryDomain] {
        [
            .workspaceMetadata, .budget, .card, .plannedExpense, .variableExpense,
            .reconciliationAccount, .savingsAccount, .income, .incomeSeries,
            .category, .preset
        ]
    }

    private var financialQueryDomains: [QueryDomain] {
        [
            .budget, .card, .plannedExpense, .variableExpense, .reconciliationAccount,
            .savingsAccount, .income, .incomeSeries, .category, .preset
        ]
    }

    private var outcomeRoutesAndPayloads: [(OutcomeRoute, OutcomePayload)] {
        [
            (.financialQuery, .financialDomain), (.workspaceMetadata, .workspaceMetadata),
            (.clarificationSelection, .clarificationSelection),
            (.followUpDecision, .followUpDecision), (.unsupported, .unsupported)
        ]
    }

    private var financialDomainsAndQueries: [(FinancialDomain, QueryDomain)] {
        [
            (.budget, .budget), (.card, .card), (.plannedExpense, .plannedExpense),
            (.variableExpense, .variableExpense), (.reconciliationAccount, .reconciliationAccount),
            (.savingsAccount, .savingsAccount), (.income, .income),
            (.incomeSeries, .incomeSeries), (.category, .category), (.preset, .preset)
        ]
    }

    private var actionRoutesAndPayloads: [(AuthoredAction, ActionPayload)] {
        [
            (.workspaceMetadata(.list), .workspaceList),
            (.workspaceMetadata(.count), .workspaceCount),
            (.workspaceMetadata(.name), .workspaceName),
            (.workspaceMetadata(.color), .workspaceColor),
            (.budget(.list), .budgetList),
            (.budget(.sum), .budgetSum),
            (.budget(.average), .budgetAverage),
            (.budget(.compare), .budgetCompare),
            (.budget(.forecast), .budgetForecast),
            (.budget(.whatIf), .budgetWhatIf),
            (.card(.list), .cardList),
            (.card(.count), .cardCount),
            (.card(.sum), .cardSum),
            (.card(.compare), .cardCompare),
            (.card(.group), .cardGroup),
            (.plannedExpense(.list), .plannedExpenseList),
            (.plannedExpense(.count), .plannedExpenseCount),
            (.plannedExpense(.sum), .plannedExpenseSum),
            (.plannedExpense(.average), .plannedExpenseAverage),
            (.plannedExpense(.last), .plannedExpenseLast),
            (.plannedExpense(.next), .plannedExpenseNext),
            (.plannedExpense(.group), .plannedExpenseGroup),
            (.variableExpense(.list), .variableExpenseList),
            (.variableExpense(.count), .variableExpenseCount),
            (.variableExpense(.sum), .variableExpenseSum),
            (.variableExpense(.average), .variableExpenseAverage),
            (.variableExpense(.last), .variableExpenseLast),
            (.variableExpense(.group), .variableExpenseGroup),
            (.reconciliationAccount(.list), .reconciliationList),
            (.reconciliationAccount(.count), .reconciliationCount),
            (.reconciliationAccount(.sum), .reconciliationSum),
            (.reconciliationAccount(.group), .reconciliationGroup),
            (.savingsAccount(.list), .savingsList),
            (.savingsAccount(.count), .savingsCount),
            (.savingsAccount(.sum), .savingsSum),
            (.savingsAccount(.last), .savingsLast),
            (.savingsAccount(.group), .savingsGroup),
            (.savingsAccount(.forecast), .savingsForecast),
            (.income(.list), .incomeList),
            (.income(.count), .incomeCount),
            (.income(.sum), .incomeSum),
            (.income(.average), .incomeAverage),
            (.income(.compare), .incomeCompare),
            (.income(.group), .incomeGroup),
            (.income(.progress), .incomeProgress),
            (.income(.coverage), .incomeCoverage),
            (.income(.forecast), .incomeForecast),
            (.incomeSeries(.list), .incomeSeriesList),
            (.incomeSeries(.count), .incomeSeriesCount),
            (.incomeSeries(.last), .incomeSeriesLast),
            (.incomeSeries(.next), .incomeSeriesNext),
            (.category(.list), .categoryList),
            (.category(.count), .categoryCount),
            (.category(.sum), .categorySum),
            (.category(.average), .categoryAverage),
            (.category(.compare), .categoryCompare),
            (.category(.groupedSpend), .categoryGroupedSpend),
            (.category(.share), .categoryShare),
            (.category(.forecast), .categoryForecast),
            (.category(.availabilitySummary), .categoryAvailabilitySummary),
            (.category(.availabilityList), .categoryAvailabilityList),
            (.preset(.list), .presetList),
            (.preset(.sum), .presetSum),
            (.preset(.next), .presetNext),
            (.preset(.group), .presetGroup)
        ]
    }

    private func definitionBytes(schema: String, instructions: String) -> Int {
        schema.utf8.count + instructions.utf8.count
    }

    private func expectNoPrivateOrSynthesisData(
        _ definition: String,
        privateRequest: String
    ) {
        #expect(definition.contains(privateRequest) == false)
        #expect(definition.contains("MarinaStarterPromptCatalog") == false)
        #expect(definition.contains("expectedAnchor") == false)
        #expect(definition.contains("replacementSemanticTuple") == false)
    }

    private func actionRouteSchemaDescription(_ domain: QueryDomain) -> String {
        switch domain {
        case .workspaceMetadata: ActionRoute.WorkspaceMetadata.generationSchema.debugDescription
        case .budget: ActionRoute.Budget.generationSchema.debugDescription
        case .card: ActionRoute.Card.generationSchema.debugDescription
        case .plannedExpense: ActionRoute.PlannedExpense.generationSchema.debugDescription
        case .variableExpense: ActionRoute.VariableExpense.generationSchema.debugDescription
        case .reconciliationAccount: ActionRoute.ReconciliationAccount.generationSchema.debugDescription
        case .savingsAccount: ActionRoute.SavingsAccount.generationSchema.debugDescription
        case .income: ActionRoute.Income.generationSchema.debugDescription
        case .incomeSeries: ActionRoute.IncomeSeries.generationSchema.debugDescription
        case .category: ActionRoute.Category.generationSchema.debugDescription
        case .preset: ActionRoute.Preset.generationSchema.debugDescription
        }
    }

    private func actionPayloadSchemaDescription(_ action: ActionPayload) -> String {
        switch action {
        case .workspaceList: Generated.WorkspaceList.generationSchema.debugDescription
        case .workspaceCount: Generated.WorkspaceCount.generationSchema.debugDescription
        case .workspaceName: Generated.WorkspaceMetadataValue.generationSchema.debugDescription
        case .workspaceColor: Generated.WorkspaceMetadataValue.generationSchema.debugDescription
        case .budgetList: Generated.BudgetList.generationSchema.debugDescription
        case .budgetSum: Generated.BudgetMetric.generationSchema.debugDescription
        case .budgetAverage: Generated.BudgetMetric.generationSchema.debugDescription
        case .budgetCompare: Generated.BudgetComparison.generationSchema.debugDescription
        case .budgetForecast: Generated.BudgetForecast.generationSchema.debugDescription
        case .budgetWhatIf: Generated.BudgetWhatIf.generationSchema.debugDescription
        case .cardList: Generated.CardList.generationSchema.debugDescription
        case .cardCount: Generated.CardCount.generationSchema.debugDescription
        case .cardSum: Generated.CardMetric.generationSchema.debugDescription
        case .cardCompare: Generated.CardComparison.generationSchema.debugDescription
        case .cardGroup: Generated.CardGroup.generationSchema.debugDescription
        case .plannedExpenseList: Generated.PlannedExpenseList.generationSchema.debugDescription
        case .plannedExpenseCount: Generated.ExpenseCount.generationSchema.debugDescription
        case .plannedExpenseSum: Generated.PlannedExpenseMetric.generationSchema.debugDescription
        case .plannedExpenseAverage: Generated.PlannedExpenseMetric.generationSchema.debugDescription
        case .plannedExpenseLast: Generated.PlannedExpenseSingle.generationSchema.debugDescription
        case .plannedExpenseNext: Generated.PlannedExpenseSingle.generationSchema.debugDescription
        case .plannedExpenseGroup: Generated.PlannedExpenseGroup.generationSchema.debugDescription
        case .variableExpenseList: Generated.VariableExpenseList.generationSchema.debugDescription
        case .variableExpenseCount: Generated.ExpenseCount.generationSchema.debugDescription
        case .variableExpenseSum: Generated.VariableExpenseMetric.generationSchema.debugDescription
        case .variableExpenseAverage: Generated.VariableExpenseMetric.generationSchema.debugDescription
        case .variableExpenseLast: Generated.VariableExpenseSingle.generationSchema.debugDescription
        case .variableExpenseGroup: Generated.VariableExpenseGroup.generationSchema.debugDescription
        case .reconciliationList: Generated.ReconciliationList.generationSchema.debugDescription
        case .reconciliationCount: Generated.AccountCount.generationSchema.debugDescription
        case .reconciliationSum: Generated.ReconciliationMetric.generationSchema.debugDescription
        case .reconciliationGroup: Generated.ReconciliationGroup.generationSchema.debugDescription
        case .savingsList: Generated.SavingsList.generationSchema.debugDescription
        case .savingsCount: Generated.AccountCount.generationSchema.debugDescription
        case .savingsSum: Generated.SavingsMetric.generationSchema.debugDescription
        case .savingsLast: Generated.SavingsMetric.generationSchema.debugDescription
        case .savingsGroup: Generated.SavingsGroup.generationSchema.debugDescription
        case .savingsForecast: Generated.SavingsMetric.generationSchema.debugDescription
        case .incomeList: Generated.IncomeList.generationSchema.debugDescription
        case .incomeCount: Generated.IncomeCount.generationSchema.debugDescription
        case .incomeSum: Generated.IncomeMetric.generationSchema.debugDescription
        case .incomeAverage: Generated.IncomeMetric.generationSchema.debugDescription
        case .incomeCompare: Generated.IncomeComparison.generationSchema.debugDescription
        case .incomeGroup: Generated.IncomeGroup.generationSchema.debugDescription
        case .incomeProgress: Generated.IncomeProgress.generationSchema.debugDescription
        case .incomeCoverage: Generated.IncomeCoverage.generationSchema.debugDescription
        case .incomeForecast: Generated.IncomeForecast.generationSchema.debugDescription
        case .incomeSeriesList: Generated.IncomeSeriesList.generationSchema.debugDescription
        case .incomeSeriesCount: Generated.IncomeSeriesCount.generationSchema.debugDescription
        case .incomeSeriesLast: Generated.IncomeSeriesSingle.generationSchema.debugDescription
        case .incomeSeriesNext: Generated.IncomeSeriesSingle.generationSchema.debugDescription
        case .categoryList: Generated.CategoryList.generationSchema.debugDescription
        case .categoryCount: Generated.CategoryCount.generationSchema.debugDescription
        case .categorySum: Generated.CategoryMetric.generationSchema.debugDescription
        case .categoryAverage: Generated.CategoryMetric.generationSchema.debugDescription
        case .categoryCompare: Generated.CategoryComparison.generationSchema.debugDescription
        case .categoryGroupedSpend: Generated.CategoryGroupedSpend.generationSchema.debugDescription
        case .categoryShare: Generated.CategoryMetric.generationSchema.debugDescription
        case .categoryForecast: Generated.CategoryForecast.generationSchema.debugDescription
        case .categoryAvailabilitySummary: Generated.CategoryAvailabilitySummary.generationSchema.debugDescription
        case .categoryAvailabilityList: Generated.CategoryAvailabilityList.generationSchema.debugDescription
        case .presetList: Generated.PresetList.generationSchema.debugDescription
        case .presetSum: Generated.PresetMetric.generationSchema.debugDescription
        case .presetNext: Generated.PresetSingle.generationSchema.debugDescription
        case .presetGroup: Generated.PresetGroup.generationSchema.debugDescription
        }
    }

    private func terminalPayloadSchemaDescription(_ route: OutcomePayload) -> String {
        switch route {
        case .clarificationSelection: Generated.ClarificationSelection.generationSchema.debugDescription
        case .followUpDecision: Generated.FollowUpDecision.generationSchema.debugDescription
        case .unsupported: Generated.Unsupported.generationSchema.debugDescription
        case .financialDomain, .workspaceMetadata: ""
        }
    }



    private func brainContext() throws -> MarinaBrainContext {
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
        let modelContext = ModelContext(container)
        let workspace = Workspace(name: "Personal", hexColor: "#2563EB")
        modelContext.insert(workspace)
        return MarinaBrainContext(
            workspace: workspace,
            modelContext: modelContext,
            ambientDateRange: HomeQueryDateRange(startDate: .now, endDate: .now),
            defaultBudgetingPeriod: .monthly,
            now: .now,
            conversationContext: .empty
        )
    }
}

@MainActor
private final class StagedFailureRuntime: MarinaFoundationModelGenerating {
    private let result: MarinaFoundationModelRuntimeResult

    init(result: MarinaFoundationModelRuntimeResult) {
        self.result = result
    }

    func generateOutcome(
        for prompt: String,
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async -> MarinaFoundationModelRuntimeResult {
        result
    }
}
#endif
