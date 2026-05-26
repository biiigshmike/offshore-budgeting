import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaUniversalQueryTests {
    @Test func catalog_coversAllSwiftDataModelsWithUniversalMetadata() {
        let catalog = MarinaEntityCatalog.current
        let expected: Set<String> = [
            "Workspace",
            "Budget",
            "BudgetCategoryLimit",
            "Card",
            "BudgetCardLink",
            "BudgetPresetLink",
            "Category",
            "Preset",
            "PlannedExpense",
            "VariableExpense",
            "AllocationAccount",
            "ExpenseAllocation",
            "AllocationSettlement",
            "SavingsAccount",
            "SavingsLedgerEntry",
            "ImportMerchantRule",
            "AssistantAliasRule",
            "IncomeSeries",
            "Income"
        ]

        #expect(catalog.persistentModelEntityNames == expected)
        for name in expected {
            guard let descriptor = catalog.descriptor(for: name) else {
                Issue.record("Missing descriptor for \(name)")
                continue
            }
            #expect(descriptor.displayFields.isEmpty == false)
            #expect(descriptor.workspaceScope.path.isEmpty == false)
            #expect(descriptor.evidenceRowType.isEmpty == false)
            #expect(descriptor.supportedOperations.map { $0.lowercased() }.contains("list"))
            #expect(descriptor.supportedOperations.map { $0.lowercased() }.contains("count"))
            #expect(descriptor.supportedOperations.map { $0.lowercased() }.contains("lookupdetails"))
            if descriptor.isSearchable {
                #expect(descriptor.searchableFields.isEmpty == false)
            }
        }

        let compiler = MarinaSemanticCatalogCompiler(catalog: catalog)
        for name in expected {
            guard let descriptor = catalog.descriptor(for: name) else { continue }
            let aliases = compiler.aliases(for: descriptor)
            let displayStem = splitCamelCase(descriptor.displayName).lowercased()
            let entityStem = splitCamelCase(descriptor.entityName).lowercased()
            #expect(aliases.isEmpty == false)
            #expect(aliases.contains { $0.contains(displayStem) || $0.contains(entityStem) })
        }
    }

    @Test func semanticCatalogCompiler_workspaceIdentityParaphrasesCompileToSelectedWorkspaceDetail() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let compiler = MarinaSemanticCatalogCompiler()
        let prompts = [
            "What workspace am I in?",
            "What is the name of this current workspace?",
            "Which workspace is selected?",
            "current workspace name"
        ]

        for prompt in prompts {
            let result = compiler.compile(
                prompt: prompt,
                interpretation: unsupportedInterpretation(prompt: prompt),
                candidate: universalCandidate(prompt),
                outcome: unsupportedOutcome(prompt: prompt),
                context: turnContext(provider: fixture.provider)
            )

            guard case .universal(let query, let reason) = result else {
                Issue.record("Expected \(prompt) to compile to selected workspace detail.")
                continue
            }
            #expect(reason.contains("semanticCatalogCompiler"))
            #expect(query.modelName == "Workspace")
            #expect(query.operation == .detail)
            #expect(query.workspaceScopePolicy == .selectedWorkspace)
            #expect(query.filters.isEmpty)
            #expect(query.presentationShape == .summaryCard)
        }
    }

    @Test func semanticCatalogCompiler_compilesWeakModelSafeCatalogPrompts() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let compiler = MarinaSemanticCatalogCompiler()
        let expected: [(prompt: String, model: String, operation: MarinaUniversalQueryOperation)] = [
            ("What is my income this month?", "Income", .sum),
            ("What is my savings this month?", "SavingsLedgerEntry", .sum),
            ("How many cards do I have?", "Card", .count),
            ("List import merchant rules", "ImportMerchantRule", .list)
        ]

        for expectation in expected {
            let result = compiler.compile(
                prompt: expectation.prompt,
                interpretation: unsupportedInterpretation(prompt: expectation.prompt),
                candidate: universalCandidate(expectation.prompt),
                outcome: unsupportedOutcome(prompt: expectation.prompt),
                context: turnContext(provider: fixture.provider)
            )

            guard case .universal(let query, _) = result else {
                Issue.record("Expected \(expectation.prompt) to compile through the catalog.")
                continue
            }
            #expect(query.modelName == expectation.model)
            #expect(query.operation == expectation.operation)
            #expect(query.workspaceScopePolicy == .selectedWorkspace)
        }
    }

    @Test func semanticCatalogCompiler_overridesMissingTargetForBroadActualIncomeAggregate() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompt = "What is my actual income this month?"
        let compiler = MarinaSemanticCatalogCompiler()
        let clarification = MarinaTypedClarification(
            kind: .missingTarget,
            message: "I need a clearer target.",
            candidate: universalCandidate(prompt),
            choices: [
                MarinaClarificationChoice(title: "Salary", entityTypeHint: .incomeSource, patchSlot: .target, rawValue: "Salary"),
                MarinaClarificationChoice(title: "Freelance", entityTypeHint: .incomeSource, patchSlot: .target, rawValue: "Freelance")
            ]
        )

        let result = compiler.compile(
            prompt: prompt,
            interpretation: MarinaTurnInterpretation(result: .clarification(clarification)),
            candidate: universalCandidate(prompt),
            outcome: .clarification(clarification),
            context: turnContext(provider: fixture.provider)
        )

        guard case .universal(let query, _) = result else {
            Issue.record("Expected broad actual income to compile instead of honoring missing-target clarification.")
            return
        }
        #expect(query.modelName == "Income")
        #expect(query.operation == .sum)
        #expect(query.filters.contains { $0.field == "income status" && $0.value == "actual" })
        #expect(query.dateRange != nil)
    }

    @Test func answerPlanner_compilesExecutableBroadReadTurnsWithoutWaitingForFailure() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompt = "Actual income"
        let query = MarinaSemanticQuery(
            subject: .income,
            operation: .sum,
            incomeStatusScope: .actual,
            responseShape: .summaryCard
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .sum,
            measure: .income,
            confidence: .high
        )
        let outcome = MarinaPlanValidationOutcome.executable(
            MarinaAggregationPlan(
                operation: .sum,
                measure: .income,
                incomeStatusScope: .actual,
                responseShape: .scalarCurrency
            )
        )

        let plan = MarinaAnswerPlanner().plan(
            prompt: prompt,
            interpretation: MarinaTurnInterpretation(result: .query(query)),
            candidate: candidate,
            outcome: outcome,
            context: turnContext(provider: fixture.provider)
        )

        guard case .execute(.universal(let universalQuery), metadata: let metadata, reason: let reason) = plan else {
            Issue.record("Expected broad executable income query to become an answer-first universal plan.")
            return
        }
        #expect(reason.contains("semanticCatalogCompiler"))
        #expect(metadata.confidence == .high)
        #expect(metadata.amountBasis == .incomeAmount)
        #expect(universalQuery.modelName == "Income")
        #expect(universalQuery.operation == .sum)
        #expect(universalQuery.filters.contains { $0.field == "income status" && $0.value == "actual" })
    }

    @Test func semanticCatalogCompiler_doesNotFlattenExplicitNamedTargetsIntoBroadAggregates() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompt = "What is my income from Salary this month?"
        let compiler = MarinaSemanticCatalogCompiler()

        let result = compiler.compile(
            prompt: prompt,
            interpretation: unsupportedInterpretation(prompt: prompt),
            candidate: universalCandidate(prompt),
            outcome: unsupportedOutcome(prompt: prompt),
            context: turnContext(provider: fixture.provider)
        )

        #expect(result == .none)
    }

    @Test func semanticCatalogCompiler_preservesBudgetLimitDetailOverBudgetOverview() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompt = "Show my Groceries budget limit"
        let compiler = MarinaSemanticCatalogCompiler()
        let query = MarinaSemanticQuery(
            subject: .budgets,
            operation: .lookupDetails,
            filters: [
                MarinaFilter(
                    role: .primaryTarget,
                    relationship: .category,
                    value: "Groceries",
                    entityTypeHint: .category,
                    allowedEntityTypeHints: [.category]
                )
            ],
            responseShape: .summaryCard,
            requestedDetail: .categoryLimits
        )
        let candidate = MarinaSemanticQueryAdapter().compatibilityCandidate(from: query, prompt: prompt)

        let result = compiler.compile(
            prompt: prompt,
            interpretation: MarinaTurnInterpretation(result: .query(query)),
            candidate: candidate,
            outcome: .executable(MarinaAggregationPlan(operation: .lookupDetails, measure: .remainingBudget, responseShape: .summaryCard)),
            context: turnContext(provider: fixture.provider)
        )

        guard case .universal(let universalQuery, _) = result else {
            Issue.record("Expected budget-limit semantics to compile to the budget category limit catalog.")
            return
        }
        #expect(universalQuery.modelName == "BudgetCategoryLimit")
        #expect(universalQuery.operation == .detail)
        #expect(universalQuery.filters.contains { $0.field == "category" && $0.value == "Groceries" })
    }

    @Test func semanticCatalogCompiler_preservesRankAndGroupingFromModelIntent() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompt = "Where did my money go this month?"
        let compiler = MarinaSemanticCatalogCompiler()
        let range = HomeQueryDateRange(
            startDate: MarinaRealisticWorkspaceFixture.date(2026, 5, 1),
            endDate: MarinaRealisticWorkspaceFixture.date(2026, 5, 31)
        )
        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .rank,
            dateRange: MarinaDateRangeRequest(role: .primary, rawText: "this month", resolvedRange: range, periodUnit: .month),
            grouping: MarinaGrouping(dimension: .category, rawText: "category"),
            ranking: MarinaRanking(direction: .largest, limit: 5, rawText: "top"),
            limit: 5,
            responseShape: .rankedList
        )
        let candidate = MarinaSemanticQueryAdapter().compatibilityCandidate(from: query, prompt: prompt)

        let result = compiler.compile(
            prompt: prompt,
            interpretation: MarinaTurnInterpretation(result: .query(query)),
            candidate: candidate,
            outcome: .executable(MarinaAggregationPlan(operation: .rank, measure: .spend, dateRange: range, grouping: MarinaGroupingCandidate(dimension: .category), ranking: MarinaRankingCandidate(direction: .largest, limit: 5), limit: 5, responseShape: .rankedList)),
            context: turnContext(provider: fixture.provider)
        )

        guard case .universal(let universalQuery, _) = result else {
            Issue.record("Expected rank/category model semantics to survive catalog compilation.")
            return
        }
        #expect(universalQuery.modelName == "VariableExpense")
        #expect(universalQuery.operation == .rank)
        #expect(universalQuery.grouping == "category")
        #expect(universalQuery.presentationShape == .rankedList)
    }

    @Test func semanticCatalogCompiler_preservesModelFilterForCardDetails() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompt = "Show me my Apple Card"
        let compiler = MarinaSemanticCatalogCompiler()
        let query = MarinaSemanticQuery(
            subject: .cards,
            operation: .lookupDetails,
            filters: [
                MarinaFilter(
                    role: .primaryTarget,
                    relationship: .card,
                    value: "Apple Card",
                    entityTypeHint: .card,
                    allowedEntityTypeHints: [.card]
                )
            ],
            responseShape: .summaryCard
        )
        let candidate = MarinaSemanticQueryAdapter().compatibilityCandidate(from: query, prompt: prompt)

        let result = compiler.compile(
            prompt: prompt,
            interpretation: MarinaTurnInterpretation(result: .query(query)),
            candidate: candidate,
            outcome: .executable(MarinaAggregationPlan(operation: .lookupDetails, measure: .transactionAmount, responseShape: .summaryCard)),
            context: turnContext(provider: fixture.provider)
        )

        guard case .universal(let universalQuery, _) = result else {
            Issue.record("Expected card detail target to remain attached to the universal query.")
            return
        }
        #expect(universalQuery.modelName == "Card")
        #expect(universalQuery.operation == .detail)
        #expect(universalQuery.filters.contains { $0.field == nil && $0.value == "Apple Card" })
    }

    @Test func semanticCatalogCompiler_blocksAdviceAndMutationRecovery() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let compiler = MarinaSemanticCatalogCompiler()
        let prompts = [
            "Should I invest more from this workspace?",
            "Delete my groceries category"
        ]

        for prompt in prompts {
            let result = compiler.compile(
                prompt: prompt,
                interpretation: unsupportedInterpretation(prompt: prompt),
                candidate: universalCandidate(prompt),
                outcome: unsupportedOutcome(prompt: prompt),
                context: turnContext(provider: fixture.provider)
            )
            #expect(result == .none)
        }
    }

    @Test func universalExecutor_generatedCapabilitiesCoverEveryPersistentModel() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let executor = MarinaUniversalQueryExecutor()
        let descriptors = MarinaEntityCatalog.current.descriptors
            .filter { $0.kind == .persistentModel }
            .sorted { $0.entityName < $1.entityName }

        for descriptor in descriptors {
            let scope: MarinaUniversalWorkspaceScopePolicy = descriptor.entityName == "Workspace" ? .explicitGlobal : .selectedWorkspace
            let count = handledCard(executor.execute(
                universalQuery(.count, descriptor: descriptor, scope: scope),
                provider: fixture.provider
            ))
            #expect(count.traceSummary.contains("universalQuery=model:\(descriptor.entityName)"))
            #expect(Int(count.primaryValue ?? "0") ?? 0 > 0)

            let list = handledCard(executor.execute(
                universalQuery(.list, descriptor: descriptor, scope: scope),
                provider: fixture.provider
            ))
            #expect(list.rows.isEmpty == false)
            #expect(list.traceSummary.contains("evidence=\(descriptor.evidenceRowType)"))

            guard let firstLabel = list.rows.first?.label else {
                Issue.record("Expected at least one \(descriptor.entityName) evidence row.")
                continue
            }

            let contains = handledCard(executor.execute(
                universalQuery(
                    .list,
                    descriptor: descriptor,
                    filters: [MarinaUniversalQueryFilter(value: containsProbe(from: firstLabel), match: .contains)],
                    scope: scope
                ),
                provider: fixture.provider
            ))
            #expect(contains.rows.isEmpty == false)

            let detail = handledCard(executor.execute(
                universalQuery(
                    .detail,
                    descriptor: descriptor,
                    filters: [MarinaUniversalQueryFilter(value: firstLabel, match: .exact)],
                    scope: scope
                ),
                provider: fixture.provider
            ))
            #expect(detail.rows.isEmpty == false)
            #expect(detail.traceSummary.contains("operation=detail"))

            for aggregationOperation in [MarinaUniversalQueryOperation.sum, .average, .rank, .groupBreakdown] {
                let result = executor.execute(
                    universalQuery(aggregationOperation, descriptor: descriptor, scope: scope),
                    provider: fixture.provider
                )
                if supportsGenericAggregation(descriptor) {
                    let card = handledCard(result)
                    #expect(card.traceSummary.contains("operation=\(aggregationOperation.rawValue)"))
                } else if case .unsupported(let unsupported) = result {
                    #expect(unsupported.kind == .unsupportedCombination)
                } else {
                    Issue.record("Expected \(aggregationOperation.rawValue) to be rejected for \(descriptor.entityName).")
                }
            }
        }
    }

    @Test func universalExecutor_countsListsFiltersAndAggregatesTypedRows() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let executor = MarinaUniversalQueryExecutor()
        let may = HomeQueryDateRange(
            startDate: MarinaRealisticWorkspaceFixture.date(2026, 5, 1),
            endDate: MarinaRealisticWorkspaceFixture.date(2026, 5, 31)
        )

        let workspaceCount = handledCard(executor.execute(
            MarinaUniversalQueryIR(
                operation: .count,
                modelName: "Workspace",
                filters: [MarinaUniversalQueryFilter(value: "Personal", match: .contains)],
                workspaceScopePolicy: .explicitGlobal,
                presentationShape: .summaryCard,
                evidenceRowType: "Workspace"
            ),
            provider: fixture.provider
        ))
        #expect(workspaceCount.primaryValue == "1")
        #expect(workspaceCount.traceSummary.contains("scope=explicitGlobal"))

        let cards = handledCard(executor.execute(
            MarinaUniversalQueryIR(
                operation: .list,
                modelName: "Card",
                workspaceScopePolicy: .selectedWorkspace,
                presentationShape: .relationshipList,
                evidenceRowType: "Card"
            ),
            provider: fixture.provider
        ))
        #expect(cards.rows.count == 5)
        #expect(cards.rows.contains { $0.label == "Apple" })

        let cardDetail = handledCard(executor.execute(
            MarinaUniversalQueryIR(
                operation: .detail,
                modelName: "Card",
                filters: [MarinaUniversalQueryFilter(value: "Apple", match: .exact)],
                workspaceScopePolicy: .selectedWorkspace,
                presentationShape: .summaryCard,
                evidenceRowType: "Card"
            ),
            provider: fixture.provider
        ))
        #expect(cardDetail.rows.first?.objectType == .card)
        #expect(cardDetail.rows.first?.sourceID == fixture.appleCard.id)

        let categories = handledCard(executor.execute(
            MarinaUniversalQueryIR(
                operation: .list,
                modelName: "Category",
                filters: [MarinaUniversalQueryFilter(value: "groc", match: .contains)],
                workspaceScopePolicy: .selectedWorkspace,
                presentationShape: .relationshipList,
                evidenceRowType: "Category"
            ),
            provider: fixture.provider
        ))
        #expect(categories.rows.map(\.label) == ["Groceries"])

        let uncategorized = handledCard(executor.execute(
            MarinaUniversalQueryIR(
                operation: .count,
                modelName: "VariableExpense",
                filters: [MarinaUniversalQueryFilter(value: "Uncategorized", match: .uncategorized)],
                dateRange: may,
                workspaceScopePolicy: .selectedWorkspace,
                presentationShape: .summaryCard,
                evidenceRowType: "VariableExpense"
            ),
            provider: fixture.provider
        ))
        #expect(uncategorized.primaryValue == "2")

        let income = handledCard(executor.execute(
            MarinaUniversalQueryIR(
                operation: .sum,
                modelName: "Income",
                filters: [MarinaUniversalQueryFilter(field: "income status", value: "actual", match: .exact)],
                dateRange: may,
                workspaceScopePolicy: .selectedWorkspace,
                presentationShape: .summaryCard,
                evidenceRowType: "Income"
            ),
            provider: fixture.provider
        ))
        #expect(income.primaryValue?.contains("3,100") == true)

        let savings = handledCard(executor.execute(
            MarinaUniversalQueryIR(
                operation: .sum,
                modelName: "SavingsLedgerEntry",
                dateRange: may,
                workspaceScopePolicy: .selectedWorkspace,
                presentationShape: .summaryCard,
                evidenceRowType: "SavingsLedgerEntry"
            ),
            provider: fixture.provider
        ))
        #expect(savings.primaryValue?.contains("250") == true)

        let allocations = handledCard(executor.execute(
            MarinaUniversalQueryIR(
                operation: .rank,
                modelName: "ExpenseAllocation",
                workspaceScopePolicy: .selectedWorkspace,
                presentationShape: .rankedList,
                evidenceRowType: "ExpenseAllocation"
            ),
            provider: fixture.provider
        ))
        #expect(allocations.rows.first?.label == "Cafe")

        if case .unsupported(let unsupported) = executor.execute(
            MarinaUniversalQueryIR(
                operation: .sum,
                modelName: "Category",
                workspaceScopePolicy: .selectedWorkspace,
                presentationShape: .scalarCurrency,
                evidenceRowType: "Category"
            ),
            provider: fixture.provider
        ) {
            #expect(unsupported.kind == .unsupportedCombination)
        } else {
            Issue.record("Expected unsafe generic aggregation to be rejected.")
        }
    }





    private func handledCard(_ result: MarinaUniversalQueryExecutionResult) -> MarinaWorkspaceAggregationCard {
        switch result {
        case .handled(let card):
            return card
        case .unsupported(let unsupported):
            Issue.record("Expected handled universal query: \(unsupported.message)")
            return MarinaWorkspaceAggregationCard(title: "Missing", traceSummary: "missing")
        }
    }

    private func answerText(_ answer: HomeAnswer) -> String {
        ([answer.title, answer.subtitle, answer.primaryValue].compactMap { $0 } + answer.rows.flatMap { [$0.title, $0.value] })
            .joined(separator: " ")
    }

    private func universalQuery(
        _ operation: MarinaUniversalQueryOperation,
        descriptor: MarinaEntityDescriptor,
        filters: [MarinaUniversalQueryFilter] = [],
        scope: MarinaUniversalWorkspaceScopePolicy
    ) -> MarinaUniversalQueryIR {
        MarinaUniversalQueryIR(
            operation: operation,
            modelName: descriptor.entityName,
            filters: filters,
            workspaceScopePolicy: scope,
            presentationShape: operation == .count ? .summaryCard : (operation == .detail ? .summaryCard : .relationshipList),
            evidenceRowType: descriptor.evidenceRowType
        )
    }

    private func promptNoun(for descriptor: MarinaEntityDescriptor) -> String {
        pluralized(splitCamelCase(descriptor.entityName).lowercased())
    }

    private func splitCamelCase(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"([A-Z])([A-Z][a-z])"#, with: "$1 $2", options: .regularExpression)
    }

    private func pluralized(_ value: String) -> String {
        if value.hasSuffix("y") {
            return String(value.dropLast()) + "ies"
        }
        if value.hasSuffix("s") {
            return value
        }
        return value + "s"
    }

    private func containsProbe(from label: String) -> String {
        label
            .split(separator: " ")
            .map(String.init)
            .first { $0.count > 2 } ?? label
    }

    private func supportsGenericAggregation(_ descriptor: MarinaEntityDescriptor) -> Bool {
        descriptor.amountFields.isEmpty == false
            && (
                descriptor.isAggregatable
                || descriptor.supportedOperations.contains("total")
                || descriptor.supportedOperations.contains("average")
                || descriptor.supportedOperations.contains("rank")
                || descriptor.supportedOperations.contains("compare")
                || descriptor.supportedOperations.contains("balance")
            )
    }

    private func universalCandidate(_ prompt: String) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            confidence: .low
        )
    }

    private func unsupportedInterpretation(prompt: String) -> MarinaTurnInterpretation {
        MarinaTurnInterpretation(
            result: .unsupported(unsupportedResponse(prompt: prompt))
        )
    }

    private func unsupportedOutcome(prompt: String) -> MarinaPlanValidationOutcome {
        .unsupported(unsupportedResponse(prompt: prompt))
    }

    private func unsupportedResponse(prompt: String) -> MarinaTypedUnsupportedResponse {
        MarinaTypedUnsupportedResponse(
            kind: .unsupportedCombination,
            message: "Weak model response for \(prompt).",
            candidate: universalCandidate(prompt)
        )
    }

    private func turnContext(provider: MarinaDataProvider) -> MarinaTurnContext {
        MarinaTurnContext(
            provider: provider,
            routerContext: MarinaInterpretationContext(
                workspaceName: "Personal",
                defaultPeriodUnit: .month,
                sessionContext: MarinaSessionContext(),
                priorQueryContext: .empty,
                cardNames: [],
                categoryNames: [],
                incomeSourceNames: [],
                presetTitles: [],
                budgetNames: [],
                aliasSummaries: [],
                now: date(2026, 5, 15)
            ),
            defaultPeriodUnit: .month,
            aiEnabled: true,
            now: date(2026, 5, 15)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private struct TestFailure: Error {}
}
