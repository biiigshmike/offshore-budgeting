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

            for unsafeOperation in [MarinaUniversalQueryOperation.sum, .average, .rank, .groupBreakdown] {
                if case .unsupported(let unsupported) = executor.execute(
                    universalQuery(unsafeOperation, descriptor: descriptor, scope: scope),
                    provider: fixture.provider
                ) {
                    #expect(unsupported.kind == .unsupportedCombination)
                } else {
                    Issue.record("Expected \(unsafeOperation.rawValue) to be rejected for \(descriptor.entityName).")
                }
            }
        }
    }

    @Test func universalExecutor_countsListsFiltersAndRejectsUnsafeAggregation() throws {
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

    @Test func sharedPipeline_handlesUniversalQueryAcceptancePrompts() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()

        let workspaceCount = try handled(await fixture.run("Count how many workspaces I have"))
        #expect(workspaceCount.answer.primaryValue == "2")
        #expect(workspaceCount.trace.executorResultSummary?.contains("universalQuery=model:Workspace") == true)

        let workspaceFilter = try handled(await fixture.run("How many workspaces do I have that contain Personal?"))
        #expect(workspaceFilter.answer.primaryValue == "1")

        let cards = try handled(await fixture.run("List my cards"))
        #expect(cards.answer.kind == .list)
        #expect(cards.trace.executorResultSummary?.contains("universalQuery=model:Card") == true)

        let groceries = try handled(await fixture.run("Show Groceries"))
        #expect(groceries.trace.executorResultSummary?.contains("universalQuery=model:Category") == true)
        #expect(answerText(groceries.answer).contains("Groceries"))

        let categoryFilter = try handled(await fixture.run("Find categories containing groc"))
        #expect(categoryFilter.trace.executorResultSummary?.contains("universalQuery=model:Category") == true)
        #expect(answerText(categoryFilter.answer).contains("Groceries"))

        let transactionCount = try handled(await fixture.run("How many transactions do I have this month?"))
        #expect(transactionCount.trace.executorResultSummary?.contains("universalQuery=model:VariableExpense") == true)
        #expect(Int(transactionCount.answer.primaryValue ?? "0") ?? 0 > 0)

        let uncategorized = try handled(await fixture.run("Count uncategorized transactions this month"))
        #expect(uncategorized.answer.primaryValue == "2")
    }

    @Test func sharedPipeline_preflightCountsAndListsEveryModelWhenFoundationIsEligible() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let coordinator = MarinaSharedPipelineCoordinator(
            availability: SharedPipelineStubAvailability(status: .available),
            structuredInterpreter: SharedPipelineThrowingStructuredInterpreter()
        )
        let context = fixture.sharedPipelineContext(aiOptInEnabled: true)

        for descriptor in MarinaEntityCatalog.current.descriptors.filter({ $0.kind == .persistentModel }).sorted(by: { $0.entityName < $1.entityName }) {
            let noun = promptNoun(for: descriptor)
            let countPrompt = "How many \(noun) do I have?"
            let count = try handled(await coordinator.run(prompt: countPrompt, context: context), prompt: countPrompt)
            #expect(count.trace.interpreterSelectionReason == .universalPreflight)
            #expect(count.trace.executorResultSummary?.contains("universalQuery=model:\(descriptor.entityName)") == true)
            #expect(Int(count.answer.primaryValue ?? "0") ?? 0 > 0)

            let listPrompt = "List my \(noun)"
            let list = try handled(await coordinator.run(prompt: listPrompt, context: context), prompt: listPrompt)
            #expect(list.trace.interpreterSelectionReason == .universalPreflight)
            #expect(list.trace.executorResultSummary?.contains("universalQuery=model:\(descriptor.entityName)") == true)
            #expect(answerText(list.answer).isEmpty == false)
        }

        let cards = try handled(await coordinator.run(prompt: "How many cards do I have?", context: context))
        #expect(cards.answer.primaryValue == "5")

        let presets = try handled(await coordinator.run(prompt: "How many presets do I have?", context: context))
        #expect(presets.answer.primaryValue == "1")
    }

    @Test func sharedPipeline_routeFixesFromSmokeTraceExecuteWithSpecificPresentation() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()

        let applePrompt = "What did I spend at Apple this month?"
        let apple = try handled(await fixture.run(applePrompt), prompt: applePrompt)
        #expect(answerText(apple.answer).contains("$120.00"))
        #expect(apple.trace.validatorOutcomeSummary?.contains("unsupportedCombination") != true)

        let savingsPrompt = "Show savings activity"
        let savings = try handled(await fixture.run(savingsPrompt), prompt: savingsPrompt)
        #expect(savings.trace.executorResultSummary?.contains("largestSavingsMovements") == true)
        #expect(answerText(savings.answer).contains("Manual savings transfer"))

        let recentPrompt = "Show last 5 recent transactions"
        let recent = try handled(await fixture.run(recentPrompt), prompt: recentPrompt)
        guard case .workspaceCard(let recentCard) = recent.aggregationResult else {
            Issue.record("Expected recent transactions to use workspace card rows.")
            return
        }
        #expect(recentCard.rows.count == 5)
        #expect(recent.trace.executorResultSummary?.contains("recentFilteredTransactions") == true)

        let utilitiesPrompt = "Show Utilities this month"
        let utilities = try handled(await fixture.run(utilitiesPrompt), prompt: utilitiesPrompt)
        #expect(utilities.trace.executorResultSummary?.contains("categoryAvailability") == true)
        #expect(answerText(utilities.answer).contains("Utilities"))

        let incomePrompt = "Compare planned vs actual income"
        let income = try handled(await fixture.run(incomePrompt), prompt: incomePrompt)
        #expect(income.answer.title == "Planned vs Actual Income")

        let breakdownPrompt = "Show me my category breakdown this month"
        let breakdown = try handled(await fixture.run(breakdownPrompt), prompt: breakdownPrompt)
        #expect(breakdown.answer.title == "Spending by Category")

        let topOnePrompt = "What is my top 1 category this month?"
        let topOne = try handled(await fixture.run(topOnePrompt), prompt: topOnePrompt)
        guard case .rankedList(let topOneList) = topOne.aggregationResult else {
            Issue.record("Expected top 1 category to use ranked list.")
            return
        }
        #expect(topOneList.rows.count == 1)
        #expect(topOne.trace.validatorOutcomeSummary?.contains("unsupportedCombination") != true)
    }

    private struct Handled {
        let answer: HomeAnswer
        let aggregationResult: MarinaAggregationResult
        let trace: MarinaSharedPipelineTrace
    }

    private func handled(_ result: MarinaSharedPipelineRuntimeResult, prompt: String? = nil) throws -> Handled {
        switch result {
        case .handled(let answer, let aggregationResult, _, let trace):
            return Handled(answer: answer, aggregationResult: aggregationResult, trace: trace)
        case .validationBlocked(let answer, _, let trace):
            let promptPrefix = prompt.map { "\($0): " } ?? ""
            Issue.record("\(promptPrefix)Expected handled result, got blocked: \(answer.title) \(trace.validatorOutcomeSummary ?? "")")
            throw TestFailure()
        case .fallbackToLegacy(let trace):
            let promptPrefix = prompt.map { "\($0): " } ?? ""
            Issue.record("\(promptPrefix)Expected handled result, got fallback: \(trace)")
            throw TestFailure()
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

    private struct TestFailure: Error {}
}
