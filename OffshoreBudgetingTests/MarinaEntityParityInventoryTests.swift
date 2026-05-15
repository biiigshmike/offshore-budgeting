import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaEntityParityInventoryTests {
    @Test func entityCatalog_coversEveryAppSchemaModel() {
        let expectedModels: Set<String> = [
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

        #expect(MarinaEntityCatalog.current.persistentModelEntityNames == expectedModels)

        for entityName in expectedModels {
            guard let descriptor = MarinaEntityCatalog.current.descriptor(for: entityName) else {
                Issue.record("Missing Marina entity descriptor for \(entityName)")
                continue
            }
            #expect(descriptor.kind == .persistentModel)
            #expect(descriptor.workspaceScope.path.isEmpty == false)
            #expect(descriptor.operations.isEmpty == false)
        }
    }

    @Test func entityCatalog_virtualEntitiesAreExplicitlyNonPersistent() {
        let virtualNames = Set(MarinaEntityCatalog.current.virtualDescriptors.map(\.entityName))

        #expect(virtualNames.contains("Virtual: Merchant"))
        #expect(virtualNames.contains("Virtual: IncomeSource"))
        #expect(virtualNames.contains("Virtual: Uncategorized"))
        #expect(virtualNames.contains("Virtual: EffectivePlannedExpenseAmount"))
        #expect(virtualNames.contains("Virtual: ActualSavings"))
        #expect(virtualNames.isDisjoint(with: MarinaEntityCatalog.current.persistentModelEntityNames))
    }

    @Test func entityCatalog_fieldDescriptorsMatchCapabilityMatrixRecords() {
        for descriptor in MarinaEntityCatalog.current.descriptors {
            guard let record = MarinaQueryCapabilityMatrix.record(for: descriptor.entityName) else {
                Issue.record("Missing compatibility record for \(descriptor.entityName)")
                continue
            }

            #expect(record.displayFields == descriptor.displayFields)
            #expect(record.amountFields == descriptor.amountFields)
            #expect(record.dateFields == descriptor.dateFields)
            #expect(record.workspaceScope == descriptor.workspaceScope.path)
            #expect(record.relationships == descriptor.relationships.map(\.name))
        }
    }

    @Test func entityCatalog_operationDescriptorsRoundTripToCapabilityRecords() {
        for descriptor in MarinaEntityCatalog.current.descriptors {
            guard let record = MarinaQueryCapabilityMatrix.record(for: descriptor.entityName) else {
                Issue.record("Missing compatibility record for \(descriptor.entityName)")
                continue
            }

            #expect(record.supportedOperations == descriptor.supportedOperations)
            #expect(record.missingOperations == descriptor.missingOperations)
            #expect(record.intentionallyUnsupportedOperations == descriptor.unsupportedOperations)
        }
    }

    @Test func capabilityMatrix_derivesModelEntityNamesFromCatalog() {
        #expect(MarinaQueryCapabilityMatrix.modelEntityNames == MarinaEntityCatalog.current.persistentModelEntityNames)
    }

    @Test func capabilityMatrix_lookupObjectTypesHaveCatalogCompatibility() {
        let supportedLookupTypes = Set(MarinaEntityCatalog.current.descriptors.compactMap(\.lookupObjectType))
        let expectedLookupTypes = Set(MarinaLookupObjectType.allCases).subtracting([.unknown])

        #expect(supportedLookupTypes == expectedLookupTypes)
        #expect(MarinaEntityCatalog.current.descriptor(for: .reconciliationAccount)?.entityName == "AllocationAccount")
        #expect(MarinaEntityCatalog.current.descriptor(for: .reconciliationItem)?.entityName == "AllocationSettlement")
    }

    @Test func capabilityRegistry_coversEveryModelsSwiftEntity() {
        let expectedModels: Set<String> = [
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

        #expect(MarinaQueryCapabilityMatrix.modelEntityNames == expectedModels)

        for entityName in expectedModels {
            guard let record = MarinaQueryCapabilityMatrix.record(for: entityName) else {
                Issue.record("Missing Marina capability record for \(entityName)")
                continue
            }
            #expect(record.entityName == entityName)
            #expect(record.workspaceScope.isEmpty == false)
            #expect(
                record.supportedOperations.isEmpty == false
                    || record.missingOperations.isEmpty == false
                    || record.intentionallyUnsupportedOperations.isEmpty == false
            )
        }
    }

    @Test func capabilityRegistry_includesVirtualQueryObjectsWithoutPretendingTheyAreModels() {
        let virtualRecords = MarinaQueryCapabilityMatrix.records.filter { $0.entityName.hasPrefix("Virtual:") }
        #expect(virtualRecords.map(\.entityName).contains("Virtual: Merchant"))
        #expect(virtualRecords.map(\.entityName).contains("Virtual: IncomeSource"))
        #expect(virtualRecords.map(\.entityName).contains("Virtual: Uncategorized"))
        #expect(virtualRecords.allSatisfy { MarinaQueryCapabilityMatrix.modelEntityNames.contains($0.entityName) == false })
    }

    @Test func appSurfaceInventory_hasExplicitParityDispositionAndSourceOfTruth() {
        #expect(MarinaQueryCapabilityMatrix.appSurfaceMetrics.isEmpty == false)

        for surface in MarinaQueryCapabilityMatrix.appSurfaceMetrics {
            #expect(surface.sourcePath.isEmpty == false)
            #expect(surface.sourceTypeName.isEmpty == false)
            #expect(surface.sourceFunctionOrProperty.isEmpty == false)
            #expect(surface.displayedMetric.isEmpty == false)
            #expect(surface.sourceEntities.isEmpty == false)

            switch surface.marinaSupportStatus {
            case .supportedRoute:
                #expect(surface.marinaRoute?.isEmpty == false)
                #expect(surface.unsupportedReason == nil)
            case .structuredClarificationRoute:
                #expect(surface.marinaRoute?.isEmpty == false)
                #expect(surface.unsupportedReason?.isEmpty == false)
            case .typedUnsupportedGap:
                #expect(surface.unsupportedReason?.isEmpty == false)
            }
        }
    }

    @Test func validator_usesCapabilityMatrixForAppSurfaceOperations() {
        let supported: [(MarinaCandidateOperation, MarinaCandidateMeasure)] = [
            (.lookupDetails, .savings),
            (.forecast, .savings),
            (.lookupDetails, .presetAmount),
            (.lookupDetails, .remainingBudget)
        ]

        for (operation, measure) in supported {
            let candidate = MarinaQueryPlanCandidate(
                source: .heuristic,
                rawPrompt: "\(operation.rawValue) \(measure.rawValue)",
                operation: operation,
                measure: measure,
                confidence: .medium
            )
            let outcome = MarinaQueryValidator().validate(
                MarinaResolvedQueryCandidate(
                    candidate: candidate,
                    resolvedTargets: [],
                    unresolvedMentions: [],
                    ambiguousMentions: [],
                    primaryDateRange: nil,
                    comparisonDateRange: nil
                )
            )

            guard case .executable(let plan) = outcome else {
                Issue.record("Expected \(operation.rawValue)/\(measure.rawValue) to be executable by capability matrix")
                continue
            }
            #expect(plan.operation == operation)
            #expect(plan.measure == measure)
        }
    }

    @Test func sharedPipelineSmoke_appSurfacePromptsRouteToExistingHomeMetrics() async throws {
        let fixture = try makeFixture()
        try seedSavingsAndPlanningData(fixture)
        let coordinator = MarinaSharedPipelineCoordinator()

        let cases: [(prompt: String, metric: HomeQueryMetric)] = [
            ("What is my actual savings so far this period?", .savingsStatus),
            ("What is my projected savings?", .forecastSavings),
            ("When is my next Planned Expense?", .nextPlannedExpense),
            ("What is my safe spend today?", .safeSpendToday)
        ]

        for testCase in cases {
            let result = await coordinator.run(
                prompt: testCase.prompt,
                context: sharedContext(fixture: fixture)
            )

            guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
                Issue.record("Expected handled result for \(testCase.prompt), got \(result.trace.compactSummary)")
                continue
            }
            #expect(homeQueryPlan?.metric == testCase.metric)
            #expect(trace.validatorOutcomeSummary?.contains("executable") == true)
        }
    }

    @Test func sharedPipelineSmoke_targetedAverageCannotSilentlyBecomeBroad() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "What is my average spend on Groceries for this year?",
            context: sharedContext(fixture: fixture, now: sharedPipelineDate(2026, 5, 15))
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected handled targeted average, got \(result.trace.compactSummary)")
            return
        }

        #expect(homeQueryPlan == nil)
        #expect(trace.executorResultSummary?.contains("targetedPeriodicAverage") == true)
        #expect(trace.executorResultSummary?.contains("targetFilterApplied=true") == true)
        #expect(trace.executorResultSummary?.contains("resolvedEntityType=category") == true)
        #expect(trace.executorResultSummary?.contains("responseScope=targeted") == true)
    }

    @Test func sharedPipelineSmoke_ambiguousRentReturnsStructuredChoicesWithIdentity() async throws {
        let fixture = try makeFixture()
        let rentCategory = Offshore.Category(name: "Rent", hexColor: "#AA0000", workspace: fixture.workspace)
        let rentPreset = Preset(title: "Rent", plannedAmount: 1_500, workspace: fixture.workspace, defaultCard: fixture.appleCard, defaultCategory: rentCategory)
        fixture.context.insert(rentCategory)
        fixture.context.insert(rentPreset)
        fixture.context.insert(PlannedExpense(title: "Rent", plannedAmount: 1_500, expenseDate: sharedPipelineDate(2026, 5, 1), workspace: fixture.workspace, card: fixture.appleCard, category: rentCategory))
        try fixture.context.save()

        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "What is my average spend on Rent?",
            context: sharedContext(fixture: fixture)
        )

        guard case .validationBlocked(_, let outcome, let trace) = result,
              case .clarification(let clarification) = outcome else {
            Issue.record("Expected structured clarification, got \(result.trace.compactSummary)")
            return
        }

        #expect(clarification.kind == .ambiguousTarget)
        #expect(clarification.candidate?.operation == .average)
        #expect(clarification.candidate?.measure == .spend)
        #expect(clarification.choices.count >= 2)
        #expect(clarification.choices.allSatisfy { $0.entityTypeHint != nil })
        #expect(clarification.choices.contains { $0.sourceID != nil })
        #expect(trace.validatorOutcomeSummary?.contains("clarification") == true)
    }

    private func seedSavingsAndPlanningData(_ fixture: MarinaPhase5Fixture) throws {
        let budget = Budget(
            name: "May Budget",
            startDate: sharedPipelineDate(2026, 5, 1),
            endDate: sharedPipelineDate(2026, 5, 31),
            workspace: fixture.workspace
        )
        let savings = SavingsAccount(name: "True Savings", total: 0, workspace: fixture.workspace)
        fixture.context.insert(budget)
        fixture.context.insert(savings)
        fixture.context.insert(Income(source: "Salary", amount: 3_000, date: sharedPipelineDate(2026, 5, 1), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(SavingsLedgerEntry(date: sharedPipelineDate(2026, 5, 10), amount: 250, note: "Period close", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, workspace: fixture.workspace, account: savings))
        fixture.context.insert(PlannedExpense(title: "Internet", plannedAmount: 90, expenseDate: sharedPipelineDate(2026, 5, 20), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()
    }
}
